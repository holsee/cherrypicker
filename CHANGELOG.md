# Changelog

All notable changes to cherrypicker are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning follows SemVer.

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
