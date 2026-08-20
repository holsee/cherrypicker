defmodule Cherrypicker.Control do
  @moduledoc """
  The control API, served on the reserved `cherrypicker.localhost` host:

      GET    /healthz            → 200 {"ok":true,"version":…}
      GET    /routes             → 200 {"routes":[{"name":…,"port":…}]}
      PUT    /routes/:name       → 200|400, body {"port":4000}
      DELETE /routes/:name       → 200

  Loopback-only by construction: the daemon binds 127.0.0.1/::1-facing
  ports and `.localhost` names never resolve off-machine, so the API's
  trust boundary is "processes on this machine" — the same boundary any
  local dev server already has.
  """

  @behaviour Plug

  import Plug.Conn

  alias Cherrypicker.Routes

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    handle(conn.method, conn.path_info, conn)
  end

  defp handle("GET", ["healthz"], conn) do
    version = Application.spec(:cherrypicker, :vsn) |> to_string()
    json(conn, 200, %{ok: true, version: version})
  end

  defp handle("GET", ["routes"], conn) do
    json(conn, 200, %{routes: Routes.list()})
  end

  defp handle("PUT", ["routes", name], conn) do
    {:ok, body, conn} = read_body(conn)

    with {:ok, %{"port" => port}} <- decode(body),
         :ok <- Routes.put(name, port) do
      json(conn, 200, %{ok: true, name: name, port: port, url: "http://#{name}.localhost"})
    else
      {:error, message} -> json(conn, 400, %{ok: false, error: message})
      _malformed -> json(conn, 400, %{ok: false, error: ~s(body must be {"port": N})})
    end
  end

  defp handle("DELETE", ["routes", name], conn) do
    :ok = Routes.delete(name)
    json(conn, 200, %{ok: true, name: name})
  end

  defp handle(_method, _path, conn) do
    json(conn, 404, %{ok: false, error: "no such endpoint"})
  end

  defp decode(body) do
    {:ok, JSON.decode!(body)}
  rescue
    _error -> {:error, :malformed}
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(payload))
  end
end
