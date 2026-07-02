# 污点追踪测试 - 快速开始指南

## 当前状态

✅ 已完成:
- 找到项目中的污点追踪代码和测试
- 创建了完整的测试套件和文档
- 准备好了测试脚本

⚠️ 待完成:
- 编译 cctest 测试框架

## 快速开始（3步）

### 方案A: 自动化编译和测试（推荐）

```bash
# 一键编译和测试
chmod +x setup_and_test.sh
./setup_and_test.sh
```

这个脚本会：
1. 检查编译环境
2. 编译 V8 的 cctest
3. 自动运行验证测试

### 方案B: 手动编译和测试

```bash
# 1. 进入V8目录
cd v8

# 2. 生成构建配置（选择一个）
gn gen out/Debug --args='is_debug=true'              # Debug版本
# 或
gn gen out/Release --args='is_debug=false'           # Release版本

# 3. 编译 cctest（首次需要10-30分钟）
ninja -C out/Debug cctest

# 4. 返回主目录
cd ..

# 5. 运行测试
./quick_verify_taint.sh
```

## 测试内容

### 现有测试（在 v8/test/cctest/test-taint-tracking.cc）

该文件包含 **2257行** 完整的污点追踪测试，涵盖：

#### 1. 基础功能测试
- ✅ `TaintLarge` - 基本污点标记和获取
- ✅ `TaintConsString*` - 字符串拼接时的污点传播
- ✅ `TaintSlicedString*` - 子串操作的污点传播

#### 2. 污点传播测试
- ✅ `TaintEncoding*` - URL编码/解码
- ✅ `TaintJoin*` - 数组join操作
- ✅ `TaintString*` - 各种字符串操作
- ✅ `TaintJSON*` - JSON解析和序列化
- ✅ `TaintRegexp` - 正则表达式替换

#### 3. Sink检测测试
- ✅ `OnBeforeCompile*` - eval触发报警
- ✅ `RecursiveTaint*` - 对象属性污点传播到eval

### 运行示例

```bash
# 运行所有污点测试
v8/out/Debug/cctest --gtest_filter="*Taint*"

# 运行基础测试
v8/out/Debug/cctest --gtest_filter="TaintLarge:TaintConsStringTwo"

# 运行sink报警测试
v8/out/Debug/cctest --gtest_filter="OnBeforeCompileEval"

# 查看测试列表
v8/out/Debug/cctest --gtest_list_tests | grep Taint
```

## 测试验证要点

### 1. 污点标记测试

**测试代码**:
```cpp
Handle<String> test = factory->NewStringFromStaticChars("test");
SetTaintStatus(*test, 2, TaintType::TAINTED);  // 标记位置2为污点
CHECK_EQ(GetTaintStatus(*test, 2), TaintType::TAINTED);  // 验证
```

**预期**: 能够成功标记和读取污点状态

### 2. 污点传播测试

**测试代码**:
```cpp
Handle<String> first = factory->NewStringFromStaticChars("first");
SetTaintStatus(*first, 2, TaintType::TAINTED);
Handle<String> cons = factory->NewConsString(first, second);
CHECK_EQ(GetTaintStatus(*cons, 2), TaintType::TAINTED);  // 传播到拼接结果
```

**预期**: 污点从源字符串传播到结果字符串

### 3. Sink报警测试

**测试代码**:
```javascript
var a = '1 + 1';
a.__setTaint__(1);  // 标记污点
eval(a);             // 传入sink
```

**预期**: TaintListener被触发，listener->GetScripts().size() > 0

## 查看测试结果

### 成功的输出示例

```
[==========] Running 1 test from 1 test suite.
[----------] 1 test from TaintTest
[ RUN      ] TaintTest.TaintLarge
[       OK ] TaintTest.TaintLarge (15 ms)
[----------] 1 test from TaintTest (15 ms total)
```

### 失败的输出示例

```
[  FAILED  ] TaintTest.TaintLarge
Expected: GetTaintStatus(*test, 2) == TaintType::TAINTED
Actual: UNTAINTED vs. TAINTED
```

## 调试技巧

### 1. 启用详细输出

```bash
# 运行单个测试并显示详细信息
v8/out/Debug/cctest --gtest_filter="TaintLarge" --gtest_print_time=1
```

### 2. 使用GDB调试

```bash
gdb v8/out/Debug/cctest
(gdb) break SetTaintStatus
(gdb) run --gtest_filter="TaintLarge"
(gdb) print *test
```

### 3. 查看污点日志

```bash
# 测试运行后检查日志
ls -lh /tmp/taint_log_*.bin
```

## 关键API说明

### C++ API

```cpp
// 标记污点
void SetTaintStatus(String object, size_t idx, TaintType type);

// 获取污点状态
TaintType GetTaintStatus(String object, size_t idx);

// 检测并记录污点到sink
int64_t LogIfTainted(Handle<String> str, TaintSinkLabel label, 
                     int symbolic_data, Isolate* isolate);
```

### JavaScript API

```javascript
// 标记污点
str.__setTaint__(position);

// 获取污点状态
var taintData = str.__getTaint__();
var array = new Uint8Array(taintData);

// 标记整个对象
__setTaint__(obj, 1);

// 获取污点常量
var constants = __taintConstants__();
str.__setTaint__(constants.Url);
```

## 文件清单

我已为您创建的文件：

1. **TAINT_TRACKING_SUMMARY.md** - 总体概述和工作流程
2. **README_TAINT_TEST.md** - 详细的测试文档
3. **test_taint_sink.cc** - 自定义测试套件（可选）
4. **setup_and_test.sh** - 自动化编译和测试脚本
5. **quick_verify_taint.sh** - 快速验证脚本
6. **run_taint_tests.sh** - 交互式测试菜单
7. **QUICKSTART.md** - 本文件

## 常见问题

### Q: 编译需要多长时间？
A: 首次编译需要 10-30 分钟，取决于机器性能。增量编译通常只需几分钟。

### Q: 需要多少磁盘空间？
A: Debug版本约需 5-10 GB，Release版本约需 2-5 GB。

### Q: 测试失败怎么办？
A: 
1. 检查是否使用了支持污点追踪的V8版本
2. 查看测试输出的错误信息
3. 使用GDB调试具体的测试用例

### Q: 如何验证功能正常？
A: 运行 `OnBeforeCompileEval` 测试，如果 listener->GetScripts().size() > 0，说明sink检测正常工作。

## 下一步

1. ✅ **运行编译**: `./setup_and_test.sh`
2. ✅ **快速验证**: `./quick_verify_taint.sh`
3. ✅ **查看结果**: 检查测试通过情况
4. ✅ **深入测试**: `./run_taint_tests.sh` 运行完整测试套件

---

**提示**: 如果您不想等待编译，可以直接查看现有测试代码来理解污点追踪的工作原理：
```bash
cat v8/test/cctest/test-taint-tracking.cc | less
```
