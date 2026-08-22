@echo off
chcp 65001 >nul
title WinBox - Windows System Toolbox
set WORKDIR=%~dp0
if not exist "%WORKDIR%\WinBox.ps1" (
    echo Error: WinBox.ps1 not found
    pause
    exit /b 1
)
start "" "%WORKDIR%\WinBox.exe"
exit
