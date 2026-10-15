@echo off
REM Iniciar-Gemini.cmd — doble clic para conectar Gemini (gemini.google.com) con tu PC
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Gemini.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Gemini.ps1" %*
)
echo.
echo Ventana cerrada. Si el tunel seguia corriendo, ya se detuvo.
pause
