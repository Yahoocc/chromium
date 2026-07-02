#!/bin/bash

# 污点追踪测试运行脚本

set -e

echo "=========================================="
echo "  Chromium 污点追踪测试工具"
echo "=========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查V8目录
if [ ! -d "v8" ]; then
    echo -e "${RED}错误: 找不到 v8 目录${NC}"
    echo "请确保在 chromium/src 目录下运行此脚本"
    exit 1
fi

# 检测构建目录
BUILD_DIR=""
for dir in out/Debug out/Default out/Release; do
    if [ -d "$dir" ]; then
        BUILD_DIR="$dir"
        echo -e "${GREEN}✓${NC} 找到构建目录: $BUILD_DIR"
        break
    fi
done

if [ -z "$BUILD_DIR" ]; then
    echo -e "${RED}错误: 找不到构建目录 (out/Debug, out/Default, out/Release)${NC}"
    echo "请先编译 Chromium"
    exit 1
fi

# 检查 cctest 可执行文件
if [ ! -f "$BUILD_DIR/cctest" ]; then
    echo -e "${YELLOW}警告: 找不到 cctest 可执行文件${NC}"
    echo "尝试编译 cctest..."

    cd v8
    if [ ! -f "out/Debug/args.gn" ]; then
        echo "生成构建配置..."
        gn gen out/Debug --args='is_debug=true'
    fi

    echo "编译 cctest (这可能需要几分钟)..."
    ninja -C out/Debug cctest
    cd ..

    BUILD_DIR="v8/out/Debug"
fi

CCTEST="$BUILD_DIR/cctest"

if [ ! -f "$CCTEST" ]; then
    echo -e "${RED}错误: 无法找到或编译 cctest${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} cctest 可执行文件: $CCTEST"
echo ""

# 显示菜单
echo "选择测试选项:"
echo "  1) 运行所有污点追踪测试"
echo "  2) 运行基本污点测试"
echo "  3) 运行污点传播测试"
echo "  4) 运行 eval 编译测试"
echo "  5) 运行自定义测试"
echo "  6) 列出所有可用的污点测试"
echo "  0) 退出"
echo ""

read -p "请选择 [0-6]: " choice

case $choice in
    1)
        echo -e "\n${GREEN}运行所有污点追踪测试...${NC}\n"
        $CCTEST --gtest_filter="*Taint*"
        ;;
    2)
        echo -e "\n${GREEN}运行基本污点测试...${NC}\n"
        $CCTEST --gtest_filter="TaintLarge*:TaintCons*:TaintSliced*"
        ;;
    3)
        echo -e "\n${GREEN}运行污点传播测试...${NC}\n"
        $CCTEST --gtest_filter="*TaintEncoding*:*TaintJoin*:*TaintString*:*TaintJSON*"
        ;;
    4)
        echo -e "\n${GREEN}运行编译相关测试 (eval sink)...${NC}\n"
        $CCTEST --gtest_filter="OnBeforeCompile*:RecursiveTaint*"
        ;;
    5)
        echo ""
        read -p "输入测试过滤器 (例如: TaintSinkBasic): " filter
        echo -e "\n${GREEN}运行测试: $filter${NC}\n"
        $CCTEST --gtest_filter="$filter"
        ;;
    6)
        echo -e "\n${GREEN}可用的污点测试:${NC}\n"
        $CCTEST --gtest_list_tests | grep -A 100 "Taint"
        ;;
    0)
        echo "退出"
        exit 0
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  测试完成"
echo "=========================================="

# 检查日志文件
if ls /tmp/taint_log_*.bin 1> /dev/null 2>&1; then
    echo -e "\n${YELLOW}污点追踪日志文件:${NC}"
    ls -lh /tmp/taint_log_*.bin | tail -5
    echo ""
    echo "提示: 可以使用专门的工具分析这些日志文件"
fi
