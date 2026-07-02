#!/bin/bash

# 快速验证污点追踪功能的脚本
# 直接运行现有的污点追踪测试

echo "=========================================="
echo "  快速验证污点追踪功能"
echo "=========================================="
echo ""

# 查找 cctest
CCTEST=""
for path in out/Debug/cctest out/Default/cctest out/Release/cctest v8/out/Debug/cctest; do
    if [ -f "$path" ]; then
        CCTEST="$path"
        echo "✓ 找到 cctest: $CCTEST"
        break
    fi
done

if [ -z "$CCTEST" ]; then
    echo "✗ 错误: 找不到 cctest 可执行文件"
    echo "请先编译: cd v8 && gn gen out/Debug && ninja -C out/Debug cctest"
    exit 1
fi

echo ""
echo "测试1: 基本污点标记和获取"
echo "----------------------------------------"
$CCTEST --gtest_filter="TaintLarge" 2>&1 | grep -E "(PASS|FAIL|OK|Running)"

echo ""
echo "测试2: 污点传播 - 字符串拼接"
echo "----------------------------------------"
$CCTEST --gtest_filter="TaintConsStringTwo" 2>&1 | grep -E "(PASS|FAIL|OK|Running)"

echo ""
echo "测试3: 污点传播 - 子串"
echo "----------------------------------------"
$CCTEST --gtest_filter="TaintSlicedString" 2>&1 | grep -E "(PASS|FAIL|OK|Running)"

echo ""
echo "测试4: Sink报警 - eval触发"
echo "----------------------------------------"
$CCTEST --gtest_filter="OnBeforeCompileEval" 2>&1 | grep -E "(PASS|FAIL|OK|Running|scripts)"

echo ""
echo "测试5: Sink报警 - 污点数据传入eval"
echo "----------------------------------------"
$CCTEST --gtest_filter="OnBeforeCompileSetTaint" 2>&1 | grep -E "(PASS|FAIL|OK|Running|scripts)"

echo ""
echo "测试6: 递归污点传播到对象"
echo "----------------------------------------"
$CCTEST --gtest_filter="RecursiveTaintObjectSimple" 2>&1 | grep -E "(PASS|FAIL|OK|Running|scripts)"

echo ""
echo "=========================================="
echo "  验证完成"
echo "=========================================="
echo ""
echo "说明:"
echo "- 'Running' 表示测试正在运行"
echo "- 'OK' 或 'PASS' 表示测试通过"
echo "- 'FAIL' 表示测试失败"
echo "- 'scripts' 数字 > 0 表示检测到污点并触发了listener"
echo ""
echo "如需查看详细输出，请运行:"
echo "  $CCTEST --gtest_filter=\"Taint*\""
