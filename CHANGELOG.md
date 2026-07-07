# Changelog

All notable changes to apx are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `apx uninstall` grew a categorized `--purge` flag so users can fully
  remove apx. Categories: `binaries`, `share`, `state`, `config`, `claude`,
  `completions`, `source`. Combine with `--dry-run` to preview and
  `--yes` to skip the confirmation prompt. The default `apx uninstall`
  (no flags) still just stops the LaunchAgent.
- `apx uninstall --purge=claude` scrubs `ANTHROPIC_BASE_URL` from
  `~/.claude/settings.json` while preserving every other key.
- `apx completions install [--shell bash|zsh|fish]` writes the completion
  script to the canonical location for that shell. `apx completions
  uninstall` removes any files installed by that command.
- `apx update --dry-run` previews git and installer changes.
- `apx update` prints a post-flight summary (old → new version,
  source clone path, whether shell completions look stale).
- `install.sh --purge` alias for `--uninstall`; delegates to
  `apx uninstall --purge --yes` when the CLI is present so there is a
  single canonical uninstall path.

### Changed

- Binaries are now installed via `install -m 0755` (atomic
  write-then-rename) instead of `cp` + `chmod`. An interrupted upgrade
  can no longer leave a partially-written executable on disk.
- Deleted migration/deprecation-shim code (`migrate_legacy`,
  `install_legacy_shim`, `LEGACY_*` constants, per-key
  `AI_PROXY_STACK_*` env fallbacks, `SQUEEZR_CMD` / `GATEWAY_CMD`
  rewrite blocks in `load_config`). v0.1 has never been released
  publicly, so nothing depended on them; keeping them was pure
  maintenance drag.
- `apx uninstall --purge=source` refuses to delete the source clone
  when the running `apx` binary lives inside it, and prints the exact
  `rm -rf` command to run manually afterwards.

- Chain-based routing. `APX_CHAIN` in `config.env` is a comma-separated
  ordered list of local services between the gateway and the upstream.
  All `*_ENABLED` and `*_TARGET_API_URL` values are derived from it.
  Presets in `apx mode` compile down to chains; new `apx chain get/set/
  clear/ls/preset` subcommands expose the primitive for arbitrary orderings.
  Legacy `apx mode` names remain valid aliases.
- `~/.config/apx/prices.env` can override the built-in per-million-token
  cost table without a version bump.
- `APX_METRICS_ENABLED` gates the Prometheus `/metrics` endpoint (default 0).
- `APX_MAX_REQUEST_BYTES` caps the proxied request body size (default 64 MiB).
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

- The gateway now discovers streamable log files by scanning `$LOG_DIR/*.log`
  instead of using a hardcoded allowlist.
- Dashboard auth accepts Bearer header or `?token=` query parameter only.
  The undocumented cookie path was removed.
- Streaming SSE responses use `resp.read1(65536)` so the first token from the
  model reaches the client the moment the upstream emits it. Buffered JSON
  responses still use blocking reads.
- Token extraction now captures up to 2 MiB of the response body for SSE
  streams so `message_delta` frames near the end of long completions are
  reliably parsed.
- Concurrent `/api/logs/stream` connections per client IP are capped by
  `APX_MAX_LOG_STREAMS_PER_IP` (default 8).
- Response `x-frame-options` and `content-security-policy` headers are
  stripped on `/proxy/pxpipe/*` and `/proxy/squeezr/*` so the dashboard
  iframes render.
- Legacy `AI_PROXY_STACK_*` environment variable fallbacks now only cover
  the load-bearing paths (`APX_ROOT`, `APX_CONFIG`, `APX_STATE`). Tuning
  knobs like `APX_LABEL`, `APX_REPO_URL`, etc. use the `APX_*` names only.

### Removed

- Hand-coded mode permutations in `bin/apx` (`set_mode` case statements)
  and `bin/apx-gateway` (`_current_mode`, `_chain_hops`). Both now compute
  routing from a single `APX_CHAIN` list plus a small service registry.

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
