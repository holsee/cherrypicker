# cherrypicker — design

Stable named local URLs as BEAM infrastructure: a loopback reverse proxy, a
route registry, and a zero-dependency client, shaped so host applications can
depend on it without cost or ceremony.

## 1. The problem

Local dev servers live on ports; ports collide, wander between runs, and read
like noise (`localhost:5173` means nothing). portless solved this for the npm
world with named `.localhost` URLs, but its shape — global npm install,
self-elevation to bind 443, a locally trusted root CA, and per-framework
`--port` flag injection — is both a large supply-chain surface and a moving
compatibility target.

## 2. Principles

- **Register, don't wrap.** Wrapping child processes is the BEAM's weakest
  cross-platform spot (no PTY on Windows, awkward signal forwarding) and flag
  injection is a compatibility treadmill. Apps start themselves and register
  `{name, port}`; the daemon only proxies.
- **The library must cost nothing.** `Cherrypicker` (the client) uses only the
  standard library (`:httpc`, `JSON`), so a host app taking the dependency
  adds no runtime processes, no pool, no supervision — and never opens a port
  as a side effect of being in a deps list.
- **Loopback is the trust boundary.** The daemon binds loopback-facing ports
  and `.localhost` never resolves off-machine. The control API is therefore as
  trusted as any local dev server — no auth theatre in phase 1.
- **Honest degradation.** No daemon → `{:error, :no_daemon}` → callers print
  their port URL as ever. A stale state file costs one failed connect, never a
  wrong answer.

## 3. Architecture

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

- **Routing is the Host header.** `<name>.localhost[:port]` → `name`; the
  reserved name `cherrypicker` serves the control API on the same listener, so
  there is exactly one port and `http://cherrypicker.localhost` is a future
  human dashboard for free.
- **Streaming both ways.** Responses are forwarded chunk-by-chunk
  (`Finch.stream/5` with an infinite receive timeout), so SSE — dev-server
  live reload — stays live. A client that disconnects mid-stream throws out of
  the stream fold, which is what stops the upstream pull.
- **`X-Forwarded-Host`** carries the raw named host so upstreams can emit
  browser-correct links; hop-by-hop headers are stripped per RFC 9110.
- **Ephemeral-capable.** `port: 0` binds a free port and the state file
  advertises it — tests and multi-instance setups need no coordination.

## 4. Phases

**Phase 1 (built):** daemon, registry, streaming HTTP proxy, control API,
state-file discovery, stdlib client, escript CLI with `--json` envelopes.

**Phase 2 — TLS, opt-in:** `cherrypicker trust` generates a local CA (the
`x509` library over OTP `:public_key`) and installs it via the platform's own
tool (`certutil`, `security add-trusted-cert`, distro trust stores); the
proxy then terminates HTTPS with per-name leaf certs minted on demand.
Documented `mkcert` interop as the escape hatch. Never a silent side effect of
any other verb.

**Phase 3 — polish:** WebSocket passthrough (Bandit upgrade + Mint WS),
background daemonization per platform, route persistence across restarts,
Burrito binaries with checksums + provenance (the cherry release pipeline,
reused), `cherrypicker.localhost` dashboard page.

## 5. Non-goals

Production serving, TLS termination for deployed sites, tunneling to the
public internet, and process management of the apps behind routes.
