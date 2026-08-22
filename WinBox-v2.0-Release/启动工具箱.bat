@echo off
chcp 65001 >nul
title WinBox - Windows System Toolbox
echo ========================================
echo   WinBox v1.0 - Windows System Toolbox
echo   集合 14 个 GitHub 优化工具精华
echo ========================================
echo.
echo 正在启动工具箱...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0WinBox.ps1"
if errorlevel 1 (
    echo.
    echo 启动失败，请以管理员身份运行此脚本
    pause
)
