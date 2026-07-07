# apx

A local macOS proxy stack for Claude Code with a stable gateway, switchable routing modes, and a unified dashboard.

```text
Claude Code -> apx Gateway :8787 -> Headroom / pxpipe / Squeezr / Anthropic
```

Claude Code always talks to the Gateway. You can switch modes without changing Claude's base URL.

> The CLI, gateway, and squeezr helper are named `apx`, `apx-gateway`, and `apx-squeezr`. Old `ai-proxy-stack` / `ai-proxy-gateway` / `ai-proxy-squeezr-foreground` commands remain installed as deprecation shims that forward to the new binaries.

## Quick Install

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

If you previously installed as `ai-proxy-stack`, the installer stops the old LaunchAgent (`io.github.ai-proxy-stack`), migrates `~/.config/ai-proxy-stack/config.env` → `~/.config/apx/config.env`, migrates state to `~/.local/state/apx/`, and installs a deprecation shim at `~/.local/bin/ai-proxy-stack` that forwards to `apx`.

## Dashboard

Open [http://127.0.0.1:8787/](http://127.0.0.1:8787/) after installing to see a single pane that aggregates every component:

- current mode, chain diagram, apx version
- live health badges for Gateway, Headroom, pxpipe, Squeezr
- Headroom stats (fetched from `:8788/stats` server-side, no CORS)
- last 50 gateway requests with status/latency
- live log tail via SSE for each service (`supervisor`, `gateway`, `headroom`, `pxpipe`, `squeezr`)
- iframed pxpipe and Squeezr dashboards

JSON APIs for scripting:

```text
GET /api/status              overall mode + health + counters
GET /api/history?n=100       gateway request history
GET /api/headroom/stats      proxied Headroom /stats JSON
GET /api/logs/stream?service=gateway   Server-Sent Events log tail
```

Disable the dashboard entirely by setting `APX_DASHBOARD_ENABLED=0` in `~/.config/apx/config.env`. The gateway keeps proxying normally either way.

## Updating

Once installed, upgrade in place from the recorded source clone:

```bash
apx check-updates             # compare installed vs origin/main
apx update                    # git pull + rerun install.sh --yes
apx update --dry-run          # preview commits and installer actions
apx update --to v0.2.0        # move to a specific tag or branch
apx version                   # show installed version and source repo
```

`update` fast-forwards the source clone, then reinstalls binaries into `~/.local/bin/`, merges any new default keys into `~/.config/apx/config.env` (backing up the existing file), refreshes the dashboard HTML, and reloads the LaunchAgent. Local port/mode/PXPIPE_MODELS customizations are preserved. Binaries are copied via `install -m 0755`, which writes to a temp file and renames atomically, so an interrupted upgrade never leaves a half-written executable.

After an update, if you had installed shell completions with `apx completions install`, `apx update` warns you when they look stale so you can refresh them:

```bash
apx completions install       # detects your shell
apx completions install --shell zsh
apx completions uninstall     # remove installed completion files
```

If you installed with the curl bootstrap, the source clone lives at `~/.local/share/apx-src` and `apx update` handles the pull for you. If you cloned somewhere else and moved the directory, either:

```bash
echo /new/path/to/apx-source > ~/.config/apx/source.path
apx update
```

or just rerun `./install.sh --yes` from the new clone.

Releases are cut with git tags of the form `vMAJOR.MINOR.PATCH` matching the `VERSION` file at the repo root. Tagged builds also publish a tarball at [Releases](https://github.com/mkhalid-s/ai-proxy-stack/releases).

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
apx uninstall --purge=state,logs    # remove selectively
```

`--purge` categories: `binaries`, `share`, `state`, `config`, `claude`, `completions`, `source`. Anything owned by other tools (`~/.headroom`, `~/.squeezr`, `~/.certs`, `~/.cache/tiktoken`, ...) is never touched. `--purge=source` refuses to delete the source clone if the running `apx` binary lives inside it, and prints the exact `rm -rf` command to run manually.

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
~/.local/bin/ai-proxy-stack            # deprecation shim -> apx
~/.local/bin/ai-proxy-gateway          # deprecation shim -> apx-gateway
~/.local/bin/ai-proxy-squeezr-foreground   # deprecation shim -> apx-squeezr
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
