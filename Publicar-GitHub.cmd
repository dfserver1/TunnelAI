@echo off
REM Publicar-GitHub.cmd - publishes TunnelAI as a PUBLIC repo on GitHub
REM   Publicar-GitHub.cmd            -> interactive wizard
REM   Publicar-GitHub.cmd -Plan      -> dry run: what it would do, changes nothing
REM   Publicar-GitHub.cmd -Privado   -> private repo
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publicar-GitHub.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publicar-GitHub.ps1" %*
)
