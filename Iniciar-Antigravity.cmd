@echo off
REM Iniciar-Antigravity.cmd — doble clic para conectar Google Antigravity (modo local, sin tunel)
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Antigravity.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Antigravity.ps1" %*
)
echo.
echo Ventana cerrada. El servidor local se detuvo.
pause
