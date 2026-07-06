# AI Proxy Stack

A local macOS proxy stack for Claude Code with a stable gateway and switchable routing modes.

```text
Claude Code -> Gateway :8787 -> Headroom / pxpipe / Squeezr / Anthropic
```

Claude Code always talks to the Gateway. You can switch modes without changing Claude's base URL.

## Quick Install

```bash
git clone <repo-url> ai-proxy-stack
cd ai-proxy-stack
./install.sh --yes
```

Preview installer actions without changing anything:

```bash
./install.sh --check-only
```

The installer copies runtime files to launchd-safe paths, installs safe dependencies when Homebrew is available, starts the LaunchAgent, and validates health.

Existing runtime config is preserved on reinstall. The installer backs it up and appends any new default keys, so local port/mode experiments are not overwritten.

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

`ai-proxy-stack mode ...` keeps this value synced in `~/.claude/settings.json`. Because the URL stays stable, switching modes does not require a Claude restart. Use `ai-proxy-stack disable` if you want to remove the setting completely.

## Modes

```bash
ai-proxy-stack mode current
ai-proxy-stack mode full
ai-proxy-stack mode headroom
ai-proxy-stack mode squeezr
ai-proxy-stack mode headroom-squeezr
ai-proxy-stack mode pxpipe
ai-proxy-stack mode direct
ai-proxy-stack disable
```

```text
full              Gateway :8787 -> Headroom :8788 -> pxpipe :47821 -> Anthropic
headroom          Gateway :8787 -> Headroom :8788 -> Anthropic
squeezr           Gateway :8787 -> Squeezr :18780 -> Anthropic
headroom-squeezr  Gateway :8787 -> Headroom :8788 -> Squeezr :18780 -> Anthropic
pxpipe            Gateway :8787 -> pxpipe :47821 -> Anthropic
direct            Gateway :8787 -> Anthropic
off               Local proxy services disabled in config
disable           Stops services and removes ANTHROPIC_BASE_URL from Claude settings
```

Current useful fallbacks:

```bash
ai-proxy-stack mode squeezr   # first Squeezr experiment, no Headroom or pxpipe
ai-proxy-stack mode pxpipe    # Headroom bypass; pxpipe only
ai-proxy-stack mode direct    # bypass all optimizers, keep Gateway stable
ai-proxy-stack disable        # stop everything and remove Claude base URL
```

## First Squeezr Experiment

Squeezr is managed by the same LaunchAgent supervisor as the other components. The stack uses `18780` instead of Squeezr's default `8080` to avoid common local port conflicts.

```bash
ai-proxy-stack mode squeezr
ai-proxy-stack status
ai-proxy-stack logs squeezr
```

Expected route:

```text
Claude Code -> Gateway :8787 -> Squeezr :18780 -> Anthropic
```

Use `ai-proxy-stack mode direct` to return to plain Gateway pass-through.

## Operations

```bash
ai-proxy-stack status
ai-proxy-stack urls
ai-proxy-stack logs all
ai-proxy-stack logs gateway
ai-proxy-stack logs headroom
ai-proxy-stack logs headroom.proxy
ai-proxy-stack logs headroom.stdout
ai-proxy-stack logs pxpipe
ai-proxy-stack logs squeezr
ai-proxy-stack install
ai-proxy-stack stop
ai-proxy-stack uninstall
```

Debug everything at once:

```bash
ai-proxy-stack logs all
```

`logs headroom` follows both the stack-managed Headroom stdout log and Headroom's detailed proxy request log at `~/.headroom/logs/proxy.log`. Use `logs headroom.proxy` when you only want request/error details.

## URLs

```text
Gateway health:   http://127.0.0.1:8787/livez
Headroom health:  http://127.0.0.1:8788/livez
Headroom stats:   http://127.0.0.1:8788/stats
pxpipe dashboard: http://127.0.0.1:47821/
Squeezr health:   http://127.0.0.1:18780/squeezr/health
Squeezr dashboard:http://127.0.0.1:18780/squeezr/dashboard
```

## pxpipe Image Models

`PXPIPE_MODELS` in `~/.config/ai-proxy-stack/config.env` is the persistent source of truth for which model bases pxpipe may convert to images. Dashboard model chips are useful for live experiments, but they are runtime-only and reset when pxpipe restarts.

The default stack template opts in the current known model bases:

```bash
PXPIPE_MODELS="claude-fable-5,claude-opus-4-8,claude-opus-4-7,claude-sonnet-5,claude-sonnet-4-6,gpt-5.6,gpt-5.5"
```

Set `PXPIPE_MODELS=off` to disable image conversion while keeping pxpipe as a pass-through logging/dashboard proxy. pxpipe does not support a wildcard; add future model bases explicitly.

## Runtime Layout

Source files live in this repository. The running LaunchAgent uses home-directory runtime mirrors because macOS LaunchAgents can be blocked from reading files under `~/Documents` by privacy controls.

```text
~/.local/bin/ai-proxy-stack
~/.local/bin/ai-proxy-gateway
~/.local/bin/ai-proxy-squeezr-foreground
~/.config/ai-proxy-stack/config.env
~/.local/state/ai-proxy-stack/
~/Library/LaunchAgents/io.github.ai-proxy-stack.plist
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
ai-proxy-stack logs headroom.proxy
```

## Open Source Notes

This project is licensed under MIT. See `LICENSE`.

Third-party tools are not vendored. The installer may install or invoke Homebrew, pipx, Node.js/npm/npx, `headroom-ai`, `ast-grep-cli`, `pxpipe-proxy`, `squeezr-ai`, `difft`, and `scc`; their licenses and terms apply. See `NOTICE`.

Do not publish runtime logs, provider events, or API traffic. See `SECURITY.md`.

See `docs/AI_PROXY_STACK.md` for detailed documentation.
