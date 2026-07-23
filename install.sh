#!/usr/bin/env bash
set -Eeuo pipefail

STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BIN="$STACK_ROOT/bin/apx"
SRC_GATEWAY_BIN="$STACK_ROOT/bin/apx-gateway"
SRC_SQUEEZR_BIN="$STACK_ROOT/bin/apx-squeezr"
SRC_CONFIG="$STACK_ROOT/config/config.env"
SRC_VERSION_FILE="$STACK_ROOT/VERSION"
SRC_DASHBOARD_HTML="$STACK_ROOT/share/dashboard.html"

RUNTIME_BIN_DIR="$HOME/.local/bin"
RUNTIME_BIN="$RUNTIME_BIN_DIR/apx"
RUNTIME_GATEWAY_BIN="$RUNTIME_BIN_DIR/apx-gateway"
RUNTIME_SQUEEZR_BIN="$RUNTIME_BIN_DIR/apx-squeezr"
RUNTIME_CONFIG_DIR="$HOME/.config/apx"
RUNTIME_CONFIG="$RUNTIME_CONFIG_DIR/config.env"
RUNTIME_SOURCE_PATH_FILE="$RUNTIME_CONFIG_DIR/source.path"
RUNTIME_STATE="$HOME/.local/state/apx"
RUNTIME_VERSION_FILE="$RUNTIME_STATE/VERSION"
RUNTIME_INSTALL_MANIFEST="$RUNTIME_STATE/install-manifest.env"
RUNTIME_SHARE_DIR="$HOME/.local/share/apx"
RUNTIME_DASHBOARD_HTML="$RUNTIME_SHARE_DIR/dashboard.html"

STACK_VERSION="$( [ -f "$SRC_VERSION_FILE" ] && head -n 1 "$SRC_VERSION_FILE" | tr -d '[:space:]' || echo "unknown" )"

YES=0
NO_START=0
SERVICE_BACKEND="${APX_SERVICE_BACKEND:-auto}"
PACKAGE_MANAGER="${APX_PACKAGE_MANAGER:-auto}"
CLIENT_TOPOLOGY="${APX_CLIENT_TOPOLOGY:-none}"
CLIENT_BASE_URL="${APX_CLIENT_BASE_URL:-}"
SKIP_DEPS=0
CHECK_ONLY=0
UNINSTALL=0
PURGE=0
FROM_PAYLOAD=0

# When invoked from the apx.sh self-extracting installer, STACK_ROOT points at
# the extracted version directory (e.g. ~/.local/share/apx/versions/v0.2.0),
# but the LaunchAgent must run out of ~/.local/share/apx/current so rollbacks
# and upgrades survive without editing the plist. APX_INSTALL_MODE_ROOT is the
# override the self-extractor sets; APX_INSTALL_MODE=release enables the
# release-mode branch inside `apx update`.
RUNTIME_APX_ROOT="${APX_INSTALL_MODE_ROOT:-}"

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --yes          Run non-interactively and install safe missing dependencies
  --no-service   Sync runtime files but do not install/start a service
  --no-start     Backward-compatible alias for --no-service
  --service-backend=auto|launchd|systemd|nohup
  --client-topology=local|docker-host|custom|none
  --client-base-url=<url>  URL used with custom topology
  --skip-deps    Skip dependency installation
  --check-only   Print checks/actions without changing anything
  --uninstall    Delegate to 'apx uninstall' when available (service-only).
  --purge        Delegate to 'apx uninstall --purge --yes' when available.
                 Plain purge removes apx-owned files only; use
                 'apx uninstall --purge=all,deps,caches --dry-run' for
                 explicit dependency/cache cleanup while the CLI exists.
  --from-payload Internal: called by the self-extracting apx.sh installer.
                 Skips git-clone bookkeeping and points APX_ROOT at
                 ~/.local/share/apx/current.
  -h, --help     Show this help

This package keeps source files in:
  $STACK_ROOT (version $STACK_VERSION)

The apx service runs from user-writable runtime paths:
  $RUNTIME_BIN
  $RUNTIME_CONFIG
  $RUNTIME_STATE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=1 ;;
    --no-service|--no-start) NO_START=1 ;;
    --service-backend) shift; SERVICE_BACKEND="${1:-}" ;;
    --service-backend=*) SERVICE_BACKEND="${1#*=}" ;;
    --client-topology) shift; CLIENT_TOPOLOGY="${1:-}" ;;
    --client-topology=*) CLIENT_TOPOLOGY="${1#*=}" ;;
    --client-base-url) shift; CLIENT_BASE_URL="${1:-}" ;;
    --client-base-url=*) CLIENT_BASE_URL="${1#*=}" ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --purge) UNINSTALL=1; PURGE=1 ;;
    --from-payload) FROM_PAYLOAD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$SERVICE_BACKEND" in auto|launchd|systemd|nohup) ;; *) echo "invalid --service-backend: $SERVICE_BACKEND" >&2; exit 2 ;; esac
case "$PACKAGE_MANAGER" in auto|apt|dnf|pacman) ;; *) echo "invalid APX_PACKAGE_MANAGER: $PACKAGE_MANAGER" >&2; exit 2 ;; esac
case "$CLIENT_TOPOLOGY" in local|docker-host|custom|none) ;; *) echo "invalid client topology: $CLIENT_TOPOLOGY" >&2; exit 2 ;; esac
if [[ "$CLIENT_TOPOLOGY" == "custom" && "$CLIENT_BASE_URL" != http://* && "$CLIENT_BASE_URL" != https://* ]]; then
  echo "--client-base-url=http(s)://... is required for custom topology" >&2
  exit 2
fi

log() { printf '[apx] %s\n' "$*"; }
warn() { printf '[apx] warning: %s\n' "$*" >&2; }
die() { printf '[apx] error: %s\n' "$*" >&2; exit 1; }
have() {
  if [[ "$1" == "npx" && "${APX_TEST_NO_NPX:-0}" == "1" ]]; then
    return 1
  fi
  command -v "$1" >/dev/null 2>&1
}
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
    printf '[apx] would: %s: ' "$desc"
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

require_supported_os() {
  case "$(uname -s)" in
    Darwin|Linux) ;;
    *) die "unsupported operating system: $(uname -s)" ;;
  esac
}

require_sources() {
  [[ -f "$SRC_BIN" ]] || die "missing source command: $SRC_BIN"
  [[ -f "$SRC_GATEWAY_BIN" ]] || die "missing source gateway: $SRC_GATEWAY_BIN"
  [[ -f "$SRC_SQUEEZR_BIN" ]] || die "missing source Squeezr helper: $SRC_SQUEEZR_BIN"
  [[ -f "$SRC_CONFIG" ]] || die "missing source config: $SRC_CONFIG"
}

run_as_root() {
  if [[ "$(id -u)" == "0" ]]; then "$@"; elif have sudo; then sudo "$@"; else die "root privileges are required: $*"; fi
}

install_platform_prereqs() {
  case "$(uname -s)" in
    Darwin)
      have brew || die "Homebrew is required for automatic dependencies; install it or pass --skip-deps"
      run_step "install macOS prerequisites" brew install pipx node
      ;;
    Linux)
      local manager="$PACKAGE_MANAGER"
      if [[ "$manager" == "auto" ]]; then
        if have apt-get; then manager=apt; elif have dnf; then manager=dnf; elif have pacman; then manager=pacman; else manager=none; fi
      fi
      if [[ "$manager" == "apt" ]]; then
        run_step "refresh apt metadata" run_as_root apt-get update
        run_step "install Debian/Ubuntu prerequisites" run_as_root apt-get install -y git curl ca-certificates python3 python3-pip pipx nodejs npm lsof procps
      elif [[ "$manager" == "dnf" ]]; then
        run_step "install Fedora/RHEL prerequisites" run_as_root dnf install -y git curl ca-certificates python3 python3-pip pipx nodejs npm lsof procps-ng
      elif [[ "$manager" == "pacman" ]]; then
        run_step "install Arch prerequisites" run_as_root pacman -Sy --needed --noconfirm git curl ca-certificates python python-pip python-pipx nodejs npm lsof procps-ng
      else
        die "no supported package manager found (expected apt-get, dnf, or pacman); install git curl python3 pipx node npm lsof procps, or pass --skip-deps"
      fi
      ;;
  esac
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

pipx_has_package() {
  local package="$1"
  have pipx || return 1
  pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$package"
}

manifest_set() {
  local key="$1" value="$2" tmp
  [[ "$CHECK_ONLY" == "1" ]] && return 0
  mkdir -p "$RUNTIME_STATE"
  tmp="$(mktemp)"
  if [[ -f "$RUNTIME_INSTALL_MANIFEST" ]]; then
    awk -F= -v key="$key" -v value="$value" '
      BEGIN { done = 0 }
      $1 == key { print key "=" value; done = 1; next }
      { print }
      END { if (!done) print key "=" value }
    ' "$RUNTIME_INSTALL_MANIFEST" > "$tmp"
  else
    {
      printf 'APX_INSTALL_MANIFEST_VERSION=1\n'
      printf '%s=%s\n' "$key" "$value"
    } > "$tmp"
  fi
  mv "$tmp" "$RUNTIME_INSTALL_MANIFEST"
}

npm_cache_content_path() {
  local cache_dir="$1" integrity="$2"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$cache_dir" "$integrity" <<'PY'
import base64
import os
import sys

cache_dir, integrity = sys.argv[1], sys.argv[2]
if not integrity.startswith("sha512-"):
    sys.exit(1)
raw = base64.b64decode(integrity.split("-", 1)[1])
digest = raw.hex()
print(os.path.join(cache_dir, "_cacache", "content-v2", "sha512", digest[:2], digest[2:4], digest[4:]))
PY
}

record_npm_cache_path() {
  local spec="$1" key="$2" cache_dir="$3" integrity path
  [[ -n "$cache_dir" ]] || return 0
  integrity="$(npm view "$spec" dist.integrity 2>/dev/null | tr -d '[:space:]' || true)"
  [[ -n "$integrity" ]] || return 0
  path="$(npm_cache_content_path "$cache_dir" "$integrity" 2>/dev/null || true)"
  [[ -n "$path" ]] || return 0
  manifest_set "$key" "$path"
}

install_deps() {
  if [[ "$SKIP_DEPS" == "1" ]]; then
    log "skipping dependency installation"
    return 0
  fi

  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

  if [[ "${APX_FORCE_INSTALL_PREREQS:-0}" == "1" ]] || ! have pipx || ! have node || ! have npm || ! have curl; then
    install_platform_prereqs
    [[ "$CHECK_ONLY" == "1" ]] && return 0
    export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  fi
  manifest_set APX_INSTALL_MANIFEST_VERSION 1

  have pipx || die "pipx is required after prerequisite installation"

  local headroom_preexisting=0
  if have headroom || pipx_has_package headroom-ai; then
    headroom_preexisting=1
  fi
  if ! have headroom && ! pipx_has_package headroom-ai; then
    run_step "install headroom-ai proxy" pipx install "headroom-ai[proxy]"
    if (( headroom_preexisting == 0 )) && pipx_has_package headroom-ai; then
      manifest_set HEADROOM_AI_INSTALLED 1
    fi
  elif ! have headroom; then
    log "headroom-ai already installed via pipx; run 'pipx ensurepath' if headroom is not on PATH"
  else
    log "Headroom already available: $(command -v headroom)"
  fi

  if have pipx; then
    run_step "ensure headroom-ai code extras" pipx runpip headroom-ai install "headroom-ai[code]"
    if ! have ast-grep && ! have sg; then
      run_step "install ast-grep-cli into headroom environment" pipx inject headroom-ai ast-grep-cli --include-apps --force
      manifest_set AST_GREP_CLI_INJECTED 1
    else
      log "ast-grep already available"
    fi
  fi

  if have headroom; then
    run_step "install Headroom helper tools" headroom tools install --tool difft --tool scc
    if [[ "$(uname -s)" == "Darwin" ]]; then
      manifest_set HEADROOM_TOOLS_CACHE_DIR "$HOME/Library/Caches/headroom/bin"
    else
      manifest_set HEADROOM_TOOLS_CACHE_DIR "${XDG_CACHE_HOME:-$HOME/.cache}/headroom/bin"
    fi
  else
    warn "headroom command is not on PATH yet; restart your shell or rerun after pipx ensurepath"
  fi

  if have npm; then
    local npm_cache
    npm_cache="$(npm config get cache 2>/dev/null || true)"
    if [[ -n "$npm_cache" ]]; then
      manifest_set NPM_CACHE_DIR "$npm_cache"
    fi
    run_step "prewarm pxpipe-proxy npm cache" npm cache add pxpipe-proxy@0.8.0
    manifest_set NPM_WARMED_PXPIPE_PROXY 1
    record_npm_cache_path pxpipe-proxy@0.8.0 NPM_PXPIPE_PROXY_CACHE_PATH "$npm_cache"
    run_step "prewarm squeezr-ai npm cache" npm cache add squeezr-ai
    manifest_set NPM_WARMED_SQUEEZR_AI 1
    record_npm_cache_path squeezr-ai NPM_SQUEEZR_AI_CACHE_PATH "$npm_cache"
  else
    warn "npm is not available; pxpipe-proxy and squeezr-ai will be fetched by npx on first start"
  fi
}

backup_if_different() {
  local src="$1"
  local dst="$2"
  if [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
    local backup
    backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
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
          print "# Added by apx installer from current defaults."
          header = 1
        }
        print $0
      }
    }
  ' "$RUNTIME_CONFIG" "$SRC_CONFIG" >> "$tmp"
  mv "$tmp" "$RUNTIME_CONFIG"
}

sync_dashboard() {
  if [[ ! -f "$SRC_DASHBOARD_HTML" ]]; then
    warn "no dashboard.html in source tree; dashboard will show a placeholder page"
    return 0
  fi
  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "would install dashboard html to $RUNTIME_DASHBOARD_HTML"
    return 0
  fi
  mkdir -p "$RUNTIME_SHARE_DIR"
  run_step "install dashboard html" cp "$SRC_DASHBOARD_HTML" "$RUNTIME_DASHBOARD_HTML"
}

install_bin() {
  # Atomic install: `install` writes to a temp file and renames into place, so
  # a killed installer can never leave a half-written executable that a
  # concurrent `apx update` would then try to run.
  local src="$1" dst="$2" label="$3"
  backup_if_different "$src" "$dst"
  run_step "install $label" install -m 0755 "$src" "$dst"
}

sync_runtime() {
  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "would sync runtime command/config into launchd-safe paths"
  else
    mkdir -p "$RUNTIME_BIN_DIR" "$RUNTIME_CONFIG_DIR" "$RUNTIME_STATE/logs" "$RUNTIME_STATE/run" "$RUNTIME_SHARE_DIR"
  fi

  if [[ "$FROM_PAYLOAD" == "1" ]]; then
    # In release mode the apx.sh header already created symlinks in
    # ~/.local/bin/apx* that point at the versioned bin dir. Trying to
    # `install -m 0755 SRC DST` where DST is a symlink to SRC fails, so we
    # skip the binary sync entirely here.
    log "from-payload: binaries already symlinked by apx.sh"
  else
    install_bin "$SRC_BIN"         "$RUNTIME_BIN"         "runtime command"
    install_bin "$SRC_GATEWAY_BIN" "$RUNTIME_GATEWAY_BIN" "runtime gateway"
    install_bin "$SRC_SQUEEZR_BIN" "$RUNTIME_SQUEEZR_BIN" "runtime Squeezr helper"
  fi

  sync_dashboard

  if [[ -f "$SRC_VERSION_FILE" && "$CHECK_ONLY" != "1" ]]; then
    printf '%s\n' "$STACK_VERSION" > "$RUNTIME_VERSION_FILE"
    log "recorded installed version: $STACK_VERSION"
  fi

  if [[ "$CHECK_ONLY" != "1" ]]; then
    local install_mode_file="$RUNTIME_CONFIG_DIR/install.mode"
    if [[ "$FROM_PAYLOAD" == "1" ]]; then
      # Release-mode installs come from an extracted payload, not a git clone.
      # Remove any stale dev-mode source pointer so `apx update` uses the
      # release channel instead of trying to git pull a directory that no
      # longer exists.
      rm -f "$RUNTIME_SOURCE_PATH_FILE"
    elif [[ -d "$STACK_ROOT/.git" ]]; then
      printf '%s\n' "$STACK_ROOT" > "$RUNTIME_SOURCE_PATH_FILE"
      log "recorded source repo path for future updates: $STACK_ROOT"
      # If a previous release-mode install left an install.mode=release file,
      # clear it so `apx update` routes through the dev-mode git branch and
      # doesn't try to fetch apx.sh from GitHub Releases on top of a git clone.
      if [[ -f "$install_mode_file" ]] && grep -qx release "$install_mode_file" 2>/dev/null; then
        log "removing stale install.mode=release (dev install detected)"
        rm -f "$install_mode_file"
      fi
    fi
  fi

  sync_config

  if [[ "$CHECK_ONLY" != "1" && -f "$RUNTIME_CONFIG" ]]; then
    local tmp_cfg
    tmp_cfg="$(mktemp)"
    if have npx; then
      sed 's|^PXPIPE_CMD=.*|PXPIPE_CMD="npx -y pxpipe-proxy@0.8.0"|' "$RUNTIME_CONFIG" > "$tmp_cfg" && mv "$tmp_cfg" "$RUNTIME_CONFIG"
    else
      # Use npm exec as a fallback (npm is guaranteed by install_deps)
      sed 's|^PXPIPE_CMD=.*|PXPIPE_CMD="npm exec --yes pxpipe-proxy@0.8.0"|' "$RUNTIME_CONFIG" > "$tmp_cfg" && mv "$tmp_cfg" "$RUNTIME_CONFIG"
    fi
  fi
}

configure_claude_client() {
  if [[ "$CLIENT_TOPOLOGY" == "none" ]]; then
    if [[ "$YES" == "1" || ! -t 0 ]]; then
      log "Claude client topology not configured; run 'apx claude configure' or 'apx claude set ...'"
      return 0
    fi
    run_step "configure Claude client topology" env APX_CONFIG="$RUNTIME_CONFIG" APX_STATE="$RUNTIME_STATE" "$RUNTIME_BIN" claude configure
    return
  fi
  local value="$CLIENT_TOPOLOGY"
  [[ "$CLIENT_TOPOLOGY" == "custom" ]] && value="$CLIENT_BASE_URL"
  run_step "configure Claude client topology ($CLIENT_TOPOLOGY)" env APX_CONFIG="$RUNTIME_CONFIG" APX_STATE="$RUNTIME_STATE" "$RUNTIME_BIN" claude set "$value"
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
  apx dashboard:    http://$bind_host:$gateway_port/
  Gateway health:   http://$bind_host:$gateway_port/livez
  apx status API:   http://$bind_host:$gateway_port/api/status
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

  if (( ${#checks[@]} == 0 )); then
    log "no services enabled; skipping health probe"
    return 0
  fi

  until urls_ok "${checks[@]}"; do
    if (( SECONDS >= deadline )); then
      "$RUNTIME_BIN" status || true
      die "service did not become healthy within 60s; inspect logs with: apx logs supervisor"
    fi
    sleep 2
  done

  "$RUNTIME_BIN" status
}

install_service() {
  if [[ "$NO_START" == "1" ]]; then
    log "skipping service install/start because --no-service was set"
    return 0
  fi
  local agent_root="${RUNTIME_APX_ROOT:-$STACK_ROOT}"
  run_step "install/start apx service" env APX_ROOT="$agent_root" APX_SERVICE_BACKEND="$SERVICE_BACKEND" "$RUNTIME_BIN" install
}

uninstall() {
  # Delegate to `apx uninstall --purge` so the CLI is the single source of
  # truth for what a purge removes. If the CLI is missing we fall back to
  # removing the binaries only.
  if [[ -x "$RUNTIME_BIN" ]]; then
    if [[ "$PURGE" == "1" ]]; then
      run_step "apx uninstall --purge" "$RUNTIME_BIN" uninstall --purge --yes
    else
      run_step "apx uninstall (service only)" "$RUNTIME_BIN" uninstall
    fi
    return 0
  fi
  run_step "remove runtime command" rm -f "$RUNTIME_BIN" "$RUNTIME_GATEWAY_BIN" "$RUNTIME_SQUEEZR_BIN"
  log "note: apx CLI was already missing; run install.sh --purge on a source clone to remove state/config"
}

main() {
  require_supported_os
  require_sources

  log "apx installer version $STACK_VERSION"

  if [[ "$UNINSTALL" == "1" ]]; then
    uninstall
    return 0
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "check-only mode: no changes will be made"
  elif [[ "$YES" != "1" ]]; then
    confirm "Install/sync apx runtime files and safe dependencies?" || die "aborted"
  fi

  install_deps
  sync_runtime
  configure_claude_client
  install_service
  validate_health
  print_urls
  log "done"
}

main "$@"
