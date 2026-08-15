#!/usr/bin/env bash
set -u

ROOT="/home/wisdom/Desktop/chromium_local/chromium/src"
CHROME="$ROOT/out/Default/chrome"
CAPNP="$ROOT/third_party/capnproto/install/bin/capnp"
SCHEMA="$ROOT/v8/src/taint_tracking/protos/logrecord.capnp"
RUN_DIR="/tmp/taint_http_messageOrigin_cdp_replay_$(date +%Y%m%d_%H%M%S)"
WWW="$RUN_DIR/www"

mkdir -p "$WWW"
printf 'ok\n' > "$WWW/health.txt"

cat > "$WWW/parent.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try {
  window.addEventListener("message", function(event) {
    document.write(event.origin);
  }, {once: true});
  var f = document.createElement("iframe");
  f.src = "/child.html";
  document.documentElement.appendChild(f);
} catch (e) {
  document.write("ERR:" + e.name + ":" + e.message);
}
</script>
HTML

cat > "$WWW/child.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
setTimeout(function() {
  parent.postMessage("child-message", "*");
}, 0);
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
httpd = ThreadingHTTPServer(
    ("127.0.0.1", port),
    functools.partial(Handler, directory=directory),
)
httpd.daemon_threads = True
httpd.serve_forever()
PY

free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

cleanup() {
  if [[ -n "${CHROME_PID:-}" ]]; then kill "$CHROME_PID" 2>/dev/null || true; fi
  if [[ -n "${SERVER_PID:-}" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

WEB_PORT="$(free_port)"
DEVTOOLS_PORT="$(free_port)"
python3 "$RUN_DIR/server.py" "$WEB_PORT" "$WWW" \
  > "$RUN_DIR/http_server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 50); do
  if curl -sS --max-time 0.2 "http://127.0.0.1:$WEB_PORT/health.txt" \
      > "$RUN_DIR/curl_health.txt" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u no_proxy \
  "$CHROME" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-crashpad \
    --disable-crash-reporter \
    --disable-breakpad \
    --disable-background-networking \
    --disable-component-update \
    --disable-sync \
    --metrics-recording-only \
    --no-first-run \
    --noerrdialogs \
    --disable-extensions \
    --disable-default-apps \
    --proxy-server=direct:// \
    --proxy-bypass-list='*' \
    "--user-data-dir=$RUN_DIR/profile" \
    "--remote-debugging-address=127.0.0.1" \
    "--remote-debugging-port=$DEVTOOLS_PORT" \
    "--js-flags=--taint_log_file=$RUN_DIR/log" \
    about:blank > "$RUN_DIR/chrome_stdout.txt" 2> "$RUN_DIR/chrome_stderr.txt" &
CHROME_PID=$!

python3 - "$DEVTOOLS_PORT" "http://127.0.0.1:$WEB_PORT/parent.html" \
    "$RUN_DIR/http_server.log" <<'PY' > "$RUN_DIR/cdp_navigate.txt" 2>&1
import base64
import json
import os
import socket
import struct
import sys
import time
import urllib.request

port = int(sys.argv[1])
url = sys.argv[2]
server_log = sys.argv[3]

for _ in range(100):
    try:
        tabs = json.loads(
            urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=0.2).read()
        )
        pages = [tab for tab in tabs if tab.get("type") == "page"]
        if pages:
            ws_url = pages[0]["webSocketDebuggerUrl"]
            break
    except Exception:
        pass
    time.sleep(0.1)
else:
    raise SystemExit("DevTools page target not available")

_, rest = ws_url.split("ws://", 1)
hostport, path = rest.split("/", 1)
host, port_text = hostport.split(":")
sock = socket.create_connection((host, int(port_text)), timeout=5)
key = base64.b64encode(os.urandom(16)).decode()
sock.sendall(
    (
        f"GET /{path} HTTP/1.1\r\n"
        f"Host: {hostport}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ).encode()
)
print(sock.recv(4096).decode(errors="replace").split("\r\n\r\n")[0])

def send(obj):
    data = json.dumps(obj).encode()
    header = bytearray([0x81])
    length = len(data)
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    mask = os.urandom(4)
    header.extend(mask)
    payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(data))
    sock.sendall(header + payload)

def recv_once(timeout=0.5):
    sock.settimeout(timeout)
    first = sock.recv(1)
    if not first:
        return None
    second = sock.recv(1)[0]
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", sock.recv(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", sock.recv(8))[0]
    if second & 0x80:
        _ = sock.recv(4)
    data = b""
    while len(data) < length:
        data += sock.recv(length - len(data))
    return json.loads(data.decode()) if data else None

send({"id": 1, "method": "Page.enable"})
send({"id": 2, "method": "Runtime.enable"})
send({"id": 3, "method": "Page.navigate", "params": {"url": url}})
print("NAVIGATED", url)

deadline = time.time() + 45
while time.time() < deadline:
    try:
        msg = recv_once(0.5)
        if msg:
            print(json.dumps(msg, ensure_ascii=False)[:800])
    except Exception:
        pass
    try:
        if "/child.html" in open(server_log, errors="ignore").read():
            print("SAW_CHILD_REQUEST")
            break
    except Exception:
        pass

sock.close()
PY

sleep 3
cleanup
trap - EXIT

for log in "$RUN_DIR"/log_*; do
  [[ -s "$log" ]] || continue
  base="$(basename "$log")"
  "$CAPNP" decode "$SCHEMA" TaintLogRecord < "$log" \
    > "$RUN_DIR/decoded_$base.txt" 2>> "$RUN_DIR/decode_errors.txt" || true
done
cat "$RUN_DIR"/decoded_log_*.txt > "$RUN_DIR/decoded.txt" 2>/dev/null || :

ACTUAL="$(grep -o 'type = [A-Za-z0-9]*' "$RUN_DIR/decoded.txt" \
  | sed 's/type = //' | sort -u | paste -sd ',' -)"
SINK="$(grep -o 'sinkType = [A-Za-z0-9]*' "$RUN_DIR/decoded.txt" \
  | sed 's/sinkType = //' | sort -u | paste -sd ',' -)"
CONTENT="$(grep -o 'content = "http://127\\.0\\.0\\.1:[0-9]*"' "$RUN_DIR/decoded.txt" \
  | head -n 1 | sed 's/content = //')"

echo "RUN_DIR=$RUN_DIR"
echo "WEB_PORT=$WEB_PORT"
echo "DEVTOOLS_PORT=$DEVTOOLS_PORT"
echo "ACTUAL=${ACTUAL:-NONE}"
echo "SINK=${SINK:-NONE}"
echo "CONTENT=${CONTENT:-NONE}"
echo
echo "HTTP requests:"
sed -n '1,80p' "$RUN_DIR/http_server.log"
echo
echo "Decoded summary:"
grep -o 'type = [A-Za-z0-9]*\|sinkType = [A-Za-z0-9]*\|content = "[^"]*"' \
  "$RUN_DIR/decoded.txt" | head -80 || true

if [[ "$ACTUAL" == "messageOrigin" && "$SINK" == "html" && "$CONTENT" != "NONE" ]]; then
  echo
  echo "PASS messageOrigin HTTP origin"
  exit 0
fi

echo
echo "FAIL messageOrigin HTTP origin"
exit 1
