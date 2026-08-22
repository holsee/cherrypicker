defmodule Cherrypicker.Daemon do
  @moduledoc """
  The running proxy: routes table + Finch pool + Bandit listener, one
  supervision tree started by the CLI (or embedded by a host app).

  On start it records `{port}` in the state file so clients
  (`Cherrypicker.register/2`, the CLI verbs) can find the control API
  without configuration; the file is removed on clean shutdown.

  The default port is 80 — that is what makes `http://myapp.localhost`
  pretty — but binding 80 needs privileges on Unix, so `:port` is
  honest configuration, not a hidden sudo. `port: 0` binds an ephemeral
  port, which the state file then advertises.
  """

  use Supervisor

  alias Cherrypicker.State

  @default_port 80

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    with {:ok, pid} <- Supervisor.start_link(__MODULE__, opts, name: __MODULE__) do
      # Written here, after the tree is fully up: the bound port is
      # final, and callers returning from start_link can rely on the
      # state file existing.
      if Keyword.get(opts, :state_file?, true), do: :ok = State.write(%{port: port()})
      {:ok, pid}
    end
  end

  @doc "The port the proxy actually bound (pass `port: 0` for ephemeral)."
  @spec port() :: :inet.port_number()
  def port do
    {_id, pid, _type, _mods} =
      __MODULE__
      |> Supervisor.which_children()
      |> Enum.find(fn {_id, _pid, _type, mods} -> mods == [Bandit] end)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    port
  end

  @impl Supervisor
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)

    # Tests drop this to milliseconds; the default gives in-flight
    # requests a grace period on shutdown.
    drain = Keyword.get(opts, :shutdown_timeout, 15_000)

    children = [
      Cherrypicker.Routes,
      {Finch, name: Cherrypicker.Finch},
      # Owns the proxy's upstream readers: monitored, never linked, and
      # gone with this tree instead of orphaned on daemon shutdown.
      {Task.Supervisor, name: Cherrypicker.ReaderSupervisor},
      {Bandit,
       plug: Cherrypicker.Proxy,
       port: port,
       startup_log: false,
       thousand_island_options: [shutdown_timeout: drain]},
      {Cherrypicker.Daemon.Announcer, state_file?: Keyword.get(opts, :state_file?, true)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defmodule Announcer do
    @moduledoc false
    # Owns cleanup only: the state file is written by Daemon.start_link
    # once the tree is up (writing from a child's init would ask the
    # still-starting supervisor for its port and deadlock); this child
    # removes it on clean shutdown.
    use GenServer

    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts) do
      if Keyword.get(opts, :state_file?, true) do
        Process.flag(:trap_exit, true)
        {:ok, :cleanup}
      else
        {:ok, :silent}
      end
    end

    @impl GenServer
    def terminate(_reason, :cleanup), do: Cherrypicker.State.remove()
    def terminate(_reason, _state), do: :ok
  end
end
