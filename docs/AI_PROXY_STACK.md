# AI Proxy Stack

This project packages a local, switchable proxy stack for Claude Code. The stack provides one stable Gateway URL for Claude and routes traffic through Headroom, pxpipe, Squeezr, or directly to Anthropic depending on the selected mode.

## Architecture

Claude Code should always use the Gateway:

```text
ANTHROPIC_BASE_URL=http://host.docker.internal:8787
```

The Gateway listens on `127.0.0.1:8787` and routes to one of these downstream paths:

```text
full              Claude -> Gateway :8787 -> Headroom :8788 -> pxpipe :47821 -> Anthropic
headroom          Claude -> Gateway :8787 -> Headroom :8788 -> Anthropic
squeezr           Claude -> Gateway :8787 -> Squeezr :18780 -> Anthropic
headroom-squeezr  Claude -> Gateway :8787 -> Headroom :8788 -> Squeezr :18780 -> Anthropic
pxpipe            Claude -> Gateway :8787 -> pxpipe :47821 -> Anthropic
direct            Claude -> Gateway :8787 -> Anthropic
off               Local proxy services disabled
```

The stable Gateway means mode changes do not require changing `ANTHROPIC_BASE_URL` or restarting Claude Code just to change proxy routing.

## Components

### Gateway

`bin/ai-proxy-gateway` is a small local reverse proxy. It is dependency-free Python and supports streaming enough for Claude Code traffic. It owns the stable public port:

```text
Gateway: 127.0.0.1:8787
```

Its only job is to forward requests to the current route target.

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
git clone <repo-url> ai-proxy-stack
cd ai-proxy-stack
./install.sh --yes
```

Check-only preview:

```bash
./install.sh --check-only
```

Useful install options:

```bash
./install.sh --yes        # non-interactive install
./install.sh --no-start   # sync runtime files without starting launchd
./install.sh --skip-deps  # skip dependency installation
./install.sh --uninstall  # remove LaunchAgent and runtime command; keep config/logs
```

The installer copies source files into launchd-safe runtime locations and starts the macOS LaunchAgent.

Re-running the installer preserves an existing runtime config. It creates a timestamped backup and appends any new default keys from the source template, instead of replacing local mode and port experiments.

## Dependency Bootstrap

When Homebrew is present, the installer can auto-install safe missing dependencies:

```text
pipx
node / npm / npx
headroom-ai[proxy]
headroom-ai[code]
ast-grep-cli
Headroom helper tools: difft, scc
pxpipe-proxy npm cache
squeezr-ai npm cache
```

Homebrew itself is not installed silently. If Homebrew is missing, the installer prints the official Homebrew install command.

RTK and Ponytail are optional add-ons and are not installed by default.

## Runtime Files

Source files in this repo:

```text
./bin/ai-proxy-stack
./bin/ai-proxy-gateway
./bin/ai-proxy-squeezr-foreground
./config/config.env
./docs/AI_PROXY_STACK.md
```

Runtime mirrors:

```text
~/.local/bin/ai-proxy-stack
~/.local/bin/ai-proxy-gateway
~/.local/bin/ai-proxy-squeezr-foreground
~/.config/ai-proxy-stack/config.env
~/.local/state/ai-proxy-stack/
~/Library/LaunchAgents/io.github.ai-proxy-stack.plist
```

The runtime mirror is intentional. macOS LaunchAgents can hit privacy/TCC failures when reading protected directories such as `~/Documents`.

## Configuration

Default config file:

```text
~/.config/ai-proxy-stack/config.env
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
HEADROOM_TARGET_API_URL="https://api.anthropic.com"

GATEWAY_CMD="$HOME/.local/bin/ai-proxy-gateway"
SQUEEZR_CMD="$HOME/.local/bin/ai-proxy-squeezr-foreground"
PXPIPE_CMD="npx -y pxpipe-proxy"
PXPIPE_MODELS="claude-fable-5,claude-opus-4-8,claude-opus-4-7,claude-sonnet-5,claude-sonnet-4-6,gpt-5.6,gpt-5.5"
HEADROOM_CMD="headroom proxy"

WORKDIR="${HOME}"

# Optional TLS/cache helpers for launchd-started Python/Node tools.
CA_BUNDLE_FILE="${HOME}/.certs/ca-bundle.pem"
TIKTOKEN_CACHE_DIR="${HOME}/.cache/tiktoken"
```

Do not edit the runtime config by hand for normal mode switches. Prefer `ai-proxy-stack mode ...`.

### Squeezr Experiment

The first Squeezr experiment is intentionally isolated from Headroom and pxpipe:

```bash
ai-proxy-stack mode squeezr
ai-proxy-stack status
ai-proxy-stack logs squeezr
```

Expected route:

```text
Claude Code -> Gateway :8787 -> Squeezr :18780 -> Anthropic
```

The stack exports `SQUEEZR_PORT=18780` and `SQUEEZR_MITM_PORT=18781` when starting Squeezr, so it does not use Squeezr's default `8080` port. Return to plain pass-through with:

```bash
ai-proxy-stack mode direct
```

### pxpipe Model Scope

pxpipe only converts requests to image blocks for model bases listed in `PXPIPE_MODELS`. The stack exports this value when it starts pxpipe, so it survives launchd restarts and `ai-proxy-stack mode ...` changes.

The pxpipe dashboard chips are runtime-only live overrides. They are useful for quick experiments, but they reset when pxpipe restarts. Keep persistent model policy in `~/.config/ai-proxy-stack/config.env`:

```bash
PXPIPE_MODELS="claude-fable-5,claude-opus-4-8,claude-opus-4-7,claude-sonnet-5,claude-sonnet-4-6,gpt-5.6,gpt-5.5"
```

Use `PXPIPE_MODELS=off` to disable image conversion while leaving pxpipe running as a pass-through logging/dashboard proxy. pxpipe has no wildcard mode; add future model bases explicitly.

## Commands

```bash
ai-proxy-stack status
ai-proxy-stack mode current
ai-proxy-stack mode full
ai-proxy-stack mode headroom
ai-proxy-stack mode squeezr
ai-proxy-stack mode headroom-squeezr
ai-proxy-stack mode pxpipe
ai-proxy-stack mode direct
ai-proxy-stack mode off
ai-proxy-stack disable
ai-proxy-stack urls
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

## Mode Behavior

`mode` updates config, restarts the LaunchAgent, and syncs Claude settings by default.

```bash
ai-proxy-stack mode pxpipe
```

Skip restart:

```bash
ai-proxy-stack mode pxpipe --no-restart
```

Skip Claude settings sync:

```bash
ai-proxy-stack mode pxpipe --no-claude-sync
```

Override Claude settings path:

```bash
AI_PROXY_STACK_CLAUDE_SETTINGS=/path/to/settings.json ai-proxy-stack mode full
```

## Claude Settings

`ai-proxy-stack mode ...` keeps this value in `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://host.docker.internal:8787"
  }
}
```

`ai-proxy-stack disable` removes `ANTHROPIC_BASE_URL`.

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

`stop` stops the LaunchAgent and child processes, but leaves Claude settings alone.

```bash
ai-proxy-stack stop
```

`disable` is the hard off switch:

```bash
ai-proxy-stack disable
```

It does all of this:

```text
sets mode to off
stops Gateway, Headroom, pxpipe, and Squeezr
stops the LaunchAgent
removes ANTHROPIC_BASE_URL from ~/.claude/settings.json
```

## Health Checks

```bash
ai-proxy-stack status
ai-proxy-stack urls
curl -fsS http://127.0.0.1:8787/livez
curl -fsS http://127.0.0.1:8788/livez
curl -fsS http://127.0.0.1:8788/stats
curl -fsS http://127.0.0.1:47821/
curl -fsS http://127.0.0.1:18780/squeezr/health
```

Logs:

```bash
ai-proxy-stack logs all
ai-proxy-stack logs supervisor
ai-proxy-stack logs gateway
ai-proxy-stack logs headroom
ai-proxy-stack logs headroom.proxy
ai-proxy-stack logs headroom.stdout
ai-proxy-stack logs pxpipe
ai-proxy-stack logs squeezr
ai-proxy-stack logs launchd.err
```

`headroom` follows both the stack-captured Headroom stdout log and Headroom's detailed proxy request log at `~/.headroom/logs/proxy.log`. Use `headroom.proxy` for request/error details only, and `headroom.stdout` for startup banners only.

## Debugging Workflow

When something goes wrong, start with status and all logs:

```bash
ai-proxy-stack status
ai-proxy-stack logs all
```

Stream one component at a time:

```bash
ai-proxy-stack logs gateway     # stable entrypoint, route target, HTTP status
ai-proxy-stack logs headroom    # Headroom startup plus detailed proxy request/error logs
ai-proxy-stack logs headroom.proxy # Headroom request/error details only
ai-proxy-stack logs pxpipe      # upstream Anthropic/OpenAI status and dashboard
ai-proxy-stack logs squeezr     # Squeezr startup, self-test, and request handling
ai-proxy-stack logs supervisor  # process restarts and health checks
ai-proxy-stack logs launchd.err # macOS LaunchAgent failures
ai-proxy-stack logs launchd.out
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
ai-proxy-stack mode direct   # Gateway -> Anthropic
ai-proxy-stack mode squeezr  # Gateway -> Squeezr -> Anthropic
ai-proxy-stack mode pxpipe   # Gateway -> pxpipe -> Anthropic
ai-proxy-stack mode headroom # Gateway -> Headroom -> Anthropic
ai-proxy-stack mode full     # Gateway -> Headroom -> pxpipe -> Anthropic
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
ai-proxy-stack mode pxpipe
ai-proxy-stack mode direct
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
ai-proxy-stack install
ai-proxy-stack logs headroom.proxy
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
ai-proxy-stack install
```

Install LiteLLM only if you want Headroom to estimate request costs:

```bash
pipx inject headroom-ai litellm
ai-proxy-stack install
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
full
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
