# Chromium 污点追踪相关问题修复记录

## 问题 1: `--dump-dom` 在 DOCTYPE 页面上超时不退出

### 问题描述

使用 `--dump-dom` 测试时，遇到以下页面会卡住不退出：
```html
<!DOCTYPE html>
<html><body>test</body></html>
```

但简单的无 DOCTYPE 页面能正常退出：
```html
<html><body>test</body></html>
```

### 可能的原因

#### 原因 1: Snap 沙箱 IPC 阻塞（最可能）

**完整的卡死链条**：

1. **渲染进程**完成页面加载和 DOM 构建
2. **渲染进程**尝试通过 IPC 将 DOM 内容发送给**主进程**
3. **Snap 沙箱**检测到无头模式下的进程间大量数据传输，判定为"可疑行为"
4. **Snap 沙箱拦截/限流** IPC 通信管道
5. **死锁发生**：
   - 渲染进程：等待主进程接收数据（"你到底收不收？"）
   - 主进程：等待渲染进程发送数据（"数据呢？怎么还没来？"）
   - 终端/用户：等待主进程输出（"怎么半天没动静？"）
6. **超时退出**

**验证方法**：
```bash
# 使用非 Snap 版本的 Chrome（本地编译版）
out/Default/chrome --headless --dump-dom 'data:text/html,<!DOCTYPE html><html><body>test</body></html>'
# 如果本地编译版正常，说明是 Snap 沙箱问题
```

**解决方法**：
- 使用本地编译的 Chrome（绕过 Snap）
- 或者使用 `--no-sandbox` 参数（但会降低安全性）

#### 原因 2: Document 完成检查条件不满足（次要可能）

在 `third_party/blink/renderer/core/dom/document.cc` 的 `Document::ShouldComplete()` 方法中：

```cpp
bool Document::ShouldComplete() {
  return parsing_state_ == kFinishedParsing && HaveImportsLoaded() &&
         !fetcher_->BlockingRequestCount() && !IsDelayingLoadEvent();
}
```

**可能的问题**：
- `BlockingRequestCount()` 非零（有未完成的资源请求）
- `IsDelayingLoadEvent()` 为 true（某些脚本延迟了 load 事件）
- DOCTYPE 触发了额外的资源加载或验证逻辑

**调试方法**：
```bash
# 添加调试日志查看各个条件的状态
# 在 Document::ShouldComplete() 中添加 LOG 输出
```

### 影响范围

这个问题会影响任何依赖页面完全加载的操作：
- `--dump-dom` 不退出
- `--virtual-time-budget` 超时
- 自动化测试等待页面加载完成时卡住

### 当前状态

问题已识别但未修复。需要进一步调试：
1. 检查 `BlockingRequestCount()` 为何非零
2. 确认 `IsDelayingLoadEvent()` 的状态
3. 可能需要修改完成条件或添加超时机制

---

## 问题 2: 污点追踪日志无法生成

### 问题描述

编译完成后运行 Chrome，使用 `--js-flags="--taint-log-file=/tmp/taint.log"` 参数无法生成污点追踪日志文件。

## 问题排查过程

### 1. 确认污点追踪代码已编译

```bash
# 检查 libv8.so 中的污点追踪符号
strings out/Default/libv8.so | grep "taint_log_file"
nm -D out/Default/libv8.so | grep "LogIfTainted"
```

结果：污点追踪代码确实编译进了 `libv8.so`。

### 2. 测试 Chrome 是否识别污点追踪标志

```bash
out/Default/chrome --headless --no-sandbox \
  --js-flags="--help" about:blank > /tmp/help.log 2>&1
grep "taint-log-file" /tmp/help.log
```

结果：标志存在，但使用**连字符** `--taint-log-file` 而不是下划线 `--taint_log_file`。

### 3. 测试运行时设置标志

```bash
out/Default/d8 --taint-log-file=/tmp/test.log -e 'eval("1+1")'
```

结果：**报错**
```
Flag processing error: Contradictory value for readonly flag --taint-log-file.
```

## 根本原因

在 `v8/src/flags/flag-definitions.h` 中，污点追踪标志被错误地放在了 `FLAG_READONLY` 块内：

```c++
// 第 4199 行
#define FLAG FLAG_READONLY

// 第 4239-4270 行：污点追踪标志定义
DEFINE_STRING(taint_log_file, nullptr, ...)
DEFINE_BOOL(taint_tracking_sources_sinks_to_logs, false, ...)
// ... 其他污点追踪标志

// 第 4274 行
#undef FLAG_READONLY
```

**只读标志无法在运行时通过命令行参数修改**，因此：
- 无法通过 `--taint-log-file=/tmp/taint.log` 设置日志路径
- 默认值是 `nullptr`（空），所以不会生成任何日志

## 解决方案

将污点追踪标志从 `FLAG_READONLY` 块中移出，放在第 4194 行 `#undef FLAG` 之前。

### 修改位置

**移动前**：标志在第 4237-4270 行（FLAG_READONLY 块内）

**移动后**：标志在第 4193-4228 行（FLAG_READONLY 块之前）

### 具体修改

```diff
 DEFINE_NEG_IMPLICATION(disallow_unsafe_flags, cppgc_young_generation)
 DEFINE_NEG_IMPLICATION(disallow_unsafe_flags, test_only_unsafe)
 
+// Legacy NDSS taint-tracking port flags.
+DEFINE_STRING(taint_log_file, nullptr,
+              "Output taint log information to this file.")
+DEFINE_BOOL(taint_tracking_sources_sinks_to_logs, false,
+            "Log taint sources and sinks.")
+// ... 其他污点追踪标志
+
 #undef FLAG
 
 #ifdef VERIFY_PREDICTABLE
 #define FLAG FLAG_READONLY
 #endif
 
 // ... verify_predictable 等只读标志
 
-// Legacy NDSS taint-tracking port flags.
-DEFINE_STRING(taint_log_file, nullptr, ...)
-// ... 删除原来位置的污点追踪标志
-
 #undef FLAG_READONLY
```

## 重新编译

```bash
# 重新生成构建文件
./buildtools/linux64/gn gen out/Default

# 增量编译（只会重新编译受影响的文件）
ninja -C out/Default -j 4 chrome
```

## 验证修复

编译完成后测试：

```bash
# 测试 1: 使用 d8 验证标志可以设置
out/Default/d8 --taint-log-file=/tmp/test.log -e 'eval("1+1")'
# 应该不再报错 "readonly flag"

# 测试 2: 使用 Chrome 测试污点追踪
rm -f /tmp/taint*
out/Default/chrome --headless --no-sandbox \
  --js-flags="--taint-log-file=/tmp/taint.log --taint-tracking-sources-sinks-to-logs" \
  'data:text/html,<!DOCTYPE html><script>var x = document.location.href; eval(x);</script>' &
CHROME_PID=$!
sleep 5
kill $CHROME_PID
ls -lh /tmp/taint*
```

## 重要的污点追踪标志

- `--taint-log-file=<path>` - 日志文件路径（必需）
- `--taint-tracking-sources-sinks-to-logs` - 记录污点源和汇聚点
- `--taint-tracking-enable-ast-modification` - 启用 AST 修改（某些场景需要）

## 污点数据源

根据代码分析，以下数据会被自动标记为污点：
- `document.location.*` (href, search, hash 等)
- `MessageEvent` 数据
- 跨域消息
- 框架树相关数据

## 参考命令（历史版本）

从旧脚本中找到的参考命令（使用旧版 V8 优化标志）：
```bash
chrome --js-flags="--taint_log_file=<path> --no-crankshaft --no-turbo --no-ignition"
```

注意：
- 现代 V8 不再支持 `--no-crankshaft`、`--no-turbo`、`--no-ignition`
- 使用 `--taint-log-file`（连字符）而不是 `--taint_log_file`（下划线）
