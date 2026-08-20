defmodule Cherrypicker.Routes do
  @moduledoc """
  The route table: name → loopback port, held in ETS behind a GenServer
  so writes serialize and reads stay lock-free on the hot proxy path.

  Names are the DNS label before `.localhost`: lowercase letters,
  digits, and hyphens, dots allowed for subdomain-style names
  (`api.myapp`). `cherrypicker` itself is reserved for the control API.
  """

  use GenServer

  @table __MODULE__
  @reserved ~w(cherrypicker)
  @name_re ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/

  @type name :: String.t()
  @type route :: %{name: name(), port: :inet.port_number()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Registers or replaces a route. Errors on bad names and ports."
  @spec put(name(), :inet.port_number()) :: :ok | {:error, String.t()}
  def put(name, port) do
    cond do
      name in @reserved -> {:error, "#{name} is reserved"}
      not Regex.match?(@name_re, name) -> {:error, "invalid name: #{name}"}
      not (is_integer(port) and port in 1..65_535) -> {:error, "invalid port: #{inspect(port)}"}
      true -> GenServer.call(__MODULE__, {:put, name, port})
    end
  end

  @doc "Removes a route; removing an absent route is not an error."
  @spec delete(name()) :: :ok
  def delete(name), do: GenServer.call(__MODULE__, {:delete, name})

  @doc "The port for a name, if routed."
  @spec fetch(name()) :: {:ok, :inet.port_number()} | :error
  def fetch(name) do
    case :ets.lookup(@table, name) do
      [{^name, port}] -> {:ok, port}
      [] -> :error
    end
  end

  @doc "Every route, name-sorted."
  @spec list() :: [route()]
  def list do
    @table
    |> :ets.tab2list()
    |> Enum.sort()
    |> Enum.map(fn {name, port} -> %{name: name, port: port} end)
  end

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, table}
  end

  @impl GenServer
  def handle_call({:put, name, port}, _from, table) do
    :ets.insert(@table, {name, port})
    {:reply, :ok, table}
  end

  def handle_call({:delete, name}, _from, table) do
    :ets.delete(@table, name)
    {:reply, :ok, table}
  end
end
