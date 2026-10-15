@echo off
REM Test-Conector-Gemini.cmd — is my tunnel Gemini-ready? (verify + requirements guide)
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Conector-Gemini.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Conector-Gemini.ps1" %*
)
