@echo off
REM Iniciar-Claude.cmd — doble clic para Claude
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Claude.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Claude.ps1" %*
)
echo.
echo Ventana cerrada.
pause
