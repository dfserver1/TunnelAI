@echo off
title TunnelAI - Gemini (SSH tunnel)
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Gemini-SSH.ps1" %*
echo.
echo === TunnelAI cerrado ===
pause
