# Chromium 污点追踪移植完整记录

## 📅 项目信息
- **开始时间**: 2026-05-27
- **当前时间**: 2026-05-28
- **项目状态**: 进行中（46% 完成）
- **原始补丁**: `v8/chromium_patch.txt` (13 个补丁)

---

## 📊 总体进度：46% (6/13 任务)

### ✅ 已完成的阶段

#### 阶段 1: 基础设施层 (100%)
- ✅ TaintTracking 核心类
- ✅ StringImpl 修改

#### 阶段 2: V8 绑定层 (100%)
- ✅ ScriptState 修改
- ✅ V8StringResource 修改

#### 阶段 3: DOM 污点标记层 (43% - 3/7)
- ✅ Location 类
- ✅ Node 类
- ✅ Document 类
- ✅ Element 类
- ⬜ HTML 元素类
- ⬜ MessageEvent
- ⬜ DOMWindowTimers

#### 阶段 4: 其他修改 (0%)
- ⬜ WindowProxy
- ⬜ Storage 和 FrameTree
- ⬜ EventTarget

---

## 🎯 已完成的工作详解

### 1. TaintTracking 核心类 ✅

**文件**:
- `third_party/blink/renderer/platform/wtf/text/taint_tracking.h`
- `third_party/blink/renderer/platform/wtf/text/taint_tracking.cc`
- `third_party/blink/renderer/platform/wtf/BUILD.gn`

**实现内容**:
- 定义了 20 种污点类型枚举
- 实现了 6 个 StringTaint 静态方法：
  - `FromString()` - 获取字符串的污点缓冲区
  - `InitTaintData()` - 初始化污点数据
  - `AllocationSize()` - 计算污点数据大小
  - `SetTainted()` - 设置污点类型
  - `GetTaintInfo()` - 获取污点信息
  - `SetTaintInfo()` - 设置污点信息

**污点类型**:
```cpp
UNTAINTED, TAINTED, COOKIE, MESSAGE, URL,
URL_HASH, URL_PROTOCOL, URL_HOST, URL_HOSTNAME,
URL_ORIGIN, URL_PORT, URL_PATHNAME, URL_SEARCH,
DOM, REFERRER, WINDOWNAME, STORAGE, NETWORK,
MULTIPLE_TAINTS, MESSAGE_ORIGIN
```

**编译状态**: ✓ 成功

---

### 2. StringImpl 修改 ✅

**文件**:
- `third_party/blink/renderer/platform/wtf/text/string_impl.h`
- `third_party/blink/renderer/platform/wtf/text/string_impl.cc`

**修改内容**:
1. **AllocationSize()** - 为每个字符串分配额外空间（length + 8 字节）
2. **CreateUninitialized()** - 初始化污点数据
3. **createStatic()** - 为静态字符串初始化污点数据

**内存布局**:
```
[StringImpl 对象] [字符数据] [污点数据 (length 字节)] [污点信息 (8 字节)]
```

**编译状态**: ✓ 成功

---

### 3. ScriptState 修改 ✅

**文件**:
- `third_party/blink/renderer/bindings/core/v8/script_state_impl.h`
- `third_party/blink/renderer/bindings/core/v8/script_state_impl.cc`

**实现内容**:
- 添加了 `LogIfTainted()` 方法
- 支持 8-bit 和 16-bit 字符串
- 调用 V8 的 `LogIfBufferTainted()` 接口

**方法签名**:
```cpp
int64_t LogIfTainted(const String& str, 
                     int argument_index,
                     v8::String::TaintSinkLabel label);
```

**编译状态**: ✓ 成功

---

### 4. V8StringResource 修改 ✅

**文件**:
- `third_party/blink/renderer/platform/bindings/to_blink_string.cc`
- `third_party/blink/renderer/platform/bindings/string_resource.h`

**实现内容**:
1. **静态断言** - 验证 V8 和 Blink 的数据结构兼容
2. **WriteTaintHelper()** - 从 V8 字符串复制污点数据到 Blink
3. **GetTaintChars()** - 在 4 个资源类中实现

**数据流**:
```
V8 字符串 (带污点)
    ↓ WriteTaintHelper()
Blink 字符串 (StringImpl + 污点缓冲区)
```

**编译状态**: ✓ 成功

---

### 5. Location 类 ✅

**文件**: `third_party/blink/renderer/core/frame/location.cc`

**修改内容**:
1. **Url()** - 添加空指针检查
2. **href()** - 添加 `TaintType::URL` 标记
3. **protocol()** - 添加 `TaintType::URL_PROTOCOL` 标记
4. **host()** - 添加 `TaintType::URL_HOST` 标记
5. **hostname()** - 添加 `TaintType::URL_HOSTNAME` 标记
6. **port()** - 添加 `TaintType::URL_PORT` 标记
7. **pathname()** - 添加 `TaintType::URL_PATHNAME` 标记
8. **search()** - 添加 `TaintType::URL_SEARCH` 标记
9. **origin()** - 添加 `TaintType::URL_ORIGIN` 标记
10. **hash()** - 添加 `TaintType::URL_HASH` 标记
11. **SetLocation()** - 添加污点检查 `TaintSinkLabel::LOCATION_ASSIGNMENT`

**安全意义**: URL 是最重要的污点来源之一

**编译状态**: ✓ 成功

**详细文档**: 见 `TAINT_TRACKING_STAGE_3.md`

---

### 6. Node 类 ✅

**文件**:
- `third_party/blink/renderer/core/dom/node.h`
- `third_party/blink/renderer/core/dom/node.cc`

**实现内容**:
- 添加了 `LogIfTaintedNode()` 辅助方法
- 简化了其他 DOM 类的污点检查代码

**方法实现**:
```cpp
void Node::LogIfTaintedNode(const String& value,
                            int symbolic_arg,
                            v8::String::TaintSinkLabel label) {
  if (value.IsNull()) return;
  
  LocalFrame* frame = GetDocument().GetFrame();
  if (!frame) return;
  
  ScriptState* script_state = ToScriptStateForMainWorld(frame);
  if (!script_state) return;
  
  script_state->LogIfTainted(value, symbolic_arg, label);
}
```

**编译状态**: ✓ 成功

**详细文档**: 见 `TAINT_TRACKING_STAGE_3.md`

---

### 7. Document 类 ✅

**文件**: `third_party/blink/renderer/core/dom/document.cc`

**修改内容**:

#### 7.1 cookie() getter
- 添加 `TaintType::COOKIE` 标记
- 所有通过 `document.cookie` 读取的 cookie 都被标记为污染

#### 7.2 setCookie()
- 添加污点检查 `TaintSinkLabel::COOKIE_SINK`
- 检测污染数据写入 cookie

#### 7.3 referrer() getter
- 添加 `TaintType::REFERRER` 标记
- 所有通过 `document.referrer` 读取的 referrer 都被标记为污染

#### 7.4 write()
- 添加污点检查 `TaintSinkLabel::HTML`
- 检测污染数据通过 `document.write()` 注入 DOM

**安全场景**:
```javascript
// Cookie 窃取
var stolen = document.cookie;  // 标记为 COOKIE
document.write(stolen);        // 检测到污染数据

// Referrer 注入
var ref = document.referrer;   // 标记为 REFERRER
document.write(ref);           // 检测到污染数据
```

**编译状态**: ✓ 成功

**详细文档**: 见 `DOCUMENT_TAINT_TRACKING.md`

---

### 8. Element 类 ✅

**文件**: `third_party/blink/renderer/core/dom/element.cc`

**修改内容**:

#### 8.1 SetInnerHTMLWithoutTrustedTypes()
- 添加污点检查 `TaintSinkLabel::HTML`
- 检测 `element.innerHTML = value` 注入

#### 8.2 SetOuterHTMLInternal()
- 添加污点检查 `TaintSinkLabel::HTML`
- 检测 `element.outerHTML = value` 注入

#### 8.3 InsertAdjacentHTMLInternal()
- 添加污点检查 `TaintSinkLabel::HTML`
- 检测 `element.insertAdjacentHTML(pos, html)` 注入

#### 8.4 AttributeChanged()
- 检测事件处理器属性（onclick, onload 等）
  - 使用 `TaintSinkLabel::JAVASCRIPT_EVENT_HANDLER_ATTRIBUTE`
- 检测 style 属性
  - 使用 `TaintSinkLabel::CSS_STYLE_ATTRIBUTE`

**XSS 防护覆盖**:
- ✅ innerHTML 赋值
- ✅ outerHTML 赋值
- ✅ insertAdjacentHTML() 调用
- ✅ 事件处理器属性（onclick 等）
- ✅ style 属性

**安全场景**:
```javascript
// innerHTML XSS
var hash = location.hash;  // 污点来源
div.innerHTML = hash;      // 检测到污染数据

// 事件处理器 XSS
var search = location.search;
img.setAttribute('onerror', search);  // 检测到污染数据

// 样式注入
var ref = document.referrer;
div.setAttribute('style', ref);  // 检测到污染数据
```

**编译状态**: ✓ 成功

**详细文档**: 见 `ELEMENT_TAINT_TRACKING.md`

---

## 🔄 待完成的工作

### 阶段 3: DOM 污点标记层（剩余 3 个任务）

#### 3.5 HTML 元素类
**需要修改的文件**:
- `HTMLScriptElement` - script.src 和 script.text
- `HTMLIFrameElement` - iframe.src
- `HTMLImageElement` - img.src
- `HTMLEmbedElement` - embed.src
- `HTMLAnchorElement` - a.href

**预计工作量**: 1-2 小时

#### 3.6 MessageEvent（跨域消息追踪）
**需要修改的文件**:
- `V8MessageEventCustom.cpp`
- `MessageEvent.h` / `MessageEvent.cpp`

**预计工作量**: 1-2 小时

#### 3.7 DOMWindowTimers
**需要修改的文件**:
- `DOMWindowTimers.cpp` - setTimeout/setInterval

**预计工作量**: 30 分钟

---

### 阶段 4: 其他修改（3 个任务）

#### 4.1 WindowProxy
**需要修改的文件**:
- `WindowProxy.cpp` - 记录页面导航

**预计工作量**: 30 分钟

#### 4.2 Storage 和 FrameTree
**需要修改的文件**:
- `StorageArea.cpp` - localStorage/sessionStorage
- `FrameTree.cpp` - window.name

**预计工作量**: 30 分钟

#### 4.3 EventTarget
**需要修改的文件**:
- `EventTarget.cpp` / `EventTarget.idl`

**预计工作量**: 30 分钟

---

## 📈 进度统计

### 按阶段统计
| 阶段 | 完成度 | 任务数 |
|------|--------|--------|
| 阶段 1: 基础设施层 | 100% | 2/2 ✅ |
| 阶段 2: V8 绑定层 | 100% | 2/2 ✅ |
| 阶段 3: DOM 污点标记层 | 57% | 4/7 |
| 阶段 4: 其他修改 | 0% | 0/3 |
| **总计** | **46%** | **6/13** |

### 按文件类型统计
| 类型 | 完成 | 待完成 |
|------|------|--------|
| 核心基础设施 | 2 | 0 |
| V8 绑定 | 2 | 0 |
| DOM 核心类 | 4 | 0 |
| HTML 元素类 | 0 | 5 |
| 事件和消息 | 0 | 1 |
| 定时器 | 0 | 1 |
| 其他 | 0 | 3 |

### 编译验证统计
- ✅ 成功编译: 6 次
- ❌ 编译失败: 0 次
- 🔄 待验证: 0 次

---

## 🛡️ 安全防护覆盖

### 已实现的污点来源（Sources）
1. ✅ **URL 相关** - `location.href`, `location.hash`, `location.search` 等
2. ✅ **Cookie** - `document.cookie`
3. ✅ **Referrer** - `document.referrer`

### 已实现的污点汇点（Sinks）
1. ✅ **HTML 注入** - `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`
2. ✅ **JavaScript 注入** - 事件处理器属性（onclick 等）
3. ✅ **CSS 注入** - style 属性
4. ✅ **Cookie 写入** - `document.cookie = value`
5. ✅ **导航** - `location.href = value`

### 待实现的污点来源
- ⬜ postMessage 数据
- ⬜ localStorage/sessionStorage
- ⬜ window.name

### 待实现的污点汇点
- ⬜ `<script>` 标签
- ⬜ `<iframe>` 标签
- ⬜ `<img>` 标签
- ⬜ `eval()` / `Function()`
- ⬜ `setTimeout()` / `setInterval()` 字符串参数

---

## 📚 文档结构

### 主要文档
1. **TAINT_TRACKING_README.md** - 文档索引和导航
2. **TAINT_TRACKING_PLAN.md** - 总体规划和架构设计
3. **TAINT_TRACKING_STAGE_3.md** - 当前阶段详细进度
4. **本文档** - 完整移植过程记录

### 阶段文档
1. **TAINT_TRACKING_SUCCESS.md** - 阶段 1 完成报告
2. **TAINT_TRACKING_STAGE_2_1.md** - 阶段 2 完成报告
3. **DOCUMENT_TAINT_TRACKING.md** - Document 类修改详解
4. **ELEMENT_TAINT_TRACKING.md** - Element 类修改详解

### 历史文档（可归档）
- TAINT_TRACKING_MIGRATION.md
- TAINT_TRACKING_PROGRESS_UPDATE.md

---

## 🔧 技术架构

### 数据流
```
污点来源 (location.hash, document.cookie, etc.)
    ↓ SetTainted()
StringImpl (字符数据 + 污点缓冲区)
    ↓ V8 ↔ Blink 转换
V8 字符串 (带污点)
    ↓ JavaScript 操作
污点汇点 (innerHTML, setAttribute, etc.)
    ↓ LogIfTaintedNode()
ScriptState::LogIfTainted()
    ↓ V8::LogIfBufferTainted()
V8 污点日志系统
```

### 关键接口
```cpp
// 设置污点
tainttracking::StringTaint::SetTainted(str.Impl(), TaintType::URL);

// 检查污点
node->LogIfTaintedNode(value, arg_idx, TaintSinkLabel::HTML);

// V8 绑定
script_state->LogIfTainted(str, arg_idx, label);
```

---

## 💡 经验总结

### 成功经验
1. ✅ **分阶段实施** - 从基础设施到应用层，逐步推进
2. ✅ **频繁编译验证** - 每完成一个类就编译，及早发现问题
3. ✅ **详细文档记录** - 每个阶段都有详细文档，便于回顾
4. ✅ **代码复用** - Node::LogIfTaintedNode() 简化了其他类的实现
5. ✅ **静态断言** - 确保 V8 和 Blink 数据结构兼容

### 技术难点
1. **内存布局** - StringImpl 的污点数据布局需要精确计算
2. **V8 绑定** - 需要理解 V8 和 Blink 的字符串转换机制
3. **空指针检查** - 需要在所有污点操作前检查指针有效性
4. **参数索引** - LogIfTainted 的 argument_index 需要正确设置

### 注意事项
1. ⚠️ **不要修改系统配置** - 这是实验室公用服务器
2. ⚠️ **只修改项目目录内的文件**
3. ⚠️ **每次修改后都要编译验证**
4. ⚠️ **保持文档更新**

---

## 📅 时间线

| 日期 | 完成内容 | 编译状态 |
|------|---------|---------|
| 2026-05-27 | TaintTracking 核心类 | ✓ |
| 2026-05-27 | StringImpl 修改 | ✓ |
| 2026-05-27 | ScriptState 修改 | ✓ |
| 2026-05-27 | V8StringResource 修改 | ✓ |
| 2026-05-27 | Location 类 | ✓ |
| 2026-05-27 | Node 类 | ✓ |
| 2026-05-27 | Document 类 | ✓ |
| 2026-05-28 | Element 类 | ✓ |
| 2026-05-28 | 创建完整文档 | - |

---

## 🎯 下一步计划

### 立即任务
1. 移植 HTML 元素类（HTMLScriptElement 等）
2. 移植 MessageEvent
3. 移植 DOMWindowTimers

### 预计完成时间
- HTML 元素类: 1-2 小时
- MessageEvent: 1-2 小时
- 其他任务: 2-3 小时
- **总计**: 预计还需 4-7 小时完成全部移植

---

## 📞 联系和支持

如有问题，请查看：
1. 原始补丁: `v8/chromium_patch.txt`
2. 文档索引: `TAINT_TRACKING_README.md`
3. 详细规划: `TAINT_TRACKING_PLAN.md`

---

**最后更新**: 2026-05-28  
**当前进度**: 46% (6/13 任务完成)  
**下一步**: 移植 HTML 元素类
