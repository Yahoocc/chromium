# Chromium 污点追踪（Taint Tracking）移植计划

## 📋 总体概览

这是一个将 2016-2018 年的污点追踪补丁移植到 2026 年 Chromium 代码库的项目。

**补丁来源**：`v8/chromium_patch.txt` (13 个补丁，2646 行)

**目标**：在 Chromium/Blink 中实现完整的污点追踪系统，用于检测和防止 XSS、代码注入等安全漏洞。

---

## 🎯 移植阶段

### 阶段 1: 基础设施层 (Foundation Layer)

#### ✅ 1.1 TaintTracking 核心类 【已完成】

**文件**：
- ✅ `third_party/blink/renderer/platform/wtf/text/taint_tracking.h`
- ✅ `third_party/blink/renderer/platform/wtf/text/taint_tracking.cc`
- ✅ `third_party/blink/renderer/platform/wtf/BUILD.gn` (已修改)

**功能**：
- ✅ 定义了 20 种污点类型枚举（与 V8 完全一致）
- ✅ 实现了 `StringTaint` 工具类的 6 个方法
- ✅ 定义了污点数据的内存布局
- ✅ 编译成功，目标文件已生成

**状态**：🟢 **完成** (2026-05-27)

**导出的符号**：
```cpp
✅ StringTaint::InitTaintData(blink::StringImpl*)
✅ StringTaint::FromString(blink::StringImpl*)
✅ StringTaint::AllocationSize(unsigned int)
✅ StringTaint::SetTainted(blink::StringImpl*, TaintType)
✅ StringTaint::GetTaintInfo(blink::StringImpl*)
✅ StringTaint::SetTaintInfo(blink::StringImpl*, long)
```

---

#### ⬜ 1.2 StringImpl 修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/platform/wtf/text/string_impl.h`
- ⬜ `third_party/blink/renderer/platform/wtf/text/string_impl.cc`

**需要的修改**：
1. 修改 `allocationSize()` 模板函数
   ```cpp
   // 原来：
   return sizeof(StringImpl) + length * sizeof(CharType);
   
   // 修改为：
   return sizeof(StringImpl) + length * sizeof(CharType) + 
          tainttracking::webkit::StringTaint::AllocationSize(length);
   ```

2. 在 `CreateUninitialized()` 中初始化污点数据
   ```cpp
   StringImpl* answer = new (string) StringImpl(length, Force8BitConstructor);
   tainttracking::webkit::StringTaint::InitTaintData(answer);
   return adoptRef(answer);
   ```

3. 在 `createStatic()` 中初始化污点数据

**预计工作量**：1-2 小时

**风险**：⚠️ 中等 - StringImpl 是核心类，修改需要谨慎

**状态**：🔴 **未开始**

---

### 阶段 2: V8 绑定层 (V8 Binding Layer)

#### ⬜ 2.1 V8StringResource 修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/bindings/core/v8/v8_string_resource.h`
- ⬜ `third_party/blink/renderer/bindings/core/v8/v8_string_resource.cc`

**需要的修改**：
1. 添加 `writeTaintHelper()` 函数
   ```cpp
   void writeTaintHelper(v8::Local<v8::String> v8String, 
                         StringImpl* buffer, 
                         int length) {
       v8String->WriteTaint(
           tainttracking::webkit::StringTaint::FromString(buffer), 
           0, length);
       v8::String::SetTaintInfo(v8String, 
           tainttracking::webkit::StringTaint::GetTaintInfo(buffer));
   }
   ```

2. 在字符串转换时调用 `writeTaintHelper()`
   - `String::fromV8String()`
   - `AtomicString::fromV8String()`

3. 添加枚举一致性检查
   ```cpp
   static_assert(
       static_cast<uint8_t>(v8::String::TaintType::URL) == 
       static_cast<uint8_t>(tainttracking::webkit::TaintType::URL),
       "Taint tracking enum must be equal.");
   ```

**预计工作量**：2-3 小时

**状态**：🔴 **未开始**

---

#### ⬜ 2.2 ScriptState 修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/bindings/core/v8/script_state.h`
- ⬜ `third_party/blink/renderer/bindings/core/v8/script_state.cc`

**需要的修改**：
1. 添加 `LogIfTainted()` 方法（两个重载）
   ```cpp
   int64_t LogIfTainted(const String& str, 
                        int arg_idx, 
                        v8::String::TaintSinkLabel label);
   
   int64_t LogIfTainted(const v8::Local<v8::String>& str, 
                        int arg_idx, 
                        v8::String::TaintSinkLabel label);
   ```

2. 实现污点检测逻辑
   - 从 Blink 字符串读取污点数据
   - 调用 V8 的 `LogIfBufferTainted()` 方法

**预计工作量**：1-2 小时

**状态**：🔴 **未开始**

---

### 阶段 3: DOM 污点标记层 (DOM Taint Source Layer)

#### ⬜ 3.1 Location 类修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/frame/location.cc`

**需要标记污点的属性**：
- `href` → `TaintType::URL`
- `protocol` → `TaintType::URL_PROTOCOL`
- `host` → `TaintType::URL_HOST`
- `hostname` → `TaintType::URL_HOSTNAME`
- `port` → `TaintType::URL_PORT`
- `pathname` → `TaintType::URL_PATHNAME`
- `search` → `TaintType::URL_SEARCH`
- `hash` → `TaintType::URL_HASH`
- `origin` → `TaintType::URL_ORIGIN`

**修改示例**：
```cpp
String Location::href() const {
    String answer = Url().StrippedForUseAsHref();
    tainttracking::webkit::StringTaint::SetTainted(
        answer.impl(), 
        tainttracking::webkit::TaintType::URL);
    return answer;
}
```

**预计工作量**：1 小时

**状态**：🔴 **未开始**

---

#### ⬜ 3.2 Document 类修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/dom/document.cc`

**需要的修改**：
1. **Cookie 读取** → 标记为 `TaintType::COOKIE`
   ```cpp
   String Document::cookie() const {
       String answer = cookies(this, cookieURL);
       tainttracking::webkit::StringTaint::SetTainted(
           answer.impl(), 
           tainttracking::webkit::COOKIE);
       return answer;
   }
   ```

2. **Referrer 读取** → 标记为 `TaintType::REFERRER`

3. **document.write/writeln** → 检测污点
   ```cpp
   void Document::write(const String& text, ...) {
       LogIfTaintedNode(text, 0, v8::String::TaintSinkLabel::HTML);
       // ... 原有逻辑
   }
   ```

**预计工作量**：1-2 小时

**状态**：🔴 **未开始**

---

#### ⬜ 3.3 Element 类修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/dom/element.cc`

**需要的修改**：
1. **innerHTML/outerHTML 设置** → 检测污点
   ```cpp
   void Element::setInnerHTML(const String& html, ...) {
       LogIfTaintedNode(html, 0, v8::String::TaintSinkLabel::HTML);
       // ... 原有逻辑
   }
   ```

2. **insertAdjacentHTML** → 检测污点

3. **setAttribute** → 检测事件处理器和 style 属性
   ```cpp
   if (caseAdjustedLocalName.startsWith("on")) {
       LogIfTaintedNode(value.getString(), 1, 
           v8::String::JAVASCRIPT_EVENT_HANDLER_ATTRIBUTE);
   }
   if (styleAttr == caseAdjustedLocalName) {
       LogIfTaintedNode(value.getString(), 1, 
           v8::String::CSS);
   }
   ```

**预计工作量**：2 小时

**状态**：🔴 **未开始**

---

#### ⬜ 3.4 Node 类修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/dom/node.h`
- ⬜ `third_party/blink/renderer/core/dom/node.cc`

**需要的修改**：
1. 添加 `LogIfTaintedNode()` 辅助方法
   ```cpp
   void Node::LogIfTaintedNode(const String& value, 
                                int symbolic_arg,
                                v8::String::TaintSinkLabel label) {
       if (!value.isNull()) {
           LocalFrame* frame = document().frame();
           if (frame) {
               ScriptState* scriptState = ScriptState::forMainWorld(frame);
               if (scriptState) {
                   scriptState->LogIfTainted(value, symbolic_arg, label);
               }
           }
       }
   }
   ```

**预计工作量**：30 分钟

**状态**：🔴 **未开始**

---

#### ⬜ 3.5 HTML 元素类修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/html/html_script_element.cc`
- ⬜ `third_party/blink/renderer/core/html/html_anchor_element.cc`
- ⬜ `third_party/blink/renderer/core/html/html_embed_element.cc`
- ⬜ `third_party/blink/renderer/core/html/html_iframe_element.cc`
- ⬜ `third_party/blink/renderer/core/html/html_image_element.cc`

**需要的修改**：

**HTMLScriptElement**：
- `src` 属性 → 检测 `SCRIPT_SRC_URL_SINK`
- `text` 属性 → 检测 `JAVASCRIPT`
- `childrenChanged()` → 检测 `JAVASCRIPT`

**HTMLAnchorElement**：
- `href` 属性 → 检测 `ANCHOR_SRC_SINK`

**HTMLEmbedElement**：
- `src` 属性 → 检测 `EMBED_SRC_SINK`

**HTMLIFrameElement**：
- `src` 属性 → 检测 `IFRAME_SRC_SINK`

**HTMLImageElement**：
- `src/srcset/sizes` 属性 → 检测 `IMG_SRC_SINK`

**预计工作量**：2-3 小时

**状态**：🔴 **未开始**

---

#### ⬜ 3.6 MessageEvent 修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/events/message_event.h`
- ⬜ `third_party/blink/renderer/core/events/message_event.cc`
- ⬜ `third_party/blink/renderer/bindings/core/v8/custom/v8_message_event_custom.cc`
- ⬜ `third_party/blink/renderer/core/events/message_event.idl`

**需要的修改**：
1. 添加 `taint_tracking_unique_id_` 成员变量
2. 在 `data` 属性 getter 中标记 `TaintType::MESSAGE`
3. 在 `origin` 属性 getter 中标记 `TaintType::MESSAGE_ORIGIN`
4. 实现跨域消息追踪

**预计工作量**：2-3 小时

**状态**：🔴 **未开始**

---

#### ⬜ 3.7 其他污点来源 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/modules/storage/storage_area.cc` - Storage API
- ⬜ `third_party/blink/renderer/core/frame/dom_window_timers.cc` - setTimeout/setInterval
- ⬜ `third_party/blink/renderer/core/page/frame_tree.cc` - window.name
- ⬜ `third_party/blink/renderer/bindings/core/v8/window_proxy.cc` - 导航日志

**需要的修改**：

**StorageArea**：
- `getItem()` → 标记 `TaintType::STORAGE`

**DOMWindowTimers**：
- `setTimeout(string)` → 检测 `JAVASCRIPT_SET_TIMEOUT`
- `setInterval(string)` → 检测 `JAVASCRIPT_SET_INTERVAL`

**FrameTree**：
- `setName()` → 标记 `TaintType::WINDOWNAME`

**WindowProxy**：
- `initialize()` → 记录导航 URL

**预计工作量**：2-3 小时

**状态**：🔴 **未开始**

---

### 阶段 4: 其他修改 (Miscellaneous)

#### ⬜ 4.1 EventTarget 修改 【待移植】

**文件**：
- ⬜ `third_party/blink/renderer/core/events/event_target.h`
- ⬜ `third_party/blink/renderer/core/events/event_target.cc`
- ⬜ `third_party/blink/renderer/core/events/event_target.idl`

**需要的修改**：
- 添加 `internalSpecialNamespaceGetRegisteredEvents()` 方法

**预计工作量**：30 分钟

**状态**：🔴 **未开始**

---

#### ⬜ 4.2 其他小修改 【待移植】

**文件**：
- ⬜ `ui/events/x/events_x_utils.cc` - 修复 NOTREACHED()
- ⬜ `extensions/renderer/static_v8_external_one_byte_string_resource.h` - 添加 TaintTrackingStringBufferImpl
- ⬜ `net/proxy/proxy_resolver_v8.cc` - 添加 TaintTrackingStringBufferImpl

**预计工作量**：1 小时

**状态**：🔴 **未开始**

---

## 📊 进度统计

### 总体进度

| 阶段 | 状态 | 进度 |
|------|------|------|
| 阶段 1: 基础设施层 | 🟡 进行中 | 50% (1/2) |
| 阶段 2: V8 绑定层 | 🔴 未开始 | 0% (0/2) |
| 阶段 3: DOM 污点标记层 | 🔴 未开始 | 0% (0/7) |
| 阶段 4: 其他修改 | 🔴 未开始 | 0% (0/2) |
| **总计** | 🟡 **进行中** | **8% (1/13)** |

### 文件统计

- ✅ **已完成**：2 个文件
- ⬜ **待移植**：约 25 个文件
- 📝 **已修改**：1 个构建文件

### 工作量估算

- ✅ **已完成**：约 4 小时（包括调试）
- ⬜ **剩余工作**：约 20-25 小时
- 📅 **预计总时长**：24-29 小时

---

## 🎯 推荐的移植顺序

### 第一优先级（核心功能）
1. ✅ **TaintTracking 核心类** - 已完成
2. ⬜ **StringImpl 修改** - 必须完成才能分配污点数据
3. ⬜ **V8StringResource 修改** - 必须完成才能传递污点数据
4. ⬜ **ScriptState 修改** - 必须完成才能检测污点

### 第二优先级（基本污点标记）
5. ⬜ **Node 类修改** - 提供辅助方法
6. ⬜ **Location 类修改** - URL 污点来源
7. ⬜ **Document 类修改** - Cookie/Referrer 污点来源
8. ⬜ **Element 类修改** - innerHTML/outerHTML 污点检测

### 第三优先级（完整功能）
9. ⬜ **HTML 元素类修改** - 各种 URL sink 检测
10. ⬜ **MessageEvent 修改** - 跨域消息追踪
11. ⬜ **其他污点来源** - Storage/setTimeout/window.name
12. ⬜ **EventTarget 修改** - 辅助功能
13. ⬜ **其他小修改** - 边缘情况

---

## ⚠️ 风险和注意事项

### 高风险区域
1. **StringImpl 修改** - 核心类，影响所有字符串
2. **V8 绑定层** - 跨引擎边界，容易出错
3. **内存布局** - 必须与 V8 保持一致

### 兼容性问题
1. **枚举值同步** - Blink 和 V8 的 TaintType 必须完全一致
2. **API 变化** - 10 年间 API 可能已改变
3. **构建系统** - 从 gyp 迁移到 GN

### 测试策略
1. **单元测试** - 每个阶段完成后测试
2. **集成测试** - 完整流程测试
3. **性能测试** - 确保性能影响可接受

---

## 📚 参考资料

- **原始补丁**：`v8/chromium_patch.txt`
- **V8 污点追踪定义**：`v8/include/v8-primitive.h`
- **技术文档**：`TAINT_TRACKING_MIGRATION.md`
- **成功报告**：`TAINT_TRACKING_SUCCESS.md`

---

## 📅 更新日志

- **2026-05-27 17:07** - 阶段 1.1 完成（TaintTracking 核心类）
- **2026-05-27 17:15** - 创建移植计划文档

---

**当前状态：阶段 1.1 已完成，等待继续移植阶段 1.2（StringImpl 修改）**

---

## 📅 更新日志（续）

- **2026-05-27 19:42** - 开始阶段 1.2（StringImpl 修改）
  - 修改了 `AllocationSize<LChar>()` 方法
  - 修改了 `AllocationSize<UChar>()` 模板方法
  - 在 `CreateUninitialized()` 中添加了污点数据初始化
  - 添加了必要的头文件包含
  - 正在编译中...

