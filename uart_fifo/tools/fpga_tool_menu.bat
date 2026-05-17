@echo off
setlocal EnableDelayedExpansion
title FPGA Tool Menu

:menu
cls
echo ==========================================
echo              FPGA 工具箱
echo ==========================================
echo.
echo   1. 编译工程
echo   2. 编译并临时下载（SOF）
echo   3. 编译并固化烧录（Flash）
echo   4. SOF 转 JIC
echo   5. 清理工程生成文件
echo   6. 查看下载线
echo   0. 退出
echo.
set /p CHOICE=请输入编号: 

if "%CHOICE%"=="1" goto compile
if "%CHOICE%"=="2" goto download
if "%CHOICE%"=="3" goto flash
if "%CHOICE%"=="4" goto jic
if "%CHOICE%"=="5" goto clean
if "%CHOICE%"=="6" goto cables
if "%CHOICE%"=="0" goto end

echo.
echo 输入无效，请重新选择。
pause
goto menu

:compile
call "%~dp0fpga_tool.bat" compile
pause
goto menu

:download
call "%~dp0fpga_tool.bat" download
pause
goto menu

:flash
call "%~dp0fpga_tool.bat" flash -FlashDevice EPCS16
pause
goto menu

:jic
call "%~dp0fpga_tool.bat" jic
pause
goto menu

:clean
call "%~dp0fpga_tool.bat" clean
pause
goto menu

:cables
call "%~dp0fpga_tool.bat" list-cables
pause
goto menu

:end
exit /b 0
