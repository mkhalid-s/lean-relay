#!/usr/bin/env bash
# One-shot installer for apx.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mkhalid-s/ai-proxy-stack/main/bootstrap.sh | bash
#   APX_REF=v0.1.0 curl -fsSL .../bootstrap.sh | bash
#   APX_SRC_DIR=$HOME/code/apx curl -fsSL .../bootstrap.sh | bash
#
# Environment variables (legacy AI_PROXY_STACK_* names are also honored):
#   APX_REPO      git URL to clone (default: mkhalid-s/ai-proxy-stack on GitHub)
#   APX_REF       git ref to check out (branch, tag, or SHA; default: main)
#   APX_SRC_DIR   checkout path (default: $HOME/.local/share/apx-src)
#   APX_YES       if set to 0, pass through interactive install (default: 1)

set -Eeuo pipefail

REPO="${APX_REPO:-${AI_PROXY_STACK_REPO:-https://github.com/mkhalid-s/ai-proxy-stack.git}}"
REF="${APX_REF:-${AI_PROXY_STACK_REF:-main}}"
CLONE_DIR="${APX_SRC_DIR:-${AI_PROXY_STACK_DIR:-$HOME/.local/share/apx-src}}"
YES_FLAG="${APX_YES:-${AI_PROXY_STACK_YES:-1}}"

log() { printf '[apx:bootstrap] %s\n' "$*"; }
die() { printf '[apx:bootstrap] error: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required. Install Xcode command line tools: xcode-select --install"

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

if [[ "$YES_FLAG" == "1" ]]; then
  exec "$INSTALLER" --yes
else
  exec "$INSTALLER"
fi
