# 污点跟踪补丁编译指南

## 概述

你已经将污点跟踪补丁移植到当前的Chromium代码库中。主要修改的文件包括：

### Blink (WebKit) 部分
- `third_party/blink/renderer/platform/wtf/text/taint_tracking.h` (新增)
- `third_party/blink/renderer/platform/wtf/text/taint_tracking.cc` (新增)
- `third_party/blink/renderer/platform/wtf/text/string_impl.cc` (修改)

### V8 部分
- `v8/src/taint_tracking.h` (新增)
- `v8/src/taint_tracking-inl.h` (新增)
- `v8/src/taint_tracking/` (整个目录，包含多个文件)

## 语法检查结果 ✓

基本语法检查已通过：
- ✓ 括号匹配正确
- ✓ namespace 结构完整
- ✓ include 指令格式正确

## 快速编译方案

### 方案1: 使用提供的脚本（推荐）

```bash
cd /home/ycc/exp/chromium
./compile_taint_tracking.sh
```

这个脚本会：
1. 创建最小化的构建配置
2. 生成构建文件
3. 只编译污点跟踪相关的目标

### 方案2: 手动增量编译

#### 前提条件
确保你已经安装了所有依赖：

```bash
cd /home/ycc/exp/chromium
gclient sync
```

#### 创建构建配置

```bash
mkdir -p out/TaintTest
cat > out/TaintTest/args.gn << 'EOF'
is_debug = false
is_component_build = false
symbol_level = 1
v8_enable_disassembler = false
v8_enable_object_print = false
v8_enable_verify_heap = false
use_goma = false
enable_nacl = false
EOF
```

#### 生成构建文件

```bash
export PATH=/home/ycc/exp/depot_tools:$PATH
gn gen out/TaintTest
```

#### 编译特定目标

```bash
# 只编译 Blink 平台库（包含 taint_tracking.cc）
ninja -C out/TaintTest -j4 blink_platform

# 只编译 V8 污点跟踪 stub
ninja -C out/TaintTest -j4 v8_taint_tracking_stub

# 或者编译完整的 V8 污点跟踪实现
ninja -C out/TaintTest -j4 v8_taint_tracking
```

### 方案3: 最快的验证方法（仅语法检查）

如果只想快速验证语法，不需要完整编译：

```bash
cd /home/ycc/exp/chromium

# 检查 Blink 部分
clang++ -std=c++20 -fsyntax-only \
  -Ithird_party/blink/renderer \
  -Ithird_party/abseil-cpp \
  -c third_party/blink/renderer/platform/wtf/text/taint_tracking.cc

# 检查 V8 stub 部分
clang++ -std=c++20 -fsyntax-only \
  -Iv8 -Iv8/include \
  -Ithird_party/abseil-cpp \
  -c v8/src/taint_tracking/taint_tracking_stub.cc
```

## 常见问题

### Q1: 缺少 gn 工具
**解决方案：** 运行 `gclient sync` 来下载所有必需的构建工具

### Q2: 缺少依赖库（如 abseil, googletest）
**解决方案：** 运行 `gclient sync` 来同步所有第三方依赖

### Q3: 编译时间太长
**解决方案：** 
- 使用增量编译，只编译修改的模块
- 使用 `-j` 参数控制并行任务数（如 `-j4`）
- 使用 component build: `is_component_build = true`

### Q4: 内存不足
**解决方案：**
- 减少并行任务数：`ninja -j2` 或 `ninja -j1`
- 设置 `symbol_level = 0` 减少调试信息

## 补丁涉及的文件列表

### 新增文件
1. `third_party/blink/renderer/platform/wtf/text/taint_tracking.h`
2. `third_party/blink/renderer/platform/wtf/text/taint_tracking.cc`
3. `v8/src/taint_tracking/` 目录下的所有文件

### 修改文件
根据补丁，以下文件可能被修改（需要验证）：
- `third_party/blink/renderer/platform/wtf/text/string_impl.cc`
- `third_party/blink/renderer/core/dom/Element.cpp`
- `third_party/blink/renderer/core/frame/Location.cpp`
- 等等（参考 chromium_patch.txt）

## 下一步建议

1. **先运行语法检查**：确保基本语法没有问题
2. **安装依赖**：运行 `gclient sync`
3. **增量编译**：使用上述方案只编译修改的模块
4. **检查错误**：如果有编译错误，逐个修复
5. **完整测试**：编译成功后，运行相关测试

## 编译时间估算

- **仅 taint_tracking 模块**: 约 5-10 分钟（首次编译）
- **blink_platform 目标**: 约 15-30 分钟
- **完整 Chrome**: 约 2-4 小时（不推荐，除非必要）

## 资源消耗

- **磁盘空间**: 至少 50GB 可用空间
- **内存**: 建议 16GB+ RAM
- **CPU**: 使用 `-j4` 到 `-j8` 取决于你的CPU核心数

## 联系与支持

如果遇到具体的编译错误，请提供：
1. 完整的错误信息
2. 你使用的编译命令
3. 系统环境信息（OS、编译器版本等）
