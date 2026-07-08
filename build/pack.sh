#!/usr/bin/env bash
# Build the self-extracting apx.sh installer plus its sha256 companion file.
#
# Usage: bash build/pack.sh [--out dist]
#
# Output:
#   dist/apx.sh           self-extracting installer
#   dist/apx.sh.sha256    "<sha256>  apx.sh"

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; OUT_DIR="${1:-}" ;;
    --out=*) OUT_DIR="${1#--out=}" ;;
    -h|--help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

VERSION_FILE="$REPO_ROOT/VERSION"
[[ -f "$VERSION_FILE" ]] || { echo "missing VERSION file at $VERSION_FILE" >&2; exit 1; }
VERSION="$(head -n 1 "$VERSION_FILE" | tr -d '[:space:]')"
[[ -n "$VERSION" ]] || { echo "VERSION file is empty" >&2; exit 1; }
# Constrain VERSION so `sed s/@@VERSION@@/${VERSION}/` (and downstream shell
# expansions) can never inject metacharacters. This is defense in depth against
# a typo like leaving a `/` in VERSION; the shar and every path derived from
# it (versions/vX.Y.Z, apx.sh.sha256, etc.) all assume a plain semver-ish tag.
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([+-][A-Za-z0-9.]+)?$ ]]; then
  echo "error: VERSION file must match ^[0-9]+(\\.[0-9]+){1,2}([+-][A-Za-z0-9.]+)?\$ (got: $VERSION)" >&2
  exit 1
fi

HEADER_SRC="$REPO_ROOT/build/header.sh"
[[ -f "$HEADER_SRC" ]] || { echo "missing $HEADER_SRC" >&2; exit 1; }

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/apx-pack.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

# Files that go into the extracted release tree. Everything else in the repo
# (docs, .github, CHANGELOG, dist, tests, etc.) is deliberately excluded from
# the runtime payload; the release tarball artifact already contains the full
# source snapshot for users who want it.
copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$STAGING/$dst")"
  cp "$REPO_ROOT/$src" "$STAGING/$dst"
}

copy bin/apx                bin/apx
copy bin/apx-gateway        bin/apx-gateway
copy bin/apx-squeezr        bin/apx-squeezr
copy share/dashboard.html   share/dashboard.html
copy config/config.env      config/config.env
copy install.sh             install.sh
copy VERSION                VERSION
[[ -f "$REPO_ROOT/LICENSE" ]] && copy LICENSE LICENSE

chmod +x "$STAGING/bin/"* "$STAGING/install.sh"

PAYLOAD_TGZ="$STAGING/payload.tar.gz"
# Deterministic-ish tar: sorted names, POSIX ustar. Not fully reproducible
# because GNU tar's --mtime flag isn't portable, but close enough for humans.
payload_files=(bin share config install.sh VERSION)
[[ -f "$STAGING/LICENSE" ]] && payload_files+=(LICENSE)
tar -C "$STAGING" \
    --exclude=payload.tar.gz \
    -czf "$PAYLOAD_TGZ" \
    "${payload_files[@]}"

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/apx.sh"

# Render header with @@VERSION@@ replaced, then split at the sentinel and
# splice the base64 payload between BEGIN and END markers.
RENDERED="$STAGING/header.sh"
sed "s/@@VERSION@@/${VERSION}/g" "$HEADER_SRC" > "$RENDERED"

BEGIN_LINE="$(grep -n '^__APX_PAYLOAD_BEGIN__$' "$RENDERED" | head -n 1 | cut -d: -f1)"
END_LINE="$(grep -n '^__APX_PAYLOAD_END__$'   "$RENDERED" | head -n 1 | cut -d: -f1)"
[[ -n "$BEGIN_LINE" && -n "$END_LINE" ]] || { echo "header is missing payload markers" >&2; exit 1; }

{
  head -n "$BEGIN_LINE" "$RENDERED"
  base64 < "$PAYLOAD_TGZ" | fold -w 76
  tail -n "+$END_LINE" "$RENDERED"
} > "$OUT"
chmod +x "$OUT"

# Compute sha256 with whichever tool is available.
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$OUT_DIR" && sha256sum apx.sh > apx.sh.sha256 )
elif command -v shasum >/dev/null 2>&1; then
  ( cd "$OUT_DIR" && shasum -a 256 apx.sh > apx.sh.sha256 )
else
  echo "no sha256sum or shasum available" >&2
  exit 1
fi

size=$(wc -c < "$OUT")
printf '[apx:pack] built %s (%d bytes, version %s)\n' "$OUT" "$size" "$VERSION"
printf '[apx:pack] sha256: %s\n' "$(awk '{print $1}' "$OUT_DIR/apx.sh.sha256")"
