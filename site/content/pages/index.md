---
title: Home
description: Stable named .localhost URLs for local dev servers, on the BEAM.
---

<section class="hero">
<img class="hero-mark" src="brand/cherrypicker.png" alt="The cherrypicker logo: a cherry driving a cherry picker" width="320" height="320">
<h1>Names for<br>your <em>ports</em></h1>
<p class="hero-tagline">Stable named <code>.localhost</code> URLs for local dev servers, on the BEAM. No DNS setup, no hosts-file edits, no root certificate and no Node.</p>
<p class="hero-actions"><a class="button" href="api/">API reference</a> <a class="button button-ghost" href="https://github.com/holsee/cherrypicker">GitHub</a></p>
<div class="cmd" data-copy><span class="cmd-os">escript</span><code>mix escript.install hex cherrypicker</code></div>
<div class="cmd" data-copy><span class="cmd-os">mix.exs, client only</span><code>{:cherrypicker, "~> 0.1"}</code></div>
</section>

Port numbers wander between runs and read like noise; names do not.
cherrypicker is a tiny reverse proxy for your own machine: tell it `mysite`
lives on port 4000 and `http://mysite.localhost` works in every browser.

```text
$ cherrypicker start
proxy up — routes serve at http://<name>.localhost (Ctrl-C to stop)
```

```text
$ cherrypicker route docs 8080
http://docs.localhost
```

## How it works

Three parts, one idea: **apps register themselves, the proxy only proxies.**

```text
~/.cherrypicker/daemon.json         (state file: the bound proxy port)
        ▲ write on start / remove on stop        ▼ read by clients
┌────────────────────── Cherrypicker.Daemon ─────────────────────┐
│ Routes (GenServer + ETS)   Finch pool   Bandit :80/:N          │
│                                            │                   │
│   Host: cherrypicker.localhost → Control (REST, JSON)          │
│   Host: <name>.localhost       → Proxy → 127.0.0.1:<port>      │
└────────────────────────────────────────────────────────────────┘
      ▲ PUT /routes/:name          ▲ GET http://mysite.localhost
      │ CLI verbs / library client │ browser / curl / agent
```

**1. Names resolve for free.** Every hostname ending in `.localhost` already
resolves to your loopback address on Windows, macOS and systemd Linux, and
browsers treat it as a secure context. cherrypicker invents no DNS; it simply
listens on one port and reads the `Host` header of each request. A request
for `docs.localhost` looks up `docs` in the route table and streams the
request to `127.0.0.1:8080`. The reserved name `cherrypicker.localhost` is
the daemon's own control API on the same listener, so there is exactly one
port to think about.

**2. The daemon is found through a state file.** On start the daemon writes
its bound port to `~/.cherrypicker/daemon.json` and removes it on shutdown.
Clients (the CLI verbs, the Elixir library, or anything that can speak HTTP)
read that file and talk to the control API. No daemon running costs a client
exactly one failed connect, and it falls back to plain port URLs. Nothing
breaks; you just lose the pretty names until the daemon is back.

**3. Apps register, nothing gets wrapped.** Tools like portless wrap your dev
server as a child process and inject port flags, which means guessing every
framework's flag taxonomy and inheriting every process-management quirk.
cherrypicker refuses all of that: your app starts however it starts, then
says where it is with `cherrypicker route mysite 4000`, one HTTP call to the
control API, or a library call from inside the app itself. The proxy streams
responses chunk by chunk, so server-sent events and live-reload connections
stay live through the named URL.

The default port is 80, which is what makes the URLs bare. Where 80 needs
privileges or is taken, start with `--port N` and URLs carry the suffix
once, permanently: `http://docs.localhost:7777`. Everything is loopback
only; nothing is reachable from off your machine.

The whole surface is five verbs and four HTTP endpoints: the
[API reference](api/) covers every one, with the JSON envelopes agents use.

## From Elixir

Any BEAM app can register itself with the zero-cost client, which uses only
the standard library:

```elixir
case Cherrypicker.register("mysite", port) do
  {:ok, url} -> IO.puts("also at " <> url)
  {:error, :no_daemon} -> :ok
end
```

[Cherry](https://cherrybomb.dev) sites get this built in as
`cherry serve --name mysite`.

## Read on

- [API reference](api/): CLI verbs, control API, and the Elixir library.
- [Design](https://github.com/holsee/cherrypicker/blob/main/DESIGN.md):
  principles, architecture and the TLS/WebSocket roadmap.
- [Source on GitHub](https://github.com/holsee/cherrypicker), MIT or
  Apache-2.0 at your option.
