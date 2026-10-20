#!/usr/bin/env pwsh
<#
  Agregar-Skill.ps1 — installs "skills" (AI roles) into the exposed folder
  Available skills (15): auditoria · web · ocr · onboarding · seguridad · documentar ·
    instalacion · migracion · rendimiento · accesibilidad · datos · testing · seo · informes · arquitectura
  Usage:
    Agregar-Skill.cmd                          # interactive menu
    Agregar-Skill.ps1 -Skill auditoria         # install that skill
    Agregar-Skill.ps1 -Skill web -Ruta C:\X    # into a specific folder
    Agregar-Skill.ps1 -Skill todas             # all of them
    Agregar-Skill.ps1 -Listar                  # list available skills
    Agregar-Skill.ps1 -Quitar                  # remove the skills from the folder
  What it does: copies TUNNELAI-SKILL-<skill>.md into the exposed root (the AI sees it with
  list_files/read_file) and copies the text to the clipboard to paste as connector instructions.
#>

param(
  [ValidateSet('auditoria','web','ocr','onboarding','seguridad','documentar','instalacion','migracion','rendimiento','accesibilidad','datos','testing','seo','informes','arquitectura','todas','ambas','')][string]$Skill = '',
  [string]$Ruta,
  [switch]$Listar,
  [switch]$Quitar,
  [switch]$Silencioso
)

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot
$skillsDir = Join-Path $raiz 'Skills'

function Write-Ok($m)  { Write-Host "✓ $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "› $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow }

$catalogo = [ordered]@{
  'auditoria'    = @{ Archivo = 'auditoria-codigo.md';       Titulo = 'Code auditing';                  Emoji = '🔍' }
  'web'          = @{ Archivo = 'desarrollo-web.md';         Titulo = 'Website development';            Emoji = '🌐' }
  'ocr'          = @{ Archivo = 'ocr-vision.md';             Titulo = 'OCR and document vision';        Emoji = '🧾' }
  'onboarding'   = @{ Archivo = 'onboarding.md';             Titulo = 'Fast project onboarding';        Emoji = '🗺️' }
  'seguridad'    = @{ Archivo = 'seguridad-dependencias.md'; Titulo = 'Dependency security';            Emoji = '🔐' }
  'documentar'   = @{ Archivo = 'documentar.md';             Titulo = 'Automatic documentation';        Emoji = '📚' }
  'instalacion'  = @{ Archivo = 'instalacion.md';            Titulo = 'Dependency installation';        Emoji = '📦' }
  'migracion'    = @{ Archivo = 'migracion.md';              Titulo = 'Migration and modernization';    Emoji = '🔄' }
  'rendimiento'  = @{ Archivo = 'rendimiento.md';            Titulo = 'Performance and profiling';      Emoji = '⚡' }
  'accesibilidad'= @{ Archivo = 'accesibilidad.md';          Titulo = 'Web accessibility (WCAG)';       Emoji = '♿' }
  'datos'        = @{ Archivo = 'datos.md';                  Titulo = 'Data analysis CSV/Excel';        Emoji = '📊' }
  'testing'      = @{ Archivo = 'testing.md';                Titulo = 'Testing and quality control';    Emoji = '🧪' }
  'seo'          = @{ Archivo = 'seo.md';                    Titulo = 'Technical SEO';                  Emoji = '🔎' }
  'informes'     = @{ Archivo = 'informes.md';               Titulo = 'Reports and PDF export';         Emoji = '📄' }
  'arquitectura' = @{ Archivo = 'arquitectura.md';           Titulo = 'Architecture diagrams';          Emoji = '🏗️' }
}

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           TunnelAI — Skills for the AI              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($Listar) {
  foreach ($k in $catalogo.Keys) {
    $p = Join-Path $skillsDir $catalogo[$k].Archivo
    (Get-Content -LiteralPath $p -TotalCount 3) -join ' ' | Out-Null
    Write-Host "  $($catalogo[$k].Emoji) $k".PadRight(14) -ForegroundColor White -NoNewline
    Write-Host " — $($catalogo[$k].Titulo)" -ForegroundColor DarkGray
  }
  Write-Host ""
  return
}

# ── destination folder: parameter, last folder, or prompt ─────────────────────
function Get-RutaDestino {
  if ($Ruta) { return $Ruta }
  $ultimaFile = Join-Path $raiz '.ultima_ruta.txt'
  $ult = ''
  if (Test-Path -LiteralPath $ultimaFile) { $ult = (Get-Content -LiteralPath $ultimaFile -Raw).Trim() }
  if ($ult) {
    Write-Info "Last folder: $ult"
    $resp = Read-Host "Install the skill there? (Y/N)"
    if ($resp -match '^[SsYy]') { return $ult }
  }
  return (Read-Host "Paste the FULL path of the exposed folder")
}

if ($Quitar) {
  $destino = Get-RutaDestino
  if (-not (Test-Path -LiteralPath $destino)) { Write-Warn "Folder does not exist: $destino"; Read-Host "Press Enter"; exit 1 }
  $borrados = 0
  Get-ChildItem -LiteralPath $destino -Filter 'TUNNELAI-SKILL-*.md' -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force; $borrados++
    Write-Ok "Deleted $($_.Name)"
  }
  if ($borrados -eq 0) { Write-Info "No skills were installed in $destino" }
  Read-Host "Press Enter" | Out-Null
  return
}

# ── choose skill ──────────────────────────────────────────────────────────────
if (-not $Skill) {
  Write-Host "  Which skill do you want to install?" -ForegroundColor White
  $mapa = [ordered]@{}
  $i = 1
  foreach ($k in $catalogo.Keys) {
    Write-Host "    $i) $($catalogo[$k].Emoji) $($catalogo[$k].Titulo)" -ForegroundColor White
    $mapa["$i"] = $k
    $i++
  }
  Write-Host "    $i) All" -ForegroundColor White
  $mapa["$i"] = 'todas'
  $op = Read-Host "Choose (number)"
  $Skill = $mapa[$op]
  if (-not $Skill) { Write-Warn "Invalid option."; Read-Host "Press Enter"; exit 1 }
}

$destino = Get-RutaDestino
$destino = $destino.Trim().Trim('"').Trim("'")
if (-not (Test-Path -LiteralPath $destino)) {
  $crear = Read-Host "Folder does not exist: $destino — create it? (Y/N)"
  if ($crear -match '^[SsYy]') { New-Item -ItemType Directory -Path $destino -Force | Out-Null; Write-Ok "Folder created" }
  else { Write-Warn "Cancelled."; Read-Host "Press Enter"; exit 1 }
}
$destino = (Resolve-Path -LiteralPath $destino).Path

$elegidos = if ($Skill -in 'todas','ambas') { @($catalogo.Keys) } else { @($Skill) }

foreach ($k in $elegidos) {
  $info = $catalogo[$k]
  $src = Join-Path $skillsDir $info.Archivo
  if (-not (Test-Path -LiteralPath $src)) { Write-Warn "Couldn't find $src"; continue }
  $dst = Join-Path $destino "TUNNELAI-SKILL-$k.md"
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Write-Ok "$($info.Emoji) $($info.Titulo) installed -> $dst"

  # skill text to the clipboard to paste as connector instructions
  if (-not $Silencioso) {
    try {
      $txt = Get-Content -LiteralPath $src -Raw
      Set-Clipboard -Value $txt
      Write-Info "Skill text copied to clipboard (paste it into the connector Instructions if supported)"
    } catch {}
  }
}

if ($Silencioso) { return }

Write-Host ""
Write-Host "── How to use it ─────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  1. Start the tunnel (Iniciar-TunnelAI / Gemini / Claude / Antigravity) with that folder."
Write-Host "  2. Tell the AI:" -ForegroundColor White
$frases = @{
  'auditoria'     = 'Read TUNNELAI-SKILL-auditoria.md and run the audit of the root'
  'web'           = 'Read TUNNELAI-SKILL-web.md and build the site I ask for in the root'
  'ocr'           = 'Read TUNNELAI-SKILL-ocr.md. Extract the text from the images with Tools\OCR.ps1 and structure it'
  'onboarding'    = 'Read TUNNELAI-SKILL-onboarding.md and give me the complete map of this project'
  'seguridad'     = 'Read TUNNELAI-SKILL-seguridad.md and review dependencies and secrets in the root'
  'documentar'    = 'Read TUNNELAI-SKILL-documentar.md and document this project (README + docs/API.md)'
  'instalacion'   = 'Read TUNNELAI-SKILL-instalacion.md. Install <package> in the project and record it'
  'migracion'     = 'Read TUNNELAI-SKILL-migracion.md and plan the migration of this project in phases'
  'rendimiento'   = 'Read TUNNELAI-SKILL-rendimiento.md and measure the bottleneck I tell you'
  'accesibilidad' = 'Read TUNNELAI-SKILL-accesibilidad.md and audit the site in the root against WCAG 2.2 AA'
  'datos'         = 'Read TUNNELAI-SKILL-datos.md and analyze the CSV I indicate'
  'testing'       = 'Read TUNNELAI-SKILL-testing.md and design the test strategy for this project'
  'seo'           = 'Read TUNNELAI-SKILL-seo.md and audit the technical SEO of this site'
  'informes'      = 'Read TUNNELAI-SKILL-informes.md. Generate the report in Markdown and PDF with Tools\HTML-a-PDF.ps1'
  'arquitectura'  = 'Read TUNNELAI-SKILL-arquitectura.md and generate ARCHITECTURE.md with Mermaid diagrams'
}
foreach ($k in $elegidos) { Write-Host "     “$($frases[$k])”" -ForegroundColor Yellow }
Write-Host "  3. The AI reads the skill from the disk itself (nothing else for you to do)." -ForegroundColor DarkGray
Write-Host ""
Read-Host "Press Enter" | Out-Null
