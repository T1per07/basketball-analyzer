@echo off
REM 篮球分析系统完整测试脚本
REM 用法: run_full_test.bat [--update-baseline] [--video NAME]

echo ========================================
echo 篮球分析系统 - 完整测试
echo ========================================

echo.
echo [1/3] 运行 pytest 单元测试...
cd /d "%~dp0backend"
python -m pytest tests/ -x -q
if errorlevel 2 (
    echo pytest 运行错误
    exit /b 2
)

echo.
echo [2/3] 运行基准回归测试...
python ..\tests\benchmark\run_benchmark.py %*
set RESULT=%errorlevel%

echo.
echo [3/3] 测试完成
if %RESULT%==0 (
    echo ✅ 全部通过
) else if %RESULT%==1 (
    echo ❌ 发现回归问题
) else (
    echo ⚠️  运行错误
)

cd /d "%~dp0"
exit /b %RESULT%
