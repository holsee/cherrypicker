defmodule Cherrypicker.Proxy do
  @moduledoc """
  The reverse proxy: `Host: <name>.localhost` → the registered loopback
  port, streaming both directions so SSE and long-poll dev servers
  (live reload included) work through it.

  The reserved host `cherrypicker.localhost` serves the control API
  (`Cherrypicker.Control`) instead of proxying. An unrouted name gets a
  404 that lists what is routed, because a dev tool's error page should
  answer the next question.
  """

  @behaviour Plug

  import Plug.Conn

  alias Cherrypicker.{Control, Routes}

  # Hop-by-hop headers never travel through a proxy (RFC 9110 §7.6.1).
  @hop_by_hop ~w(connection keep-alive proxy-authenticate proxy-authorization
                 te trailers transfer-encoding upgrade)

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case route_name(conn.host) do
      "cherrypicker" -> Control.call(conn, [])
      name -> proxy(conn, name)
    end
  end

  # "myapp.localhost" → "myapp"; a bare or foreign host maps to itself,
  # which will be unrouted and get the helpful 404.
  defp route_name(host) do
    String.replace_suffix(host, ".localhost", "")
  end

  defp proxy(conn, name) do
    case Routes.fetch(name) do
      {:ok, port} -> forward(conn, name, port)
      :error -> not_routed(conn, name)
    end
  end

  defp forward(conn, name, port) do
    {:ok, body, conn} = read_full_body(conn)

    request =
      Finch.build(
        conn.method |> String.downcase() |> String.to_atom(),
        upstream_url(conn, port),
        upstream_headers(conn),
        if(body == "", do: nil, else: body)
      )

    stream_response(conn, request, name, port)
  end

  defp upstream_url(conn, port) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    "http://127.0.0.1:#{port}#{conn.request_path}#{query}"
  end

  # The upstream learns the name it is being served as, port included —
  # the raw Host header, not Plug's port-stripped conn.host — so links
  # and redirects it emits can stay browser-correct.
  defp upstream_headers(conn) do
    host = conn |> get_req_header("host") |> List.first(conn.host)

    conn.req_headers
    |> Enum.reject(fn {key, _value} -> key in @hop_by_hop end)
    |> List.keystore("x-forwarded-host", 0, {"x-forwarded-host", host})
  end

  # Streams the upstream response chunk by chunk into the client
  # connection: status and headers arrive first, then each body chunk
  # is flushed as it lands — an SSE stream stays a stream.
  #
  # The Finch pull runs in a monitored reader process while this one —
  # the owner of the client socket — waits in `relay/5` with the socket
  # in `active: :once`. A browser that abandons an idle stream then
  # arrives as a `:tcp_closed` message instead of going unnoticed until
  # the next write, which for a silent long-poll or SSE upstream never
  # comes; without the watch, every abandoned stream held its client
  # socket, this process, and the upstream connection forever.
  defp stream_response(conn, request, name, port) do
    client = client_socket(conn)
    watch(client)

    owner = self()

    reader =
      spawn_monitor(fn ->
        result =
          Finch.stream(
            request,
            Cherrypicker.Finch,
            :ok,
            fn event, :ok ->
              send(owner, {:upstream, event})
              :ok
            end,
            receive_timeout: :infinity
          )

        send(owner, {:upstream_done, result})
      end)

    try do
      relay(conn, reader, client, name, port)
    after
      # Runs on every internal unwind — Bandit's send_chunked raising on
      # a client that died at just the wrong moment included — so no
      # exception path can orphan the reader. Both reap calls are no-ops
      # when the reader already finished.
      reap(reader)
      unwatch(client)
      drain(client)
    end
  end

  defp relay(conn, {pid, ref} = reader, client, name, port) do
    receive do
      {:upstream, {:status, status}} ->
        relay(%{conn | status: status}, reader, client, name, port)

      {:upstream, {:headers, headers}} ->
        relay(merge_upstream_headers(conn, headers), reader, client, name, port)

      {:upstream, {:data, data}} ->
        case send_chunk(conn, data) do
          {:ok, conn} -> relay(conn, reader, client, name, port)
          {:error, _reason} -> halt_reader(reader, conn)
        end

      # Sent by the reader after every event it will ever send; mailbox
      # order from a single sender makes this the natural terminator.
      {:upstream_done, result} ->
        Process.demonitor(ref, [:flush])
        finish(conn, result, name, port)

      {:DOWN, ^ref, :process, ^pid, _reason} ->
        finish(conn, :reader_down, name, port)

      # The whole point: the browser leaving is an event now.
      {:tcp_closed, ^client} ->
        halt_reader(reader, conn)

      {:tcp_error, ^client, _reason} ->
        halt_reader(reader, conn)

      # Request bytes mid-response would be a pipelining client; browsers
      # never pipeline, and a connection whose bytes we have consumed
      # cannot be handed back to Bandit cleanly anyway.
      {:tcp, ^client, _bytes} ->
        halt_reader(reader, conn)
    end
  end

  # Killing the reader is what releases the upstream: Finch's pool
  # monitors the process that checked the connection out and closes it
  # when that process dies.
  defp halt_reader(reader, conn) do
    reap(reader)
    conn
  end

  defp reap({pid, ref}) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
  end

  defp finish(%Plug.Conn{state: :chunked} = conn, _result, _name, _port), do: conn

  # Status + headers but not a byte of body: send the empty response.
  defp finish(conn, {:ok, :ok}, _name, _port), do: send_chunked(conn, conn.status)

  defp finish(conn, _error, name, port), do: bad_gateway(conn, name, port)

  defp merge_upstream_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      if key in @hop_by_hop or key == "content-length" do
        conn
      else
        put_resp_header(conn, key, value)
      end
    end)
  end

  defp send_chunk(conn, data) do
    conn = if conn.state == :chunked, do: conn, else: send_chunked(conn, conn.status)
    chunk(conn, data)
  end

  # The one deliberate reach into Bandit's internals: its adapter holds
  # the ThousandIsland socket for the client connection. A shape this
  # doesn't recognise (HTTP/2, a future Bandit) degrades to the old
  # behaviour — no client watch — rather than crashing.
  defp client_socket(%Plug.Conn{adapter: {Bandit.Adapter, adapter}}) do
    case adapter do
      %{transport: %{socket: %ThousandIsland.Socket{socket: socket}}} when is_port(socket) ->
        socket

      _other ->
        nil
    end
  end

  defp client_socket(_conn), do: nil

  defp watch(nil), do: :ok

  defp watch(socket) do
    _ = :inet.setopts(socket, active: :once)
    :ok
  end

  # Bandit expects the socket passive between requests; hand it back so.
  defp unwatch(nil), do: :ok

  defp unwatch(socket) do
    _ = :inet.setopts(socket, active: false)
    :ok
  end

  # The reader may have queued events between the last receive and its
  # death; flush them so a keep-alive connection's next request starts
  # with a clean mailbox.
  defp drain(client) do
    receive do
      {:upstream, _event} -> drain(client)
      {:upstream_done, _result} -> drain(client)
      {:tcp, socket, _bytes} when socket == client -> drain(client)
      {:tcp_closed, socket} when socket == client -> drain(client)
      {:tcp_error, socket, _reason} when socket == client -> drain(client)
    after
      0 -> :ok
    end
  end

  defp read_full_body(conn, acc \\ []) do
    case read_body(conn) do
      {:ok, chunk, conn} -> {:ok, IO.iodata_to_binary([acc, chunk]), conn}
      {:more, chunk, conn} -> read_full_body(conn, [acc, chunk])
    end
  end

  defp not_routed(conn, name) do
    routed =
      case Routes.list() do
        [] -> "Nothing is routed yet."
        routes -> "Routed: " <> Enum.map_join(routes, ", ", &"#{&1.name} → :#{&1.port}")
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "#{name} is not routed. #{routed}\n")
  end

  defp bad_gateway(conn, name, port) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(502, "#{name} routes to 127.0.0.1:#{port}, but nothing answered there.\n")
  end
end
