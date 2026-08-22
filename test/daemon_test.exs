defmodule Cherrypicker.DaemonTest do
  # Not async: these tests own CHERRYPICKER_HOME and real TCP ports.
  use ExUnit.Case

  @moduledoc """
  The end-to-end loop: daemon up on an ephemeral port, a stub upstream,
  routes registered through the public client API, requests proxied by
  Host header — the exact path `cherry serve --name` rides.
  """

  defmodule Upstream do
    @moduledoc false
    @behaviour Plug
    import Plug.Conn

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(%Plug.Conn{path_info: ["sse"]} = conn, _opts) do
      conn =
        conn
        |> put_resp_header("content-type", "text/event-stream")
        |> send_chunked(200)

      {:ok, conn} = chunk(conn, "data: one\n\n")
      Process.sleep(50)
      {:ok, conn} = chunk(conn, "data: two\n\n")
      conn
    end

    def call(%Plug.Conn{path_info: ["echo-host"]} = conn, _opts) do
      forwarded = conn |> get_req_header("x-forwarded-host") |> List.first("none")
      send_resp(conn, 200, "forwarded-host: #{forwarded}")
    end

    def call(conn, _opts) do
      send_resp(conn, 200, "hello from upstream #{conn.request_path}")
    end
  end

  setup do
    home = Path.join(System.tmp_dir!(), "cherrypicker-#{System.unique_integer([:positive])}")
    System.put_env("CHERRYPICKER_HOME", home)
    on_exit(fn -> System.delete_env("CHERRYPICKER_HOME") end)
    on_exit(fn -> File.rm_rf!(home) end)

    start_supervised!({Cherrypicker.Daemon, port: 0, shutdown_timeout: 100})
    proxy_port = Cherrypicker.Daemon.port()

    upstream =
      start_supervised!(
        {Bandit,
         plug: Upstream,
         port: 0,
         startup_log: false,
         thousand_island_options: [shutdown_timeout: 100]}
      )

    {:ok, {_ip, upstream_port}} = ThousandIsland.listener_info(upstream)

    {:ok, proxy: proxy_port, upstream: upstream_port}
  end

  test "the daemon announces itself and the client finds it", %{proxy: proxy} do
    assert {:ok, ^proxy} = Cherrypicker.daemon_port()
  end

  test "register → proxied request by Host header → unregister", ctx do
    assert {:ok, url} = Cherrypicker.register("myapp", ctx.upstream)
    assert url == "http://myapp.localhost:#{ctx.proxy}"

    assert {200, body} = get(ctx.proxy, "myapp.localhost", "/posts/")
    assert body == "hello from upstream /posts/"

    assert {:ok, [%{name: "myapp"}]} = Cherrypicker.routes()

    assert :ok = Cherrypicker.unregister("myapp")
    assert {404, _body} = get(ctx.proxy, "myapp.localhost", "/")
  end

  test "an SSE stream passes through chunk by chunk", ctx do
    {:ok, _url} = Cherrypicker.register("myapp", ctx.upstream)

    assert {200, body} = get(ctx.proxy, "myapp.localhost", "/sse")
    assert body == "data: one\n\ndata: two\n\n"
  end

  test "the upstream sees the named host it is being served as", ctx do
    {:ok, _url} = Cherrypicker.register("myapp", ctx.upstream)

    assert {200, body} = get(ctx.proxy, "myapp.localhost", "/echo-host")
    assert body == "forwarded-host: myapp.localhost:#{ctx.proxy}"
  end

  test "an unrouted name 404s and names what is routed", ctx do
    {:ok, _url} = Cherrypicker.register("myapp", ctx.upstream)

    assert {404, body} = get(ctx.proxy, "nosuch.localhost", "/")
    assert body =~ "nosuch is not routed"
    assert body =~ "myapp → :#{ctx.upstream}"
  end

  test "an abandoned idle stream releases the upstream connection", ctx do
    # A hand-rolled upstream that sends SSE headers plus one event and
    # then goes silent — the shape of a live-reload stream — handing the
    # test its accepted socket so the proxy hanging up is observable.
    parent = self()
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, upstream_port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, accepted} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(accepted, 0, 5_000)

      response =
        "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n" <>
          "transfer-encoding: chunked\r\n\r\n" <> http_chunk("data: one\n\n")

      :ok = :gen_tcp.send(accepted, response)

      # Nothing more will ever be sent; recv returns only when the
      # proxy closes its side.
      send(parent, {:upstream_closed, :gen_tcp.recv(accepted, 0, 5_000)})
    end)

    {:ok, _url} = Cherrypicker.register("idle", upstream_port)

    # A raw client: open the stream, see the first event, vanish.
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", ctx.proxy, [:binary, active: false])

    :ok =
      :gen_tcp.send(
        socket,
        "GET / HTTP/1.1\r\nhost: idle.localhost:#{ctx.proxy}\r\n\r\n"
      )

    assert recv_until(socket, "data: one") =~ "data: one"
    :ok = :gen_tcp.close(socket)

    # Before the fix this timed out: the proxy never noticed the client
    # leave, and held its upstream pull (and both sockets) forever.
    assert_receive {:upstream_closed, {:error, :closed}}, 5_000
  end

  test "a route to a dead port answers 502, not a crash", ctx do
    {:ok, dead} = :gen_tcp.listen(0, [])
    {:ok, dead_port} = :inet.port(dead)
    :gen_tcp.close(dead)

    {:ok, _url} = Cherrypicker.register("ghost", dead_port)

    assert {502, body} = get(ctx.proxy, "ghost.localhost", "/")
    assert body =~ "nothing answered"
  end

  test "the client refuses garbage the daemon refuses", ctx do
    assert {:error, message} = Cherrypicker.register("Bad Name", ctx.upstream)
    assert message =~ "invalid name"
  end

  test "a stale state file reads as no daemon" do
    home = System.get_env("CHERRYPICKER_HOME")
    stop_supervised!(Cherrypicker.Daemon)

    # The clean shutdown removed the file; a crashed daemon would not
    # have. Recreate that world: a file pointing at a dead port.
    File.mkdir_p!(home)
    File.write!(Path.join(home, "daemon.json"), JSON.encode!(%{port: 1}))

    assert :error = Cherrypicker.daemon_port()
    assert {:error, :no_daemon} = Cherrypicker.register("myapp", 4000)
  end

  defp http_chunk(data) do
    Integer.to_string(byte_size(data), 16) <> "\r\n" <> data <> "\r\n"
  end

  defp recv_until(socket, marker, acc \\ "") do
    if acc =~ marker do
      acc
    else
      {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
      recv_until(socket, marker, acc <> data)
    end
  end

  defp get(proxy_port, host, path) do
    url = ~c"http://127.0.0.1:#{proxy_port}#{path}"

    headers = [{~c"host", ~c"#{host}:#{proxy_port}"}, {~c"connection", ~c"close"}]

    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(:get, {url, headers}, [], body_format: :binary)

    {status, body}
  end
end
