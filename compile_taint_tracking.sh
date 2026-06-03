#!/bin/bash
# 污点跟踪增量编译脚本

set -e

echo "======================================"
echo "污点跟踪代码增量编译脚本"
echo "======================================"
echo ""

# 检查是否在Chromium根目录
if [ ! -f ".gn" ]; then
    echo "❌ 错误：请在Chromium根目录运行此脚本"
    exit 1
fi

# 设置环境变量
export PATH=/home/ycc/exp/depot_tools:$PATH

# 构建目录
BUILD_DIR="out/TaintTest"

echo "1. 准备构建配置..."
if [ ! -d "$BUILD_DIR" ]; then
    mkdir -p "$BUILD_DIR"
    cat > "$BUILD_DIR/args.gn" << 'ARGS'
# 最小化构建配置，用于快速编译测试
is_debug = false
is_component_build = false
symbol_level = 1
v8_enable_disassembler = false
v8_enable_object_print = false
v8_enable_verify_heap = false
use_goma = false
enable_nacl = false
ARGS
    echo "   ✓ 已创建构建配置"
else
    echo "   ✓ 使用现有构建配置"
fi

echo ""
echo "2. 生成构建文件..."
echo "   注意：如果缺少gn工具，请运行："
echo "   gclient sync"
echo ""

# 尝试生成构建文件
if command -v gn &> /dev/null; then
    gn gen "$BUILD_DIR" 2>&1 | tail -5
    if [ $? -eq 0 ]; then
        echo "   ✓ 构建文件生成成功"
    else
        echo "   ❌ gn gen 失败"
        exit 1
    fi
else
    echo "   ⚠️  未找到gn工具，跳过此步骤"
    echo "   请先运行: gclient sync"
fi

echo ""
echo "3. 编译污点跟踪相关目标..."
echo ""

# 如果构建文件存在，尝试编译特定目标
if [ -f "$BUILD_DIR/build.ninja" ]; then
    echo "   编译 Blink WTF 部分..."
    ninja -C "$BUILD_DIR" -j4 blink_platform 2>&1 | tail -20

    echo ""
    echo "   编译 V8 污点跟踪部分..."
    ninja -C "$BUILD_DIR" -j4 v8_taint_tracking_stub 2>&1 | tail -20

    echo ""
    echo "   ✓ 增量编译完成"
else
    echo "   ⚠️  build.ninja不存在，无法编译"
    echo "   请先运行 gn gen $BUILD_DIR"
fi

echo ""
echo "======================================"
echo "完成！"
echo "======================================"
echo ""
echo "如果遇到错误，可以尝试："
echo "1. 安装依赖: gclient sync"
echo "2. 只编译特定目标:"
echo "   ninja -C $BUILD_DIR blink_platform"
echo "   ninja -C $BUILD_DIR v8_taint_tracking_stub"
echo ""
