#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APX="$ROOT/bin/apx"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/apx-lifecycle.XXXXXX")"
trap 'pkill -P $$ 2>/dev/null || true; rm -rf "$TMP"' EXIT

# Isolate from runner XDG_* so unit/plist paths stay under the fake HOME.
# Otherwise SYSTEMD_USER_DIR follows XDG_CONFIG_HOME (e.g. /home/runner/.config)
# and assertions on $HOME/.config/systemd/... fail in CI.
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR XDG_CACHE_HOME

HOME="$TMP/home"
export HOME
mkdir -p "$HOME/.config/apx" "$HOME/.local/state/apx" "$HOME/bin" "$HOME/.local/bin"

# LaunchAgent ProgramArguments always points at ~/.local/bin/apx. Without this
# symlink, a Darwin fallback to launchd hangs inside `launchctl kickstart`.
ln -sf "$APX" "$HOME/.local/bin/apx"

PYTHON3="$(command -v python3 || true)"
if [[ -z "$PYTHON3" ]]; then
  echo "ERROR: python3 is required for lifecycle tests" >&2
  exit 1
fi

# Pick a free port so CI runners don't collide on a fixed 18787.
PORT="${APX_TEST_PORT:-}"
if [[ -z "$PORT" ]]; then
  PORT="$("$PYTHON3" - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
fi

cat > "$HOME/bin/fake-gateway" <<'PYGW'
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    port = int(os.environ.get("GATEWAY_PORT", sys.argv[1] if len(sys.argv) > 1 else 18787))
except (ValueError, IndexError):
    port = 18787


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *_):
        pass


ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PYGW

# Invoke via absolute python3 so bash -lc / shebang PATH differences cannot hide the interpreter.
GATEWAY_CMD="$PYTHON3 $HOME/bin/fake-gateway"

cat > "$HOME/.config/apx/config.env" <<EOF
BIND_HOST=127.0.0.1
GATEWAY_PORT=$PORT
GATEWAY_ENABLED=1
APX_CHAIN=""
HEADROOM_ENABLED=0
PXPIPE_ENABLED=0
SQUEEZR_ENABLED=0
GATEWAY_CMD="$GATEWAY_CMD"
GATEWAY_TARGET_API_URL="https://api.anthropic.com"
WORKDIR="$HOME"
HEALTH_INTERVAL_SECONDS=1
STARTUP_TIMEOUT_SECONDS=60
APX_SERVICE_BACKEND=nohup
EOF

export APX_CONFIG="$HOME/.config/apx/config.env"
export APX_STATE="$HOME/.local/state/apx"
export APX_RUN_DIR="$TMP/run"
# Force nohup via env override so Darwin CI cannot fall through to launchd
# (plist points at ~/.local/bin/apx, which is not installed in this test).
export APX_SERVICE_BACKEND=nohup
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

wait_livez() {
  local _
  # Integer sleeps only — macOS /bin/sleep historically rejected fractions.
  # macOS runners have been observed to take 30-60s for the gateway to
  # become healthy, so allow generous headroom here.
  for _ in $(seq 1 90); do
    if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/livez" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: gateway did not become healthy on port $PORT" >&2
  echo "service backend: $("$APX" status 2>/dev/null | grep -i 'service backend' || true)" >&2
  if [[ -f "$APX_STATE/logs/supervisor.log" ]]; then
    echo "---- supervisor.log ----" >&2
    cat "$APX_STATE/logs/supervisor.log" >&2 || true
  fi
  if [[ -f "$APX_STATE/logs/gateway.log" ]]; then
    echo "---- gateway.log ----" >&2
    cat "$APX_STATE/logs/gateway.log" >&2 || true
  fi
  return 1
}

"$APX" start >/dev/null
wait_livez

second="$("$APX" start 2>&1)"
if [[ "$second" != *"already running"* ]]; then
  echo "ERROR: Expected 'already running' message, got: $second" >&2
  exit 1
fi

"$APX" stop >/dev/null
if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/livez" >/dev/null 2>&1; then
  echo "ERROR: gateway still healthy after stop" >&2
  exit 1
fi

# Foreign pid must not be killed by stop; keep this short so a failed kill
# cannot stall CI for half a minute.
sleep 5 & foreign=$!
mkdir -p "$APX_RUN_DIR"
printf '%s\n' "$foreign" > "$APX_RUN_DIR/supervisor.pid"
"$APX" stop >/dev/null
kill -0 "$foreign"
kill "$foreign" 2>/dev/null || true
wait "$foreign" 2>/dev/null || true

mkdir -p "$TMP/stubs"
cat > "$TMP/stubs/systemctl" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$HOME/systemctl.log"
case "$*" in *show-environment*) exit 0 ;; *is-active*) exit 1 ;; esac
exit 0
SH
cat > "$TMP/stubs/launchctl" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$HOME/launchctl.log"
case "${1:-}" in print) exit 1 ;; esac
exit 0
SH
chmod +x "$TMP/stubs/systemctl" "$TMP/stubs/launchctl"

APX_PATH="$TMP/stubs:$PATH" APX_SERVICE_BACKEND=systemd "$APX" install >/dev/null
[[ -f "$HOME/.config/systemd/user/io.github.apx.service" ]]
grep -q 'enable --now io.github.apx.service' "$HOME/systemctl.log"
APX_PATH="$TMP/stubs:$PATH" APX_SERVICE_BACKEND=systemd "$APX" uninstall >/dev/null
[[ ! -f "$HOME/.config/systemd/user/io.github.apx.service" ]]

if [[ "$(uname -s)" == Darwin ]]; then
  APX_PATH="$TMP/stubs:$PATH" APX_SERVICE_BACKEND=launchd "$APX" install >/dev/null
  [[ -f "$HOME/Library/LaunchAgents/io.github.apx.plist" ]]
  plutil -lint "$HOME/Library/LaunchAgents/io.github.apx.plist" >/dev/null
  APX_PATH="$TMP/stubs:$PATH" APX_SERVICE_BACKEND=launchd "$APX" uninstall >/dev/null
  [[ ! -f "$HOME/Library/LaunchAgents/io.github.apx.plist" ]]
fi

# Ensure later config edits do not try to talk to a leftover launchd/systemd backend.
export APX_SERVICE_BACKEND=nohup
rm -f "$HOME/.config/apx/service.backend"

mkdir -p "$HOME/.claude"
printf '{"env":{"KEEP":"1"}}\n' > "$HOME/.claude/settings.json"
"$APX" claude set local >/dev/null
grep -q 'APX_CLIENT_TOPOLOGY=local' "$APX_CONFIG"
grep -q 'http://127.0.0.1:' "$HOME/.claude/settings.json"
"$APX" claude set docker-host >/dev/null
grep -q 'APX_CLIENT_TOPOLOGY=docker-host' "$APX_CONFIG"
grep -q 'host.docker.internal' "$HOME/.claude/settings.json"
"$APX" mode direct --no-restart >/dev/null
grep -q 'host.docker.internal' "$HOME/.claude/settings.json"

echo lifecycle-ok
