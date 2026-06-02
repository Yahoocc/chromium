# 污点追踪移植 - 阶段 3 进度报告

## 更新时间
2026-05-27

## 📊 总体进度：30% (4/13 任务)

---

## ✅ 已完成（4个任务）

### 阶段 1: 基础设施层 - 100% 完成

#### ✅ 1.1 TaintTracking 核心类
- 创建了 `taint_tracking.h` 和 `taint_tracking.cc`
- 定义了 20 种污点类型枚举
- 实现了 6 个 StringTaint 静态方法
- 修改了 BUILD.gn
- **编译成功** ✓

#### ✅ 1.2 StringImpl 修改
- 修改了 `string_impl.h` 的 `AllocationSize()` 方法
- 修改了 `string_impl.cc` 的 `CreateUninitialized()` 方法
- 为每个字符串分配额外的污点数据空间（length + 8 字节）
- **编译成功** ✓

### 阶段 2: V8 绑定层 - 100% 完成

#### ✅ 2.1 ScriptState 修改
**修改的文件：**
1. `third_party/blink/renderer/bindings/core/v8/script_state_impl.h`
   - 添加了 `LogIfTainted()` 方法声明

2. `third_party/blink/renderer/bindings/core/v8/script_state_impl.cc`
   - 实现了 `LogIfTainted()` 方法
   - 支持 8-bit 和 16-bit 字符串
   - 调用 V8 的 `LogIfBufferTainted()` 接口

**作用：**
- 提供了从 Blink 到 V8 的污点检查接口
- 支持检查字符串是否被污染并记录日志

#### ✅ 2.2 V8StringResource 修改
**修改的文件：**
1. `third_party/blink/renderer/platform/bindings/to_blink_string.cc`
   - 添加了污点追踪静态断言（验证 V8 和 Blink 的数据结构兼容）
   - 添加了 `WriteTaintHelper()` 函数
   - 修改了 `StringTraits<String>::FromV8String()`
   - 修改了 `StringTraits<AtomicString>::FromV8String()`

2. `third_party/blink/renderer/platform/bindings/string_resource.h`
   - `StringResourceBase` 继承 `v8::String::TaintTrackingBase`
   - 添加了 `InitTaintChars()` 和 `GetTaintChars()` 虚函数
   - 在 4 个资源类中实现了 `GetTaintChars()`：
     - `StringResource16`
     - `ParkableStringResource16`
     - `StringResource8`
     - `ParkableStringResource8`

**作用：**
- 实现了 V8 和 Blink 之间字符串污点数据的双向传递
- 当字符串从 V8 传递到 Blink 时，自动复制污点数据

**编译状态：** ✓ 成功

### 阶段 3: DOM 污点标记层 - 28% (2/7)

#### ✅ 3.1 Location 类（URL 污点来源）
**修改的文件：**
`third_party/blink/renderer/core/frame/location.cc`

**修改内容：**
1. **添加头文件：**
   - `#include "third_party/blink/renderer/bindings/core/v8/script_state_impl.h"`
   - `#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"`
   - `#include "third_party/blink/renderer/platform/wtf/text/taint_tracking.h"`

2. **修改 `Url()` 方法：**
   - 添加了空指针检查，防止崩溃
   - 检查 frame、document 是否存在

3. **为所有 URL 属性 getter 添加污点标记：**
   - `href()` → `TaintType::URL`
   - `protocol()` → `TaintType::URL_PROTOCOL`
   - `host()` → `TaintType::URL_HOST`
   - `hostname()` → `TaintType::URL_HOSTNAME`
   - `port()` → `TaintType::URL_PORT`
   - `pathname()` → `TaintType::URL_PATHNAME`
   - `search()` → `TaintType::URL_SEARCH`
   - `origin()` → `TaintType::URL_ORIGIN`
   - `hash()` → `TaintType::URL_HASH`

4. **在 `SetLocation()` 方法中添加污点检查：**
   - 检查设置的 URL 是否被污染
   - 使用 `TaintSinkLabel::LOCATION_ASSIGNMENT`

**作用：**
- URL 是最重要的污点来源之一
- 所有从 `window.location` 读取的 URL 部分都会被标记为污染
- 设置 `window.location` 时会检查是否使用了污染的数据

**编译状态：** ✓ 成功

#### ✅ 3.2 Node 类（辅助方法）
**修改的文件：**
1. `third_party/blink/renderer/core/dom/node.h`
   - 添加了 `LogIfTaintedNode()` 方法声明

2. `third_party/blink/renderer/core/dom/node.cc`
   - 添加头文件：
     - `#include "third_party/blink/renderer/bindings/core/v8/script_state_impl.h"`
     - `#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"`
   - 实现了 `LogIfTaintedNode()` 方法：
     - 检查字符串是否为空
     - 获取当前 frame 和 ScriptState
     - 调用 `ScriptState::LogIfTainted()` 进行污点检查

**作用：**
- 提供了一个便捷的辅助方法供其他 DOM 类使用
- 简化了污点检查的代码
- 会被 Document、Element、HTMLScriptElement 等类使用

**编译状态：** 🔄 正在验证中...

---

## ⬜ 待完成（9个任务）

### 阶段 3: DOM 污点标记层 - 28% (2/7)

#### 3.3 Document 类（Cookie/Referrer/write）
**需要修改：**
- `cookie` getter：添加 `TaintType::COOKIE` 标记
- `cookie` setter：添加污点检查 `TaintSinkLabel::COOKIE_SINK`
- `referrer` getter：添加 `TaintType::REFERRER` 标记
- `write()` / `writeln()` 方法：添加污点检查 `TaintSinkLabel::HTML`

#### 3.4 Element 类（innerHTML/outerHTML）
**需要修改：**
- `setInnerHTML()`：添加污点检查 `TaintSinkLabel::HTML`
- `setOuterHTML()`：添加污点检查 `TaintSinkLabel::HTML`
- `insertAdjacentHTML()`：添加污点检查 `TaintSinkLabel::HTML`
- `setAttribute()`：
  - 以 "on" 开头的属性：检查 `TaintSinkLabel::JAVASCRIPT_EVENT_HANDLER_ATTRIBUTE`
  - "style" 属性：检查 `TaintSinkLabel::CSS` 或 `CSS_STYLE_ATTRIBUTE`

#### 3.5 HTML 元素类（script/iframe/img 等）
**需要修改：**
- `HTMLScriptElement`：
  - `src` 属性：检查 `TaintSinkLabel::SCRIPT_SRC_URL_SINK`
  - `text` 属性：检查 `TaintSinkLabel::JAVASCRIPT`
  - `childrenChanged()`：检查 `TaintSinkLabel::JAVASCRIPT`
- `HTMLIFrameElement`：
  - `src` 属性：检查 `TaintSinkLabel::IFRAME_SRC_SINK`
- `HTMLImageElement`：
  - `src` 属性：检查 `TaintSinkLabel::IMG_SRC_SINK`
- `HTMLEmbedElement`：
  - `src` 属性：检查 `TaintSinkLabel::EMBED_SRC_SINK`
- `HTMLAnchorElement`：
  - `href` 属性：检查 `TaintSinkLabel::ANCHOR_SRC_SINK`

#### 3.6 MessageEvent（跨域消息）
**需要修改：**
- `V8MessageEventCustom.cpp`：
  - `dataAttributeGetterCustom()`：设置 `TaintType::MESSAGE`
  - `originAttributeGetterCustom()`：设置 `TaintType::MESSAGE_ORIGIN`
- `MessageEvent.h` / `MessageEvent.cpp`：
  - 添加 `taint_tracking_unique_id_` 成员
  - 实现 `TaintTrackingInfo()` 和 `SetTaintTrackingInfo()` 方法

#### 3.7 DOMWindowTimers（setTimeout/setInterval）
**需要修改：**
- `setTimeout()`：检查 `TaintSinkLabel::JAVASCRIPT_SET_TIMEOUT`
- `setInterval()`：检查 `TaintSinkLabel::JAVASCRIPT_SET_INTERVAL`

### 阶段 4: 其他修改 - 0% (0/3)

#### 4.1 WindowProxy 修改
**需要修改：**
- 记录页面导航时的 URL
- 更新污点追踪上下文 ID

#### 4.2 Storage 和 FrameTree
**需要修改：**
- `StorageArea::getItem()`：添加 `TaintType::STORAGE` 标记
- `FrameTree::setName()`：添加 `TaintType::WINDOWNAME` 标记

#### 4.3 EventTarget 修改
**需要修改：**
- 添加 `internalSpecialNamespaceGetRegisteredEvents()` 方法

---

## 📅 下一步行动

### 立即任务
1. **等待 Node 类编译完成**
2. 如果编译成功，继续移植 **Document 类**
3. 然后移植 **Element 类**

### 优先级排序
1. **高优先级**: Document 类（Cookie 和 write 方法）
2. **高优先级**: Element 类（innerHTML/outerHTML）
3. **中优先级**: HTML 元素类（script, iframe 等）
4. **中优先级**: MessageEvent（跨域消息追踪）
5. **低优先级**: 其他污点来源

---

## 🔧 技术要点

### 已实现的关键功能
1. **污点数据存储**: 每个字符串都有对应的污点缓冲区（length 字节）
2. **V8 ↔ Blink 传递**: 字符串转换时自动传递污点数据
3. **污点检查接口**: `ScriptState::LogIfTainted()` 可以检查并记录污点
4. **污点标记接口**: `StringTaint::SetTainted()` 可以为字符串设置污点类型
5. **辅助方法**: `Node::LogIfTaintedNode()` 简化了 DOM 类的污点检查

### 架构设计
```
V8 字符串 (带污点)
    ↓ WriteTaintHelper()
Blink 字符串 (StringImpl + 污点缓冲区)
    ↓ SetTainted()
污点标记 (URL, COOKIE, MESSAGE 等)
    ↓ LogIfTaintedNode()
污点检查 (innerHTML, script.src 等)
    ↓ LogIfTainted()
V8 污点日志系统
```

### 污点类型（已定义）
```cpp
enum TaintType {
  UNTAINTED = 0,
  TAINTED = 1,
  COOKIE = 2,
  MESSAGE = 3,
  URL = 4,
  URL_HASH = 5,
  URL_PROTOCOL = 6,
  URL_HOST = 7,
  URL_HOSTNAME = 8,
  URL_ORIGIN = 9,
  URL_PORT = 10,
  URL_PATHNAME = 11,
  URL_SEARCH = 12,
  DOM = 13,
  REFERRER = 14,
  WINDOWNAME = 15,
  STORAGE = 16,
  NETWORK = 17,
  MULTIPLE_TAINTS = 18,
  MESSAGE_ORIGIN = 19,
  MAX_TAINT_TYPE = 20
};
```

---

## 📝 注意事项

1. **编译依赖**: 确保 V8 的污点追踪补丁已经应用
2. **API 兼容性**: 静态断言确保 V8 和 Blink 的数据结构兼容
3. **性能影响**: 每个字符串增加了额外的内存开销（length + 8 字节）
4. **空指针检查**: 所有污点操作都需要检查字符串是否为空
5. **ScriptState 获取**: 需要确保在正确的上下文中获取 ScriptState

---

## 🎯 预计完成时间

- **阶段 3 剩余**: 预计需要 2-3 小时（5 个子任务）
- **阶段 4**: 预计需要 1 小时（3 个子任务）
- **总计**: 预计还需要 3-4 小时完成全部移植

---

## 📚 参考文档

- 原始补丁: `v8/chromium_patch.txt`
- 阶段 1 文档: `TAINT_TRACKING_SUCCESS.md`
- 阶段 2 文档: `TAINT_TRACKING_STAGE_2_1.md`
- 总体进度: `TAINT_TRACKING_PROGRESS_UPDATE.md`
