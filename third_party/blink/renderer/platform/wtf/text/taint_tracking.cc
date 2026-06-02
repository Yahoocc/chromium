// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifdef UNSAFE_BUFFERS_BUILD
// TODO(crbug.com/351564777): Remove this and convert code to safer constructs.
#pragma allow_unsafe_buffers
#endif

#include "third_party/blink/renderer/platform/wtf/text/taint_tracking.h"

#include <cstring>

#include "third_party/blink/renderer/platform/wtf/text/string_impl.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_uchar.h"

namespace tainttracking {
namespace webkit {

// static
void StringTaint::InitTaintData(blink::StringImpl* impl) {
  if (impl) {
    memset(FromString(impl), 0, impl->length() + sizeof(int64_t));
  }
}

// static
TaintData* StringTaint::FromString(blink::StringImpl* impl) {
  if (!impl) {
    return nullptr;
  }

  size_t len = impl->length();
  if (impl->Is8Bit()) {
    return reinterpret_cast<TaintData*>(
        &(reinterpret_cast<blink::LChar*>(impl + 1)[len]));
  } else {
    return reinterpret_cast<TaintData*>(
        &(reinterpret_cast<UChar*>(impl + 1)[len]));
  }
}

// static
size_t StringTaint::AllocationSize(unsigned length) {
  return (length * sizeof(TaintData)) + sizeof(int64_t);
}

// static
void StringTaint::SetTainted(blink::StringImpl* impl, TaintType type) {
  if (impl) {
    memset(FromString(impl), static_cast<TaintData>(type), impl->length());
  }
}

namespace {

int64_t* TaintInfoFromString(blink::StringImpl* impl) {
  if (impl) {
    return reinterpret_cast<int64_t*>(StringTaint::FromString(impl) +
                                      impl->length());
  } else {
    return nullptr;
  }
}

}  // namespace

// static
int64_t StringTaint::GetTaintInfo(blink::StringImpl* impl) {
  int64_t* info = TaintInfoFromString(impl);
  return info ? *info : 0;
}

// static
void StringTaint::SetTaintInfo(blink::StringImpl* impl, int64_t info) {
  int64_t* info_ptr = TaintInfoFromString(impl);
  if (info_ptr) {
    *info_ptr = info;
  }
}

}  // namespace webkit
}  // namespace tainttracking
