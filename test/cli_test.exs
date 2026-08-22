defmodule Cherrypicker.CLITest do
  # Not async: shares CHERRYPICKER_HOME and the daemon with real ports.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Cherrypicker.CLI

  setup do
    home = Path.join(System.tmp_dir!(), "cherrypicker-cli-#{System.unique_integer([:positive])}")
    System.put_env("CHERRYPICKER_HOME", home)
    on_exit(fn -> System.delete_env("CHERRYPICKER_HOME") end)
    on_exit(fn -> File.rm_rf!(home) end)
    :ok
  end

  defp with_daemon(fun) do
    start_supervised!({Cherrypicker.Daemon, port: 0, shutdown_timeout: 100})
    fun.(Cherrypicker.Daemon.port())
  end

  test "version prints and exits 0" do
    vsn = Application.spec(:cherrypicker, :vsn) |> to_string()
    assert capture_io(fn -> assert CLI.run(["version"]) == 0 end) =~ "cherrypicker #{vsn}"
  end

  test "route and ls against a live daemon, human and json" do
    with_daemon(fn proxy ->
      out = capture_io(fn -> assert CLI.run(["route", "myapp", "4000"]) == 0 end)
      assert out =~ "http://myapp.localhost:#{proxy}"

      out = capture_io(fn -> assert CLI.run(["ls", "--json"]) == 0 end)

      assert JSON.decode!(out) == %{
               "ok" => true,
               "command" => "ls",
               "routes" => [%{"name" => "myapp", "port" => 4000}]
             }

      assert capture_io(fn -> assert CLI.run(["unroute", "myapp"]) == 0 end) =~ "unrouted"
      assert capture_io(fn -> assert CLI.run(["ls"]) == 0 end) =~ "nothing routed"
    end)
  end

  test "route without a daemon fails with the remedy" do
    err = capture_io(:stderr, fn -> assert CLI.run(["route", "myapp", "4000"]) == 1 end)
    assert err =~ "cherrypicker start"
  end

  test "usage errors exit 2" do
    assert capture_io(:stderr, fn -> assert CLI.run(["--json"]) == 2 end) =~ "verb is required"
    assert capture_io(:stderr, fn -> assert CLI.run(["route", "a", "x"]) == 2 end) =~ "integer"
    assert capture_io(:stderr, fn -> assert CLI.run(["--nope"]) == 2 end) =~ "unknown option"
  end

  test "bare, help, and --help print the usage screen and exit 0" do
    for argv <- [[], ["help"], ["--help"], ["-h"]] do
      out = capture_io(fn -> assert CLI.run(argv) == 0 end)
      assert out =~ "usage: cherrypicker <verb>"
      assert out =~ "route NAME PORT"
    end
  end
end
