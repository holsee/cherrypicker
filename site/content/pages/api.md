---
title: API reference
description: The complete cherrypicker surface, CLI verbs, control API and Elixir library.
---

Three ways in, one behaviour: the CLI verbs, the HTTP control API and the
Elixir library all speak to the same route table. Anything the CLI can do,
an agent can do with `--json`, and any HTTP client can do directly.

## CLI verbs

```text
cherrypicker start [--port N]     # run the proxy (foreground)
cherrypicker route NAME PORT      # name → 127.0.0.1:PORT
cherrypicker unroute NAME
cherrypicker ls
cherrypicker version
```

Every verb takes `--json` for a machine-readable envelope. Exit codes: `0`
success, `1` the command ran and failed, `2` usage error.

### start

Runs the proxy in the foreground. The default port is 80, which gives bare
URLs; any `--port` works where 80 needs privileges or is taken.

```text
$ cherrypicker start --port 7777
proxy up — routes serve at http://<name>.localhost:7777 (Ctrl-C to stop)
```

On start the daemon writes its bound port to the state file
(`~/.cherrypicker/daemon.json`, or under `$CHERRYPICKER_HOME` when set) and
removes it on clean shutdown. `--port 0` binds an ephemeral free port, which
the state file then advertises.

### route

Registers a name against a loopback port and prints the named URL.

```text
$ cherrypicker route docs 8080
http://docs.localhost
```

Names must be lowercase DNS labels: letters, digits and inner hyphens, with
dots allowed for subdomain-style names (`api.myapp`). `cherrypicker` itself
is reserved for the control API. Registering an existing name replaces its
port, which is exactly what a dev server restarting on a new port wants.

### unroute, ls, version

```text
$ cherrypicker ls
cherry.localhost → 127.0.0.1:4000
docs.localhost → 127.0.0.1:8080
```

```text
$ cherrypicker unroute docs
docs unrouted
```

```text
$ cherrypicker version
cherrypicker 0.1.0
```

### JSON envelopes

Every verb takes `--json`; envelopes always carry `ok` and `command`.

```text
$ cherrypicker ls --json
{"command":"ls","ok":true,"routes":[{"name":"cherry","port":4000}]}
```

Failures put the reason in `error` and exit `1`:

```json
{
  "ok": false,
  "command": "route",
  "error": "no daemon is running — start one with: cherrypicker start"
}
```

## HTTP control API

The control API lives on the proxy's own listener, selected by the `Host`
header `cherrypicker.localhost`, so with a running daemon these URLs work
from a browser or curl as written. Requests and responses are JSON. The
route table is in memory: routes are gone when the daemon stops.

### GET /healthz

Liveness probe, used by clients to detect stale state files.

```json
{ "ok": true, "version": "0.1.0" }
```

### GET /routes

Every registered route.

```json
{
  "routes": [
    { "name": "cherry", "port": 4000 },
    { "name": "docs", "port": 8080 }
  ]
}
```

### PUT /routes/:name

Registers or replaces a route. The body names the loopback port; the
response carries the named URL (bare when the proxy holds port 80).

```text
$ curl -X PUT http://cherrypicker.localhost/routes/docs \
       -H "content-type: application/json" -d '{"port":8080}'
{"name":"docs","ok":true,"port":8080,"url":"http://docs.localhost"}
```

Invalid names and ports return `400` with the reason:

```json
{ "ok": false, "error": "invalid name: Bad_Name" }
```

### DELETE /routes/:name

Removes a route. Deleting an absent route succeeds.

```json
{ "ok": true, "name": "docs" }
```

## Proxy behaviour

- Requests to `http://<name>.localhost[:port]` stream to `127.0.0.1:<port>`
  chunk by chunk in both directions, so server-sent events and live-reload
  connections stay open through the named URL.
- `X-Forwarded-Host` carries the original named host, so upstreams can emit
  browser-correct links. Hop-by-hop headers are stripped per RFC 9110.
- An unrouted name gets a `404` naming what is routed; a routed name whose
  app is down gets a `502` saying nothing answered there.

## Elixir library

The `Cherrypicker` module is the client: it finds the daemon through the
state file and speaks the control API using only the standard library, so
depending on it adds no processes, no pool and no open ports to your app.

```elixir
{:cherrypicker, "~> 0.1"}
```

### Cherrypicker.register(name, port)

Registers `name` to proxy to `127.0.0.1:port`, returning the named URL.

```elixir
@spec register(String.t(), :inet.port_number()) ::
        {:ok, String.t()} | {:error, :no_daemon | String.t()}
```

`{:error, :no_daemon}` means no daemon is reachable; callers treat that as
"fall back to the port URL", never as a failure. A `String.t()` error is the
daemon refusing the route (invalid or reserved name, bad port).

### Cherrypicker.unregister(name)

Removes a route. Absent routes and absent daemons are fine; always `:ok`.

```elixir
@spec unregister(String.t()) :: :ok
```

### Cherrypicker.routes()

Every registered route.

```elixir
@spec routes() ::
        {:ok, [%{name: String.t(), port: :inet.port_number()}]}
        | {:error, :no_daemon | String.t()}
```

### Cherrypicker.daemon_port()

The daemon's bound proxy port, when one is answering. Reads the state file,
then probes `/healthz`, so a stale file reports `:error` rather than a wrong
answer.

```elixir
@spec daemon_port() :: {:ok, :inet.port_number()} | :error
```

### Embedding the daemon

A host app can run the proxy in its own supervision tree instead of the
CLI:

```elixir
children = [
  {Cherrypicker.Daemon, port: 8080}
]
```

Options: `port` (default 80; `0` binds an ephemeral port),
`shutdown_timeout` (milliseconds of grace for in-flight requests on
shutdown, default 15000) and `state_file?` (default `true`; set `false` for
an embedded proxy that other clients should not discover).
`Cherrypicker.Daemon.port/0` returns the port actually bound.
