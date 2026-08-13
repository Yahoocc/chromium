#!/usr/bin/env bash
set -u

NAME="$1"
EXPECTED="$2"
ROOT="/home/wisdom/Desktop/chromium_local/chromium/src"
CHROME="$ROOT/out/Default/chrome"
CAPNP="$ROOT/third_party/capnproto/install/bin/capnp"
SCHEMA="$ROOT/v8/src/taint_tracking/protos/logrecord.capnp"
RUN_DIR="/tmp/taint_one_source_${NAME}_$(date +%Y%m%d_%H%M%S)"
WWW="$RUN_DIR/www"

mkdir -p "$WWW"
printf 'ok\n' > "$WWW/health.txt"

case "$NAME" in
  cookie)
    BODY='document.cookie = "source_cookie=cookie-source-value; path=/; SameSite=Lax"; document.write(document.cookie);'
    ;;
  message)
    BODY='window.addEventListener("message", function(event) { document.write(event.data); }, {once: true}); setTimeout(function(){ window.postMessage("message-source-value", location.origin); }, 0);'
    ;;
  messageOrigin)
    BODY='window.addEventListener("message", function(event) { document.write(event.origin); }, {once: true}); setTimeout(function(){ window.postMessage("message-source-value", location.origin); }, 0);'
    ;;
  messageIframe)
    BODY='var frame = document.createElement("iframe"); frame.src = "child.html"; document.body.appendChild(frame); window.addEventListener("message", function(event) { document.write(event.data); }, {once: true});'
    cat > "$WWW/child.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
parent.postMessage("message-source-value", "*");
</script>
HTML
    ;;
  messageOriginIframe)
    BODY='var frame = document.createElement("iframe"); frame.src = "child.html"; document.body.appendChild(frame); window.addEventListener("message", function(event) { document.write(event.origin); }, {once: true});'
    cat > "$WWW/child.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
parent.postMessage("message-source-value", "*");
</script>
HTML
    ;;
  urlSearch)
    BODY='document.write(location.search);'
    ;;
  storage)
    BODY='localStorage.setItem("source-key", "storage-source-value"); var s = localStorage.getItem("source-key"); document.write(s);'
    ;;
  *)
    echo "unknown case: $NAME" >&2
    exit 2
    ;;
esac

cat > "$WWW/page.html" <<HTML
<!doctype html><meta charset="utf-8"><script>
try { $BODY }
catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML

cat > "$RUN_DIR/server.py" <<'PY'
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import functools
import sys

class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def end_headers(self):
        self.send_header("Connection", "close")
        super().end_headers()

port = int(sys.argv[1])
directory = sys.argv[2]
handler = functools.partial(Handler, directory=directory)
httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)
httpd.daemon_threads = True
httpd.serve_forever()
PY

PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
BASE="http://127.0.0.1:$PORT"
python3 "$RUN_DIR/server.py" "$PORT" "$WWW" > "$RUN_DIR/http_server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

python3 - "$BASE" <<'PY'
import sys, time, urllib.request
base = sys.argv[1]
for _ in range(50):
    try:
        urllib.request.urlopen(base + "/health.txt", timeout=0.2).read()
        raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit(1)
PY

URL="$BASE/page.html?payload=url-source#hash-source"
timeout 35s "$CHROME" \
  --headless=new \
  --disable-crash-reporter \
  --disable-breakpad \
  --no-zygote \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --no-sandbox \
  --disable-hang-monitor \
  --disable-background-networking \
  --disable-sync \
  --metrics-recording-only \
  --no-first-run \
  --noerrdialogs \
  --virtual-time-budget=5000 \
  "--user-data-dir=$RUN_DIR/profile" \
  "--js-flags=--taint_log_file=$RUN_DIR/log" \
  --dump-dom "$URL" > "$RUN_DIR/stdout.txt" 2> "$RUN_DIR/stderr.txt"
STATUS=$?
kill "$SERVER_PID" 2>/dev/null || true

LOG="$(find "$RUN_DIR" -maxdepth 1 -type f -name 'log_*' -size +0c | sort | head -n 1 || true)"
if [[ -n "$LOG" ]]; then
  "$CAPNP" decode "$SCHEMA" TaintLogRecord < "$LOG" > "$RUN_DIR/decoded.txt" 2>> "$RUN_DIR/decode_errors.txt" || true
else
  : > "$RUN_DIR/decoded.txt"
fi

ACTUAL="$(grep -o 'type = [A-Za-z0-9]*' "$RUN_DIR/decoded.txt" | sed 's/type = //' | sort -u | paste -sd ',' -)"
SINK="$(grep -o 'sinkType = [A-Za-z0-9]*' "$RUN_DIR/decoded.txt" | sed 's/sinkType = //' | sort -u | paste -sd ',' -)"
BYTES=0
if [[ -n "$LOG" ]]; then BYTES="$(stat -c '%s' "$LOG")"; fi
PAGE_HITS="$(grep -Ec 'GET /page\\.html' "$RUN_DIR/http_server.log" || true)"
STDOUT_SIZE="$(stat -c '%s' "$RUN_DIR/stdout.txt" 2>/dev/null || echo 0)"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  RESULT=PASS
else
  RESULT=FAIL
fi

printf '%s %-14s expected=%-14s actual=%-14s sink=%-8s status=%s bytes=%s page_hits=%s stdout=%s\n' "$RESULT" "$NAME" "$EXPECTED" "${ACTUAL:-NONE}" "${SINK:-NONE}" "$STATUS" "$BYTES" "$PAGE_HITS" "$STDOUT_SIZE"
echo "RUN_DIR=$RUN_DIR"
grep -o 'type = [A-Za-z0-9]*\|sinkType = [A-Za-z0-9]*\|content = "[^"]*"' "$RUN_DIR/decoded.txt" | head -20 || true
