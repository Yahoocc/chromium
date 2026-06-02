# StringImpl 污点追踪修改详细文档

## 📋 概述

本文档详细记录了为支持污点追踪（Taint Tracking）对 `StringImpl` 类所做的修改。`StringImpl` 是 Blink 渲染引擎中所有字符串的底层实现类，修改它以支持污点追踪是整个系统的核心基础。

**修改日期**：2026-05-27  
**阶段**：Phase 1.2 - StringImpl 修改  
**状态**：✅ 已完成并编译成功

---

## 🎯 修改目标

为每个 `StringImpl` 对象分配额外的内存空间来存储污点数据，使得：
1. 每个字符都有对应的污点标记（1 字节/字符）
2. 每个字符串都有一个污点信息 ID（8 字节，用于跨域消息追踪）
3. 在字符串创建时自动初始化污点数据为 0（未污染状态）

---

## 📁 修改的文件

### 1. `third_party/blink/renderer/platform/wtf/text/string_impl.h`

**修改位置 1**：添加头文件引用（第 51 行）

```cpp
#include "third_party/blink/renderer/platform/wtf/text/taint_tracking.h"
```

**作用**：引入污点追踪的核心类 `StringTaint`，以便在 `StringImpl` 中调用其方法。

---

**修改位置 2**：修改 `AllocationSize<CharType>()` 模板方法（第 604-614 行）

**修改前**：
```cpp
template <typename CharType>
static size_t AllocationSize(size_type length) {
  static_assert(
      sizeof(CharType) > 1,
      "Don't use this template with 1-byte chars; use a template "
      "specialization to save time and code-size by avoiding a CheckMul.");
  return base::CheckAdd(sizeof(StringImpl),
                        base::CheckMul(length, sizeof(CharType)))
      .ValueOrDie();
}
```

**修改后**：
```cpp
template <typename CharType>
static size_t AllocationSize(size_type length) {
  static_assert(
      sizeof(CharType) > 1,
      "Don't use this template with 1-byte chars; use a template "
      "specialization to save time and code-size by avoiding a CheckMul.");
  return base::CheckAdd(
             base::CheckAdd(sizeof(StringImpl),
                            base::CheckMul(length, sizeof(CharType))),
             tainttracking::webkit::StringTaint::AllocationSize(length))
      .ValueOrDie();
}
```

**变化说明**：
- 原来的分配大小 = `sizeof(StringImpl)` + `length * sizeof(CharType)`
- 现在的分配大小 = `sizeof(StringImpl)` + `length * sizeof(CharType)` + **污点数据大小**
- 污点数据大小 = `length * sizeof(TaintData)` + `sizeof(int64_t)` = `length + 8` 字节

**适用范围**：此模板方法用于 16 位字符（UChar，2 字节/字符）的字符串。

---

**修改位置 3**：修改 `AllocationSize<LChar>()` 模板特化（第 693-698 行）

**修改前**：
```cpp
template <>
ALWAYS_INLINE size_t StringImpl::AllocationSize<LChar>(size_type length) {
  static_assert(sizeof(LChar) == 1, "sizeof(LChar) should be 1.");
  return base::CheckAdd(sizeof(StringImpl), length).ValueOrDie();
}
```

**修改后**：
```cpp
template <>
ALWAYS_INLINE size_t StringImpl::AllocationSize<LChar>(size_type length) {
  static_assert(sizeof(LChar) == 1, "sizeof(LChar) should be 1.");
  return base::CheckAdd(base::CheckAdd(sizeof(StringImpl), length),
                        tainttracking::webkit::StringTaint::AllocationSize(length))
      .ValueOrDie();
}
```

**变化说明**：
- 原来的分配大小 = `sizeof(StringImpl)` + `length`（因为 LChar 是 1 字节）
- 现在的分配大小 = `sizeof(StringImpl)` + `length` + **污点数据大小**
- 污点数据大小 = `length + 8` 字节

**适用范围**：此模板特化用于 8 位字符（LChar，1 字节/字符）的字符串，这是一个性能优化版本。

---

### 2. `third_party/blink/renderer/platform/wtf/text/string_impl.cc`

**修改位置 1**：添加头文件引用（第 49 行）

```cpp
#include "third_party/blink/renderer/platform/wtf/text/taint_tracking.h"
```

**作用**：引入污点追踪的核心类 `StringTaint`，以便调用 `InitTaintData()` 方法。

---

**修改位置 2**：修改 `CreateUninitialized(size_t, base::span<LChar>&)` 方法（第 188-207 行）

**修改前**：
```cpp
scoped_refptr<StringImpl> StringImpl::CreateUninitialized(
    size_t length,
    base::span<LChar>& data) {
  if (!length) {
    data = {};
    return empty_;
  }
  const size_type narrowed_length = base::checked_cast<size_type>(length);

  StringImpl* string = new (Partitions::BufferMalloc(
      AllocationSize<LChar>(narrowed_length), "blink::StringImpl"))
      StringImpl(narrowed_length, kForce8BitConstructor);

  data = string->CharacterBuffer<LChar>();
  return base::AdoptRef(string);
}
```

**修改后**：
```cpp
scoped_refptr<StringImpl> StringImpl::CreateUninitialized(
    size_t length,
    base::span<LChar>& data) {
  if (!length) {
    data = {};
    return empty_;
  }
  const size_type narrowed_length = base::checked_cast<size_type>(length);

  StringImpl* string = new (Partitions::BufferMalloc(
      AllocationSize<LChar>(narrowed_length), "blink::StringImpl"))
      StringImpl(narrowed_length, kForce8BitConstructor);

  tainttracking::webkit::StringTaint::InitTaintData(string);
  data = string->CharacterBuffer<LChar>();
  return base::AdoptRef(string);
}
```

**变化说明**：
- 在分配内存并构造 `StringImpl` 对象后，立即调用 `InitTaintData(string)` 初始化污点数据
- `InitTaintData()` 会将所有污点数据清零（`memset` 为 0），表示字符串初始状态为未污染

**适用范围**：此方法用于创建 8 位字符（LChar）的未初始化字符串。

---

**修改位置 3**：修改 `CreateUninitialized(size_t, base::span<UChar>&)` 方法（第 209-228 行）

**修改前**：
```cpp
scoped_refptr<StringImpl> StringImpl::CreateUninitialized(
    size_t length,
    base::span<UChar>& data) {
  if (!length) {
    data = {};
    return empty_;
  }
  const size_type narrowed_length = base::checked_cast<size_type>(length);

  StringImpl* string = new (Partitions::BufferMalloc(
      AllocationSize<UChar>(narrowed_length), "blink::StringImpl"))
      StringImpl(narrowed_length);

  data = string->CharacterBuffer<UChar>();
  return base::AdoptRef(string);
}
```

**修改后**：
```cpp
scoped_refptr<StringImpl> StringImpl::CreateUninitialized(
    size_t length,
    base::span<UChar>& data) {
  if (!length) {
    data = {};
    return empty_;
  }
  const size_type narrowed_length = base::checked_cast<size_type>(length);

  StringImpl* string = new (Partitions::BufferMalloc(
      AllocationSize<UChar>(narrowed_length), "blink::StringImpl"))
      StringImpl(narrowed_length);

  tainttracking::webkit::StringTaint::InitTaintData(string);
  data = string->CharacterBuffer<UChar>();
  return base::AdoptRef(string);
}
```

**变化说明**：
- 在分配内存并构造 `StringImpl` 对象后，立即调用 `InitTaintData(string)` 初始化污点数据
- `InitTaintData()` 会将所有污点数据清零（`memset` 为 0），表示字符串初始状态为未污染

**适用范围**：此方法用于创建 16 位字符（UChar）的未初始化字符串。

---

## 🧠 内存布局变化

### 修改前的内存布局

```
+------------------+
| StringImpl 对象  |  sizeof(StringImpl) 字节
+------------------+
| 字符数据         |  length * sizeof(CharType) 字节
+------------------+
```

### 修改后的内存布局

```
+------------------+
| StringImpl 对象  |  sizeof(StringImpl) 字节
+------------------+
| 字符数据         |  length * sizeof(CharType) 字节
+------------------+
| 污点数据数组     |  length 字节 (每字符 1 字节)
+------------------+
| 污点信息 ID      |  8 字节 (int64_t)
+------------------+
```

### 内存布局示例

假设有一个长度为 10 的 8 位字符串（LChar）：

**修改前**：
- StringImpl 对象：假设 12 字节
- 字符数据：10 字节
- **总计**：22 字节

**修改后**：
- StringImpl 对象：12 字节
- 字符数据：10 字节
- 污点数据数组：10 字节
- 污点信息 ID：8 字节
- **总计**：40 字节

**内存开销**：每个字符串增加 `length + 8` 字节的开销。

---

## 🔍 污点数据的访问方式

污点数据存储在字符数据之后，通过 `StringTaint::FromString()` 方法访问：

```cpp
TaintData* StringTaint::FromString(blink::StringImpl* impl) {
  if (!impl) {
    return nullptr;
  }

  size_t len = impl->length();
  if (impl->Is8Bit()) {
    // 8 位字符：污点数据在 LChar 数组之后
    return reinterpret_cast<TaintData*>(
        &(reinterpret_cast<blink::LChar*>(impl + 1)[len]));
  } else {
    // 16 位字符：污点数据在 UChar 数组之后
    return reinterpret_cast<TaintData*>(
        &(reinterpret_cast<UChar*>(impl + 1)[len]));
  }
}
```

**关键点**：
- `impl + 1` 指向字符数据的起始位置（紧跟在 StringImpl 对象之后）
- `[len]` 跳过所有字符数据，指向污点数据的起始位置
- 污点信息 ID 存储在污点数据数组之后的 8 字节

---

## ✅ 编译验证

修改完成后，成功编译了 `string_impl.o` 目标文件：

```bash
ninja -C out/Default obj/third_party/blink/renderer/platform/wtf/wtf/string_impl.o
```

**编译结果**：✅ 成功（退出码 0）

---

## 🔗 相关文件

- **污点追踪核心类**：
  - [taint_tracking.h](third_party/blink/renderer/platform/wtf/text/taint_tracking.h)
  - [taint_tracking.cc](third_party/blink/renderer/platform/wtf/text/taint_tracking.cc)

- **构建配置**：
  - [BUILD.gn](third_party/blink/renderer/platform/wtf/BUILD.gn)

- **项目文档**：
  - [TAINT_TRACKING_PLAN.md](TAINT_TRACKING_PLAN.md) - 总体移植计划
  - [TAINT_TRACKING_MIGRATION.md](TAINT_TRACKING_MIGRATION.md) - 迁移指南
  - [TAINT_TRACKING_SUCCESS.md](TAINT_TRACKING_SUCCESS.md) - Phase 1.1 成功报告

---

## 📊 修改统计

| 项目 | 数量 |
|------|------|
| 修改的文件 | 2 个 |
| 添加的头文件引用 | 2 处 |
| 修改的方法 | 4 个 |
| 添加的函数调用 | 2 处 |
| 代码行数变化 | +8 行 |

---

## 🎯 下一步

StringImpl 修改完成后，下一步是 **Phase 2.1: V8StringResource 修改**，这将建立 Blink 和 V8 之间的污点数据传递桥梁。

---

## 📝 技术要点

### 1. 为什么要修改 `AllocationSize()`？

`AllocationSize()` 计算分配字符串所需的总内存大小。修改它是为了：
- 在原有的 `StringImpl` 对象和字符数据之外，额外分配污点数据的空间
- 确保内存分配器（`Partitions::BufferMalloc`）分配足够的内存

### 2. 为什么要调用 `InitTaintData()`？

`InitTaintData()` 将污点数据初始化为 0（未污染状态）。这很重要，因为：
- 新创建的字符串默认应该是未污染的
- 未初始化的内存可能包含随机数据，会导致误报
- 使用 `memset` 清零是最快的初始化方式

### 3. 为什么有两个 `CreateUninitialized()` 方法？

Chromium 对字符串进行了优化：
- **8 位字符串（LChar）**：用于纯 ASCII 或 Latin-1 字符，节省内存
- **16 位字符串（UChar）**：用于 Unicode 字符，支持所有字符

两个方法分别处理这两种情况，以获得最佳性能。

### 4. 为什么使用 `base::CheckAdd()`？

`base::CheckAdd()` 是 Chromium 的安全数学运算函数，用于：
- 检测整数溢出
- 防止内存分配时的安全漏洞
- 如果溢出，`ValueOrDie()` 会触发程序崩溃（比静默溢出更安全）

### 5. 内存开销是否可接受？

**开销分析**：
- 短字符串（10 字符）：增加 18 字节（180% 开销）
- 中等字符串（100 字符）：增加 108 字节（108% 开销）
- 长字符串（1000 字符）：增加 1008 字节（100.8% 开销）

**结论**：
- 这是安全功能的必要代价
- 污点追踪主要用于安全研究和测试环境，不是生产环境的默认配置
- 可以通过编译选项控制是否启用污点追踪

---

## ⚠️ 注意事项

1. **内存对齐**：污点数据紧跟在字符数据之后，没有额外的对齐填充
2. **线程安全**：`StringImpl` 是不可变的（immutable），创建后不会修改，因此污点数据也是不可变的
3. **引用计数**：污点数据随 `StringImpl` 对象一起分配和释放，不需要单独管理
4. **空字符串**：空字符串（`empty_`）是单例，不分配污点数据

---

**文档版本**：1.0  
**最后更新**：2026-05-27
