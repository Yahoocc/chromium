// Copyright 2023 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "third_party/blink/renderer/bindings/core/v8/script_state_impl.h"

#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/platform/bindings/dom_wrapper_world.h"
#include "third_party/blink/renderer/platform/wtf/text/taint_tracking.h"

namespace blink {

// static
void ScriptStateImpl::Init() {
  ScriptState::SetCreateCallback(ScriptStateImpl::Create);
}

// static
ScriptState* ScriptStateImpl::Create(v8::Local<v8::Context> context,
                                     DOMWrapperWorld* world,
                                     ExecutionContext* execution_context) {
  return MakeGarbageCollected<ScriptStateImpl>(context, std::move(world),
                                               execution_context);
}

ScriptStateImpl::ScriptStateImpl(v8::Local<v8::Context> context,
                                 DOMWrapperWorld* world,
                                 ExecutionContext* execution_context)
    : ScriptState(context, world, execution_context),
      execution_context_(execution_context) {}

void ScriptStateImpl::Trace(Visitor* visitor) const {
  ScriptState::Trace(visitor);
  visitor->Trace(execution_context_);
}

int64_t ScriptStateImpl::LogIfTainted(const String& str,
                                       int argument_index,
                                       v8::String::TaintSinkLabel label) {
  if (!ContextIsValid()) {
    return -1;
  }

  StringImpl* impl = str.Impl();
  if (!impl) {
    return -1;
  }

  tainttracking::webkit::TaintData* buffer = tainttracking::webkit::StringTaint::FromString(impl);
  // SAFETY: Characters8() and Characters16() return pointers to the internal
  // string buffer, which is safe to pass to V8's taint tracking API.
  UNSAFE_BUFFERS({
    if (impl->Is8Bit()) {
      return v8::String::LogIfBufferTainted(
          buffer,
          impl->Characters8(),
          impl->length(),
          argument_index,
          GetIsolate(),
          label);
    } else {
      return v8::String::LogIfBufferTainted(
          buffer,
          impl->Characters16(),
          impl->length(),
          argument_index,
          GetIsolate(),
          label);
    }
  });
}

}  // namespace blink
