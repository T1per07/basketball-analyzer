@echo off
REM BASANS Portable Package Builder
REM Creates a zip file for portable distribution

echo ========================================
echo BASANS Portable Package Builder
echo ========================================

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

REM Create portable directory
set PORTABLE_DIR=BASANS-Portable-1.0.0
if exist "%PORTABLE_DIR%" rmdir /s /q "%PORTABLE_DIR%"
mkdir "%PORTABLE_DIR%"

echo Copying files...

REM Copy executable and DLLs
copy "..\BASANS\basketball_analyzer.exe" "%PORTABLE_DIR%\" >nul
copy "..\BASANS\dartjni.dll" "%PORTABLE_DIR%\" >nul
copy "..\BASANS\flutter_onnxruntime_plugin.dll" "%PORTABLE_DIR%\" >nul
copy "..\BASANS\flutter_windows.dll" "%PORTABLE_DIR%\" >nul
copy "..\BASANS\onnxruntime.dll" "%PORTABLE_DIR%\" >nul
copy "..\BASANS\native_assets.json" "%PORTABLE_DIR%\" >nul

REM Copy data directory
xcopy "..\BASANS\data" "%PORTABLE_DIR%\data\" /e /i /y >nul

REM Create README
echo BASANS - Basketball Analyzer v1.0.0 > "%PORTABLE_DIR%\README.txt"
echo. >> "%PORTABLE_DIR%\README.txt"
echo This is a portable version. No installation required. >> "%PORTABLE_DIR%\README.txt"
echo Simply run basketball_analyzer.exe to start the application. >> "%PORTABLE_DIR%\README.txt"
echo. >> "%PORTABLE_DIR%\README.txt"
echo For more information, visit: https://basans.surge.sh >> "%PORTABLE_DIR%\README.txt"

REM Create zip file
echo Creating zip file...
powershell -Command "Compress-Archive -Path '%PORTABLE_DIR%\*' -DestinationPath 'BASANS-Portable-1.0.0.zip' -Force"

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo SUCCESS: Portable package created!
    echo Output: BASANS-Portable-1.0.0.zip
    echo ========================================
) else (
    echo.
    echo ========================================
    echo ERROR: Failed to create zip file
    echo ========================================
)

REM Clean up
rmdir /s /q "%PORTABLE_DIR%"

pause
