@echo off
setlocal

set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%clean_project.ps1

if not exist "%PS_SCRIPT%" (
    echo PowerShell script not found:
    echo %PS_SCRIPT%
    pause
    exit /b 1
)

echo This will clean Quartus generated files under prj.
echo Source files and project settings will be kept.
echo.
choice /C YN /M "Continue"
if errorlevel 2 (
    echo Clean canceled.
    pause
    exit /b 0
)

powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Force %*

set EXIT_CODE=%ERRORLEVEL%
if not "%EXIT_CODE%"=="0" (
    echo.
    echo Clean failed. Exit code: %EXIT_CODE%
    pause
    exit /b %EXIT_CODE%
)

echo.
echo Clean finished.
pause
exit /b 0
