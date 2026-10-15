@echo off
REM Iniciar-TunnelAI.cmd — doble clic para levantar el tunel
REM Pide la ruta y deja la ventana abierta con la URL /mcp
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-TunnelAI.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-TunnelAI.ps1" %*
)
echo.
echo Ventana cerrada. Si el tunel seguia corriendo, ya se detuvo.
pause
