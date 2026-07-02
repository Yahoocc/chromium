# 污点追踪测试说明

## 概述

本测试套件用于验证Chromium/V8中的污点追踪（Taint Tracking）功能，包括：
1. **污点标记**：使用 `__setTaint__()` 标记数据为污点
2. **污点传播**：通过字符串操作、对象属性等传播污点
3. **Sink报警**：当污点数据到达危险sink（如`eval`）时触发报警

## 测试文件

- `test_taint_sink.cc` - 完整的测试用例集
- `v8/test/cctest/test-taint-tracking.cc` - V8原有的污点追踪测试

## 如何运行测试

### 方法1: 使用V8的cctest框架

```bash
# 1. 将测试文件添加到V8测试目录
cp test_taint_sink.cc v8/test/cctest/

# 2. 修改 v8/test/cctest/BUILD.gn，添加新测试文件
# 在 cctest_sources 中添加: "test_taint_sink.cc"

# 3. 编译测试
cd v8
gn gen out/Debug --args='is_debug=true'
ninja -C out/Debug cctest

# 4. 运行所有污点追踪测试
out/Debug/cctest --gtest_filter="Taint*"

# 或者运行特定测试
out/Debug/cctest --gtest_filter="TaintSinkBasic"
```

### 方法2: 直接使用现有测试

```bash
# 运行V8现有的污点追踪测试
cd v8
out/Debug/cctest --gtest_filter="*Taint*"
```

## 测试用例说明

### 1. TaintSinkBasic - 基本sink报警
```javascript
var tainted_input = 'alert(1)';
tainted_input.__setTaint__(1);  // 标记为污点
eval(tainted_input);             // 传播到sink → 应该触发报警
```
**预期**: 触发至少1次sink报警

### 2. TaintPropagationConcat - 字符串拼接传播
```javascript
var user_input = '1';
user_input.__setTaint__(1);
var code = '1 + ' + user_input;  // 污点传播
eval(code);                       // → 触发报警
```
**预期**: 污点通过拼接传播，触发报警

### 3. TaintPropagationSubstring - 子串传播
```javascript
var tainted = '1234567890';
tainted.__setTaint__(1);
var slice = tainted.substring(0, 1);  // 子串继承污点
eval(slice);                           // → 触发报警
```
**预期**: 子串操作保持污点，触发报警

### 4. MultipleTaintSources - 多个污点源
```javascript
var url_param = 'param1';
var cookie_val = 'value1';
url_param.__setTaint__(1);
cookie_val.__setTaint__(1);
var combined = url_param + '=' + cookie_val;
eval('"' + combined + '"');  // → 触发报警
```
**预期**: 多个污点源合并后仍能检测

### 5. NoTaintNoAlert - 无污点不报警
```javascript
var clean_data = '1 + 1';
// 没有调用 __setTaint__
eval(clean_data);  // → 不应该触发污点报警
```
**预期**: 无污点数据不触发报警

### 6. TaintPropagationObject - 对象属性传播
```javascript
var obj = { code: '1' };
__setTaint__(obj, 1);  // 标记整个对象
eval(obj.code);         // 属性访问继承污点 → 触发报警
```
**预期**: 对象属性继承污点，触发报警

### 7. ComplexTaintPropagation - 复杂传播路径
```javascript
var input = 'attack';
input.__setTaint__(1);
var step1 = input.toUpperCase();      // ATTACK
var step2 = step1.toLowerCase();      // attack
var step3 = 'eval("' + step2 + '")';  // eval("attack")
var step4 = step3.substring(5, 11);   // attack
eval('"' + step4 + '"');               // → 触发报警
```
**预期**: 经过多次变换后污点仍然保留，触发报警

## 验证方法

### 检查点1: 污点是否被正确标记
```javascript
var str = 'test';
str.__setTaint__(1);
// 检查: 使用 __getTaint__() 可以读取污点状态
var taint_data = new Uint8Array(str.__getTaint__());
console.log(taint_data[0]);  // 应该是 1（已标记）
```

### 检查点2: 污点是否正确传播
```javascript
var source = 'src';
source.__setTaint__(1);
var derived = source + '_derived';
// 检查: derived 应该继承污点
var taint = new Uint8Array(derived.__getTaint__());
console.log(taint[0]);  // 应该是 1（继承了污点）
```

### 检查点3: Sink是否触发报警
使用 `SinkAlertListener` 监听器：
- 监听 `TaintLogRecord::Message::JS_SINK_TAINTED` 消息
- 计数报警次数
- 验证 sink 类型（如 `JAVASCRIPT` 对应 eval）

## 调试技巧

### 启用污点追踪日志
```bash
# 设置环境变量启用详细日志
export V8_TAINT_TRACKING_LOG=1

# 或者在代码中设置flag
FLAG_taint_tracking_enable_export_ast = true;
FLAG_taint_tracking_enable_ast_modification = true;
```

### 检查日志输出
污点追踪会生成日志文件，通常在：
```bash
# 日志文件位置
/tmp/taint_log_*.bin

# 查看日志
ls -lh /tmp/taint_log_*
```

### 使用GDB调试
```bash
gdb out/Debug/cctest
(gdb) break LogIfTainted
(gdb) run --gtest_filter="TaintSinkBasic"
```

## 常见问题

### Q1: 测试运行但没有报警
**原因**: 污点追踪可能未启用
**解决**: 
- 检查编译配置是否包含污点追踪
- 确认 `kTaintTrackingEnabled = true`
- 检查测试初始化是否正确调用 `CcTest::InitializeVM()`

### Q2: 报警触发但数据不准确
**原因**: 污点传播逻辑可能有bug
**调试**:
- 在每个传播点打印 `__getTaint__()` 的值
- 检查 `OnNewConsString`, `OnNewSlicedString` 等函数
- 查看 `taint_tracking.cc` 中的传播逻辑

### Q3: 编译错误
**原因**: V8版本或路径问题
**解决**:
- 确保使用正确的V8版本（支持污点追踪的版本）
- 检查头文件路径
- 参考 `v8/test/cctest/BUILD.gn` 的配置

## 扩展测试

### 添加新的Sink类型
除了 `eval`，还可以测试其他sink：
- `Function` 构造函数
- `innerHTML` (需要Blink环境)
- `document.write` (需要Blink环境)
- `setTimeout`/`setInterval` 的字符串参数

### 测试不同的Taint类型
```javascript
// 测试不同的污点类型
var url_data = location.href;
url_data.__setTaint__(__taintConstants__().Url);

var cookie_data = document.cookie;
cookie_data.__setTaint__(__taintConstants__().Cookie);
```

## 参考资料

- V8源码: `v8/src/taint_tracking/`
- 现有测试: `v8/test/cctest/test-taint-tracking.cc`
- 污点追踪论文: Dynamic Taint Analysis for JavaScript
