@echo off
title TunnelAI - menu
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0TunnelAI.ps1" %*
echo.
echo === TunnelAI cerrado ===
pause
