# Element 类污点追踪修改总结

## 修改时间
2026-05-28

## 📝 修改内容

### 文件
`third_party/blink/renderer/core/dom/element.cc`

---

## 修改详情

### 1. SetInnerHTMLWithoutTrustedTypes() - 添加污点检查
**位置**: 第 9307 行  
**修改**: 在设置 innerHTML 前检查 HTML 内容是否被污染

```cpp
void Element::SetInnerHTMLWithoutTrustedTypes(const String& html,
                                              ExceptionState& exception_state) {
  // Taint tracking: check if the HTML is tainted
  LogIfTaintedNode(html, 0, v8::String::TaintSinkLabel::HTML);

  SetInnerHTMLInternal(
      html, FragmentParserConfig::ParseDeclarativeShadowRoots::kDontParse,
      FragmentParserConfig::ForceHtml::kDontForce, Sanitizer::Mode::kUnsafe,
      FragmentParserOptions(), trusted_types_names::kInnerHTML,
      exception_state);
}
```

**作用**: 检测通过 `element.innerHTML = value` 注入的污染数据（XSS 攻击的主要途径）

**调用链**:
```
element.innerHTML = value
  ↓
setInnerHTML()
  ↓
SetInnerHTMLWithoutTrustedTypes()  ← 污点检查在这里
  ↓
SetInnerHTMLInternal()
```

---

### 2. SetOuterHTMLInternal() - 添加污点检查
**位置**: 第 9325 行  
**修改**: 在设置 outerHTML 前检查 HTML 内容是否被污染

```cpp
void Element::SetOuterHTMLInternal(const String& html,
                                   ExceptionState& exception_state) {
  if (exception_state.HadException()) {
    return;
  }

  // Taint tracking: check if the HTML is tainted
  LogIfTaintedNode(html, 0, v8::String::TaintSinkLabel::HTML);

  Node* p = parentNode();
  // ...
}
```

**作用**: 检测通过 `element.outerHTML = value` 注入的污染数据

**调用链**:
```
element.outerHTML = value
  ↓
setOuterHTML()
  ↓
SetOuterHTMLInternal()  ← 污点检查在这里
```

---

### 3. InsertAdjacentHTMLInternal() - 添加污点检查
**位置**: 第 9605 行  
**修改**: 在插入相邻 HTML 前检查内容是否被污染

```cpp
void Element::InsertAdjacentHTMLInternal(const String& where,
                                         const String& html,
                                         ExceptionState& exception_state) {
  if (exception_state.HadException()) {
    return;
  }

  // Taint tracking: check if the HTML is tainted
  LogIfTaintedNode(html, 1, v8::String::TaintSinkLabel::HTML);

  Node* context_node = ContextNodeForInsertion(where, this, exception_state);
  // ...
}
```

**作用**: 检测通过 `element.insertAdjacentHTML(position, html)` 注入的污染数据

**参数说明**:
- `argument_index = 1`: 因为 `html` 是第二个参数（第一个是 `where`）

**调用链**:
```
element.insertAdjacentHTML('beforebegin', html)
  ↓
insertAdjacentHTML()
  ↓
InsertAdjacentHTMLInternal()  ← 污点检查在这里
```

---

### 4. AttributeChanged() - 添加事件处理器和样式属性检查
**位置**: 第 3780 行  
**修改**: 在属性变化时检查事件处理器和 style 属性

```cpp
void Element::AttributeChanged(const AttributeModificationParams& params) {
  // Taint tracking: check for event handlers and style attributes
  const QualifiedName& name = params.name;
  if (name.LocalName().StartsWith("on")) {
    // Event handler attribute (onclick, onload, etc.)
    LogIfTaintedNode(params.new_value, 1,
                     v8::String::TaintSinkLabel::JAVASCRIPT_EVENT_HANDLER_ATTRIBUTE);
  } else if (name == html_names::kStyleAttr) {
    // Style attribute
    LogIfTaintedNode(params.new_value, 1,
                     v8::String::TaintSinkLabel::CSS_STYLE_ATTRIBUTE);
  }

  ParseAttribute(params);
  // ...
}
```

**作用**: 
1. **事件处理器检查**: 检测通过 `element.setAttribute('onclick', code)` 注入的 JavaScript 代码
2. **样式属性检查**: 检测通过 `element.setAttribute('style', css)` 注入的 CSS 代码

**检测的属性**:
- `onclick`, `onload`, `onerror`, `onmouseover` 等所有以 "on" 开头的属性
- `style` 属性

**调用链**:
```
element.setAttribute('onclick', 'alert(1)')
  ↓
setAttribute()
  ↓
AttributeChanged()  ← 污点检查在这里
```

---

## 🎯 安全意义

### 污点汇点（Sinks）覆盖

Element 类是 XSS 攻击的主要目标，以下是被保护的攻击面：

#### 1. innerHTML 注入
```javascript
// 攻击场景
var userInput = location.hash.substring(1);  // 被标记为 URL_HASH
element.innerHTML = userInput;               // 检测到污染数据注入 HTML
```

#### 2. outerHTML 注入
```javascript
// 攻击场景
var malicious = document.referrer;  // 被标记为 REFERRER
element.outerHTML = malicious;      // 检测到污染数据注入 HTML
```

#### 3. insertAdjacentHTML 注入
```javascript
// 攻击场景
var xss = document.cookie;                        // 被标记为 COOKIE
element.insertAdjacentHTML('beforeend', xss);     // 检测到污染数据注入 HTML
```

#### 4. 事件处理器注入
```javascript
// 攻击场景
var code = location.search.substring(1);  // 被标记为 URL_SEARCH
element.setAttribute('onclick', code);    // 检测到污染数据注入事件处理器
```

#### 5. 样式注入
```javascript
// 攻击场景
var css = location.hash.substring(1);  // 被标记为 URL_HASH
element.setAttribute('style', css);    // 检测到污染数据注入样式
```

---

## 📊 污点检查标签

| 方法 | TaintSinkLabel | 说明 |
|------|----------------|------|
| `setInnerHTML()` | `HTML` | HTML 注入检测 |
| `setOuterHTML()` | `HTML` | HTML 注入检测 |
| `insertAdjacentHTML()` | `HTML` | HTML 注入检测 |
| `setAttribute('onclick', ...)` | `JAVASCRIPT_EVENT_HANDLER_ATTRIBUTE` | 事件处理器注入检测 |
| `setAttribute('style', ...)` | `CSS_STYLE_ATTRIBUTE` | CSS 注入检测 |

---

## 🔗 与其他类的关系

Element 类使用了 Node 类提供的 `LogIfTaintedNode()` 辅助方法：

```
Node::LogIfTaintedNode()
    ↓
Element::SetInnerHTMLWithoutTrustedTypes()
Element::SetOuterHTMLInternal()
Element::InsertAdjacentHTMLInternal()
Element::AttributeChanged()
```

---

## 📈 XSS 防护覆盖率

### 已覆盖的 XSS 向量
✅ `innerHTML` 赋值  
✅ `outerHTML` 赋值  
✅ `insertAdjacentHTML()` 调用  
✅ `onclick` 等事件处理器属性  
✅ `style` 属性  

### 待覆盖的 XSS 向量（后续任务）
⬜ `<script>` 标签的 `src` 和 `textContent`  
⬜ `<iframe>` 标签的 `src`  
⬜ `<img>` 标签的 `src`  
⬜ `<a>` 标签的 `href`  
⬜ `eval()` 和 `Function()` 构造器  
⬜ `setTimeout()` / `setInterval()` 字符串参数  

---

## ✅ 编译状态
🔄 正在编译验证中...

---

## 🧪 测试场景

### 测试用例 1: innerHTML XSS
```javascript
// 应该被检测到
var hash = location.hash;  // 污点来源
div.innerHTML = hash;      // 污点汇点 - 应该触发警告
```

### 测试用例 2: 事件处理器 XSS
```javascript
// 应该被检测到
var search = location.search;        // 污点来源
img.setAttribute('onerror', search); // 污点汇点 - 应该触发警告
```

### 测试用例 3: 样式注入
```javascript
// 应该被检测到
var ref = document.referrer;      // 污点来源
div.setAttribute('style', ref);   // 污点汇点 - 应该触发警告
```

### 测试用例 4: 安全的使用（不应触发）
```javascript
// 不应该被检测到
var safe = "Hello World";  // 非污点数据
div.innerHTML = safe;      // 安全 - 不应该触发警告
```

---

## 📚 相关文档
- 总体规划: `TAINT_TRACKING_PLAN.md`
- 当前进度: `TAINT_TRACKING_STAGE_3.md`
- Document 类修改: `DOCUMENT_TAINT_TRACKING.md`
- 文档索引: `TAINT_TRACKING_README.md`

---

## 🔍 技术细节

### argument_index 参数说明

`LogIfTaintedNode()` 的第二个参数 `argument_index` 表示该字符串在 JavaScript 函数调用中的参数位置：

- `innerHTML = value` → `argument_index = 0`（value 是第一个参数）
- `outerHTML = value` → `argument_index = 0`
- `insertAdjacentHTML(where, html)` → `argument_index = 1`（html 是第二个参数）
- `setAttribute(name, value)` → `argument_index = 1`（value 是第二个参数）

这个信息用于 V8 的污点追踪系统生成更准确的日志。

---

## 📝 代码审查要点

1. ✅ 所有 HTML 注入点都添加了污点检查
2. ✅ 事件处理器属性使用了正确的标签
3. ✅ style 属性使用了专门的 CSS 标签
4. ✅ argument_index 参数设置正确
5. ✅ 使用了 Node 类的辅助方法，代码复用良好

---

**最后更新**: 2026-05-28  
**编译状态**: 待验证  
**下一步**: 移植 HTML 元素类（HTMLScriptElement, HTMLIFrameElement 等）
