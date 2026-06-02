// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_WTF_TEXT_TAINT_TRACKING_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_WTF_TEXT_TAINT_TRACKING_H_

#include <stddef.h>
#include <stdint.h>

#include "third_party/blink/renderer/platform/wtf/wtf_export.h"

namespace blink {
class StringImpl;
}

namespace tainttracking {
namespace webkit {

// Must match the same definition in ../../../../../v8/include/v8-primitive.h.
// See that file for information about this datatype. We define a copy here so
// that the wtf build doesn't have to depend on the v8 code.
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

  MAX_TAINT_TYPE = 19,

  URL_ENCODED = 32,            // 1 << 5
  URL_COMPONENT_ENCODED = 64,  // 2 << 5
  ESCAPE_ENCODED = 96,         // 3 << 5
  MULTIPLE_ENCODINGS = 128,    // 4 << 5

  NO_ENCODING = 0,

  TAINT_TYPE_MASK = 31,      // 1 << 5 - 1
  ENCODIING_TYPE_MASK = 224  // 7 << 5
};

#define TAINT_TRACKING_TAINT_TYPE_FOR(V) \
  V(UNTAINTED)                           \
  V(TAINTED)                             \
  V(COOKIE)                              \
  V(MESSAGE)                             \
  V(URL)                                 \
  V(URL_HASH)                            \
  V(URL_PROTOCOL)                        \
  V(URL_HOST)                            \
  V(URL_HOSTNAME)                        \
  V(URL_ORIGIN)                          \
  V(URL_PORT)                            \
  V(URL_PATHNAME)                        \
  V(URL_SEARCH)                          \
  V(DOM)                                 \
  V(REFERRER)                            \
  V(WINDOWNAME)                          \
  V(STORAGE)                             \
  V(NETWORK)                             \
  V(MULTIPLE_TAINTS)                     \
  V(MESSAGE_ORIGIN)                      \
  V(MAX_TAINT_TYPE)

typedef uint8_t TaintData;

class WTF_EXPORT StringTaint {
 public:
  static TaintData* FromString(blink::StringImpl* impl);
  static void InitTaintData(blink::StringImpl* impl);
  static size_t AllocationSize(unsigned length);
  static void SetTainted(blink::StringImpl* impl, TaintType type);
  static int64_t GetTaintInfo(blink::StringImpl* impl);
  static void SetTaintInfo(blink::StringImpl* impl, int64_t info);
};

}  // namespace webkit
}  // namespace tainttracking

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_WTF_TEXT_TAINT_TRACKING_H_
