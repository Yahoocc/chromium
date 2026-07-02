#!/bin/bash

# 编译和运行污点追踪测试的完整指南

echo "=========================================="
echo "  污点追踪功能 - 编译和测试指南"
echo "=========================================="
echo ""

# 检查当前目录
if [ ! -d "v8" ]; then
    echo "✗ 错误: 请在 chromium/src 目录下运行此脚本"
    exit 1
fi

echo "步骤1: 检查构建环境"
echo "----------------------------------------"

# 检查ninja
if ! command -v ninja &> /dev/null; then
    echo "✗ 警告: ninja 未安装"
    echo "  安装: sudo apt-get install ninja-build"
else
    echo "✓ ninja 已安装"
fi

# 检查gn
if ! command -v gn &> /dev/null; then
    echo "✗ 警告: gn 未找到"
    echo "  gn 通常在 depot_tools 中"
else
    echo "✓ gn 已安装"
fi

echo ""
echo "步骤2: 编译 V8 cctest"
echo "----------------------------------------"
echo "这将需要一些时间（首次编译可能需要10-30分钟）"
echo ""

read -p "是否继续编译? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "跳过编译"
    exit 0
fi

cd v8

# 选择构建配置
echo "选择构建类型:"
echo "  1) Debug (带调试符号，适合开发)"
echo "  2) Release (优化版本，运行更快)"
read -p "请选择 [1-2]: " build_type

if [ "$build_type" == "2" ]; then
    BUILD_DIR="out/Release"
    BUILD_ARGS="is_debug=false"
else
    BUILD_DIR="out/Debug"
    BUILD_ARGS="is_debug=true"
fi

echo ""
echo "使用构建目录: $BUILD_DIR"

# 生成构建文件
if [ ! -f "$BUILD_DIR/args.gn" ]; then
    echo "生成构建配置..."
    gn gen $BUILD_DIR --args="$BUILD_ARGS"
fi

# 编译 cctest
echo ""
echo "开始编译 cctest..."
echo "提示: 这可能需要较长时间，请耐心等待"
echo ""

ninja -C $BUILD_DIR cctest

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ 编译成功!"
    echo ""
    echo "cctest 位置: v8/$BUILD_DIR/cctest"

    cd ..

    echo ""
    echo "步骤3: 运行污点追踪测试"
    echo "----------------------------------------"

    # 运行一个简单测试验证
    echo "运行验证测试..."
    v8/$BUILD_DIR/cctest --gtest_filter="TaintLarge"

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ 测试运行成功!"
        echo ""
        echo "=========================================="
        echo "  设置完成！"
        echo "=========================================="
        echo ""
        echo "您现在可以运行:"
        echo "  1. ./quick_verify_taint.sh       # 快速验证"
        echo "  2. ./run_taint_tests.sh          # 交互式测试"
        echo "  3. v8/$BUILD_DIR/cctest --gtest_filter=\"*Taint*\"  # 所有测试"
    else
        echo ""
        echo "✗ 测试运行失败"
        echo "请检查编译是否完整"
    fi
else
    echo ""
    echo "✗ 编译失败"
    echo "请检查:"
    echo "  1. 依赖是否已安装 (tools/dev/v8gen.py -h)"
    echo "  2. 磁盘空间是否充足"
    echo "  3. 构建配置是否正确"
    cd ..
    exit 1
fi
