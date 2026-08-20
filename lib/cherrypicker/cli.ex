defmodule Cherrypicker.CLI do
  @moduledoc """
  The `cherrypicker` command:

      cherrypicker start [--port N]     # run the proxy (foreground)
      cherrypicker route NAME PORT      # name → 127.0.0.1:PORT
      cherrypicker unroute NAME
      cherrypicker ls
      cherrypicker version

  Every verb takes `--json` for a machine-readable envelope. Exit codes:
  0 success, 1 the command ran and failed, 2 usage error.
  """

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    argv |> run() |> System.halt()
  end

  @doc "The dispatcher, separated from `main/1` so tests avoid the halt."
  @spec run([String.t()]) :: 0 | 1 | 2
  def run(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv, strict: [json: :boolean, port: :integer])

    case {args, invalid} do
      {_args, [{flag, _value} | _rest]} -> usage("unknown option #{flag}")
      {["start" | rest], []} -> start(rest, opts)
      {["route", name, port], []} -> route(name, port, opts)
      {["unroute", name], []} -> unroute(name, opts)
      {["ls"], []} -> ls(opts)
      {["version"], []} -> version(opts)
      {[], []} -> usage("a verb is required: start, route, unroute, ls, version")
      {[verb | _rest], []} -> usage("unknown or incomplete verb: #{verb}")
    end
  end

  defp start([], opts) do
    port = Keyword.get(opts, :port, 80)

    case Cherrypicker.Daemon.start_link(port: port) do
      {:ok, _pid} ->
        bound = Cherrypicker.Daemon.port()
        emit(opts, %{ok: true, command: "start", port: bound}, banner(bound))
        Process.sleep(:infinity)

      {:error, reason} ->
        fail(opts, "start", "could not bind port #{port}: #{inspect(reason)}")
    end
  end

  defp start(_extra, _opts), do: usage("start takes no arguments")

  defp route(name, port_string, opts) do
    case Integer.parse(port_string) do
      {port, ""} ->
        case Cherrypicker.register(name, port) do
          {:ok, url} ->
            emit(opts, %{ok: true, command: "route", name: name, port: port, url: url}, url)
            0

          {:error, :no_daemon} ->
            fail(opts, "route", no_daemon())

          {:error, message} ->
            fail(opts, "route", message)
        end

      _not_an_integer ->
        usage("PORT must be an integer, got #{port_string}")
    end
  end

  defp unroute(name, opts) do
    :ok = Cherrypicker.unregister(name)
    emit(opts, %{ok: true, command: "unroute", name: name}, "#{name} unrouted")
    0
  end

  defp ls(opts) do
    case Cherrypicker.routes() do
      {:ok, []} ->
        emit(opts, %{ok: true, command: "ls", routes: []}, "nothing routed")
        0

      {:ok, routes} ->
        human = Enum.map_join(routes, "\n", &"#{&1.name}.localhost → 127.0.0.1:#{&1.port}")
        emit(opts, %{ok: true, command: "ls", routes: routes}, human)
        0

      {:error, :no_daemon} ->
        fail(opts, "ls", no_daemon())

      {:error, message} ->
        fail(opts, "ls", message)
    end
  end

  defp version(opts) do
    version = Application.spec(:cherrypicker, :vsn) |> to_string()
    emit(opts, %{ok: true, command: "version", version: version}, "cherrypicker #{version}")
    0
  end

  defp banner(80), do: "proxy up — routes serve at http://<name>.localhost (Ctrl-C to stop)"

  defp banner(port),
    do: "proxy up — routes serve at http://<name>.localhost:#{port} (Ctrl-C to stop)"

  defp no_daemon, do: "no daemon is running — start one with: cherrypicker start"

  defp emit(opts, envelope, human) do
    if opts[:json], do: IO.puts(JSON.encode!(envelope)), else: IO.puts(human)
  end

  defp fail(opts, command, message) do
    if opts[:json] do
      IO.puts(JSON.encode!(%{ok: false, command: command, error: message}))
    else
      IO.puts(:stderr, "error: #{message}")
    end

    1
  end

  defp usage(message) do
    IO.puts(:stderr, "usage: #{message}")
    2
  end
end
