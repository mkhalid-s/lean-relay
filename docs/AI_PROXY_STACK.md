# LeanRelay

**Local context-efficiency platform for AI agents — operated through the `apx` CLI.**

**LeanRelay** is the project name for this local context-efficiency platform. The
`apx` CLI (formerly packaged as `ai-proxy-stack`) provides one stable Gateway
URL for Claude Code and routes traffic through Headroom, pxpipe, Squeezr, or
directly to Anthropic depending on the selected mode. The gateway also serves a
unified dashboard that aggregates health, request history, Headroom stats, and
log tails from every component.

> **Commands:** `apx` (CLI), `apx-gateway` (gateway), `apx-squeezr` (Squeezr
> helper). Legacy `ai-proxy-stack*` shims are not installed. The GitHub
> repository remains `ai-proxy-stack` so existing install URLs keep working.

## Architecture

Claude Code should always use the Gateway:

```text
same host/container:  ANTHROPIC_BASE_URL=http://127.0.0.1:8787
container to macOS:   ANTHROPIC_BASE_URL=http://host.docker.internal:8787
```

The Gateway listens on `127.0.0.1:8787` and routes to one of these downstream paths:

```text
headroom-pxpipe   Claude -> Gateway :8787 -> Headroom :8788 -> pxpipe :47821 -> Anthropic
pxpipe-headroom   Claude -> Gateway :8787 -> pxpipe :47821 -> Headroom :8788 -> Anthropic
headroom          Claude -> Gateway :8787 -> Headroom :8788 -> Anthropic
squeezr           Claude -> Gateway :8787 -> Squeezr :18780 -> Anthropic
headroom-squeezr  Claude -> Gateway :8787 -> Headroom :8788 -> Squeezr :18780 -> Anthropic
pxpipe            Claude -> Gateway :8787 -> pxpipe :47821 -> Anthropic
direct            Claude -> Gateway :8787 -> Anthropic
off               Local proxy services disabled
```

`full` remains a deprecated alias of `headroom-pxpipe` for backward compatibility.

The stable Gateway means mode changes do not require changing `ANTHROPIC_BASE_URL` or restarting Claude Code just to change proxy routing.

## Components

### Gateway

`bin/apx-gateway` is a small local reverse proxy. It is dependency-free Python and supports streaming enough for Claude Code traffic. It owns the stable public port and, when the dashboard is enabled, also serves the unified dashboard at `/` and JSON APIs at `/api/*`.

```text
Gateway: 127.0.0.1:8787
```

Its main job is to forward requests to the current route target; the dashboard is a thin layer bolted onto the same server.

### Headroom

Headroom runs on an internal port:

```text
Headroom: 127.0.0.1:8788
```

It can optimize LLM request context before forwarding upstream. In current testing, it starts and proxies health endpoints correctly, but Claude Code `/v1/messages?beta=true` traffic can return `502` through Headroom. See Troubleshooting.

### pxpipe

pxpipe runs on:

```text
pxpipe: 127.0.0.1:47821
```

It provides the dashboard, tracking, and provider-facing optimization including text-to-image conversion for eligible bulky context. Recent testing showed `pxpipe` mode successfully handled Claude `/v1/messages?beta=true` traffic.

### Squeezr

Squeezr runs on:

```text
Squeezr: 127.0.0.1:18780
```

The stack intentionally does not use Squeezr's default `8080` port. The first experiment is `squeezr` mode, which routes Claude through Gateway directly to Squeezr. `headroom-squeezr` is available for later chained testing.

### RTK

RTK does not run inside this host proxy stack. If Claude Code runs inside a devcontainer, RTK must be installed inside that devcontainer because it trims Bash/tool output before it enters Claude context.

Flow with RTK:

```text
Devcontainer Bash output -> RTK -> Claude Code -> Gateway :8787 -> selected route -> Anthropic
```

## Installation

```bash
git clone https://github.com/mkhalid-s/ai-proxy-stack.git
cd ai-proxy-stack
./install.sh --yes
```

Or one-line:

```bash
curl -fsSL https://raw.githubusercontent.com/mkhalid-s/ai-proxy-stack/main/bootstrap.sh | bash
```

Check-only preview:

```bash
./install.sh --check-only
```

Useful install options:

```bash
./install.sh --yes        # non-interactive install
./install.sh --no-service # sync runtime files without starting a service
./install.sh --service-backend nohup
./install.sh --skip-deps  # skip dependency installation
./install.sh --uninstall  # remove service; keep config/logs
```

The installer copies source files into user-writable runtime locations and starts
launchd on macOS, systemd-user when available on Linux, or the nohup fallback.

Re-running the installer preserves an existing runtime config. It creates a timestamped backup and appends any new default keys from the source template, instead of replacing local mode and port experiments.

## Dependency Bootstrap

The installer can use Homebrew, apt, dnf, or pacman to install safe missing dependencies:

```text
pipx
node / npm / npx
headroom-ai[proxy]
headroom-ai[code]
ast-grep-cli
Headroom helper tools: difft, scc
pxpipe-proxy@0.8.0 npm cache
squeezr-ai npm cache
```

Package managers themselves are not installed or reconfigured by apx.

RTK and Ponytail are optional add-ons and are not installed by default.

## Runtime Files

Source files in this repo:

```text
./bin/apx
./bin/apx-gateway
./bin/apx-squeezr
./config/config.env
./share/dashboard.html
./docs/AI_PROXY_STACK.md
```

Runtime mirrors:

```text
~/.local/bin/apx
~/.local/bin/apx-gateway
~/.local/bin/apx-squeezr
~/.config/apx/config.env
~/.config/apx/service.backend
~/.local/state/apx/
~/.local/share/apx/dashboard.html
~/Library/LaunchAgents/io.github.apx.plist             # macOS
~/.config/systemd/user/io.github.apx.service           # Linux systemd-user
$XDG_RUNTIME_DIR/apx/                                  # ephemeral Linux PID/lock state
```

The runtime mirror is intentional. It avoids macOS privacy/TCC restrictions and
supports Linux XDG config/state/runtime conventions. See
[`DEVCONTAINER.md`](DEVCONTAINER.md) for container topologies.

## Configuration

Default config file:

```text
~/.config/apx/config.env
```

Source template:

```text
./config/config.env
```

Important values:

```bash
BIND_HOST=127.0.0.1
GATEWAY_PORT=8787
HEADROOM_PORT=8788
PXPIPE_PORT=47821
SQUEEZR_PORT=18780
SQUEEZR_MITM_PORT=18781

GATEWAY_ENABLED=1
HEADROOM_ENABLED=1
PXPIPE_ENABLED=0
SQUEEZR_ENABLED=0

GATEWAY_TARGET_API_URL="http://127.0.0.1:8788"
PXPIPE_TARGET_API_URL="https://api.anthropic.com"
HEADROOM_TARGET_API_URL="https://api.anthropic.com"

GATEWAY_CMD="$HOME/.local/bin/apx-gateway"
SQUEEZR_CMD="$HOME/.local/bin/apx-squeezr"
PXPIPE_CMD="npx -y pxpipe-proxy@0.8.0"
PXPIPE_MODELS="claude-fable-5,claude-opus-4-8,claude-opus-4-7,claude-sonnet-5,claude-sonnet-4-6,gpt-5.6,gpt-5.5"
HEADROOM_CMD="headroom proxy"

WORKDIR="${HOME}"

# Optional TLS/cache helpers for launchd-started Python/Node tools.
CA_BUNDLE_FILE="${HOME}/.certs/ca-bundle.pem"
TIKTOKEN_CACHE_DIR="${HOME}/.cache/tiktoken"
```

Do not edit the runtime config by hand for normal mode switches. Prefer `apx mode ...`.

### Squeezr Experiment

The first Squeezr experiment is intentionally isolated from Headroom and pxpipe:

```bash
apx mode squeezr
apx status
apx logs squeezr
```

Expected route:

```text
Claude Code -> Gateway :8787 -> Squeezr :18780 -> Anthropic
```

The stack exports `SQUEEZR_PORT=18780` and `SQUEEZR_MITM_PORT=18781` when starting Squeezr, so it does not use Squeezr's default `8080` port. Return to plain pass-through with:

```bash
apx mode direct
```

### pxpipe Before Headroom

`pxpipe-headroom` runs the same order used by some devcontainer experiments:

```bash
apx mode pxpipe-headroom
```

Expected route:

```text
Claude Code -> Gateway :8787 -> pxpipe :47821 -> Headroom :8788 -> Anthropic
```

This is separate from `headroom-pxpipe` (formerly `full`), which keeps the `Gateway -> Headroom -> pxpipe` order.

### pxpipe Model Scope

pxpipe only converts requests to image blocks for model bases listed in `PXPIPE_MODELS`. The stack exports this value when it starts pxpipe, so it survives launchd restarts and `apx mode ...` changes.

The pxpipe dashboard chips are runtime-only live overrides. They are useful for quick experiments, but they reset when pxpipe restarts. Keep persistent model policy in `~/.config/apx/config.env`:

```bash
PXPIPE_MODELS="claude-fable-5,claude-opus-4-8,claude-opus-4-7,claude-sonnet-5,claude-sonnet-4-6,gpt-5.6,gpt-5.5"
```

Use `PXPIPE_MODELS=off` to disable image conversion while leaving pxpipe running as a pass-through logging/dashboard proxy. pxpipe has no wildcard mode; add future model bases explicitly.

## Commands

```bash
apx status
apx mode current
apx mode headroom-pxpipe
apx mode pxpipe-headroom
apx mode headroom
apx mode squeezr
apx mode headroom-squeezr
apx mode pxpipe
apx mode direct
apx mode off
apx disable
apx urls
apx logs gateway
apx logs headroom
apx logs headroom.proxy
apx logs headroom.stdout
apx logs pxpipe
apx logs squeezr
apx install
apx stop
apx uninstall
```

## Mode Behavior

`mode` updates config, restarts the active service backend, and syncs Claude settings by default.

```bash
apx mode pxpipe
```

Skip restart:

```bash
apx mode pxpipe --no-restart
```

Skip Claude settings sync:

```bash
apx mode pxpipe --no-claude-sync
```

Override Claude settings path:

```bash
APX_CLAUDE_SETTINGS=/path/to/settings.json apx mode headroom-pxpipe
```

## Claude Settings

`apx mode ...` keeps this value in `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://host.docker.internal:8787"
  }
}
```

`apx disable` removes `ANTHROPIC_BASE_URL`.

Other useful Claude settings from this local setup:

```json
{
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "ENABLE_TOOL_SEARCH": "true",
    "BASH_MAX_OUTPUT_LENGTH": "12000",
    "TASK_MAX_OUTPUT_LENGTH": "16000",
    "MAX_MCP_OUTPUT_TOKENS": "12000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "75"
  }
}
```

## Disable vs Stop

`stop` stops the active apx service backend and child processes, but leaves Claude settings alone.

```bash
apx stop
```

`disable` is the hard off switch:

```bash
apx disable
```

It does all of this:

```text
sets mode to off
stops Gateway, Headroom, pxpipe, and Squeezr
stops the active apx service
removes ANTHROPIC_BASE_URL from ~/.claude/settings.json
```

## Health Checks

```bash
apx status
apx urls
curl -fsS http://127.0.0.1:8787/livez
curl -fsS http://127.0.0.1:8788/livez
curl -fsS http://127.0.0.1:8788/stats
curl -fsS http://127.0.0.1:47821/
curl -fsS http://127.0.0.1:18780/squeezr/health
```

Logs:

```bash
apx logs all
apx logs supervisor
apx logs gateway
apx logs headroom
apx logs headroom.proxy
apx logs headroom.stdout
apx logs pxpipe
apx logs squeezr
apx logs launchd.err
```

`headroom` follows both the stack-captured Headroom stdout log and Headroom's detailed proxy request log at `~/.headroom/logs/proxy.log`. Use `headroom.proxy` for request/error details only, and `headroom.stdout` for startup banners only.

## Debugging Workflow

When something goes wrong, start with status and all logs:

```bash
apx status
apx logs all
```

Stream one component at a time:

```bash
apx logs gateway     # stable entrypoint, route target, HTTP status
apx logs headroom    # Headroom startup plus detailed proxy request/error logs
apx logs headroom.proxy # Headroom request/error details only
apx logs pxpipe      # upstream Anthropic/OpenAI status and dashboard
apx logs squeezr     # Squeezr startup, self-test, and request handling
apx logs supervisor  # process restarts and health checks
apx logs launchd.err # macOS launchd failures
apx logs launchd.out
```

Interpret common failures:

```text
Gateway 502 via Headroom  -> Headroom request path failed
pxpipe 429 upstream body  -> Anthropic/provider rate limit
Gateway health failed     -> gateway process/target route issue
Headroom health failed    -> Headroom process did not start or crashed
pxpipe health failed      -> pxpipe process did not start or port is in use
Squeezr health failed     -> Squeezr process did not start or port is in use
```

Quick isolation:

```bash
apx mode direct   # Gateway -> Anthropic
apx mode pxpipe-headroom # Gateway -> pxpipe -> Headroom -> Anthropic
apx mode squeezr  # Gateway -> Squeezr -> Anthropic
apx mode pxpipe   # Gateway -> pxpipe -> Anthropic
apx mode headroom # Gateway -> Headroom -> Anthropic
apx mode headroom-pxpipe # Gateway -> Headroom -> pxpipe -> Anthropic
```

## Troubleshooting

### Headroom returns 502

Observed behavior:

```text
Gateway -> Headroom :8788 -> Anthropic
POST /v1/messages?beta=true -> 502
```

Health endpoints can still be OK while request forwarding fails:

```text
Gateway health: ok
Headroom health: ok
Headroom request path: 502
```

Use `pxpipe` or `direct` mode as a workaround:

```bash
apx mode pxpipe
apx mode direct
```

Recent local finding:

```text
pxpipe mode successfully handled /v1/messages?beta=true with 200 responses
headroom mode returned repeated 502 responses when launchd-started Python lacked CA bundle env vars
```

The root cause in that case was TLS verification inside the pipx Python runtime:

```text
SSLCertVerificationError: unable to get local issuer certificate
Basic Constraints of CA cert not marked critical
```

The stack now exports `HEADROOM_TLS_STRICT=0`, `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, and `NODE_EXTRA_CA_CERTS` to Headroom when `CA_BUNDLE_FILE` exists. This keeps cert verification on while relaxing OpenSSL's strict CA-extension check for corporate/local CA bundles.

### Headroom tokenizer cache

`tiktoken` downloads encoder files from `openaipublic.blob.core.windows.net` on cache miss. Because LaunchAgents do not inherit your interactive shell environment, Headroom can fail tokenizer downloads unless the CA bundle and cache dir are explicit.

The stack sets:

```bash
CA_BUNDLE_FILE="${HOME}/.certs/ca-bundle.pem"
TIKTOKEN_CACHE_DIR="${HOME}/.cache/tiktoken"
```

If needed, pre-seed the cache with the known encoder files using a trusted downloader, then restart:

```bash
apx install
apx logs headroom.proxy
```

After the cache is seeded, the old `openaipublic.blob.core.windows.net ... SSLCertVerificationError` tokenizer warning should not appear.

### Headroom Kompress ML logs

These startup lines are informational in the lightweight default profile:

```text
Kompress model not cached; deferring download to first use
Kompress: not installed (pip install headroom-ai[ml] for ML compression)
LiteLLM not available - cannot calculate costs
```

Headroom is still useful without Kompress ML:

```text
Code-Aware: ENABLED
Tree-Sitter: loaded
Magika: ENABLED
CCR: ENABLED
```

Install the heavier ML extra only if you explicitly want Kompress ML compression:

```bash
pipx inject headroom-ai 'headroom-ai[ml]'
apx install
```

Install LiteLLM only if you want Headroom to estimate request costs:

```bash
pipx inject headroom-ai litellm
apx install
```

Leaving LiteLLM uninstalled only disables local cost calculation; it does not block proxying, caching, CCR, or AST/code-aware compression.

### Anthropic returns 429

A `429` from pxpipe logs like this is provider-side rate limiting:

```text
POST /v1/messages -> 429
rate_limit_error
```

Local proxy mode changes cannot bypass account/provider rate limits. They can only reduce request size or change how requests are routed.

### Headroom shows zero savings

Headroom stats may show:

```text
requests_compressed=0
tokens_saved=0
compress_user_messages=false
compress_system_messages=false
```

That means Headroom is running but not materially reducing the request. RTK also needs to be installed where Claude Code runs; if Claude is inside a devcontainer, install RTK inside the devcontainer.

### pxpipe dashboard unavailable

pxpipe is only running in these modes:

```text
headroom-pxpipe
pxpipe-headroom
pxpipe
```

In `headroom` and `direct`, pxpipe is intentionally disabled.

## RTK In Devcontainers

If Claude Code runs inside a Linux devcontainer, install RTK inside the devcontainer. In this environment, the shared devcontainer setup uses a post-start script to repair RTK on every container start.

Expected flow:

```text
Devcontainer Bash output -> RTK -> Claude Code -> Gateway :8787 -> selected route -> Anthropic
```

## Open Source Compliance

The project is MIT licensed. See `../LICENSE`.

Third-party tools are not vendored. The installer may install or invoke external tools, including Homebrew, pipx, Node.js/npm/npx, `headroom-ai`, `ast-grep-cli`, `pxpipe-proxy`, `difft`, and `scc`. Their own licenses, terms, and network behavior apply. See `../NOTICE`.

Runtime logs, PID files, provider event logs, and request/response data can contain sensitive metadata. They are ignored by `.gitignore` and should not be published.
