# Changelog

All notable changes to cherrypicker are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning follows SemVer.

## [Unreleased]

### Fixed
- The proxy releases abandoned idle streams: the client socket is watched in
  `active: :once` while a monitored reader pulls from the upstream, so a
  browser closing a silent SSE or long-poll connection frees the socket, the
  handler process, and the upstream connection immediately. Previously all
  three leaked forever, since a vanished client was only noticed on a failed
  write that an idle stream never makes. (#12)

## [0.1.0] — 2026-08-21

First release on [Hex](https://hex.pm/packages/cherrypicker).

### Added
- The daemon: Bandit listener with Host-header routing, ETS route registry,
  streaming HTTP proxy (SSE and live-reload safe), and the JSON control API
  on the reserved `cherrypicker.localhost` host. (#2)
- CLI verbs `start`, `route`, `unroute`, `ls`, `version`, all with `--json`
  envelopes; exit codes 0/1/2. (#2)
- Zero-cost Elixir client (`Cherrypicker.register/2`, `unregister/1`,
  `routes/0`, `daemon_port/0`), stdlib only. (#2)
- State-file discovery in `~/.cherrypicker/daemon.json`, `CHERRYPICKER_HOME`
  override, stale files detected via `/healthz`. (#2)
- Project site at [holsee.github.io/cherrypicker](https://holsee.github.io/cherrypicker/)
  with the full API reference, built with Cherry. (#2)
- Agent skill (`skills/cherrypicker/SKILL.md`). (#3)
