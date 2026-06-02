# Document 类污点追踪修改总结

## 修改时间
2026-05-27

## 📝 修改内容

### 文件
`third_party/blink/renderer/core/dom/document.cc`

### 1. 添加头文件
```cpp
#include "third_party/blink/renderer/platform/wtf/text/taint_tracking.h"
```

### 2. cookie() getter - 添加污点标记
**位置**: 第 6777 行  
**修改**: 为返回的 cookie 字符串添加 `TaintType::COOKIE` 标记

```cpp
String answer = cookie_jar_->Cookies();
tainttracking::StringTaint::SetTainted(answer.Impl(),
                                       tainttracking::TaintType::COOKIE);
return answer;
```

**作用**: 所有通过 `document.cookie` 读取的 cookie 都会被标记为污染数据

---

### 3. setCookie() - 添加污点检查
**位置**: 第 6810 行  
**修改**: 在设置 cookie 前检查值是否被污染

```cpp
// Taint tracking: check if the cookie value is tainted
LogIfTaintedNode(value, 0, v8::String::TaintSinkLabel::COOKIE_SINK);

cookie_jar_->SetCookie(value);
```

**作用**: 检测是否有污染数据被写入 cookie（XSS 攻击的常见目标）

---

### 4. referrer() getter - 添加污点标记
**位置**: 第 6857 行  
**修改**: 为返回的 referrer 字符串添加 `TaintType::REFERRER` 标记

```cpp
const AtomicString& Document::referrer() const {
  if (Loader()) {
    const AtomicString& answer = Loader()->GetReferrer();
    if (!answer.IsNull()) {
      tainttracking::StringTaint::SetTainted(
          answer.Impl(), tainttracking::TaintType::REFERRER);
    }
    return answer;
  }
  return g_null_atom;
}
```

**作用**: 所有通过 `document.referrer` 读取的 referrer 都会被标记为污染数据

---

### 5. write() - 添加污点检查
**位置**: 第 4760 行  
**修改**: 在写入 HTML 前检查内容是否被污染

```cpp
void Document::write(const String& text,
                     LocalDOMWindow* entered_window,
                     ExceptionState& exception_state) {
  TRACE_EVENT1("blink", "Document::write", "size_in_bytes",
               text.CharactersSizeInBytes());

  // Taint tracking: check if the text is tainted
  LogIfTaintedNode(text, 0, v8::String::TaintSinkLabel::HTML);

  if (!IsA<HTMLDocument>(this)) {
    // ...
  }
  // ...
}
```

**作用**: 检测是否有污染数据通过 `document.write()` 写入 DOM（XSS 攻击的主要途径）

---

## 🎯 安全意义

### 污点来源（Sources）
1. **document.cookie** - Cookie 数据可能包含敏感信息或被攻击者控制
2. **document.referrer** - Referrer 可能包含敏感 URL 参数

### 污点汇点（Sinks）
1. **document.cookie = value** - 防止污染数据写入 cookie
2. **document.write(html)** - 防止污染数据注入 HTML（XSS）

### 攻击场景示例
```javascript
// 场景 1: Cookie 窃取
var stolen = document.cookie;  // 被标记为 COOKIE
document.write(stolen);        // 检测到污染数据写入 HTML

// 场景 2: Referrer 注入
var ref = document.referrer;   // 被标记为 REFERRER
document.write(ref);           // 检测到污染数据写入 HTML

// 场景 3: Cookie 污染
var userInput = location.hash; // 被标记为 URL_HASH
document.cookie = userInput;   // 检测到污染数据写入 cookie
```

---

## 📊 与其他类的关系

Document 类使用了 Node 类提供的 `LogIfTaintedNode()` 辅助方法：

```
Node::LogIfTaintedNode()
    ↓
Document::write()
Document::setCookie()
```

---

## ✅ 编译状态
🔄 正在编译验证中...

---

## 📚 相关文档
- 总体规划: `TAINT_TRACKING_PLAN.md`
- 当前进度: `TAINT_TRACKING_STAGE_3.md`
- 文档索引: `TAINT_TRACKING_README.md`
