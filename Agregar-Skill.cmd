@echo off
REM Agregar-Skill.cmd — installs skills (AI roles) into the exposed folder
REM   Agregar-Skill.cmd                      -> menu (1-15) or "All"
REM   Agregar-Skill.cmd auditoria            -> direct install
REM   Agregar-Skill.cmd instalacion          -> dependency installation skill
REM   Agregar-Skill.cmd ocr C:\Proyectos\X   -> en una carpeta concreta
REM   Agregar-Skill.cmd -Listar              -> skills disponibles
setlocal
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agregar-Skill.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agregar-Skill.ps1" %*
)
