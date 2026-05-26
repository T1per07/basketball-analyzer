#!/bin/bash
# 篮球分析系统完整测试脚本
# 用法: ./run_full_test.sh [--update-baseline] [--video NAME]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "篮球分析系统 - 完整测试"
echo "========================================"

echo ""
echo "[1/3] 运行 pytest 单元测试..."
cd backend
python -m pytest tests/ -x -q
cd ..

echo ""
echo "[2/3] 运行基准回归测试..."
cd backend
python ../tests/benchmark/run_benchmark.py "$@"
EXIT_CODE=$?
cd ..

echo ""
echo "[3/3] 测试完成"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 全部通过"
elif [ $EXIT_CODE -eq 1 ]; then
    echo "❌ 发现回归问题"
else
    echo "⚠️  运行错误"
fi

exit $EXIT_CODE
