@echo off
echo ========================================
echo   Basketball Shot Analyzer - Launcher
echo ========================================
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.10+ first.
    pause
    exit /b 1
)

:: Check Node
node --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js not found. Install Node.js 18+ first.
    pause
    exit /b 1
)

:: Install backend dependencies
echo [1/4] Installing backend dependencies...
cd /d "%~dp0backend"
pip install -r requirements.txt -q 2>nul

:: Install frontend dependencies
echo [2/4] Installing frontend dependencies...
cd /d "%~dp0frontend"
if not exist node_modules (
    call npm install --silent
)

:: Build frontend
echo [3/4] Building frontend...
call npm run build

:: Start backend
echo [4/4] Starting backend server...
echo.
echo ========================================
echo   Server starting on http://localhost:8000
echo   Frontend served at http://localhost:8000
echo ========================================
echo.
cd /d "%~dp0backend"
python -m uvicorn app:app --host 0.0.0.0 --port 8000 --reload
