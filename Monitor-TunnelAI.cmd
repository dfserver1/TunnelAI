@echo off
REM Monitor-TunnelAI.cmd — Sentinel for TunnelAI sessions (also useful standalone)
REM   Monitor-TunnelAI.cmd                 -> watches port 3001 (ChatGPT/Gemini) with auto-recovery
REM   Monitor-TunnelAI.cmd 3002            -> vigila Claude
REM   Monitor-TunnelAI.cmd 3003            -> vigila Antigravity (local)
setlocal
set PUERTO=%1
if "%PUERTO%"=="" set PUERTO=3001
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Monitor-TunnelAI.ps1" -Puerto %PUERTO% -AutoRecuperar
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Monitor-TunnelAI.ps1" -Puerto %PUERTO% -AutoRecuperar
)
echo.
echo Vigia cerrado.
pause
