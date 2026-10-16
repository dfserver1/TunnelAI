@echo off
title TunnelAI - Gemini
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Gemini.ps1" %*
echo.
echo === TunnelAI corriendo en segundo plano ===
echo Ya puedes cerrar esta ventana.
echo Para detenerlo: Limpiar-Bloqueo.cmd
pause
