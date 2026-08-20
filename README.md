# cherrypicker

Stable named `.localhost` URLs for local dev servers. For humans and agents, on the BEAM.

```text
$ cherrypicker start --port 7777
proxy up — routes serve at http://<name>.localhost:7777 (Ctrl-C to stop)

$ cherrypicker route mysite 4000
http://mysite.localhost:7777
```

Port numbers wander; names do not. `*.localhost` resolves to loopback natively on
Windows, macOS, and systemd Linux — no DNS setup, no hosts-file edits.

## Why not portless?

[portless](https://github.com/vercel-labs/portless) proved the idea. It is also a
global npm install that self-elevates and installs a root CA — a maximal
supply-chain surface. cherrypicker is the BEAM answer: two runtime dependencies
(Bandit, Finch), no Node, no npm, and no certificate authority until the day TLS
ships as an explicit opt-in.

## The register model

cherrypicker never wraps or spawns your app. Apps start themselves and say where
they are:

```text
cherrypicker route mysite 4000     # from a shell
```

```elixir
# or from any BEAM app, with the zero-cost client:
case Cherrypicker.register("mysite", port) do
  {:ok, url} -> IO.puts("also at " <> url)
  {:error, :no_daemon} -> :ok   # fall back to the port URL
end
```

No PORT-injection guesswork, no per-framework flag taxonomy, nothing to break
when a CLI changes its flags. [Cherry](https://github.com/holsee/cherry) sites
get this via `cherry serve --name mysite`.

## Verbs

| verb | does |
|---|---|
| `start [--port N]` | run the proxy in the foreground (default port 80; 80 needs privileges, any `--port` works) |
| `route NAME PORT` | `http://NAME.localhost[:proxy port]` → `127.0.0.1:PORT` |
| `unroute NAME` | remove a route |
| `ls` | list routes |
| `version` | version |

Every verb takes `--json`. Exit codes: `0` success, `1` failure, `2` usage.

## Install

```sh
mix escript.install github holsee/cherrypicker
```

Or as a dependency for the client API: `{:cherrypicker, github: "holsee/cherrypicker"}`.

## Status

Early. HTTP proxying with full streaming (SSE and live-reload safe) works and is
tested; TLS via a local CA, WebSocket passthrough, and background daemonization
are designed but not built — see [DESIGN.md](DESIGN.md).

## Licence

MIT or Apache-2.0, at your option.
