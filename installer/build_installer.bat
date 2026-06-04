@echo off
REM BASANS Installer Build Script
REM Requires NSIS (Nullsoft Scriptable Install System) to be installed
REM Download from: https://nsis.sourceforge.io/Download

echo ========================================
echo BASANS Installer Builder
echo ========================================

REM Check if NSIS is installed
where makensis >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: NSIS not found in PATH
    echo.
    echo Please install NSIS from: https://nsis.sourceforge.io/Download
    echo After installation, add NSIS to your PATH or run this script from NSIS directory
    echo.
    echo Default NSIS installation path: C:\Program Files (x86)\NSIS
    echo.
    pause
    exit /b 1
)

REM Check if source files exist
if not exist "..\BASANS\basketball_analyzer.exe" (
    echo ERROR: BASANS build not found
    echo Please build the Flutter app first:
    echo   cd basketball_analyzer_app
    echo   flutter build windows
    echo.
    pause
    exit /b 1
)

echo Building BASANS installer...
echo.

REM Build installer
makensis /V4 basans_installer.nsi

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo SUCCESS: Installer created successfully!
    echo Output: BASANS-Setup-1.0.0.exe
    echo ========================================
) else (
    echo.
    echo ========================================
    echo ERROR: Failed to build installer
    echo ========================================
)

pause
