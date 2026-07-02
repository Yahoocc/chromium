#!/bin/bash

# 内存监控脚本 - 如果可用内存少于20G则停止ninja编译

NINJA_PID=$1
MIN_MEMORY_GB=20

if [ -z "$NINJA_PID" ]; then
    echo "错误: 需要提供ninja进程PID"
    echo "用法: $0 <ninja_pid>"
    exit 1
fi

echo "开始监控内存，ninja PID: $NINJA_PID"
echo "当可用内存少于 ${MIN_MEMORY_GB}G 时将停止编译"

while true; do
    # 检查ninja进程是否还在运行
    if ! kill -0 $NINJA_PID 2>/dev/null; then
        echo "$(date): ninja进程已结束，停止监控"
        exit 0
    fi

    # 获取可用内存（单位：GB）
    available_memory=$(free -g | awk '/^Mem:/ {print $7}')

    echo "$(date): 可用内存: ${available_memory}G"

    if [ "$available_memory" -lt "$MIN_MEMORY_GB" ]; then
        echo "$(date): 警告！可用内存 ${available_memory}G 少于阈值 ${MIN_MEMORY_GB}G"
        echo "$(date): 停止ninja编译进程 $NINJA_PID"
        kill -TERM $NINJA_PID
        sleep 2
        # 如果还没停止，强制kill
        if kill -0 $NINJA_PID 2>/dev/null; then
            echo "$(date): 强制停止ninja进程"
            kill -9 $NINJA_PID
        fi
        echo "$(date): 编译已停止，监控结束"
        exit 0
    fi

    sleep 10
done
