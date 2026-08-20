defmodule Cherrypicker do
  @moduledoc """
  Stable named `.localhost` URLs for local dev servers, on the BEAM.

  A running daemon (`cherrypicker start`, or `Cherrypicker.Daemon` in a
  supervision tree) proxies `http://<name>.localhost[:port]` to
  registered loopback ports. This module is the client: it finds the
  daemon through its state file and speaks the control API using only
  the standard library, so depending on it costs a host application
  nothing at runtime.

  The register model, deliberately: apps start themselves and say where
  they are — no child-process wrapping, no PORT-injection guesswork.

      case Cherrypicker.register("mysite", 4000) do
        {:ok, url} -> IO.puts("also at " <> url)
        {:error, :no_daemon} -> :ok
      end
  """

  alias Cherrypicker.State

  @type name :: String.t()
  @type error :: :no_daemon | String.t()

  @doc """
  Registers `name` to proxy to `127.0.0.1:port`, returning the named
  URL. `{:error, :no_daemon}` when no daemon is reachable — callers
  treat that as "fall back to the port URL", never as a failure.
  """
  @spec register(name(), :inet.port_number()) :: {:ok, String.t()} | {:error, error()}
  def register(name, port) do
    case control(:put, "/routes/#{URI.encode_www_form(name)}", JSON.encode!(%{port: port})) do
      {:ok, 200, %{"url" => url}} -> {:ok, visible_url(url)}
      {:ok, _status, %{"error" => message}} -> {:error, message}
      {:error, :no_daemon} -> {:error, :no_daemon}
    end
  end

  @doc "Removes a route; absent routes and absent daemons are fine."
  @spec unregister(name()) :: :ok
  def unregister(name) do
    _result = control(:delete, "/routes/#{URI.encode_www_form(name)}", nil)
    :ok
  end

  @doc "Every registered route."
  @spec routes() :: {:ok, [%{name: name(), port: :inet.port_number()}]} | {:error, error()}
  def routes do
    case control(:get, "/routes", nil) do
      {:ok, 200, %{"routes" => routes}} ->
        {:ok, Enum.map(routes, fn %{"name" => n, "port" => p} -> %{name: n, port: p} end)}

      {:ok, _status, _body} ->
        {:error, "unexpected control response"}

      {:error, :no_daemon} ->
        {:error, :no_daemon}
    end
  end

  @doc "The daemon's bound proxy port, when one is answering."
  @spec daemon_port() :: {:ok, :inet.port_number()} | :error
  def daemon_port do
    with {:ok, %{port: port}} <- State.read(),
         {:ok, 200, %{"ok" => true}} <- control_on(port, :get, "/healthz", nil) do
      {:ok, port}
    else
      _stale_or_missing -> :error
    end
  end

  # --- control-plane HTTP, stdlib only ---------------------------------------

  defp control(method, path, body) do
    case State.read() do
      {:ok, %{port: port}} -> control_on(port, method, path, body)
      :error -> {:error, :no_daemon}
    end
  end

  defp control_on(port, method, path, body) do
    url = ~c"http://127.0.0.1:#{port}#{path}"
    headers = [{~c"host", ~c"cherrypicker.localhost"}]

    request =
      case body do
        nil -> {url, headers}
        json -> {url, headers, ~c"application/json", json}
      end

    case :httpc.request(method, request, [timeout: 2_000], body_format: :binary) do
      {:ok, {{_http, status, _reason}, _headers, response}} ->
        {:ok, status, decode(response)}

      {:error, _reason} ->
        {:error, :no_daemon}
    end
  end

  defp decode(response) do
    JSON.decode!(response)
  rescue
    _error -> %{}
  end

  # Port 80 disappears from the printed URL; anything else stays.
  defp visible_url(url) do
    case State.read() do
      {:ok, %{port: 80}} -> url
      {:ok, %{port: port}} -> url <> ":#{port}"
      :error -> url
    end
  end
end
