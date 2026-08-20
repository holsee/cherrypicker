defmodule Cherrypicker.State do
  @moduledoc """
  The daemon's discovery file: `~/.cherrypicker/daemon.json`, holding
  the bound proxy port. Written by the daemon on start, removed on
  clean shutdown, read by every client that needs to find the control
  API without being told where it is.

  A stale file (daemon crashed) is possible; clients treat "file
  present but nothing answers" as `:no_daemon`, so staleness costs one
  failed connect, never a wrong answer.
  """

  @type info :: %{port: :inet.port_number()}

  @doc "Where the state file lives; override with CHERRYPICKER_HOME for tests."
  @spec path() :: Path.t()
  def path do
    home = System.get_env("CHERRYPICKER_HOME") || Path.join(System.user_home!(), ".cherrypicker")
    Path.join(home, "daemon.json")
  end

  @spec write(info()) :: :ok
  def write(%{port: port}) do
    file = path()
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, JSON.encode!(%{port: port}))
  end

  @spec read() :: {:ok, info()} | :error
  def read do
    with {:ok, raw} <- File.read(path()),
         %{"port" => port} when is_integer(port) <- decode(raw) do
      {:ok, %{port: port}}
    else
      _missing_or_malformed -> :error
    end
  end

  @spec remove() :: :ok
  def remove do
    File.rm(path())
    :ok
  end

  defp decode(raw) do
    JSON.decode!(raw)
  rescue
    _error -> :malformed
  end
end
