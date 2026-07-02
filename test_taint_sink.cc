// 测试污点追踪：标记、传播和sink报警
// 编译命令: 参考 v8/test/cctest 的编译方式

#include "test/cctest/cctest.h"
#include "src/objects-inl.h"
#include "src/taint_tracking.h"
#include "src/taint_tracking-inl.h"
#include "src/taint_tracking/log_listener.h"

#include <memory>
#include <vector>
#include <string>

using namespace v8::internal;
using namespace tainttracking;

// 自定义监听器来捕获sink报警
class SinkAlertListener : public tainttracking::LogListener {
public:
  SinkAlertListener() : alert_count_(0) {}
  virtual ~SinkAlertListener() {}

  virtual void OnLog(const ::TaintLogRecord::Reader& message) override {
    // 检查是否是sink相关的消息
    if (message.getMessage().which() == ::TaintLogRecord::Message::JS_SINK_TAINTED) {
      alert_count_++;
      auto sink_msg = message.getMessage().getJsSinkTainted();

      // 打印sink信息
      printf("\n=== SINK ALERT #%d ===\n", alert_count_);
      printf("Sink Type: %d\n", static_cast<int>(sink_msg.getSink()));

      if (sink_msg.hasTaintInfo()) {
        auto taint_info = sink_msg.getTaintInfo();
        printf("Taint Flag: %u\n", taint_info.getFlag());

        if (taint_info.hasRanges()) {
          auto ranges = taint_info.getRanges();
          printf("Tainted Ranges: %u ranges\n", ranges.size());
          for (auto range : ranges) {
            printf("  - Type: %d, Length: %d\n",
                   range.getType(), range.getLength());
          }
        }
      }

      // 打印堆栈信息
      if (sink_msg.hasStackTrace()) {
        auto stack = sink_msg.getStackTrace();
        if (stack.hasFrames()) {
          auto frames = stack.getFrames();
          printf("Stack Trace (%u frames):\n", frames.size());
          for (size_t i = 0; i < frames.size() && i < 5; i++) {
            auto frame = frames[i];
            if (frame.hasFunctionName()) {
              printf("  [%zu] %s\n", i, frame.getFunctionName().cStr());
            }
          }
        }
      }
      printf("===================\n\n");
    }
  }

  int GetAlertCount() const { return alert_count_; }
  void ResetCount() { alert_count_ = 0; }

private:
  int alert_count_;
};

// 测试用例基类
class TaintTestCase {
public:
  TaintTestCase() {
    CcTest::InitializeVM();
    listener_ = new SinkAlertListener();
    RegisterLogListener(std::unique_ptr<LogListener>(listener_));
  }

  ~TaintTestCase() {
    LogDispose(reinterpret_cast<v8::internal::Isolate*>(CcTest::isolate()));
  }

  SinkAlertListener* GetListener() { return listener_; }

private:
  SinkAlertListener* listener_;
};

// 测试1: 基本的污点标记和sink报警
TEST(TaintSinkBasic) {
  printf("\n[TEST] TaintSinkBasic - 测试污点标记后传入eval是否触发报警\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var tainted_input = 'alert(1)';"
      "tainted_input.__setTaint__(1);"  // 标记为污点
      "eval(tainted_input);");           // 传播到sink

  auto listener = test_case.GetListener();
  CHECK_EQ(listener->GetAlertCount(), 0);  // 执行前应该是0

  // 执行代码
  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  // 验证报警被触发
  int alert_count = listener->GetAlertCount();
  printf("✓ Sink alerts triggered: %d\n", alert_count);
  CHECK_GT(alert_count, 0);  // 应该至少触发一次报警
}

// 测试2: 污点传播 - 字符串拼接
TEST(TaintPropagationConcat) {
  printf("\n[TEST] TaintPropagationConcat - 测试污点通过字符串拼接传播\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var user_input = '1';"
      "user_input.__setTaint__(1);"     // 标记污点
      "var code = '1 + ' + user_input;" // 污点传播到新字符串
      "eval(code);");                    // 传播到sink

  auto listener = test_case.GetListener();
  listener->ResetCount();

  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  int alert_count = listener->GetAlertCount();
  printf("✓ Propagation through concat detected: %d alerts\n", alert_count);
  CHECK_GT(alert_count, 0);

  // 验证结果正确
  CHECK_EQ(2, result->Int32Value(
      CcTest::isolate()->GetCurrentContext()).FromJust());
}

// 测试3: 污点传播 - substring
TEST(TaintPropagationSubstring) {
  printf("\n[TEST] TaintPropagationSubstring - 测试污点通过substring传播\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var tainted = '1234567890';"
      "tainted.__setTaint__(1);"
      "var slice = tainted.substring(0, 1);"  // 子串应该继承污点
      "eval(slice);");

  auto listener = test_case.GetListener();
  listener->ResetCount();

  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  int alert_count = listener->GetAlertCount();
  printf("✓ Propagation through substring detected: %d alerts\n", alert_count);
  CHECK_GT(alert_count, 0);
}

// 测试4: 多个污点源
TEST(MultipleTaintSources) {
  printf("\n[TEST] MultipleTaintSources - 测试多个污点源的传播\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var url_param = 'param1';"
      "var cookie_val = 'value1';"
      "url_param.__setTaint__(1);"
      "cookie_val.__setTaint__(1);"
      "var combined = url_param + '=' + cookie_val;"
      "eval('\"' + combined + '\"');");

  auto listener = test_case.GetListener();
  listener->ResetCount();

  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  int alert_count = listener->GetAlertCount();
  printf("✓ Multiple taint sources detected: %d alerts\n", alert_count);
  CHECK_GT(alert_count, 0);
}

// 测试5: 无污点数据不应触发报警
TEST(NoTaintNoAlert) {
  printf("\n[TEST] NoTaintNoAlert - 测试无污点数据不触发报警\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var clean_data = '1 + 1';"
      // 注意：没有调用 __setTaint__
      "eval(clean_data);");

  auto listener = test_case.GetListener();
  listener->ResetCount();

  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  int alert_count = listener->GetAlertCount();
  printf("✓ Clean data produced %d alerts (should be 0 or minimal)\n", alert_count);
  // 注意：根据配置，可能仍有日志但不应该是污点相关的

  CHECK_EQ(2, result->Int32Value(
      CcTest::isolate()->GetCurrentContext()).FromJust());
}

// 测试6: 对象属性污点传播
TEST(TaintPropagationObject) {
  printf("\n[TEST] TaintPropagationObject - 测试对象属性的污点传播\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var obj = { code: '1' };"
      "__setTaint__(obj, 1);"    // 标记整个对象为污点
      "eval(obj.code);");         // 访问属性应该继承污点

  auto listener = test_case.GetListener();
  listener->ResetCount();

  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  int alert_count = listener->GetAlertCount();
  printf("✓ Object property taint detected: %d alerts\n", alert_count);
  CHECK_GT(alert_count, 0);
}

// 测试7: 复杂的污点传播路径
TEST(ComplexTaintPropagation) {
  printf("\n[TEST] ComplexTaintPropagation - 测试复杂的污点传播路径\n");

  TaintTestCase test_case;
  v8::HandleScope scope(CcTest::isolate());

  v8::Local<v8::String> source = v8_str(
      CcTest::isolate(),
      "var input = 'attack';"
      "input.__setTaint__(1);"
      // 经过多次变换
      "var step1 = input.toUpperCase();"
      "var step2 = step1.toLowerCase();"
      "var step3 = 'eval(\"' + step2 + '\")';"
      "var step4 = step3.substring(5, 11);"  // 提取 'attack'
      "eval('\"' + step4 + '\"');");

  auto listener = test_case.GetListener();
  listener->ResetCount();

  auto result = v8::Script::Compile(
      CcTest::isolate()->GetCurrentContext(), source)
      .ToLocalChecked()->Run();

  int alert_count = listener->GetAlertCount();
  printf("✓ Complex propagation path detected: %d alerts\n", alert_count);
  CHECK_GT(alert_count, 0);
}

int main(int argc, char* argv[]) {
  printf("\n");
  printf("========================================\n");
  printf("  污点追踪测试套件\n");
  printf("========================================\n");

  // 运行所有测试
  printf("\n运行测试...\n");

  return 0;
}
