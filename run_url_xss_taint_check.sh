#!/usr/bin/env bash
set -u

if [ $# -lt 1 ]; then
  echo "用法: $0 '<url>'"
  echo "示例: $0 'file:///tmp/taint_test_sink.html'"
  exit 1
fi

URL="$1"
ROOT="/home/wisdom/Desktop/chromium_local/chromium/src"
CHROME="$ROOT/out/Default/chrome"
CAPNP="$ROOT/third_party/capnproto/install/bin/capnp"
SCHEMA="$ROOT/v8/src/taint_tracking/protos/logrecord.capnp"
WORK_DIR="/tmp/taint_test"
DECODE_DIR="/tmp/taint_test_decoded"
LOG_PREFIX="$WORK_DIR/log"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-15}"
STEP_DELAY="${STEP_DELAY:-2}"

pause_for_demo() {
  sleep "$STEP_DELAY"
}

cd "$ROOT" || exit 1

echo "第一步：停止现有 Chrome 进程，避免 profile 或后台进程影响本次测试"
pause_for_demo
pkill -9 chrome 2>/dev/null || true
sleep 2
echo "第一步完成"
pause_for_demo
echo

echo "第二步：清理并创建测试目录"
pause_for_demo
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$DECODE_DIR"
echo "第二步完成：$WORK_DIR"
pause_for_demo
echo

echo "第三步：启动 Chrome 运行目标 URL，等待生成污点日志"
echo "目标 URL：$URL"
echo "Chrome timeout：${TIMEOUT_SECONDS}s"
pause_for_demo
timeout "$TIMEOUT_SECONDS" "$CHROME" "$URL" \
  --headless=new \
  --js-flags="--taint_log_file=$LOG_PREFIX --taint_tracking_enable_page_logging --taint_tracking_sources_sinks_to_logs" \
  --user-data-dir="$WORK_DIR/profile" \
  --no-sandbox \
  --disable-hang-monitor \
  --disable-gpu >/tmp/taint_test_chrome.out 2>/tmp/taint_test_chrome.err || true

echo "Chrome 已结束或超时，等待日志落盘"
sleep 3
echo "第三步完成"
pause_for_demo
echo

echo "第四步：查看本次生成的日志文件"
pause_for_demo
ls -lh "$WORK_DIR" || true
echo "--- Log file sizes ---"
pause_for_demo
wc -c "$WORK_DIR"/log* 2>/dev/null || true
pause_for_demo
echo

echo "第五步：寻找非空日志并进行 capnp decode"
pause_for_demo
FOUND_LOG=0
FOUND_XSS=0

for log_file in "$WORK_DIR"/log_*; do
  [ -f "$log_file" ] || continue
  [ -s "$log_file" ] || continue

  FOUND_LOG=1
  base_name="$(basename "$log_file")"
  decoded_file="$DECODE_DIR/record_${base_name}"

  echo "正在 decode 非空日志：$log_file"
  pause_for_demo
  "$CAPNP" decode "$SCHEMA" TaintLogRecord < "$log_file" > "$decoded_file" 2>"$decoded_file.err" || true

  if [ ! -s "$decoded_file" ]; then
    echo "decode 结果为空或失败，错误信息如下："
    pause_for_demo
    cat "$decoded_file.err" 2>/dev/null || true
    continue
  fi

  echo "decode 完成：$decoded_file"
  pause_for_demo
  echo

  if grep -Eiq "jsSinkTainted|<script|alert\(|javascript|innerHTML|document\.write|eval\(|onerror|onload" "$decoded_file"; then
    FOUND_XSS=1
    echo "经 decode 之后，发现它有 XSS"
    pause_for_demo
    echo "命中的日志文件：$log_file"
    echo "decode 后的位置和内容如下："
    echo "----------------------------------------"
    pause_for_demo
    grep -Ein -A 8 -B 4 "jsSinkTainted|sinkType|targetString|<script|alert\(|javascript|innerHTML|document\.write|eval\(|onerror|onload" "$decoded_file" | head -120
    echo "----------------------------------------"
    pause_for_demo
    echo
  else
    echo "这个日志 decode 后暂时没有 grep 到明显 XSS 特征：$decoded_file"
    echo
  fi
done

if [ "$FOUND_LOG" -eq 0 ]; then
  echo "没有找到非空 taint 日志，本次没有可 decode 的内容。"
  echo "可以查看 Chrome 错误输出：/tmp/taint_test_chrome.err"
  exit 2
fi

if [ "$FOUND_XSS" -eq 1 ]; then
  echo "第六步完成：最终结论：经 decode 之后，发现它有 XSS"
  exit 0
fi

echo "第六步完成：最终结论：decode 成功，但没有发现明显 XSS 特征"
exit 0
