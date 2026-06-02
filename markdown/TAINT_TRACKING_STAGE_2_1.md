# 污点追踪移植 - 阶段 2.1: V8StringResource 修改

## 完成时间
2026-05-27

## 修改概述
阶段 2.1 完成了 V8 和 Blink 之间字符串污点数据传递的关键桥梁。

## 修改的文件

### 1. third_party/blink/renderer/platform/bindings/to_blink_string.cc
**修改内容：**
- 添加了 `taint_tracking.h` 头文件
- 添加了静态断言验证 V8 和 Blink 的 TaintData 大小一致
- 添加了静态断言验证 V8 和 Blink 的 TaintType 枚举值一致
- 添加了 `WriteTaintHelper()` 辅助函数，用于从 V8 字符串写入污点数据到 Blink StringImpl
- 修改了 `StringTraits<String>::FromV8String()` 调用 `WriteTaintHelper()`
- 修改了 `StringTraits<AtomicString>::FromV8String()` 在两个分支中都调用 `WriteTaintHelper()`

**作用：**
当 V8 字符串转换为 Blink 字符串时，自动传递污点数据。

### 2. third_party/blink/renderer/platform/bindings/string_resource.h
**修改内容：**
- 添加了 `taint_tracking.h` 头文件
- 修改 `StringResourceBase` 继承 `v8::String::TaintTrackingBase`
- 在 `StringResourceBase` 中添加了虚函数：
  - `virtual uint8_t* InitTaintChars(size_t length)`
  - `virtual uint8_t* GetTaintChars() const = 0`
- 在以下类中实现了 `GetTaintChars()` 方法：
  - `StringResource16`
  - `ParkableStringResource16`
  - `StringResource8`
  - `ParkableStringResource8`

**作用：**
使 Blink 的外部字符串资源能够向 V8 提供污点数据访问接口。

### 3. third_party/blink/renderer/bindings/core/v8/script_state_impl.h
**修改内容：**
- 添加了 `v8/include/v8.h` 头文件
- 添加了公共方法：
  ```cpp
  int64_t LogIfTainted(const String& str, int argument_index, v8::String::TaintSinkLabel label);
  ```

**作用：**
提供检查字符串污点并记录到 V8 污点日志的接口。

### 4. third_party/blink/renderer/bindings/core/v8/script_state_impl.cc
**修改内容：**
- 添加了 `taint_tracking.h` 头文件
- 实现了 `LogIfTainted()` 方法：
  - 检查 ScriptState 是否有效
  - 获取字符串的污点数据缓冲区
  - 根据字符串是 8 位还是 16 位调用相应的 V8 API
  - 调用 `v8::String::LogIfBufferTainted()` 记录污点信息

**作用：**
实现污点检查和日志记录的核心逻辑。

## 技术要点

### 污点数据传递流程
1. **V8 → Blink**: 当 V8 字符串转换为 Blink 字符串时，`WriteTaintHelper()` 调用 `v8::String::WriteTaint()` 将污点数据写入 StringImpl 的污点缓冲区
2. **Blink → V8**: 当 Blink 字符串外部化为 V8 字符串时，通过 `GetTaintChars()` 方法提供污点数据访问

### 静态断言的作用
确保 V8 和 Blink 的污点追踪数据结构完全兼容：
- `TaintData` 类型大小必须相同
- `TaintType` 枚举值必须一一对应

### 字符串类型处理
代码正确处理了多种字符串类型：
- 8 位字符串 (LChar)
- 16 位字符串 (UChar)
- 普通字符串 (String)
- 原子字符串 (AtomicString)
- 可停放字符串 (ParkableString)

## 下一步
继续移植阶段 3: DOM 污点标记层，包括：
- Location 类（URL 污点来源）
- Document 类（Cookie/Referrer）
- Element 类（innerHTML/outerHTML）
- 其他 DOM 元素类

## 编译状态
✅ **编译成功！**

所有修改的文件都成功编译：
- `third_party/blink/renderer/platform/wtf:wtf` - ✓ 编译成功
- `third_party/blink/renderer/bindings/core/v8:v8` - ✓ 编译成功

没有编译错误或警告。
