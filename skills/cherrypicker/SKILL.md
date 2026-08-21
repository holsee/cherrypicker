---
name: cherrypicker
description: Give local dev servers stable named .localhost URLs through the cherrypicker daemon and CLI. Use when an agent starts long-running dev servers and needs predictable URLs across restarts, when port numbers collide or wander, or when registering an app with a running cherrypicker daemon from the shell or from Elixir. Do not use for production serving or for exposing anything beyond the local machine.
---

# cherrypicker

Use the `cherrypicker` CLI to give local dev servers stable named URLs: `http://<name>.localhost` instead of a port number that changes between runs. The daemon is a loopback reverse proxy; apps register `{name, port}` with it — nothing is wrapped, spawned, or port-injected.

## Start safely

1. Run `cherrypicker version`. If it fails, stop and report that cherrypicker must be installed: `mix escript.install hex cherrypicker` (or `mix escript.install github holsee/cherrypicker`), with `~/.mix/escripts` on `PATH`.
2. Check for a running daemon with `cherrypicker ls --json`. Exit `0` means a daemon is up; exit `1` with `"no daemon is running"` means you must start one.
3. Add `--json` to every scripted call. Envelopes always carry `ok` and `command`; failures put the reason in `error`. Exit codes: `0` success, `1` the command ran and failed, `2` usage error.

## Run the daemon

`cherrypicker start` runs the proxy in the **foreground** — in automation, background it, and stop it when the session's work is done. The default port 80 gives bare URLs (`http://docs.localhost`) but needs privileges on Linux; when 80 is refused or taken, use `--port N` (URLs gain a fixed `:N` suffix) or `--port 0` for any free port. The bound port is in the start envelope and in the state file `~/.cherrypicker/daemon.json` (`CHERRYPICKER_HOME` overrides the directory — set it in tests to avoid touching the user's real daemon).

Routes live in memory: a restarted daemon starts empty, so re-register after restarting it.

## Route

```text
cherrypicker route NAME PORT      # returns the URL to use
cherrypicker unroute NAME
cherrypicker ls
```

- Names are lowercase DNS labels, dots allowed (`api.myapp`); `cherrypicker` is reserved.
- Registering an existing name replaces its port — re-register freely after an app restarts on a new port; never treat "name already exists" as a failure mode, it does not exist.
- Use the URL from the `route` envelope verbatim; do not reconstruct it by guessing the proxy port.
- SSE and live-reload connections stream through named URLs; do not fall back to port URLs for them.

## From Elixir

The `cherrypicker` hex package is a zero-cost client (stdlib only, no processes, no ports opened):

```elixir
case Cherrypicker.register("mysite", port) do
  {:ok, url} -> url                  # advertise this
  {:error, :no_daemon} -> :fallback  # use the port URL; this is normal, not an error
  {:error, reason} -> reason         # daemon refused (bad name); report it
end
```

Also `Cherrypicker.unregister/1` (always `:ok`), `Cherrypicker.routes/0`, `Cherrypicker.daemon_port/0`, and `{Cherrypicker.Daemon, port: N}` to embed the proxy in a supervision tree. Cherry sites: prefer `cherry serve --name mysite`, which does the registration and fallback itself.

## Interpret failures

- `no daemon is running`: start one or fall back to port URLs; never invent a URL.
- `invalid name: X` / `X is reserved`: fix the name; the daemon's reason says which rule broke.
- HTTP `404` from a named URL: the name is not routed — the body lists what is.
- HTTP `502`: the route exists but nothing answered on its port; the app behind it is down.
- The full HTTP control API (for raw curl or non-BEAM clients) is documented at https://holsee.github.io/cherrypicker/api/ — select it with the `Host: cherrypicker.localhost` header on the proxy port.
