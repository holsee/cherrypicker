<p align="center">
  <img src="https://raw.githubusercontent.com/holsee/cherrypicker/main/assets/cherrypicker-640.png" alt="The cherrypicker logo: a cherry driving a cherry picker" width="420">
</p>

<p align="center">
  <strong>Stable named <code>.localhost</code> URLs for local dev servers.</strong><br>
  For humans and agents, on the BEAM — no Node, no npm, no root CA.
</p>

<p align="center">
  <a href="https://hex.pm/packages/cherrypicker"><img src="https://img.shields.io/hexpm/v/cherrypicker.svg" alt="Hex version"></a>
  <a href="https://hexdocs.pm/cherrypicker"><img src="https://img.shields.io/badge/hex-docs-8e7ce6.svg" alt="Hex docs"></a>
  <a href="https://github.com/holsee/cherrypicker/actions/workflows/ci.yml"><img src="https://github.com/holsee/cherrypicker/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="#licence"><img src="https://img.shields.io/badge/licence-MIT%20or%20Apache--2.0-blue.svg" alt="Licence: MIT or Apache-2.0"></a>
</p>

<p align="center">
  <a href="https://holsee.github.io/cherrypicker/">Website</a> ·
  <a href="https://holsee.github.io/cherrypicker/api/">API reference</a> ·
  <a href="https://github.com/holsee/cherrypicker/blob/main/DESIGN.md">Design</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

Port numbers wander between runs and read like noise (`localhost:5173` means
nothing). Names do not. cherrypicker is a tiny loopback reverse proxy: tell it
`docs` lives on port 8080 and `http://docs.localhost` works in every browser.

```text
$ cherrypicker start
proxy up — routes serve at http://<name>.localhost (Ctrl-C to stop)
```

```text
$ cherrypicker route docs 8080
http://docs.localhost
```

`*.localhost` already resolves to loopback on Windows, macOS, and systemd
Linux — no DNS setup, no hosts-file edits, no root certificate, no Node.

## Install

From Hex:

```sh
mix escript.install hex cherrypicker
```

Or straight from source:

```sh
mix escript.install github holsee/cherrypicker
```

Both install the `cherrypicker` binary into `~/.mix/escripts` — make sure
that directory is on your `PATH`. To use only the Elixir client library, skip
the escript and add the dependency (see [From Elixir](#from-elixir)).

### Agent skill

The repo ships an agent skill
([`skills/cherrypicker/SKILL.md`](https://github.com/holsee/cherrypicker/blob/main/skills/cherrypicker/SKILL.md)) that teaches
coding agents the daemon lifecycle, the register model, and the `--json`
envelopes:

```sh
gh skill install holsee/cherrypicker
```

## The daemon

Everything routes through one long-running process:

```sh
cherrypicker start
```

That binds port **80**, which is what makes the URLs bare. Windows and
modern macOS let a normal user bind 80; on Linux it needs
`cap_net_bind_service` or a different port. When 80 is taken or refused:

```text
$ cherrypicker start --port 7777
proxy up — routes serve at http://<name>.localhost:7777 (Ctrl-C to stop)
```

URLs then carry the `:7777` suffix, once and permanently — the names stay
stable either way. `--port 0` binds any free port.

On start the daemon writes its bound port to `~/.cherrypicker/daemon.json`
(override the directory with `CHERRYPICKER_HOME`); every client finds it
through that file, so there is nothing to configure. The file is removed on
clean shutdown. The daemon runs in the foreground — stop it with Ctrl-C.
Routes live in memory and are gone when it stops.

The daemon binds loopback only: nothing is reachable from other machines.

## Working with routes

cherrypicker never wraps or spawns your app — the **register model**. Start
your dev server however you normally do, then say where it is:

```text
$ cherrypicker route docs 8080
http://docs.localhost
```

```text
$ cherrypicker ls
cherry.localhost → 127.0.0.1:4000
docs.localhost → 127.0.0.1:8080
```

```text
$ cherrypicker unroute docs
docs unrouted
```

Registering an existing name replaces its port — exactly what a dev server
restarting on a new port wants. Names are lowercase DNS labels (dots allowed:
`api.myapp`); `cherrypicker` is reserved for the control API.

Every verb takes `--json` for a machine-readable envelope, and exit codes are
`0` success / `1` failure / `2` usage — built for agents as much as humans:

```text
$ cherrypicker ls --json
{"command":"ls","ok":true,"routes":[{"name":"cherry","port":4000}]}
```

Requests to a named URL stream through chunk by chunk in both directions, so
SSE and live-reload connections stay live. See the
[API reference](https://holsee.github.io/cherrypicker/api/) for the complete
CLI, proxy, and HTTP control-API contract.

## From Elixir

Add the client to any BEAM app:

```elixir
{:cherrypicker, "~> 0.1"}
```

The client is deliberately **zero-cost**: it uses only the standard library,
starts no processes, and never opens a port as a side effect of being in a
deps list. Register your app's server at startup:

```elixir
case Cherrypicker.register("mysite", port) do
  {:ok, url} -> IO.puts("also at " <> url)
  {:error, :no_daemon} -> :ok   # fall back to the port URL
end
```

`{:error, :no_daemon}` is the designed quiet path — no daemon running costs
one failed connect and your app prints its port URL as ever. Also available:
`Cherrypicker.unregister/1`, `Cherrypicker.routes/0`, and
`Cherrypicker.daemon_port/0`.

A host app can also embed the daemon itself in its supervision tree:

```elixir
children = [
  {Cherrypicker.Daemon, port: 8080}
]
```

[Cherry](https://cherrybomb.dev) sites get all of this built in as
`cherry serve --name mysite`.

## Why not portless?

[portless](https://github.com/vercel-labs/portless) proved the idea. It is
also a global npm install that self-elevates and installs a root CA — a
maximal supply-chain surface — and it wraps your dev server as a child
process, injecting per-framework port flags. cherrypicker is the BEAM
answer: two runtime dependencies (Bandit, Finch), no Node, no certificate
authority until TLS ships as an explicit opt-in, and no process wrapping —
apps register themselves.

## Status

HTTP proxying with full streaming (SSE and live-reload safe) works and is
tested on Linux and Windows. TLS via an opt-in local CA, WebSocket
passthrough, and background daemonization are designed but not built — see
[DESIGN.md](DESIGN.md).

## Licence

MIT or Apache-2.0, at your option.
