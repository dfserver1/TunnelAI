#!/usr/bin/env pwsh
# TunnelAI.ps1 - one menu that orchestrates every TunnelAI session.
#
#   1 ChatGPT          Cloudflare quick tunnel (request/response, new URL per run)
#   2 Gemini           Tailscale Funnel (streaming SSE, detached, stable URL)
#   3 Claude           Cloudflare quick tunnel (expose-files-mcp, new URL per run)
#   4 Antigravity      local only (127.0.0.1:3003), no tunnel
#   5 Antigravity      remote: shared public tunnel + Bearer token
#   6 Verify           environment, dependencies and ports
#   7 Stop             ports, quick tunnels, Tailscale Funnel, sentinels
#
# Before opening the tunnel it installs the 15 skills into the exposed folder
# (toggle with "s"), so the AI finds TUNNELAI-SKILL-*.md through the tunnel.
#
# Usage:
#   TunnelAI.cmd                              # interactive menu
#   TunnelAI.ps1 -Opcion 2 -Ruta C:\MyApp     # non-interactive, one action
#   TunnelAI.ps1 -Opcion 1 -Ruta C:\MyApp -SinSkills
# Parameters:
#   -Opcion <1..7>  -Ruta <folder>  -SinSkills  -Ventana (Gemini: keep the log)
#   -MaxMinutos <n> -Token <key>
param(
  [string]$Opcion = '',
  [string]$Ruta,
  [switch]$SinSkills,
  [switch]$Ventana,
  [int]$MaxMinutos = 0,
  [string]$Token = ''
)

$ErrorActionPreference = "Stop"

$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch {
    if ($i -eq 3) {
      Write-Host "No pude cargar lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red
      Read-Host "Pulsa Enter"
      exit 1
    }
    Start-Sleep 2
  }
}

$pwshExe = (Get-Process -Id $PID).Path

function Show-TunnelAiMenu {
  param([string]$Carpeta, [bool]$Skills)
  Write-Host ""
  Write-Host "  ================================================================" -ForegroundColor Cyan
  Write-Host "    TunnelAI - elige el asistente y listo" -ForegroundColor Cyan
  Write-Host "  ================================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "    Carpeta : " -NoNewline -ForegroundColor Gray
  Write-Host $Carpeta -ForegroundColor White -NoNewline
  Write-Host "   (c = cambiar)" -ForegroundColor DarkGray
  Write-Host "    Skills  : " -NoNewline -ForegroundColor Gray
  if ($Skills) { Write-Host "INSTALAR las 15 en la carpeta" -ForegroundColor Green -NoNewline }
  else { Write-Host "no instalar" -ForegroundColor DarkGray -NoNewline }
  Write-Host "   (s = cambiar)" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "    1  ChatGPT             Cloudflare, URL nueva      :3001"
  Write-Host "    2  Gemini web/movil    Tailscale Funnel, URL fija :3001"
  Write-Host "    3  Claude              Cloudflare, URL nueva      :3002"
  Write-Host "    4  Antigravity         local, sin tunel           :3003"
  Write-Host "    5  Antigravity remoto  tunel compartido + Bearer  :3001"
  Write-Host "    6  Verificar entorno"
  Write-Host "    7  Detener todo"
  Write-Host "    0  Salir"
  Write-Host ""
}

function Install-TunnelAiSkills {
  param([string]$Carpeta)
  $instalador = Join-Path $PSScriptRoot 'Agregar-Skill.ps1'
  Write-Host ""
  Write-Info "Instalando las 15 skills en $Carpeta ..."
  & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $instalador -Skill todas -Ruta $Carpeta -Silencioso
  if ($LASTEXITCODE -ne 0) { Write-Warn "El instalador de skills termino con codigo $LASTEXITCODE." }
  else { Write-Ok "Skills instaladas: la IA las vera por el tunel (list_files)." }
}

function Invoke-TunnelAiOpcion {
  param([string]$op, [string]$Carpeta, [bool]$Skills)

  switch ($op) {
    '1' {
      if ($Skills) { Install-TunnelAiSkills -Carpeta $Carpeta }
      Start-TunnelAiSession -Cliente ChatGPT -Ruta $Carpeta -MaxMinutos $MaxMinutos
    }
    '2' {
      if ($Skills) { Install-TunnelAiSkills -Carpeta $Carpeta }
      Start-TunnelAiRemoteSession -Ruta $Carpeta -Proveedor 'tailscale' -Desatacado:(-not $Ventana)
    }
    '3' {
      if ($Skills) { Install-TunnelAiSkills -Carpeta $Carpeta }
      Start-TunnelAiSession -Cliente Claude -Ruta $Carpeta -MaxMinutos $MaxMinutos
    }
    '4' {
      if ($Skills) { Install-TunnelAiSkills -Carpeta $Carpeta }
      Start-TunnelAiSession -Cliente Antigravity -Ruta $Carpeta -Token $Token
    }
    '5' {
      if ($Skills) { Install-TunnelAiSkills -Carpeta $Carpeta }
      Start-TunnelAiSession -Cliente AntigravityRemoto -Ruta $Carpeta -Token $Token -MaxMinutos $MaxMinutos
    }
    '6' {
      & $pwshExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verificar-Entorno.ps1')
    }
    '7' {
      & $pwshExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Limpiar-Bloqueo.ps1')
    }
    default {
      Write-Warn "Opcion no valida: $op"
      return $false
    }
  }
  return $true
}

$carpeta = Read-TunnelAiRuta -Ruta $Ruta
$skillsOn = -not $SinSkills

# Non-interactive: run the requested option once and exit (scripts, shortcuts, tests).
if ($Opcion) {
  $ok = Invoke-TunnelAiOpcion -op $Opcion.Trim() -Carpeta $carpeta -Skills $skillsOn
  if (-not $ok) { exit 2 }
  exit 0
}

while ($true) {
  Show-TunnelAiMenu -Carpeta $carpeta -Skills $skillsOn
  $op = (Read-Host "  Opcion").Trim().ToLower()

  if ($op -in '0', 'q', 'salir') { break }
  if ($op -in 'c', 'carpeta') { $carpeta = Read-TunnelAiRuta -Ruta ''; continue }
  if ($op -in 's', 'skills') { $skillsOn = -not $skillsOn; continue }

  $null = Invoke-TunnelAiOpcion -op $op -Carpeta $carpeta -Skills $skillsOn
}

Write-Host ""
Write-Info "Hasta luego."
