@echo off
REM Iniciar-Antigravity-Remoto.cmd — Antigravity via the SHARED tunnel (public URL + Bearer)
REM Same PC? Prefer Iniciar-Antigravity.cmd (local, no tunnel)
REM   Iniciar-Antigravity-Remoto.cmd -Token mi-clave
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Antigravity-Remoto.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Iniciar-Antigravity-Remoto.ps1" %*
)
echo.
echo Ventana cerrada. El tunel se detuvo.
pause
