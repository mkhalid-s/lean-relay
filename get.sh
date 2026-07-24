#!/usr/bin/env bash
# LeanRelay release bootstrap installer (`apx`).
#
# Fetches the self-extracting apx.sh from a GitHub Release, verifies its
# SHA-256 against the checksum published in the same release, and executes
# it. This is the release-mode counterpart to bootstrap.sh (which does a
# git-clone-based dev install).
#
# Usage:
#   curl -fsSL https://github.com/mkhalid-s/lean-relay/releases/latest/download/get.sh | bash
#   curl -fsSL https://.../get.sh | APX_VERSION=v0.3.0 bash
#   curl -fsSL https://.../get.sh | bash -s -- --no-service --skip-deps
#
# Environment variables:
#   APX_VERSION   release tag to install (default: "latest")
#   APX_REPO      GitHub owner/repo (default: mkhalid-s/lean-relay)
#
# This script is intentionally tiny so a suspicious user can audit it end
# to end before running. It never executes apx.sh unless the checksum
# published alongside it in the same release matches.
set -Eeuo pipefail

REPO="${APX_REPO:-mkhalid-s/lean-relay}"
VERSION="${APX_VERSION:-latest}"

if [[ "$VERSION" == "latest" ]]; then
  URL_PREFIX="https://github.com/$REPO/releases/latest/download"
else
  URL_PREFIX="https://github.com/$REPO/releases/download/$VERSION"
fi

log() { printf '[apx:get] %s\n' "$*" >&2; }
die() { printf '[apx:get] error: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA_CMD=(shasum -a 256)
else
  die "need sha256sum or shasum on PATH"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/apx-get.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

log "downloading apx.sh ($VERSION) from $URL_PREFIX"
curl -fsSL --retry 3 --retry-connrefused "$URL_PREFIX/apx.sh"        -o "$tmp/apx.sh"
curl -fsSL --retry 3 --retry-connrefused "$URL_PREFIX/apx.sh.sha256" -o "$tmp/apx.sh.sha256"

# The published .sha256 references the file as "apx.sh"; normalize the
# expected filename column so `sha256sum -c` matches the local path.
awk '{print $1"  apx.sh"}' "$tmp/apx.sh.sha256" > "$tmp/apx.sh.sha256.local"
( cd "$tmp" && "${SHA_CMD[@]}" -c apx.sh.sha256.local >/dev/null ) \
  || die "SHA-256 verification FAILED for apx.sh (refusing to execute)"
log "checksum verified"

log "running apx.sh $*"
bash "$tmp/apx.sh" "$@"
