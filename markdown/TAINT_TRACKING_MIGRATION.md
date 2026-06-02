# Taint Tracking 移植进度报告

## 已完成的工作

### 1. TaintTracking 基础文件创建 ✅

已成功创建并移植以下文件：

#### `third_party/blink/renderer/platform/wtf/text/taint_tracking.h`
- 定义了 `TaintType` 枚举（与 V8 的定义保持一致）
- 包含 20 种污点类型：UNTAINTED, TAINTED, COOKIE, MESSAGE, URL, URL_HASH, URL_PROTOCOL, URL_HOST, URL_HOSTNAME, URL_ORIGIN, URL_PORT, URL_PATHNAME, URL_SEARCH, DOM, REFERRER, WINDOWNAME, STORAGE, NETWORK, MULTIPLE_TAINTS, MESSAGE_ORIGIN
- 定义了编码类型：URL_ENCODED, URL_COMPONENT_ENCODED, ESCAPE_ENCODED 等
- 提供了 `StringTaint` 类，包含以下静态方法：
  - `FromString()` - 从 StringImpl 获取污点数据缓冲区
  - `InitTaintData()` - 初始化污点数据
  - `AllocationSize()` - 计算污点数据所需的额外内存
  - `SetTainted()` - 设置字符串的污点类型
  - `GetTaintInfo()` - 获取污点信息 ID
  - `SetTaintInfo()` - 设置污点信息 ID

#### `third_party/blink/renderer/platform/wtf/text/taint_tracking.cc`
- 实现了所有 `StringTaint` 类的方法
- 关键实现细节：
  - 污点数据存储在 StringImpl 内存布局的末尾
  - 每个字符对应一个字节的污点数据
  - 额外存储 8 字节的 int64_t 污点信息 ID（用于跨域消息追踪）
  - 内存布局：`[StringImpl对象] [字符数据] [污点数据] [污点信息ID]`
  - 添加了空指针检查，防止崩溃

#### `third_party/blink/renderer/platform/wtf/BUILD.gn`
- 已将 `taint_tracking.cc` 和 `taint_tracking.h` 添加到构建系统
- 位置：在 `string_view.h` 之后，`text_codec.cc` 之前

### 2. 关键设计决策

#### 与 V8 的兼容性
- `TaintType` 枚举值必须与 `v8/include/v8-primitive.h` 中的定义完全一致
- 使用 `TAINT_TRACKING_TAINT_TYPE_FOR` 宏来确保两边的枚举同步
- 在后续的绑定层代码中会有 `static_assert` 来验证一致性

#### 内存管理
- 污点数据与字符串数据一起分配，避免额外的内存分配开销
- 使用 `memset` 进行批量初始化和设置，性能较好
- 支持 8-bit (LChar) 和 16-bit (UChar) 字符串

## 编译状态

- ✅ GN 构建文件生成成功
- 🔄 正在编译 wtf 模块（后台运行中）

## 下一步工作（暂未开始）

### 3. StringImpl 修改
需要修改 `third_party/blink/renderer/platform/wtf/text/string_impl.h` 和 `string_impl.cc`：
- 修改 `allocationSize()` 模板函数，增加污点数据的空间
- 在 `createUninitialized()` 中调用 `StringTaint::InitTaintData()`
- 在 `createStatic()` 中调用 `StringTaint::InitTaintData()`

### 4. V8 绑定层修改
需要修改以下文件以实现 Blink ↔ V8 的污点数据传递：
- `third_party/blink/renderer/bindings/core/v8/v8_string_resource.h`
- `third_party/blink/renderer/bindings/core/v8/v8_string_resource.cc`
- `third_party/blink/renderer/bindings/core/v8/script_state.h`
- `third_party/blink/renderer/bindings/core/v8/script_state.cc`

### 5. DOM 层污点设置
需要在以下位置设置污点标记：
- `Location` 类（href, protocol, host, hostname, port, pathname, search, hash, origin）
- `Document` 类（cookie, referrer, write/writeln）
- `Element` 类（innerHTML, outerHTML, insertAdjacentHTML, setAttribute）
- `HTMLScriptElement` 类（src, text）
- `HTMLAnchorElement`, `HTMLEmbedElement`, `HTMLIFrameElement`, `HTMLImageElement`
- `MessageEvent` 类（data, origin）
- `StorageArea` 类（getItem）
- `DOMWindowTimers` 类（setTimeout, setInterval）

### 6. 污点检测点
需要在以下危险操作处添加污点检查：
- innerHTML/outerHTML 赋值
- document.write/writeln
- eval 调用
- setTimeout/setInterval 字符串参数
- script.src/script.text 设置
- location 赋值
- 各种 URL sink（anchor.href, iframe.src, img.src 等）

## 技术细节

### 内存布局示例
```
对于字符串 "hello" (5 个字符)：

┌──────────────┬───────────────┬─────────────────┬──────────────┐
│ StringImpl   │ 'h' 'e' 'l'   │ T T T T T       │ int64_t      │
│ 对象头       │ 'l' 'o'       │ (5 bytes)       │ (8 bytes)    │
│              │ (5 bytes)     │ 污点数据         │ 污点信息ID    │
└──────────────┴───────────────┴─────────────────┴──────────────┘

T = TaintData (uint8_t)，每个字符一个字节
```

### 污点类型说明
- **来源污点**：URL, COOKIE, MESSAGE, DOM, REFERRER, WINDOWNAME, STORAGE, NETWORK
- **细粒度 URL 污点**：URL_HASH, URL_PROTOCOL, URL_HOST, URL_HOSTNAME, URL_ORIGIN, URL_PORT, URL_PATHNAME, URL_SEARCH
- **编码状态**：URL_ENCODED, URL_COMPONENT_ENCODED, ESCAPE_ENCODED
- **特殊标记**：MESSAGE_ORIGIN（用于跨域消息来源追踪）

## 注意事项

1. **枚举值同步**：必须确保 Blink 的 `TaintType` 与 V8 的 `TaintType` 完全一致
2. **性能影响**：每个字符串增加 `length + 8` 字节的内存开销
3. **空指针安全**：所有方法都已添加空指针检查
4. **构建系统**：已从 gyp 迁移到 GN

## 参考
- 原始补丁：`v8/chromium_patch.txt`
- V8 污点追踪定义：`v8/include/v8-primitive.h`
