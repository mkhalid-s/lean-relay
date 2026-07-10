#!/usr/bin/env bash
# apx-version: @@VERSION@@
#
# Self-extracting installer for LeanRelay (apx).
#
# Layout after install:
#   ~/.local/share/apx/versions/vX.Y.Z/    extracted payload
#   ~/.local/share/apx/current              symlink -> versions/vX.Y.Z
#   ~/.local/bin/apx*                        symlinks -> current/bin/apx*
#   ~/.config/apx/install.mode               "release" (drives apx update)
#
# Common usage:
#   bash apx.sh                             install and start the service
#   bash apx.sh --print-version             print embedded version and exit
#   bash apx.sh --no-service                extract only; do not touch launchd
#   bash apx.sh --dry-run                   show what would happen; no writes
#   bash apx.sh --force                     reinstall over an existing version
#   bash apx.sh --extract-to <dir>          extract payload into <dir> and stop

set -Eeuo pipefail

APX_EMBEDDED_VERSION="@@VERSION@@"

log()  { printf '[apx:installer] %s\n' "$*"; }
warn() { printf '[apx:installer] warning: %s\n' "$*" >&2; }
die()  { printf '[apx:installer] error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
apx installer for LeanRelay (embedded version: $APX_EMBEDDED_VERSION)

Usage: bash apx.sh [options]

Options:
  --print-version         Print embedded apx version and exit
  --extract-to <dir>      Extract payload into <dir> and exit (no install)
  --no-service            Sync files but do not start the LaunchAgent
  --skip-deps             Do not install/refresh Homebrew or pipx dependencies
  --force                 Overwrite an existing installation of this version
  --dry-run               Show what would happen; make no changes
  -h, --help              Show this help
EOF
}

DRY_RUN=0
FORCE=0
NO_SERVICE=0
SKIP_DEPS=0
PRINT_VERSION=0
EXTRACT_ONLY=""
INSTALL_YES="${APX_YES:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-version) PRINT_VERSION=1 ;;
    --extract-to) shift; EXTRACT_ONLY="${1:-}" ;;
    --extract-to=*) EXTRACT_ONLY="${1#--extract-to=}" ;;
    --no-service) NO_SERVICE=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift || true
done

if [[ "$PRINT_VERSION" == "1" ]]; then
  printf '%s\n' "$APX_EMBEDDED_VERSION"
  exit 0
fi

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[apx:installer] would: '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

base64_decode() {
  # macOS BSD and GNU coreutils both accept -d for decode; older BSD used -D.
  # If neither works we die with a clear message rather than letting the
  # downstream tar/gzip surface an opaque "unexpected EOF" error.
  if base64 -d </dev/null >/dev/null 2>&1; then
    base64 -d
  elif base64 -D </dev/null >/dev/null 2>&1; then
    base64 -D
  else
    die "no working base64 decoder found (tried '-d' and '-D')"
  fi
}

# Extract the embedded payload to $1. Refuses when the file is piped from
# stdin (e.g. curl | bash) because there is no seekable self to read from.
extract_payload() {
  local dest="$1"
  local self="${BASH_SOURCE[0]}"
  if [[ -z "$self" || ! -f "$self" ]]; then
    die "cannot self-extract: run this file directly (e.g. bash apx.sh), not via 'curl | bash'"
  fi
  mkdir -p "$dest"
  awk '
    /^__APX_PAYLOAD_END__$/   { exit }
    seen                      { print }
    /^__APX_PAYLOAD_BEGIN__$/ { seen=1 }
  ' "$self" | base64_decode | tar -xz -C "$dest"
}

SHARE_ROOT="${APX_SHARE:-$HOME/.local/share/apx}"
VERSIONS_DIR="$SHARE_ROOT/versions"
CURRENT_LINK="$SHARE_ROOT/current"
BIN_DIR="${APX_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="$(dirname "${APX_CONFIG:-$HOME/.config/apx/config.env}")"
INSTALL_MODE_FILE="$CONFIG_DIR/install.mode"

VERSION_TAG="v${APX_EMBEDDED_VERSION}"
TARGET_DIR="$VERSIONS_DIR/$VERSION_TAG"
STAGING_DIR="$VERSIONS_DIR/.$VERSION_TAG.tmp.$$"

if [[ -n "$EXTRACT_ONLY" ]]; then
  log "extracting payload to $EXTRACT_ONLY"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: no extraction performed"
    exit 0
  fi
  extract_payload "$EXTRACT_ONLY"
  log "done"
  exit 0
fi

case "$(uname -s)" in
  Darwin) ;;
  Linux)
    warn "Linux is best-effort: LaunchAgent step will be skipped and dependency install (Homebrew/pipx) is macOS-only"
    NO_SERVICE=1
    # install.sh's dep step gates on Homebrew, which is macOS-only, so
    # a Linux run would die inside require_brew_for_deps. Auto-skip so the
    # file-sync path completes and users still get a working CLI.
    SKIP_DEPS=1
    ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac

if ! grep -q '^__APX_PAYLOAD_BEGIN__$' "${BASH_SOURCE[0]}" 2>/dev/null; then
  die "installer is missing its embedded payload; the file is likely corrupted"
fi

log "apx $APX_EMBEDDED_VERSION -> $TARGET_DIR"

if [[ -d "$TARGET_DIR" && "$FORCE" != "1" ]]; then
  # Exact-match the current symlink target so a partial-prefix tag (e.g.
  # v0.2 vs v0.2.0, or v0.2.0 vs v0.2.0-rc1) does not spuriously match.
  if [[ -L "$CURRENT_LINK" && "$(readlink "$CURRENT_LINK")" == "versions/$VERSION_TAG" ]]; then
    log "already installed and active: $VERSION_TAG"
    log "use --force to reinstall, or run: apx update"
    exit 0
  fi
  log "version $VERSION_TAG is already extracted; flipping current -> $VERSION_TAG"
else
  if [[ "$DRY_RUN" == "1" ]]; then
    log "would extract payload into $TARGET_DIR"
  else
    mkdir -p "$VERSIONS_DIR"
    rm -rf "$STAGING_DIR"
    trap 'rm -rf "$STAGING_DIR"' EXIT
    extract_payload "$STAGING_DIR"

    for required in bin/apx bin/apx-gateway bin/apx-squeezr install.sh VERSION; do
      [[ -e "$STAGING_DIR/$required" ]] || die "payload is missing $required"
    done
    chmod +x "$STAGING_DIR/bin/"* "$STAGING_DIR/install.sh"

    if [[ -d "$TARGET_DIR" ]]; then
      rm -rf "$TARGET_DIR"
    fi
    mv "$STAGING_DIR" "$TARGET_DIR"
    trap - EXIT
    log "extracted to $TARGET_DIR"
  fi
fi

flip_current() {
  local target="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "would flip $CURRENT_LINK -> $target"
    return 0
  fi
  mkdir -p "$SHARE_ROOT"
  # Record the version we are moving AWAY from so `apx rollback` can undo
  # the shar upgrade even if the user never ran `apx use` before. The state
  # dir might not exist yet on a fresh install; create it on demand.
  local state_dir="${APX_STATE:-$HOME/.local/state/apx}"
  if [[ -L "$CURRENT_LINK" ]]; then
    local prev_tag
    prev_tag="$(basename "$(readlink "$CURRENT_LINK")")"
    if [[ -n "$prev_tag" && "$prev_tag" != "$(basename "$target")" ]]; then
      mkdir -p "$state_dir" 2>/dev/null || true
      printf '%s\n' "$prev_tag" > "$state_dir/previous.tag" 2>/dev/null || true
    fi
  fi
  # `ln -sfn NEW EXISTING` unlinks and re-symlinks. Not perfectly atomic, but
  # microsecond risk window is acceptable and matches `stow`, `nvm`, `rustup`.
  # Do NOT use `mv -f tmp existing_symlink`: macOS mv follows the symlink and
  # moves tmp INTO the target directory (a versioned dir), leaving current
  # unchanged.
  ln -sfn "$target" "$CURRENT_LINK"
  log "current -> $target"
}
flip_current "versions/$VERSION_TAG"

link_bin() {
  local name="$1"
  local src="$CURRENT_LINK/bin/$name"
  local dst="$BIN_DIR/$name"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "would symlink $dst -> $src"
    return 0
  fi
  mkdir -p "$BIN_DIR"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    mv -f "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
  fi
  ln -sfn "$src" "$dst"
}
link_bin apx
link_bin apx-gateway
link_bin apx-squeezr

if [[ "$DRY_RUN" != "1" ]]; then
  mkdir -p "$CONFIG_DIR"
  printf 'release\n' > "$INSTALL_MODE_FILE"
fi

INSTALLER="$TARGET_DIR/install.sh"
if [[ "$DRY_RUN" != "1" && ! -x "$INSTALLER" ]]; then
  die "installer missing in payload: $INSTALLER"
fi

installer_flags=(--from-payload)
if [[ "$INSTALL_YES" == "1" ]]; then
  installer_flags+=(--yes)
fi
if [[ "$NO_SERVICE" == "1" ]]; then
  installer_flags+=(--no-start)
fi
if [[ "$SKIP_DEPS" == "1" ]]; then
  installer_flags+=(--skip-deps)
fi
if [[ "$DRY_RUN" == "1" ]]; then
  installer_flags+=(--check-only)
fi

log "running installer: ${installer_flags[*]}"
APX_INSTALL_MODE_ROOT="$CURRENT_LINK" \
APX_INSTALL_MODE="release" \
run "$INSTALLER" "${installer_flags[@]}"

log "install complete"
exit 0

__APX_PAYLOAD_BEGIN__
__APX_PAYLOAD_END__
