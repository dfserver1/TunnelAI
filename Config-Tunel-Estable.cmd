@echo off
REM Config-Tunel-Estable.cmd - sets up a named Cloudflare tunnel (stable URL, free, with a domain)
REM   Config-Tunel-Estable.cmd            -> interactive wizard
REM   Config-Tunel-Estable.cmd -Plan      -> dry run: what it would do, changes nothing
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Config-Tunel-Estable.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Config-Tunel-Estable.ps1" %*
)
