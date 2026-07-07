# Changelog

All notable changes to apx are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Gateway now stamps `X-Apx-Request-Id` on every proxied request. The id is
  echoed back to the client, logged, persisted in history, and available on
  the dashboard.
- Chunked-transfer-encoded request bodies are supported (previously only
  `Content-Length` requests were forwarded correctly).
- Background health probe thread; `/api/status` returns cached snapshots
  instantly instead of blocking up to 4.5s on synchronous probes.
- Gateway passthrough routes at `/proxy/pxpipe/*` and `/proxy/squeezr/*` so
  the dashboard iframes work from inside a devcontainer that reaches the
  gateway over `host.docker.internal`.
- Per-day JSONL history at `~/.local/state/apx/history/YYYY-MM-DD.jsonl`.
  Set `APX_HISTORY_PERSIST=0` to disable.
- Cost + token estimation: gateway parses Anthropic/OpenAI `usage` fields on
  both JSON and SSE responses and reports `tokens_in`, `tokens_out`, and
  `cost_est_usd` per request. Session totals appear on the dashboard.
- Optional dashboard authentication via `APX_DASHBOARD_TOKEN` (Bearer,
  cookie, or `?token=` query string). Non-loopback binds without a token
  refuse to start.
- Prometheus-compatible `/metrics` endpoint.
- `apx completions {bash,zsh,fish}` subcommand emits shell completion
  scripts.
- `apx update --to <ref>`, `--to-latest`, and `--force` for detached HEAD
  and dirty source clones.
- CI workflow (`.github/workflows/ci.yml`): `bash -n`, `shellcheck`,
  `python -m py_compile`, help/completions smoke tests.

### Changed

- Concurrent `/api/logs/stream` connections per client IP are capped by
  `APX_MAX_LOG_STREAMS_PER_IP` (default 8).
- Response `x-frame-options` and `content-security-policy` headers are
  stripped on `/proxy/pxpipe/*` and `/proxy/squeezr/*` so the dashboard
  iframes render.
- Legacy `AI_PROXY_STACK_*` environment variables are still honored as
  fallbacks for one release cycle.

## [0.1.0] - 2026-07-07

### Added

- Rebranded to `apx`. Commands are `apx`, `apx-gateway`, `apx-squeezr`;
  legacy `ai-proxy-stack*` binaries remain as deprecation shims.
- Unified dashboard served by `apx-gateway` at
  `http://127.0.0.1:8787/`, aggregating mode, health, request history,
  Headroom stats, live log tails, and iframed pxpipe/Squeezr dashboards.
- Versioning: top-level `VERSION` file, `apx version`,
  `apx check-updates`, `apx update` commands.
- One-line install via `bootstrap.sh`.
- GitHub Actions release workflow that verifies the tag matches
  `VERSION` and publishes a tarball + sha256.
- Renamed `full` mode to `headroom-pxpipe`; `full` is a deprecated alias.
