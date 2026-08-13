#!/usr/bin/env bash
set -u

ROOT="/home/wisdom/Desktop/chromium_local/chromium/src"
CHROME="$ROOT/out/Default/chrome"
CAPNP="$ROOT/third_party/capnproto/install/bin/capnp"
SCHEMA="$ROOT/v8/src/taint_tracking/protos/logrecord.capnp"
RUN_DIR="/tmp/taint_15_source_isolated_health_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$RUN_DIR"

free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

make_common_server() {
  local dir="$1"
  cat > "$dir/server.py" <<'PY'
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
}

wait_server() {
  local base="$1"
  python3 - "$base" <<'PY'
import sys, time, urllib.request
base = sys.argv[1]
last = None
for _ in range(50):
    try:
        urllib.request.urlopen(base + "/health.txt", timeout=0.2).read()
        raise SystemExit(0)
    except Exception as e:
        last = e
        time.sleep(0.1)
print(f"server did not start: {last}", file=sys.stderr)
raise SystemExit(1)
PY
}

write_page() {
  local www="$1"
  local name="$2"
  mkdir -p "$www"
  printf 'ok\n' > "$www/health.txt"

  case "$name" in
    cookie)
      cat > "$www/page.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try { document.cookie = "source_cookie=cookie-source-value; path=/; SameSite=Lax"; document.write(document.cookie); }
catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
      ;;
    message)
      cat > "$www/page.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try {
  window.addEventListener("message", event => document.write(event.data), {once: true});
  setTimeout(() => window.postMessage("message-source-value", location.origin), 0);
} catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
      ;;
    messageOrigin)
      cat > "$www/page.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try {
  window.addEventListener("message", event => document.write(event.origin), {once: true});
  setTimeout(() => window.postMessage("message-source-value", location.origin), 0);
} catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
      ;;
    url) expr='location.href' ;;
    urlHash) expr='location.hash' ;;
    urlProtocol) expr='location.protocol' ;;
    urlHost) expr='location.host' ;;
    urlHostname) expr='location.hostname' ;;
    urlOrigin) expr='location.origin' ;;
    urlPort) expr='location.port' ;;
    urlPathname) expr='location.pathname' ;;
    urlSearch) expr='location.search' ;;
    referrer)
      cat > "$www/start.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>location.href = "/page.html";</script>
HTML
      cat > "$www/page.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try { document.write(document.referrer); }
catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
      ;;
    windowname)
      cat > "$www/page.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try { window.name = "windowname-source-value"; document.write(window.name); }
catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
      ;;
    storage)
      cat > "$www/page.html" <<'HTML'
<!doctype html><meta charset="utf-8"><script>
try { localStorage.setItem("source-key", "storage-source-value"); var s = localStorage.getItem("source-key"); document.write(s); }
catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
      ;;
  esac

  if [[ "${expr:-}" != "" ]]; then
    cat > "$www/page.html" <<HTML
<!doctype html><meta charset="utf-8"><script>
try { document.write($expr); }
catch (e) { document.write("ERR:" + e.name + ":" + e.message); }
</script>
HTML
  fi
}

run_case() {
  local name="$1"
  local expected="$2"
  local dir="$RUN_DIR/$name"
  local www="$dir/www"
  local port base url server_pid status log actual sink bytes page_hits stdout_size
  local expr=""

  mkdir -p "$dir"
  write_page "$www" "$name"
  make_common_server "$dir"

  port="$(free_port)"
  base="http://127.0.0.1:$port"
  python3 "$dir/server.py" "$port" "$www" > "$dir/http_server.log" 2>&1 &
  server_pid=$!

  if ! wait_server "$base"; then
    kill "$server_pid" 2>/dev/null || true
    printf 'FAIL %-14s expected=%-14s actual=SERVER sink=NONE status=server bytes=0 chrome_hits=0 stdout=0\n' "$name" "$expected"
    return
  fi

  if [[ "$name" == "referrer" ]]; then
    url="$base/start.html?from=referrer-source"
  else
    url="$base/page.html?payload=url-source#hash-source"
  fi

  timeout 30s "$CHROME" \
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
    "--user-data-dir=$dir/profile" \
    "--js-flags=--taint_log_file=$dir/log" \
    --dump-dom "$url" > "$dir/stdout.txt" 2> "$dir/stderr.txt"
  status=$?
  kill "$server_pid" 2>/dev/null || true

  log="$(find "$dir" -maxdepth 1 -type f -name 'log_*' -size +0c | sort | head -n 1 || true)"
  if [[ -n "$log" ]]; then
    "$CAPNP" decode "$SCHEMA" TaintLogRecord < "$log" > "$dir/decoded.txt" 2>> "$dir/decode_errors.txt" || true
  else
    : > "$dir/decoded.txt"
  fi

  actual="$(grep -o 'type = [A-Za-z0-9]*' "$dir/decoded.txt" | sed 's/type = //' | sort -u | paste -sd ',' -)"
  sink="$(grep -o 'sinkType = [A-Za-z0-9]*' "$dir/decoded.txt" | sed 's/sinkType = //' | sort -u | paste -sd ',' -)"
  bytes=0
  if [[ -n "$log" ]]; then bytes="$(stat -c '%s' "$log")"; fi
  page_hits="$(grep -Ec 'GET /(page|start)\\.html' "$dir/http_server.log" || true)"
  stdout_size="$(stat -c '%s' "$dir/stdout.txt" 2>/dev/null || echo 0)"

  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS %-14s expected=%-14s actual=%-14s sink=%-8s status=%s bytes=%s chrome_hits=%s stdout=%s\n' "$name" "$expected" "$actual" "$sink" "$status" "$bytes" "$page_hits" "$stdout_size"
  else
    printf 'FAIL %-14s expected=%-14s actual=%-14s sink=%-8s status=%s bytes=%s chrome_hits=%s stdout=%s\n' "$name" "$expected" "${actual:-NONE}" "${sink:-NONE}" "$status" "$bytes" "$page_hits" "$stdout_size"
  fi
}

echo "RUN_DIR=$RUN_DIR"
run_case cookie cookie
run_case message message
run_case messageOrigin messageOrigin
run_case url url
run_case urlHash urlHash
run_case urlProtocol urlProtocol
run_case urlHost urlHost
run_case urlHostname urlHostname
run_case urlOrigin urlOrigin
run_case urlPort urlPort
run_case urlPathname urlPathname
run_case urlSearch urlSearch
run_case referrer referrer
run_case windowname windowname
run_case storage storage

