@echo off
title TunnelAI - Gemini (remote streaming tunnel)
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Gemini-Remoto.ps1" %*
echo.
echo === TunnelAI cerrado ===
pause
