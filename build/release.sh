#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: build/release.sh VERSION [--push] [--watch] [--skip-tests]

Prepare a LeanRelay/apx release from a clean main branch.

Steps:
  1. Verify identity, branch, clean tree, and release tag availability.
  2. Move CHANGELOG.md [Unreleased] notes into VERSION's dated section.
  3. Update VERSION.
  4. Run release validations and build dist/apx.sh.
  5. Commit "Release VERSION" and create tag "vVERSION".
  6. With --push, push main and the tag. With --watch, wait for release.yml.

Identity defaults protect this repo's personal-account release flow:
  APX_RELEASE_GH_USER=mkhalid-s
  APX_RELEASE_EXPECT_EMAIL=mkhalid-s@users.noreply.github.com

Examples:
  build/release.sh 0.5.3
  build/release.sh 0.5.3 --push --watch
EOF
}

version=""
push=0
watch=0
skip_tests=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) push=1 ;;
    --watch) watch=1; push=1 ;;
    --skip-tests) skip_tests=1 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$version" ]]; then
        echo "unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      version="$1"
      ;;
  esac
  shift
done

if [[ -z "$version" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.]+)?$ ]]; then
  echo "error: VERSION must be semver-like X.Y.Z, got: $version" >&2
  exit 2
fi

tag="v$version"
expected_email="${APX_RELEASE_EXPECT_EMAIL:-mkhalid-s@users.noreply.github.com}"
expected_gh_user="${APX_RELEASE_GH_USER:-mkhalid-s}"

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ "$current_branch" != "main" ]]; then
  echo "error: releases must be cut from main, current branch is: ${current_branch:-detached}" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty; commit or stash changes before cutting a release" >&2
  git status --short >&2
  exit 1
fi

commit_email="$(git config user.email || true)"
if [[ "$commit_email" != "$expected_email" ]]; then
  echo "error: git user.email is $commit_email, expected $expected_email" >&2
  echo "set APX_RELEASE_EXPECT_EMAIL to override intentionally" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "error: local tag already exists: $tag" >&2
  exit 1
fi
if [[ "$push" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: --push requires GitHub CLI (gh)" >&2
    exit 1
  fi
  gh_login="$(env -u GH_TOKEN gh api user --jq .login 2>/dev/null || true)"
  if [[ "$gh_login" != "$expected_gh_user" ]]; then
    echo "error: active GitHub CLI account is ${gh_login:-unknown}, expected $expected_gh_user" >&2
    echo "run: env -u GH_TOKEN gh auth switch -u $expected_gh_user" >&2
    exit 1
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    echo "error: remote tag already exists: $tag" >&2
    exit 1
  fi
fi

python3 - "$version" <<'CHANGELOG_PY'
import datetime
import re
import sys
from pathlib import Path

version = sys.argv[1]
root = Path.cwd()
(root / "VERSION").write_text(version + "\n")
path = root / "CHANGELOG.md"
text = path.read_text()
marker = "## [Unreleased]"
if marker not in text:
    raise SystemExit("CHANGELOG.md missing ## [Unreleased]")
match = re.search(r"^## \[Unreleased\]\n(?P<body>.*?)(?=^## \[)", text, re.M | re.S)
if not match:
    raise SystemExit("could not parse CHANGELOG.md Unreleased section")
body = match.group("body").strip()
date = datetime.date.today().isoformat()
release_heading = f"## [{version}] - {date}"
if re.search(rf"^## \[{re.escape(version)}\](?:\s|$)", text, re.M):
    raise SystemExit(f"CHANGELOG.md already contains release section for {version}")
if body:
    replacement = f"## [Unreleased]\n\n{release_heading}\n\n{body}\n\n"
else:
    replacement = f"## [Unreleased]\n\n{release_heading}\n\n"
text = text[:match.start()] + replacement + text[match.end():]
path.write_text(text)
CHANGELOG_PY

run_validations() {
  bash -n bin/apx get.sh bootstrap.sh install.sh tests/lifecycle.sh build/pack.sh build/header.sh
  python3 -m py_compile bin/apx-gateway
  git diff --check
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=warning install.sh bootstrap.sh get.sh bin/apx bin/apx-squeezr build/pack.sh build/header.sh tests/lifecycle.sh
  else
    echo "[apx:release] shellcheck not installed locally; release workflow will run it" >&2
  fi
  if [[ "$skip_tests" != "1" ]]; then
    unset FAKE_HOME
    bash tests/lifecycle.sh
  fi
  bash build/pack.sh
  embedded="$(bash dist/apx.sh --print-version)"
  if [[ "$embedded" != "$version" ]]; then
    echo "error: dist/apx.sh version $embedded does not match $version" >&2
    exit 1
  fi
  (cd dist && shasum -a 256 -c apx.sh.sha256)
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/apx-release-${version}.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  bash dist/apx.sh --extract-to "$tmp" >/dev/null
  extracted="$(head -n 1 "$tmp/VERSION" | tr -d '[:space:]')"
  if [[ "$extracted" != "$version" ]]; then
    echo "error: extracted VERSION $extracted does not match $version" >&2
    exit 1
  fi
  bash -n "$tmp/bin/apx" "$tmp/bin/apx-squeezr" "$tmp/install.sh"
}

run_validations

git add VERSION CHANGELOG.md
git -c commit.gpgsign=false commit -m "Release $version"
git -c tag.gpgSign=false tag "$tag"

echo "[apx:release] prepared $tag at $(git rev-parse --short HEAD)"

if [[ "$push" == "1" ]]; then
  env -u GH_TOKEN git -c credential.helper='!gh auth git-credential' push origin main
  env -u GH_TOKEN git -c credential.helper='!gh auth git-credential' push origin "$tag"
  echo "[apx:release] pushed main and $tag"
fi

if [[ "$watch" == "1" ]]; then
  head_sha="$(git rev-parse HEAD)"
  run_id=""
  for _ in $(seq 1 30); do
    run_id="$(env -u GH_TOKEN gh run list --workflow release.yml --limit 10 --json databaseId,headBranch,headSha --jq ".[] | select(.headBranch == \"$tag\" and .headSha == \"$head_sha\") | .databaseId" | head -n 1)"
    [[ -n "$run_id" ]] && break
    sleep 5
  done
  if [[ -z "$run_id" ]]; then
    echo "error: release workflow did not appear for $tag" >&2
    exit 1
  fi
  env -u GH_TOKEN gh run watch "$run_id" --exit-status
  env -u GH_TOKEN gh release view "$tag" --json tagName,url,isDraft,isPrerelease,publishedAt,assets
fi
