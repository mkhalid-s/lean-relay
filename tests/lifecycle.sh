#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APX="$ROOT/bin/apx"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/apx-lifecycle.XXXXXX")"
trap 'pkill -P $$ 2>/dev/null || true; rm -rf "$TMP"' EXIT
HOME="$TMP/home"
export HOME
mkdir -p "$HOME/.config/apx" "$HOME/.local/state/apx" "$HOME/bin"
PORT="${APX_TEST_PORT:-18787}"

cat > "$HOME/bin/fake-gateway" <<'PYGW'
#!/usr/bin/env python3
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *_): pass
ThreadingHTTPServer(('127.0.0.1', int(os.environ['GATEWAY_PORT'])), H).serve_forever()
PYGW
chmod +x "$HOME/bin/fake-gateway"
cat > "$HOME/.config/apx/config.env" <<EOF
BIND_HOST=127.0.0.1
GATEWAY_PORT=$PORT
GATEWAY_ENABLED=1
APX_CHAIN=""
HEADROOM_ENABLED=0
PXPIPE_ENABLED=0
SQUEEZR_ENABLED=0
GATEWAY_CMD="$HOME/bin/fake-gateway"
GATEWAY_TARGET_API_URL="https://api.anthropic.com"
WORKDIR="$HOME"
HEALTH_INTERVAL_SECONDS=1
STARTUP_TIMEOUT_SECONDS=10
APX_SERVICE_BACKEND=nohup
EOF
export APX_CONFIG="$HOME/.config/apx/config.env"
export APX_STATE="$HOME/.local/state/apx"
export APX_RUN_DIR="$TMP/run"
export PATH="$HOME/bin:$PATH"

"$APX" start >/dev/null
curl -fsS "http://127.0.0.1:$PORT/livez" >/dev/null
second="$("$APX" start 2>&1)"
[[ "$second" == *"already running"* ]]
"$APX" stop >/dev/null
! curl -fsS "http://127.0.0.1:$PORT/livez" >/dev/null 2>&1

sleep 30 & foreign=$!
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
fi

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
