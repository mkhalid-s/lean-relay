# apx

A local macOS proxy stack for Claude Code with a stable gateway, switchable routing modes, and a unified dashboard.

```text
Claude Code -> apx Gateway :8787 -> Headroom / pxpipe / Squeezr / Anthropic
```

Claude Code always talks to the Gateway. You can switch modes without changing Claude's base URL.

> The CLI, gateway, and squeezr helper are named `apx`, `apx-gateway`, and `apx-squeezr`. No legacy `ai-proxy-stack*` shims are installed.

## Quick Install

apx ships two install modes. Pick whichever matches how you work.

### Release mode (single-file installer, no git required)

**One-liner** (fetches `apx.sh`, verifies its SHA-256 against the checksum published in the same release, then runs it):

```bash
curl -fsSL https://github.com/mkhalid-s/ai-proxy-stack/releases/latest/download/get.sh | bash
```

`get.sh` is a ~2 KB bootstrap you can audit end-to-end before running (it never executes `apx.sh` unless the checksum matches). Pin a specific version or pass through installer flags:

```bash
# pin a version
curl -fsSL https://.../get.sh | APX_VERSION=v0.4.0 bash

# forward flags to apx.sh (e.g. do not start the LaunchAgent)
curl -fsSL https://.../get.sh | bash -s -- --no-service --skip-deps
```

**Manual (two-step)** if you'd rather download and verify yourself:

```bash
curl -fsSLO https://github.com/mkhalid-s/ai-proxy-stack/releases/latest/download/apx.sh
curl -fsSL  https://github.com/mkhalid-s/ai-proxy-stack/releases/latest/download/apx.sh.sha256 | shasum -a 256 -c -
bash apx.sh
```

`apx.sh` is a ~70 KB self-extracting bash installer that carries the runtime as an embedded base64 tarball. It installs into a versioned layout at `~/.local/share/apx/versions/vX.Y.Z/` and flips `~/.local/share/apx/current` to point at it. `~/.local/bin/apx*` are symlinks into `current/bin/`, so `apx use vX.Y.Z` and `apx rollback` are atomic.

Options:

```bash
bash apx.sh --print-version       # print embedded apx version and exit
bash apx.sh --no-service          # extract and set up files without starting launchd
bash apx.sh --skip-deps           # skip Homebrew/pipx dependency install
bash apx.sh --dry-run             # show what would happen; make no changes
bash apx.sh --force               # reinstall over an existing version
bash apx.sh --extract-to <dir>    # extract payload into <dir> and exit
```

Release-mode installs use `~/.config/apx/install.mode = release`, which switches `apx update` onto the release channel (verified download, no git clone required).

### Dev mode (git clone, hackable)

One-line install (clones into `~/.local/share/apx-src` and runs the installer):

```bash
curl -fsSL https://raw.githubusercontent.com/mkhalid-s/ai-proxy-stack/main/bootstrap.sh | bash
```

Pin a specific release tag:

```bash
APX_REF=v0.1.0 curl -fsSL https://raw.githubusercontent.com/mkhalid-s/ai-proxy-stack/main/bootstrap.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/mkhalid-s/ai-proxy-stack.git
cd ai-proxy-stack
./install.sh --yes
```

Preview installer actions without changing anything:

```bash
./install.sh --check-only
```

The installer copies runtime files to launchd-safe paths, installs safe dependencies when Homebrew is available, starts the LaunchAgent, and validates health.

Existing runtime config is preserved on reinstall. The installer backs it up and appends any new default keys, so local port/mode experiments are not overwritten.

## Dashboard

Open [http://127.0.0.1:8787/](http://127.0.0.1:8787/) after installing to see a single pane that aggregates every component. The dashboard is zero-build, self-contained, and served by `apx-gateway`.

It includes:

- gateway KPIs: request volume, status buckets, p95 latency, first-byte latency, token totals, cache token totals, estimated cost, and tool-call counts
- current mode, chain diagram, apx version, and capture-level badge
- a comparative tool view that normalizes Headroom, pxpipe, and Squeezr savings/cache/request data side-by-side
- session rollups and drill-in details keyed by `X-Apx-Session-Id`
- per-tool cards that appear only when the tool is enabled or reachable:
  - Headroom: lifetime/session tokens saved, savings percentage, request failures, cache hits/entries
  - pxpipe: saved input tokens, all-spend savings percentage, compressed-request coverage, A/B cost split, PNG throughput
  - Squeezr: saved tokens, expand-rate quality signal, mode/circuit-breaker state, latency p95, technique breakdown
- live log tail via SSE for each service (`supervisor`, `gateway`, `headroom`, `pxpipe`, `squeezr`)
- native pxpipe and Squeezr dashboards collapsed into accordions, so they do not load or take space until expanded

JSON APIs for scripting:

```text
GET /api/status                         overall mode + health + counters
GET /api/history?n=100                  in-memory gateway history
GET /api/metrics/summary?window=1h      request/status/token/cost aggregate
GET /api/metrics/timeseries?window=1h   bucketed latency/request/token series
GET /api/metrics/sessions?window=24h    grouped sessions
GET /api/metrics/session/<id>           per-request session detail
GET /api/tool/detect                    enabled/reachable/doing_work per tool
GET /api/tool/compare                   normalized Headroom/pxpipe/Squeezr rows
GET /api/tool/headroom                  Headroom /stats + Prometheus parse
GET /api/tool/pxpipe                    pxpipe /proxy-stats + /api/stats.json
GET /api/tool/squeezr                   Squeezr /health + /stats + /limits
GET /api/events/stream                  SSE fan-in for live dashboard updates
GET /api/logs/stream?service=gateway    Server-Sent Events log tail
```

Disable the dashboard entirely by setting `APX_DASHBOARD_ENABLED=0` in `~/.config/apx/config.env`. The gateway keeps proxying normally either way.

### Capture and Local Metrics

By default, apx records only metadata:

```bash
APX_CAPTURE=metadata
```

Metadata mode stores timing, status, path, model, request/session ids, token counts, cache token counts, byte counts, estimated cost, and tool-call count. It does **not** store request or response bodies.

Full capture is available for local debugging, but it is gated by an explicit acknowledgment:

```bash
APX_CAPTURE=full
APX_CAPTURE_FULL_ACK=i-understand
```

Full capture stores a truncated, redacted copy of request/response bodies in the local SQLite database. The gateway refuses to start if `APX_CAPTURE=full` is set without the acknowledgment. Known secret headers and common API-key/token/password fields are redacted before persistence.

Metrics are local-only:

```bash
APX_METRICS_DB="${HOME}/.local/state/apx/metrics.db"
APX_METRICS_RETENTION_DAYS=30
APX_METRICS_BACKFILL=1
```

Set `APX_METRICS_DB=""` (or `off`) to disable SQLite while keeping the existing JSONL history log.

## Updating

`apx update` picks the right update channel automatically based on how you installed:

- **Release mode** (`apx.sh` installer): downloads the newest `apx.sh` from GitHub Releases, verifies its SHA256 against the co-published `.sha256` file, and re-extracts into a fresh `~/.local/share/apx/versions/vX.Y.Z/`. The old version stays on disk so rollback is instant.
- **Dev mode** (git clone): `git fetch` and fast-forward the recorded source clone, then rerun `install.sh --yes`.

Common commands (work in both modes):

```bash
apx check-updates             # compare installed vs origin/main
apx update                    # update in place using the appropriate channel
apx update --dry-run          # release mode: fetch + verify; dev mode: preview git changes
apx update --to v0.2.0        # release mode: install a specific release tag
apx update --to-latest        # release mode: latest release (default)
apx update --force            # reinstall even if already at latest
apx version                   # show installed version, mode, and channel
```

Release-mode users get atomic version management:

```bash
apx versions                  # list installed versions (current marked *)
apx use v0.2.0                # switch to a previously-installed version (atomic)
apx rollback                  # switch to the previous version
apx cleanup --keep 2          # prune older versions, keep current + one previous
apx cleanup --keep 2 --dry-run
```

Version switches are a single `ln -sfn` on the `~/.local/share/apx/current` symlink. The LaunchAgent survives the swap because `APX_ROOT` is set to `~/.local/share/apx/current`, so restarting the service after `apx use` picks up the new binaries automatically.

After an update, if you had installed shell completions with `apx completions install`, `apx update` warns you when they look stale so you can refresh them:

```bash
apx completions install       # detects your shell
apx completions install --shell zsh
apx completions uninstall     # remove installed completion files
```

Dev-mode-specific: if you cloned somewhere non-default and moved the directory, either:

```bash
echo /new/path/to/apx-source > ~/.config/apx/source.path
apx update
```

or just rerun `./install.sh --yes` from the new clone.

Releases are cut with git tags of the form `vMAJOR.MINOR.PATCH` matching the `VERSION` file at the repo root. Every tagged build publishes both a source tarball and a self-extracting `apx.sh` (plus `apx.sh.sha256`) at [Releases](https://github.com/mkhalid-s/ai-proxy-stack/releases).

## Claude Code Setting

Inside a devcontainer, use the stable Gateway URL:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://host.docker.internal:8787"
  }
}
```

For host-only Claude sessions, `http://127.0.0.1:8787` also works.

`apx mode ...` keeps this value synced in `~/.claude/settings.json`. Because the URL stays stable, switching modes does not require a Claude restart. Use `apx disable` if you want to remove the setting completely.

## Modes and chains

`apx` has one underlying routing model — an ordered chain of local services
between the gateway and Anthropic. `apx mode` gives that model a small
curated set of preset names; `apx chain` gives you the primitive directly
for arbitrary orderings and future services.

```bash
apx mode current
apx mode headroom-pxpipe        # preset -> chain "headroom,pxpipe"
apx mode pxpipe-headroom        # preset -> chain "pxpipe,headroom"
apx mode headroom
apx mode squeezr
apx mode headroom-squeezr
apx mode pxpipe
apx mode direct                 # empty chain
apx disable                     # gateway off; ANTHROPIC_BASE_URL removed

# Freeform ordering / power user:
apx chain get
apx chain set headroom,pxpipe
apx chain set squeezr,headroom,pxpipe
apx chain clear                 # equivalent to `apx mode direct`
apx chain ls                    # list known services
apx chain preset ls             # list preset chains
```

```text
headroom-pxpipe   Gateway :8787 -> Headroom :8788 -> pxpipe :47821 -> Anthropic
pxpipe-headroom   Gateway :8787 -> pxpipe :47821 -> Headroom :8788 -> Anthropic
headroom          Gateway :8787 -> Headroom :8788 -> Anthropic
squeezr           Gateway :8787 -> Squeezr :18780 -> Anthropic
headroom-squeezr  Gateway :8787 -> Headroom :8788 -> Squeezr :18780 -> Anthropic
pxpipe            Gateway :8787 -> pxpipe :47821 -> Anthropic
direct            Gateway :8787 -> Anthropic
off               Local proxy services disabled in config
disable           Stops services and removes ANTHROPIC_BASE_URL from Claude settings
```

`full` is kept as a deprecated alias of `headroom-pxpipe` for backward compat.

Current useful fallbacks:

```bash
apx mode squeezr            # first Squeezr experiment, no Headroom or pxpipe
apx mode pxpipe-headroom    # compare pxpipe before Headroom
apx mode pxpipe             # Headroom bypass; pxpipe only
apx mode direct             # bypass all optimizers, keep Gateway stable
apx disable                 # stop everything and remove Claude base URL
```

## First Squeezr Experiment

Squeezr is managed by the same LaunchAgent supervisor as the other components. The stack uses `18780` instead of Squeezr's default `8080` to avoid common local port conflicts.

```bash
apx mode squeezr
apx status
apx logs squeezr
```

Expected route:

```text
Claude Code -> Gateway :8787 -> Squeezr :18780 -> Anthropic
```

Use `apx mode direct` to return to plain Gateway pass-through.

## Operations

```bash
apx status
apx urls
apx logs all
apx logs gateway
apx logs headroom
apx logs headroom.proxy
apx logs headroom.stdout
apx logs pxpipe
apx logs squeezr
apx install
apx stop
apx uninstall                       # stop LaunchAgent; keep everything else
apx uninstall --purge --dry-run     # preview a full removal
apx uninstall --purge --yes         # remove binaries, config, state, share,
                                    # completions, and ANTHROPIC_BASE_URL from
                                    # ~/.claude/settings.json
apx uninstall --purge=state         # remove selectively
apx uninstall --purge=deps --dry-run
apx uninstall --purge=caches --dry-run
apx uninstall --purge=all,deps,caches --yes
```

Any `--purge...` invocation first stops apx and removes its LaunchAgent plist, then removes the selected categories. Plain `--purge` removes apx-owned files: `binaries`, `share`, `state`, `config`, `claude`, and `completions`. The `source`, `deps`, and `caches` categories are explicit opt-ins.

- `deps` removes dependency installs apx recorded creating, currently the `headroom-ai` pipx app and any apx-recorded `ast-grep-cli` injection.
- `caches` removes manifest-gated install/prewarm caches, currently Headroom helper binaries, cached npm tarballs, and matching npx temp installs for `pxpipe-proxy` / `squeezr-ai`.
- `source` removes the recorded source clone only when the path is safe and the running `apx` binary is not inside it.

Run `--dry-run` first to see exact paths and commands. apx never removes Homebrew, Node/npm/npx, pipx, uv, global npm packages, unrelated pipx apps, `~/.headroom`, `~/.squeezr`, `~/.certs`, or `~/.cache/tiktoken`.

Debug everything at once:

```bash
apx logs all
```

`logs headroom` follows both the stack-managed Headroom stdout log and Headroom's detailed proxy request log at `~/.headroom/logs/proxy.log`. Use `logs headroom.proxy` when you only want request/error details.

## URLs

```text
apx dashboard:    http://127.0.0.1:8787/
apx status API:   http://127.0.0.1:8787/api/status
Gateway health:   http://127.0.0.1:8787/livez
Headroom health:  http://127.0.0.1:8788/livez
Headroom stats:   http://127.0.0.1:8788/stats
pxpipe dashboard: http://127.0.0.1:47821/
Squeezr health:   http://127.0.0.1:18780/squeezr/health
Squeezr dashboard:http://127.0.0.1:18780/squeezr/dashboard
```

## pxpipe Image Models

`PXPIPE_MODELS` in `~/.config/apx/config.env` is the persistent source of truth for which model bases pxpipe may convert to images. Dashboard model chips are useful for live experiments, but they are runtime-only and reset when pxpipe restarts.

The default stack template opts in the current known model bases:

```bash
PXPIPE_MODELS="claude-fable-5,claude-opus-4-8,claude-opus-4-7,claude-sonnet-5,claude-sonnet-4-6,gpt-5.6,gpt-5.5"
```

Set `PXPIPE_MODELS=off` to disable image conversion while keeping pxpipe as a pass-through logging/dashboard proxy. pxpipe does not support a wildcard; add future model bases explicitly.

## Runtime Layout

Source files live in this repository. The running LaunchAgent uses home-directory runtime mirrors because macOS LaunchAgents can be blocked from reading files under `~/Documents` by privacy controls.

```text
~/.local/bin/apx
~/.local/bin/apx-gateway
~/.local/bin/apx-squeezr
~/.config/apx/config.env
~/.local/state/apx/
~/.local/share/apx/dashboard.html
~/Library/LaunchAgents/io.github.apx.plist
```

## Known Findings

Headroom runs in a lightweight default profile:

```text
Code-Aware: enabled
Tree-Sitter: loaded
Magika: enabled
CCR: enabled
Kompress ML: not installed
```

This is expected and stable. Startup lines such as these are informational:

```text
Kompress model not cached; deferring download to first use
Kompress: not installed (pip install headroom-ai[ml] for ML compression)
LiteLLM not available - cannot calculate costs
```

Install `headroom-ai[ml]` only if you want heavier optional ML compression. The default keeps the stack lighter.
Install `litellm` only if you want Headroom to estimate request costs; proxying and optimization still work without it.

For launchd-started Python tools, the stack exports `CA_BUNDLE_FILE` and `TIKTOKEN_CACHE_DIR` so Headroom can validate corporate/local CA bundles and use a stable tiktoken cache. If you see tokenizer TLS errors, check:

```bash
apx logs headroom.proxy
```

## Open Source Notes

This project is licensed under MIT. See `LICENSE`.

Third-party tools are not vendored. The installer may install or invoke Homebrew, pipx, Node.js/npm/npx, `headroom-ai`, `ast-grep-cli`, `pxpipe-proxy`, `squeezr-ai`, `difft`, and `scc`; their licenses and terms apply. See `NOTICE`.

Do not publish runtime logs, provider events, or API traffic. See `SECURITY.md`.

See `docs/AI_PROXY_STACK.md` for detailed documentation.
