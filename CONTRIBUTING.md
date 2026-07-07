# Contributing

Thanks for improving apx.

## Development

Run these checks before sending changes:

```bash
bash -n install.sh
bash -n bootstrap.sh
bash -n bin/apx
bash -n bin/apx-squeezr
python3 -c "import ast; ast.parse(open('bin/apx-gateway').read())"
./install.sh --check-only
```

Keep scripts portable:

- Do not commit user-specific absolute paths.
- Do not commit runtime logs, PID files, or generated LaunchAgent output.
- Keep dependency installation explicit and visible to the user.
- Preserve backward compatibility for the `ai-proxy-stack` / `ai-proxy-gateway` /
  `ai-proxy-squeezr-foreground` shim names for at least one minor release.

## Releasing

Versions are tracked in the top-level `VERSION` file (semver `MAJOR.MINOR.PATCH`).
Existing installs read this at install time and expose it as `apx version`.

To cut a release:

```bash
# 1. Bump the version
echo "0.2.0" > VERSION
git commit -am "Release v0.2.0"

# 2. Tag it (tag must match VERSION with a leading "v")
git tag v0.2.0
git push origin main --tags
```

The `.github/workflows/release.yml` workflow verifies the tag matches
`VERSION`, builds an `apx-<version>.tar.gz` tarball with a sha256 checksum,
and publishes a GitHub Release.

Existing users pick up the new version by running `apx update`.

## Security

Do not include API keys, provider tokens, local credentials, or private logs in
issues or pull requests.
