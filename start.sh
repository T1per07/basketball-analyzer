#!/bin/bash
echo "========================================"
echo "  Basketball Shot Analyzer - Launcher"
echo "========================================"
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python3 not found."
    exit 1
fi

# Check Node
if ! command -v node &> /dev/null; then
    echo "[ERROR] Node.js not found."
    exit 1
fi

# Install backend deps
echo "[1/4] Installing backend dependencies..."
cd "$SCRIPT_DIR/backend"
pip3 install -r requirements.txt -q 2>/dev/null

# Install frontend deps
echo "[2/4] Installing frontend dependencies..."
cd "$SCRIPT_DIR/frontend"
if [ ! -d "node_modules" ]; then
    npm install --silent
fi

# Build frontend
echo "[3/4] Building frontend..."
npm run build

# Start backend
echo "[4/4] Starting backend server..."
echo
echo "========================================"
echo "  Server: http://localhost:8000"
echo "========================================"
echo
cd "$SCRIPT_DIR/backend"
python3 -m uvicorn app:app --host 0.0.0.0 --port 8000 --reload
