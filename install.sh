#!/usr/bin/env bash
set -Eeuo pipefail

STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BIN="$STACK_ROOT/bin/ai-proxy-stack"
SRC_GATEWAY_BIN="$STACK_ROOT/bin/ai-proxy-gateway"
SRC_SQUEEZR_BIN="$STACK_ROOT/bin/ai-proxy-squeezr-foreground"
SRC_CONFIG="$STACK_ROOT/config/config.env"

RUNTIME_BIN="$HOME/.local/bin/ai-proxy-stack"
RUNTIME_GATEWAY_BIN="$HOME/.local/bin/ai-proxy-gateway"
RUNTIME_SQUEEZR_BIN="$HOME/.local/bin/ai-proxy-squeezr-foreground"
RUNTIME_CONFIG_DIR="$HOME/.config/ai-proxy-stack"
RUNTIME_CONFIG="$RUNTIME_CONFIG_DIR/config.env"
RUNTIME_STATE="$HOME/.local/state/ai-proxy-stack"

YES=0
NO_START=0
SKIP_DEPS=0
CHECK_ONLY=0
UNINSTALL=0

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --yes          Run non-interactively and install safe missing dependencies
  --no-start     Sync runtime files but do not install/start the LaunchAgent
  --skip-deps    Skip dependency installation
  --check-only   Print checks/actions without changing anything
  --uninstall    Stop/remove LaunchAgent and runtime command; keep config/logs
  -h, --help     Show this help

This package keeps source files in:
  $STACK_ROOT

The macOS LaunchAgent runs from launchd-safe runtime paths:
  $RUNTIME_BIN
  $RUNTIME_CONFIG
  $RUNTIME_STATE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=1 ;;
    --no-start) NO_START=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf '[ai-proxy-stack] %s\n' "$*"; }
warn() { printf '[ai-proxy-stack] warning: %s\n' "$*" >&2; }
die() { printf '[ai-proxy-stack] error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
urls_ok() {
  local url
  for url in "$@"; do
    curl -fsS "$url" >/dev/null 2>&1 || return 1
  done
  return 0
}

run_step() {
  local desc="$1"
  shift
  if [[ "$CHECK_ONLY" == "1" ]]; then
    printf '[ai-proxy-stack] would: %s: ' "$desc"
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  log "$desc"
  "$@"
}

confirm() {
  local prompt="$1"
  if [[ "$YES" == "1" ]]; then
    return 0
  fi
  local answer
  printf '%s [y/N] ' "$prompt"
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this installer currently supports macOS LaunchAgents only"
}

require_sources() {
  [[ -f "$SRC_BIN" ]] || die "missing source command: $SRC_BIN"
  [[ -f "$SRC_GATEWAY_BIN" ]] || die "missing source gateway: $SRC_GATEWAY_BIN"
  [[ -f "$SRC_SQUEEZR_BIN" ]] || die "missing source Squeezr helper: $SRC_SQUEEZR_BIN"
  [[ -f "$SRC_CONFIG" ]] || die "missing source config: $SRC_CONFIG"
}

require_brew_for_deps() {
  if have brew; then
    return 0
  fi

  cat >&2 <<'EOF'
Homebrew is required to auto-install safe dependencies, but it is not installed.

Install Homebrew first:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Then rerun:
  ./install.sh --yes

Or skip dependency installation:
  ./install.sh --skip-deps
EOF
  exit 1
}

install_if_missing() {
  local cmd="$1"
  local desc="$2"
  shift 2
  if have "$cmd"; then
    log "$desc already available: $(command -v "$cmd")"
    return 0
  fi
  run_step "install $desc" "$@"
}

install_deps() {
  if [[ "$SKIP_DEPS" == "1" ]]; then
    log "skipping dependency installation"
    return 0
  fi

  require_brew_for_deps

  install_if_missing pipx "pipx" brew install pipx
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

  if ! have node || ! have npm || ! have npx; then
    run_step "install Node.js/npm/npx" brew install node
  else
    log "Node.js/npm/npx already available"
  fi

  if ! have headroom; then
    run_step "install headroom-ai proxy" pipx install "headroom-ai[proxy]"
  else
    log "Headroom already available: $(command -v headroom)"
  fi

  if have pipx; then
    run_step "ensure headroom-ai code extras" pipx runpip headroom-ai install "headroom-ai[code]"
    if ! have ast-grep && ! have sg; then
      run_step "install ast-grep-cli into headroom environment" pipx inject headroom-ai ast-grep-cli --include-apps --force
    else
      log "ast-grep already available"
    fi
  fi

  if have headroom; then
    run_step "install Headroom helper tools" headroom tools install --tool difft --tool scc
  else
    warn "headroom command is not on PATH yet; restart your shell or rerun after pipx ensurepath"
  fi

  if have npm; then
    run_step "prewarm pxpipe-proxy npm cache" npm cache add pxpipe-proxy
    run_step "prewarm squeezr-ai npm cache" npm cache add squeezr-ai
  else
    warn "npm is not available; pxpipe-proxy and squeezr-ai will be fetched by npx on first start"
  fi
}

backup_if_different() {
  local src="$1"
  local dst="$2"
  if [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
    local backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
    run_step "backup existing $(basename "$dst")" cp "$dst" "$backup"
  fi
}

sync_config() {
  if [[ ! -f "$RUNTIME_CONFIG" ]]; then
    run_step "install runtime config" cp "$SRC_CONFIG" "$RUNTIME_CONFIG"
    return 0
  fi

  backup_if_different "$SRC_CONFIG" "$RUNTIME_CONFIG"
  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "would preserve existing runtime config and append any missing default keys"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  cp "$RUNTIME_CONFIG" "$tmp"
  awk -F= '
    FNR == NR {
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/) seen[$1] = 1
      next
    }
    $0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/ {
      key = $1
      if (!(key in seen)) {
        if (!header) {
          print ""
          print "# Added by ai-proxy-stack installer from current defaults."
          header = 1
        }
        print $0
      }
    }
  ' "$RUNTIME_CONFIG" "$SRC_CONFIG" >> "$tmp"
  mv "$tmp" "$RUNTIME_CONFIG"
}

sync_runtime() {
  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "would sync runtime command/config into launchd-safe paths"
  else
    mkdir -p "$HOME/.local/bin" "$RUNTIME_CONFIG_DIR" "$RUNTIME_STATE/logs" "$RUNTIME_STATE/run"
  fi

  backup_if_different "$SRC_BIN" "$RUNTIME_BIN"
  run_step "install runtime command" cp "$SRC_BIN" "$RUNTIME_BIN"
  run_step "make runtime command executable" chmod +x "$RUNTIME_BIN"

  backup_if_different "$SRC_GATEWAY_BIN" "$RUNTIME_GATEWAY_BIN"
  run_step "install runtime gateway" cp "$SRC_GATEWAY_BIN" "$RUNTIME_GATEWAY_BIN"
  run_step "make runtime gateway executable" chmod +x "$RUNTIME_GATEWAY_BIN"

  backup_if_different "$SRC_SQUEEZR_BIN" "$RUNTIME_SQUEEZR_BIN"
  run_step "install runtime Squeezr helper" cp "$SRC_SQUEEZR_BIN" "$RUNTIME_SQUEEZR_BIN"
  run_step "make runtime Squeezr helper executable" chmod +x "$RUNTIME_SQUEEZR_BIN"

  sync_config
}

print_urls() {
  local bind_host="127.0.0.1"
  local gateway_port="8787"
  local pxpipe_port="47821"
  local headroom_port="8788"
  local squeezr_port="18780"
  if [[ -f "$RUNTIME_CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_CONFIG"
    bind_host="${BIND_HOST:-$bind_host}"
    gateway_port="${GATEWAY_PORT:-$gateway_port}"
    pxpipe_port="${PXPIPE_PORT:-$pxpipe_port}"
    headroom_port="${HEADROOM_PORT:-$headroom_port}"
    squeezr_port="${SQUEEZR_PORT:-$squeezr_port}"
  fi

  cat <<EOF

Dashboard and service URLs:
  Gateway health:   http://$bind_host:$gateway_port/livez
  pxpipe dashboard: http://$bind_host:$pxpipe_port/
  Headroom health:  http://$bind_host:$headroom_port/livez
  Headroom stats:   http://$bind_host:$headroom_port/stats
  Squeezr health:   http://$bind_host:$squeezr_port/squeezr/health
  Squeezr dashboard:http://$bind_host:$squeezr_port/squeezr/dashboard

Claude Code in a devcontainer should use:
  ANTHROPIC_BASE_URL=http://host.docker.internal:$gateway_port
EOF
}

validate_health() {
  if [[ "$NO_START" == "1" || "$CHECK_ONLY" == "1" ]]; then
    return 0
  fi

  log "validating service health"
  "$RUNTIME_BIN" status

  # shellcheck disable=SC1090
  source "$RUNTIME_CONFIG"
  local bind_host="${BIND_HOST:-127.0.0.1}"
  local gateway_port="${GATEWAY_PORT:-8787}"
  local pxpipe_port="${PXPIPE_PORT:-47821}"
  local headroom_port="${HEADROOM_PORT:-8788}"
  local squeezr_port="${SQUEEZR_PORT:-18780}"
  local deadline=$((SECONDS + 60))

  local checks=()
  [[ "${GATEWAY_ENABLED:-1}" == "1" ]] && checks+=("http://$bind_host:$gateway_port/livez")
  [[ "${PXPIPE_ENABLED:-0}" == "1" ]] && checks+=("http://$bind_host:$pxpipe_port/")
  [[ "${HEADROOM_ENABLED:-0}" == "1" ]] && checks+=("http://$bind_host:$headroom_port/livez")
  [[ "${SQUEEZR_ENABLED:-0}" == "1" ]] && checks+=("http://$bind_host:$squeezr_port/squeezr/health")

  until urls_ok "${checks[@]}"; do
    if (( SECONDS >= deadline )); then
      "$RUNTIME_BIN" status || true
      die "service did not become healthy within 60s; inspect logs with: ai-proxy-stack logs supervisor"
    fi
    sleep 2
  done

  "$RUNTIME_BIN" status
}

install_service() {
  if [[ "$NO_START" == "1" ]]; then
    log "skipping LaunchAgent install/start because --no-start was set"
    return 0
  fi
  run_step "install/start LaunchAgent" env AI_PROXY_STACK_ROOT="$STACK_ROOT" "$RUNTIME_BIN" install
}

uninstall() {
  if [[ -x "$RUNTIME_BIN" ]]; then
    run_step "stop/remove LaunchAgent" "$RUNTIME_BIN" uninstall
  fi
  run_step "remove runtime command" rm -f "$RUNTIME_BIN"
  log "kept config and logs:"
  log "  $RUNTIME_CONFIG"
  log "  $RUNTIME_STATE"
}

main() {
  require_macos
  require_sources

  if [[ "$UNINSTALL" == "1" ]]; then
    uninstall
    return 0
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "check-only mode: no changes will be made"
  elif [[ "$YES" != "1" ]]; then
    confirm "Install/sync AI proxy stack runtime files and safe dependencies?" || die "aborted"
  fi

  install_deps
  sync_runtime
  install_service
  validate_health
  print_urls
  log "done"
}

main "$@"
