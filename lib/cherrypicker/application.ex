defmodule Cherrypicker.Application do
  # The library starts nothing: the daemon tree is started explicitly
  # by the CLI (`cherrypicker start`) or embedded by a host app via
  # `Cherrypicker.Daemon`. A dependency must never open a port as a
  # side effect of being in a deps list.
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: Cherrypicker.Supervisor)
  end
end
