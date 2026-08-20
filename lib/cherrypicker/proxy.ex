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
  defp stream_response(conn, request, name, port) do
    finch_stream = fn
      {:status, status}, conn -> %{conn | status: status}
      {:headers, headers}, conn -> merge_upstream_headers(conn, headers)
      {:data, data}, conn -> send_chunk_or_halt(conn, data)
    end

    case Finch.stream(request, Cherrypicker.Finch, conn, finch_stream, receive_timeout: :infinity) do
      {:ok, %Plug.Conn{state: :chunked} = conn} -> conn
      # Status + headers but not a byte of body: send the empty response.
      {:ok, conn} -> send_chunked(conn, conn.status)
      {:error, _conn_or_reason, _reason} -> bad_gateway(conn, name, port)
      {:error, _reason} -> bad_gateway(conn, name, port)
    end
  catch
    # Thrown by the chunk sender when the browser goes away mid-stream;
    # unwinding through Finch.stream is what stops the upstream pull.
    {:client_gone, conn} -> conn
  end

  defp merge_upstream_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      if key in @hop_by_hop or key == "content-length" do
        conn
      else
        put_resp_header(conn, key, value)
      end
    end)
  end

  defp send_chunk_or_halt(conn, data) do
    conn = if conn.state == :chunked, do: conn, else: send_chunked(conn, conn.status)

    case chunk(conn, data) do
      {:ok, conn} -> conn
      # The browser went away mid-stream; stop pulling from upstream.
      {:error, _reason} -> throw({:client_gone, conn})
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
