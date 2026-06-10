#!/bin/bash
# Chromium 低内存编译监控脚本

set -e

# 配置参数
MEMORY_THRESHOLD_GB=5
CHECK_INTERVAL=10  # 每 10 秒检查一次
BUILD_DIR="out/Default"
PARALLEL_JOBS=4

echo "======================================"
echo "Chromium 低内存编译启动器"
echo "======================================"
echo "并行任务数: $PARALLEL_JOBS"
echo "内存阈值: ${MEMORY_THRESHOLD_GB}GB 可用内存"
echo "检查间隔: ${CHECK_INTERVAL}秒"
echo ""

# 1. 重新生成构建文件
echo "[1/3] 运行 gn gen 生成构建文件..."
gn gen "$BUILD_DIR"
echo "✓ 构建文件生成完成"
echo ""

# 2. 启动后台编译进程
echo "[2/3] 启动 ninja 编译（-j $PARALLEL_JOBS）..."
ninja -C "$BUILD_DIR" -j "$PARALLEL_JOBS" chrome &
NINJA_PID=$!
echo "✓ Ninja PID: $NINJA_PID"
echo ""

# 3. 内存监控循环
echo "[3/3] 开始内存监控..."
echo "======================================"

while kill -0 $NINJA_PID 2>/dev/null; do
    # 获取可用内存（GB）
    AVAILABLE_MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    AVAILABLE_MEM_GB=$(echo "scale=2; $AVAILABLE_MEM_KB / 1024 / 1024" | bc)

    # 获取总内存
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$(echo "scale=2; $TOTAL_MEM_KB / 1024 / 1024" | bc)

    # 计算使用百分比
    USED_PERCENT=$(echo "scale=1; (1 - $AVAILABLE_MEM_KB / $TOTAL_MEM_KB) * 100" | bc)

    echo -ne "\r可用内存: ${AVAILABLE_MEM_GB}GB / ${TOTAL_MEM_GB}GB (使用率: ${USED_PERCENT}%)   "

    # 检查是否低于阈值
    if (( $(echo "$AVAILABLE_MEM_GB < $MEMORY_THRESHOLD_GB" | bc -l) )); then
        echo ""
        echo ""
        echo "⚠️  警告: 可用内存低于 ${MEMORY_THRESHOLD_GB}GB！"
        echo "🛑 停止编译进程 (PID: $NINJA_PID)..."
        kill -TERM $NINJA_PID
        sleep 2
        kill -9 $NINJA_PID 2>/dev/null || true
        echo "✓ 编译已停止"
        echo ""
        echo "你可以稍后运行以下命令继续编译："
        echo "  ninja -C $BUILD_DIR -j $PARALLEL_JOBS chrome"
        exit 1
    fi

    sleep "$CHECK_INTERVAL"
done

# 编译完成
wait $NINJA_PID
EXIT_CODE=$?

echo ""
echo ""
echo "======================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ 编译成功完成！"
else
    echo "✗ 编译失败 (退出码: $EXIT_CODE)"
fi
echo "======================================"
exit $EXIT_CODE
