# Changelog

All notable changes to apx are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Manifest-backed dependency/cache uninstall cleanup.** `apx uninstall`
  keeps plain `--purge` limited to apx-owned files, but now supports explicit
  opt-in categories for resources the installer recorded creating or warming:
  `--purge=deps`, `--purge=caches`, and `--purge=all,deps,caches`.
  Dry-run prints the exact planned actions before anything is removed. The
  recorded source clone is also explicit-only via `--purge=source`.

### Changed

- **`--purge=source` is now opt-in.** Plain `--purge` no longer removes the
  recorded source clone. Pass `--purge=source` (or include it in the
  comma-separated list) to remove it.

### Fixed

- **Uninstall path safety.** Directory purges now validate that recursive
  delete targets are non-root children of the active `$HOME`, preventing
  accidental broad deletes if path override environment variables are unsafe.
- **Refuse non-default apx paths on `--purge`.** `apx uninstall --purge` now
  refuses to run when `APX_SHARE`, `APX_STATE`, or `APX_CONFIG` point outside
  the default `~/.local/share/apx`, `~/.local/state/apx`, `~/.config/apx`
  layout, closing an env-override path that could target arbitrary directories
  under `$HOME`.
- **Validate `APX_LABEL` on startup.** `apx` rejects `APX_LABEL` values that
  contain anything outside `[A-Za-z0-9._-]`, preventing traversal into other
  LaunchAgents plists or arbitrary `*.plist` paths under `$HOME`.
- **Nested source clone guard.** `--purge=share|state|config` now refuses to
  remove a category directory when the recorded source clone (from
  `~/.config/apx/source.path`) lives inside it, and instructs the user to run
  `apx uninstall --purge=source` first or relocate the clone.
- **Lazy runtime directory creation.** `~/.local/state/apx/run` and
  `~/.local/state/apx/logs` are only created by commands that need them
  (`start`, `install`, `supervisor`), not at every CLI invocation. `apx --help`
  and `apx uninstall --dry-run` no longer touch the filesystem.
- **Uninstall `state`-without-`deps,caches` note.** When `--purge=state` is
  invoked without `deps`/`caches` and the install manifest still exists, apx
  prints a note that the manifest is about to be removed and suggests the
  combined form `--purge=all,deps,caches`. The note (and the env-override
  refusal) print before the interactive confirmation, so users can back out
  without ever typing `yes`.
- **Trailing-slash tolerance on `APX_SHARE`/`APX_STATE`/`APX_CONFIG`.** The
  default-layout guard now normalizes a trailing `/`, so
  `APX_SHARE=$HOME/.local/share/apx/` is accepted instead of being refused as
  non-default.
- **`log()` self-heals a missing `~/.local/state/apx/logs`.** If the log
  directory was manually removed between `apx start` and `apx stop`, the
  stop path no longer aborts under `set -Eeuo pipefail` before killing the
  supervisor and children.

## [0.1.0] - 2026-07-08

_Initial public release. `v0.1` was never published; all pre-release work
(rebrand to `apx`, unified dashboard, gateway v0.2, chain routing, single-file
distribution) ships together as `0.1.0`._

### Fixed (round-2 review swarm)

- **`apx use` respects a stopped service.** After a version switch, we
  used to unconditionally kickstart the LaunchAgent. If the user had
  run `apx stop` we would auto-start it back up. Now we only restart
  when `launchctl print` shows the service is currently loaded, and
  otherwise emit a `run 'apx start' to load the new version` note.
- **Launchd label read from the installed plist.** `apx use` and
  `apx rollback` no longer trust `$LABEL` from the caller's env for
  the `launchctl kickstart` target — they read the actual `Label` key
  from `$PLIST_FILE` via `plutil` (or `defaults` as a fallback), so a
  one-off `APX_LABEL=custom` invocation never mis-targets the wrong
  service on subsequent switches.
- **Semver-correct version ordering.** Replaced `sort -V` in
  `list_installed_versions` with an in-CLI comparator (awk tokenises
  each tag; sort uses numeric keys). GNU and BSD `sort -V` disagree
  on pre-release ordering (`v0.2.0-rc1` vs `v0.2.0`); the new logic
  follows the semver spec everywhere: release > pre-release within
  the same base version.
- **`apx.sh` upgrade seeds `previous.tag`.** The self-extracting
  header now records the previously-active tag before flipping
  `current`, so `apx rollback` immediately after an `apx.sh` upgrade
  correctly undoes the upgrade instead of falling back to the
  version-sort heuristic.
- **Linux `apx update` no longer dies in `require_brew_for_deps`.**
  The shar header auto-adds `--skip-deps` on Linux (in addition to
  `--no-service`), so a release-channel update on WSL or a Linux dev
  box completes without trying to install pipx/headroom/node via
  Homebrew.
- **`do_update_release` cleanup is now trap-guaranteed.** The
  downloaded shar temp dir is cleaned up in a subshell whose `EXIT`
  trap fires on every path, including bash abort under
  `set -Eeuo pipefail`. Previous `RETURN`-only trap could leak the
  temp dir on `bash "$downloaded"` failures.
- **`cleanup` clears stale `previous.tag`.** If `apx cleanup` deletes
  the version recorded in `state/previous.tag`, the pointer file is
  removed so a subsequent `apx rollback` falls back cleanly instead
  of erroring on a missing directory.
- **`flip_current_to` refreshes the top-level `dashboard.html`.**
  `~/.local/share/apx/dashboard.html` (which the gateway serves) is
  overwritten with the target version's copy on every switch, so
  `apx use vOLD` no longer leaves the newer dashboard in place.
- **Filesystem-first `install.mode` inference.** `read_install_mode`
  now checks `versions/` + `current` before consulting the
  `install.mode` file, and self-heals a stale `dev` file when the
  release layout is present. Prevents an old file from misrouting
  `apx update` after a mode change.
- **Rollback prints a note on fallback.** When `previous.tag` exists
  but points at a missing or same-as-current version, we log a
  "recorded previous version unavailable; picking newest installed
  tag" line before flipping, so the heuristic pick is visible.
- **CHANGELOG PR guard is strict.** The CI check now escapes regex
  metacharacters in the version and right-anchors the heading, so a
  `0.2.0` bump no longer false-matches `## [0.2.0-rc1]`,
  `## [0.20.0]`, or `## [0.2.0.1]`.
- **Comment and error hygiene.** Corrected the `ln -sfn` atomicity
  comment (unlink+symlink, not `rename()`); replaced the stale
  "array expansion" rationale in `do_update_release`; and added a
  clear `die "no working base64 decoder found"` diagnostic in the
  shar header when neither `-d` nor `-D` is supported.
- **CI shasum consistency.** Release workflow now uses `sha256sum`
  end-to-end on Ubuntu runners instead of mixing `shasum -a 256`.

### Fixed (post-review swarm)

- **state/VERSION mismatch after `apx use` / rollback.** `flip_current_to`
  wrote `v0.2.0` while `install.sh` writes `0.2.0`, breaking
  `apx check-updates` and the release-mode "already up to date" guard.
  Both writers now use the unprefixed `X.Y.Z` form.
- **Service reload after version switch.** `apx use` and `apx rollback`
  used to re-exec `$0 restart` through the just-flipped symlink, which
  could wedge if the new version renamed the `restart` subcommand. They
  now call `launchctl kickstart -k` (with `bootstrap` fallback) directly.
- **Rollback semantics.** `apx rollback` used to pick the highest
  non-current tag by version sort, which meant rolling back from
  `apx use vOLD` jumped forward instead of undoing the switch.
  `flip_current_to` now records the previous tag in
  `$STATE_DIR/previous.tag` and `apx rollback` uses that first, falling
  back to version sort only when the pointer is absent.
- **Prefix-tag false match in `apx.sh`.** The header's "already
  installed" fast path used substring matching (`*"$VERSION_TAG"*`), so
  `v0.2` would spuriously match `versions/v0.2.0-rc1`. Now compared for
  exact equality.
- **`apx update` misleading summary.** When the shar short-circuited
  with "already installed", `do_update_release` still printed
  `pre -> post`. It now prints an explicit "unchanged" line.
- **bash 3.2 unbound arrays.** `${extra[@]}` in `do_update_release` and
  `${checks[@]}` in `install.sh validate_health` blew up under
  `set -Eeuo pipefail` on macOS's default bash when the array was
  empty. Both are guarded now.
- **BSD/GNU `stat` portability.** Completion-staleness check used
  `stat -f %m` (BSD only). New `mtime_of` helper tries `stat -c %Y`
  (GNU) first, then `stat -f %m`, so Linux CI and WSL work correctly.
- **`set -e` swallowed rollback error path.** `list_installed_versions
  | grep -v | head -n 1` aborted the whole CLI when `grep` matched
  nothing. Wrapped in `{ ...; } || true`.
- **VERSION templating in `pack.sh`.** `sed s/@@VERSION@@/${VERSION}/`
  would break if VERSION ever contained `/`, `\`, `&`, or newline. Now
  validated against a strict regex before packing.
- **`bash apx.sh --dry-run` on fresh install.** The installer
  executability check ran unconditionally, so dry-run died with
  "installer missing in payload" before printing the preview. Skipped
  in dry-run mode.
- **`install.mode` inference and cleanup.** `read_install_mode` now
  falls back to filesystem inspection when the file is missing but
  `versions/` and `current` exist (and self-heals). Dev-mode
  reinstalls now clear a stale `install.mode=release` so
  `apx update` uses the right channel.
- **`--to <ref>` on custom release URLs.** The URL rewrite from
  `/releases/latest/` to `/releases/download/<tag>/` used to silently
  no-op on non-GitHub URLs, fetching whatever "latest" resolved to.
  It now errors out explicitly.
- **`apx use` / `flip_current_to` validate the target.** New
  `version_dir_is_valid` gate refuses to flip `current` to a directory
  missing `bin/apx*`, `install.sh`, or `VERSION`.
- **`apx cleanup` refuses on dangling current.** Refuses to delete
  versions when the `current` symlink is missing or points at a
  non-existent directory (previously would have deleted everything).
- **Version ordering.** Sort by `sort -V` on tag names instead of
  `ls -1t` mtime, which is fragile after restore-from-backup or rsync.
- **`mktemp -d -t` naming drift.** Both `bin/apx` and `build/pack.sh`
  now use `mktemp -d "${TMPDIR:-/tmp}/apx-*.XXXXXX"` for identical
  behavior on BSD and GNU.
- **`do_update_release` temp dir leak.** Uses `trap ... RETURN` so the
  downloaded shar directory is cleaned up on every exit path, including
  errors under `set -e`.
- **Recovery.** `flip_current_to` now also recreates
  `~/.local/bin/apx*` symlinks defensively so a user who deleted them
  by hand can recover with `apx use vX.Y.Z`.
- **`install.sh --from-payload` on Linux.** `require_macos` now
  permits `--no-start` (or `APX_SKIP_MACOS_GATE=1`) so the release-mode
  Linux path syncs files without gating on Darwin.

### Added (CI/CD)

- **CI split into named parallel jobs:** `lint`, `pack` (linux+macos
  matrix), `smoke` (linux+macos install → 2nd version → rollback →
  use → cleanup → uninstall), and a PR-only `changelog` guard that
  fails when `VERSION` bumps without a matching heading in
  `CHANGELOG.md`. Concurrency group cancels stale runs.
- **Release pipeline gains stages:** `verify` (tag + lint) → `build`
  (tarball + apx.sh + sha256) → `smoke` (install/uninstall the packed
  artifact on Ubuntu and macOS) → `publish`. Cross-job artifact
  upload/download ensures `publish` uses the exact same bytes that
  passed smoke. `fail_on_unmatched_files: true` prevents publishing an
  incomplete release.

### Added

- **Single-file distribution.** `bash build/pack.sh` produces
  `dist/apx.sh` (~60 KB), a self-extracting bash installer that carries
  the runtime as an embedded base64 tarball plus `dist/apx.sh.sha256`.
  Users can install with:
  ```bash
  curl -fsSLO https://github.com/mkhalid-s/ai-proxy-stack/releases/latest/download/apx.sh
  curl -fsSL  https://github.com/mkhalid-s/ai-proxy-stack/releases/latest/download/apx.sh.sha256 | shasum -a 256 -c -
  bash apx.sh
  ```
  Supports `--print-version`, `--extract-to <dir>`, `--no-service`,
  `--skip-deps`, `--force`, `--dry-run`.
- **Versioned install layout.** Release-mode installs write to
  `~/.local/share/apx/versions/vX.Y.Z/` and flip the
  `~/.local/share/apx/current` symlink. `~/.local/bin/apx*` are symlinks
  into `current/bin/`, so version swaps are one `ln -sfn` away.
- **New CLI commands (release mode only):**
  - `apx versions` lists installed versions with the current marked.
  - `apx use <version>` atomically switches `current` to a version and
    restarts the LaunchAgent.
  - `apx rollback` switches to the previous version.
  - `apx cleanup [--keep N] [--dry-run]` prunes older versions while
    always retaining `current`.
- **`apx update` release-mode channel.** When
  `~/.config/apx/install.mode == release`, `apx update` fetches
  `apx.sh` + `apx.sh.sha256` from GitHub Releases, verifies the
  checksum, and re-runs the shar into a fresh versioned dir.
  `--to v0.2.0` and `--to-latest` pin an exact tag; `--dry-run` fetches
  and verifies without installing.
- **`install.sh --from-payload`** internal flag used by the shar
  header. Skips binary sync (already symlinked by the header) and
  clears any stale `source.path` so `apx update` uses the release
  channel.
- **Release workflow** (`release.yml`) now attaches `apx.sh` and
  `apx.sh.sha256` to every tagged build alongside the source tarball.
- **CI checks** (`ci.yml`) now pack `apx.sh`, verify `--print-version`
  matches the `VERSION` file, verify the `.sha256`, and extract into
  a scratch dir to confirm the payload is complete.
- `apx uninstall` grew a categorized `--purge` flag so users can fully
  remove apx. Categories: `binaries`, `share`, `state`, `config`, `claude`,
  `completions`, `source`. Combine with `--dry-run` to preview and
  `--yes` to skip the confirmation prompt. The default `apx uninstall`
  (no flags) still just stops the LaunchAgent. The `share` category
  removes the entire versioned layout (`versions/`, `current`) in one
  shot.
- `apx uninstall --purge=claude` scrubs `ANTHROPIC_BASE_URL` from
  `~/.claude/settings.json` while preserving every other key.
- `apx completions install [--shell bash|zsh|fish]` writes the completion
  script to the canonical location for that shell. `apx completions
  uninstall` removes any files installed by that command.
- `apx update --dry-run` previews git and installer changes.
- `apx update` prints a post-flight summary (old → new version,
  source clone path, whether shell completions look stale).
- `install.sh --purge` alias for `--uninstall`; delegates to
  `apx uninstall --purge --yes` when the CLI is present so there is a
  single canonical uninstall path.

### Changed

- Binaries are now installed via `install -m 0755` (atomic
  write-then-rename) instead of `cp` + `chmod`. An interrupted upgrade
  can no longer leave a partially-written executable on disk.
- Deleted migration/deprecation-shim code (`migrate_legacy`,
  `install_legacy_shim`, `LEGACY_*` constants, per-key
  `AI_PROXY_STACK_*` env fallbacks, `SQUEEZR_CMD` / `GATEWAY_CMD`
  rewrite blocks in `load_config`). v0.1 has never been released
  publicly, so nothing depended on them; keeping them was pure
  maintenance drag.
- `apx uninstall --purge=source` refuses to delete the source clone
  when the running `apx` binary lives inside it, and prints the exact
  `rm -rf` command to run manually afterwards.

- Chain-based routing. `APX_CHAIN` in `config.env` is a comma-separated
  ordered list of local services between the gateway and the upstream.
  All `*_ENABLED` and `*_TARGET_API_URL` values are derived from it.
  Presets in `apx mode` compile down to chains; new `apx chain get/set/
  clear/ls/preset` subcommands expose the primitive for arbitrary orderings.
  Legacy `apx mode` names remain valid aliases.
- `~/.config/apx/prices.env` can override the built-in per-million-token
  cost table without a version bump.
- `APX_METRICS_ENABLED` gates the Prometheus `/metrics` endpoint (default 0).
- `APX_MAX_REQUEST_BYTES` caps the proxied request body size (default 64 MiB).
- Gateway now stamps `X-Apx-Request-Id` on every proxied request. The id is
  echoed back to the client, logged, persisted in history, and available on
  the dashboard.
- Chunked-transfer-encoded request bodies are supported (previously only
  `Content-Length` requests were forwarded correctly).
- Background health probe thread; `/api/status` returns cached snapshots
  instantly instead of blocking up to 4.5s on synchronous probes.
- Gateway passthrough routes at `/proxy/pxpipe/*` and `/proxy/squeezr/*` so
  the dashboard iframes work from inside a devcontainer that reaches the
  gateway over `host.docker.internal`.
- Per-day JSONL history at `~/.local/state/apx/history/YYYY-MM-DD.jsonl`.
  Set `APX_HISTORY_PERSIST=0` to disable.
- Cost + token estimation: gateway parses Anthropic/OpenAI `usage` fields on
  both JSON and SSE responses and reports `tokens_in`, `tokens_out`, and
  `cost_est_usd` per request. Session totals appear on the dashboard.
- Optional dashboard authentication via `APX_DASHBOARD_TOKEN` (Bearer,
  cookie, or `?token=` query string). Non-loopback binds without a token
  refuse to start.
- Prometheus-compatible `/metrics` endpoint.
- `apx completions {bash,zsh,fish}` subcommand emits shell completion
  scripts.
- `apx update --to <ref>`, `--to-latest`, and `--force` for detached HEAD
  and dirty source clones.
- CI workflow (`.github/workflows/ci.yml`): `bash -n`, `shellcheck`,
  `python -m py_compile`, help/completions smoke tests.

### Changed

- The gateway now discovers streamable log files by scanning `$LOG_DIR/*.log`
  instead of using a hardcoded allowlist.
- Dashboard auth accepts Bearer header or `?token=` query parameter only.
  The undocumented cookie path was removed.
- Streaming SSE responses use `resp.read1(65536)` so the first token from the
  model reaches the client the moment the upstream emits it. Buffered JSON
  responses still use blocking reads.
- Token extraction now captures up to 2 MiB of the response body for SSE
  streams so `message_delta` frames near the end of long completions are
  reliably parsed.
- Concurrent `/api/logs/stream` connections per client IP are capped by
  `APX_MAX_LOG_STREAMS_PER_IP` (default 8).
- Response `x-frame-options` and `content-security-policy` headers are
  stripped on `/proxy/pxpipe/*` and `/proxy/squeezr/*` so the dashboard
  iframes render.
- Legacy `AI_PROXY_STACK_*` environment variable fallbacks now only cover
  the load-bearing paths (`APX_ROOT`, `APX_CONFIG`, `APX_STATE`). Tuning
  knobs like `APX_LABEL`, `APX_REPO_URL`, etc. use the `APX_*` names only.

### Removed

- Hand-coded mode permutations in `bin/apx` (`set_mode` case statements)
  and `bin/apx-gateway` (`_current_mode`, `_chain_hops`). Both now compute
  routing from a single `APX_CHAIN` list plus a small service registry.

### Added (foundational)

- Rebranded to `apx`. Commands are `apx`, `apx-gateway`, `apx-squeezr`;
  legacy `ai-proxy-stack*` binaries remain as deprecation shims.
- Unified dashboard served by `apx-gateway` at
  `http://127.0.0.1:8787/`, aggregating mode, health, request history,
  Headroom stats, live log tails, and iframed pxpipe/Squeezr dashboards.
- Versioning: top-level `VERSION` file, `apx version`,
  `apx check-updates`, `apx update` commands.
- One-line install via `bootstrap.sh`.
- GitHub Actions release workflow that verifies the tag matches
  `VERSION` and publishes a tarball + sha256.
- Renamed `full` mode to `headroom-pxpipe`; `full` is a deprecated alias.
