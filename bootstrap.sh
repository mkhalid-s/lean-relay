#!/usr/bin/env bash
# One-shot dev installer for LeanRelay (`apx`).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mkhalid-s/lean-relay/main/bootstrap.sh | bash
#   APX_REF=v0.1.0 curl -fsSL .../bootstrap.sh | bash
#   APX_SRC_DIR=$HOME/code/apx curl -fsSL .../bootstrap.sh | bash
#
# Environment variables (legacy AI_PROXY_STACK_* names are also honored):
#   APX_REPO      git URL to clone (default: mkhalid-s/lean-relay on GitHub)
#   APX_REF       git ref to check out (branch, tag, or SHA; default: main)
#   APX_SRC_DIR   checkout path (default: $HOME/.local/share/apx-src)
#   APX_YES       if set to 0, pass through interactive install (default: 1)
#   APX_SERVICE_BACKEND  auto|launchd|systemd|nohup (default: auto)
#   APX_SKIP_DEPS if set to 1, skip dependency installation
#   APX_NO_SERVICE if set to 1, install files without starting a service
#   APX_CLIENT_TOPOLOGY local|docker-host|custom|none
#   APX_CLIENT_BASE_URL URL used with custom topology

set -Eeuo pipefail

REPO="${APX_REPO:-${AI_PROXY_STACK_REPO:-https://github.com/mkhalid-s/lean-relay.git}}"
REF="${APX_REF:-${AI_PROXY_STACK_REF:-main}}"
CLONE_DIR="${APX_SRC_DIR:-${AI_PROXY_STACK_DIR:-$HOME/.local/share/apx-src}}"
YES_FLAG="${APX_YES:-${AI_PROXY_STACK_YES:-1}}"
SERVICE_BACKEND="${APX_SERVICE_BACKEND:-auto}"
SKIP_DEPS="${APX_SKIP_DEPS:-0}"
NO_SERVICE="${APX_NO_SERVICE:-0}"
CLIENT_TOPOLOGY="${APX_CLIENT_TOPOLOGY:-none}"
CLIENT_BASE_URL="${APX_CLIENT_BASE_URL:-}"

log() { printf '[apx:bootstrap] %s\n' "$*"; }
die() { printf '[apx:bootstrap] error: %s\n' "$*" >&2; exit 1; }

if ! command -v git >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin) die "git is required. Install Xcode command line tools: xcode-select --install" ;;
    Linux) die "git is required. Install it with apt, dnf, or pacman, then retry" ;;
    *) die "git is required" ;;
  esac
fi

mkdir -p "$(dirname "$CLONE_DIR")"

if [[ -d "$CLONE_DIR/.git" ]]; then
  log "updating existing clone at $CLONE_DIR"
  git -C "$CLONE_DIR" remote set-url origin "$REPO"
  git -C "$CLONE_DIR" fetch --tags --prune origin
else
  log "cloning $REPO into $CLONE_DIR"
  git clone "$REPO" "$CLONE_DIR"
fi

if ! git -C "$CLONE_DIR" rev-parse --verify --quiet "$REF" >/dev/null; then
  die "ref not found in $REPO: $REF"
fi
git -C "$CLONE_DIR" checkout "$REF"
if git -C "$CLONE_DIR" symbolic-ref -q HEAD >/dev/null; then
  git -C "$CLONE_DIR" pull --ff-only origin "$REF" 2>/dev/null \
    || log "note: could not fast-forward $REF"
fi

INSTALLER="$CLONE_DIR/install.sh"
[[ -x "$INSTALLER" ]] || die "installer missing or not executable: $INSTALLER"

set --
[[ "$YES_FLAG" == "1" ]] && set -- "$@" --yes
[[ "$SKIP_DEPS" == "1" ]] && set -- "$@" --skip-deps
[[ "$NO_SERVICE" == "1" ]] && set -- "$@" --no-service
set -- "$@" --service-backend "$SERVICE_BACKEND"
set -- "$@" --client-topology "$CLIENT_TOPOLOGY"
[[ -n "$CLIENT_BASE_URL" ]] && set -- "$@" --client-base-url "$CLIENT_BASE_URL"
exec "$INSTALLER" "$@"
