@echo off
setlocal

set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%create_project_from_template.ps1

if "%~1"=="" (
    set /p PROJECT_NAME=New project name: 
) else (
    set PROJECT_NAME=%~1
)

if "%PROJECT_NAME%"=="" (
    echo Project name is required.
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ProjectName "%PROJECT_NAME%"

set EXIT_CODE=%ERRORLEVEL%
if not "%EXIT_CODE%"=="0" (
    echo.
    echo Create project failed. Exit code: %EXIT_CODE%
    pause
    exit /b %EXIT_CODE%
)

echo.
echo Create project finished.
pause
exit /b 0
