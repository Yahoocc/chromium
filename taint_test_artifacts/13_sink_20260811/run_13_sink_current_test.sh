#!/usr/bin/env bash
set -u

ROOT="/home/wisdom/Desktop/chromium_local/chromium/src"
CHROME="$ROOT/out/Default/chrome"
CAPNP="$ROOT/third_party/capnproto/install/bin/capnp"
SCHEMA="$ROOT/v8/src/taint_tracking/protos/logrecord.capnp"
RUN_DIR="/tmp/taint_13_sink_current_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$RUN_DIR/pages" "$RUN_DIR/decoded"

make_page() {
  local name="$1"
  local body="$2"
  local path="$RUN_DIR/pages/$name.html"
  printf '%s\n' '<!doctype html><meta charset="utf-8"><body><script>' > "$path"
  printf '%s\n' 'function tainted(value) {' >> "$path"
  printf '%s\n' '  localStorage.setItem("taint-key", value);' >> "$path"
  printf '%s\n' '  return localStorage.getItem("taint-key");' >> "$path"
  printf '%s\n' '}' >> "$path"
  printf '%s\n' 'try {' >> "$path"
  printf '%s\n' "$body" >> "$path"
  printf '%s\n' '} catch (e) {' >> "$path"
  printf '%s\n' '  document.body.append("ERR:" + e.name + ":" + e.message);' >> "$path"
  printf '%s\n' '}' >> "$path"
  printf '%s\n' '</script></body>' >> "$path"
}

make_page html 'var s = tainted("<b>html-taint</b>"); document.write(s);'
make_page javascript 'var s = tainted("window.__javascript_sink = 1;"); var sc = document.createElement("script"); document.body.appendChild(sc); sc.textContent = s; document.body.append("done");'
make_page cookie 'var s = tainted("taint_cookie=cookie-taint; path=/"); document.cookie = s; document.body.append("done");'
make_page javascriptEventHandlerAttribute 'var s = tainted("window.__event_sink = 1"); var a = document.createElement("a"); document.body.appendChild(a); a.setAttribute("onclick", s); document.body.append("done");'
make_page cssStyleAttribute 'var s = tainted("color: rgb(1, 2, 3); background-image: url(about:blank#css-taint)"); var d = document.createElement("div"); document.body.appendChild(d); d.setAttribute("style", s); document.body.append("done");'
make_page javascriptSetTimeout 'var s = tainted("window.__timeout_sink = 1"); setTimeout(s, 0); document.body.append("done");'
make_page javascriptSetInterval 'var s = tainted("window.__interval_sink = 1"); var id = setInterval(s, 10); setTimeout(function(){ clearInterval(id); document.body.append("done"); }, 30);'
make_page anchorSrcSink 'var s = tainted("https://example.invalid/anchor-taint"); var a = document.createElement("a"); document.body.appendChild(a); a.setAttribute("href", s); document.body.append("done");'
make_page embedSrcSink 'var s = tainted("https://example.invalid/embed-taint"); var e = document.createElement("embed"); document.body.appendChild(e); e.setAttribute("src", s); document.body.append("done");'
make_page iframeSrcSink 'var s = tainted("https://example.invalid/iframe-taint"); var f = document.createElement("iframe"); document.body.appendChild(f); f.setAttribute("src", s); document.body.append("done");'
make_page imgSrcSink 'var s = tainted("https://example.invalid/img-taint.png"); var i = document.createElement("img"); document.body.appendChild(i); i.setAttribute("src", s); document.body.append("done");'
make_page scriptSrcUrlSink 'var s = tainted("https://example.invalid/script-taint.js"); var sc = document.createElement("script"); document.body.appendChild(sc); sc.setAttribute("src", s); document.body.append("done");'
make_page locationAssignment 'var s = tainted("about:blank#location-taint"); window.location = s; document.body.append("done");'

cases=(
  html
  javascript
  cookie
  javascriptEventHandlerAttribute
  cssStyleAttribute
  javascriptSetTimeout
  javascriptSetInterval
  anchorSrcSink
  embedSrcSink
  iframeSrcSink
  imgSrcSink
  scriptSrcUrlSink
  locationAssignment
)

echo "RUN_DIR=$RUN_DIR"
echo "CHROME=$CHROME"
echo "CAPNP=$CAPNP"
echo

for name in "${cases[@]}"; do
  page="$RUN_DIR/pages/$name.html"
  profile="$RUN_DIR/profile_$name"
  log_prefix="$RUN_DIR/${name}_log"
  stdout="$RUN_DIR/${name}.stdout"
  stderr="$RUN_DIR/${name}.stderr"
  mkdir -p "$profile"

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
    --user-data-dir="$profile" \
    --js-flags="--taint_log_file=$log_prefix" \
    --dump-dom "file://$page" > "$stdout" 2> "$stderr"
  status=$?

  decoded="$RUN_DIR/decoded/$name.txt"
  : > "$decoded"
  logs=( "$RUN_DIR"/${name}_log_* )
  if [ -e "${logs[0]}" ]; then
    for log in "${logs[@]}"; do
      if [ -s "$log" ]; then
        "$CAPNP" decode "$SCHEMA" TaintLogRecord < "$log" >> "$decoded" 2>> "$RUN_DIR/decode_errors.txt" || true
      fi
    done
  fi

  sink_types="$(grep -o 'sinkType = [A-Za-z0-9]*' "$decoded" | sed 's/sinkType = //' | sort -u | tr '\n' ',' | sed 's/,$//')"
  source_types="$(grep -o 'type = [A-Za-z0-9]*' "$decoded" | sed 's/type = //' | sort -u | tr '\n' ',' | sed 's/,$//')"
  log_count="$(find "$RUN_DIR" -maxdepth 1 -type f -name "${name}_log_*" -size +0c | wc -l)"
  decoded_size="$(wc -c < "$decoded")"

  printf '%-36s status=%-3s logs=%-2s decoded=%-6s sinkTypes=%s sources=%s\n' \
    "$name" "$status" "$log_count" "$decoded_size" "${sink_types:-NONE}" "${source_types:-NONE}"
done

echo
echo "Decoded records are in: $RUN_DIR/decoded"
