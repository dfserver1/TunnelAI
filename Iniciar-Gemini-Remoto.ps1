#!/usr/bin/env pwsh
# Iniciar-Gemini-Remoto.ps1 - Gemini over a reliable streaming tunnel (ngrok / Tailscale Funnel).
# Why not the others:
#   * Cloudflare quick tunnels buffer SSE responses until they end -> Gemini never gets the
#     `endpoint` frame and aborts after ~10 s with "context canceled".
#   * localhost.run answers 200 to you but 502 to everyone else, Google included, so Gemini
#     reports "The MCP server could not be reached. Check the URL."
# Usage: Iniciar-Gemini-Remoto.cmd [-Proveedor ngrok|tailscale] [-Dominio mi-dominio.ngrok-free.app]
param(
  [string]$Ruta,
  [ValidateSet('ngrok','tailscale','localhost')][string]$Proveedor = 'tailscale',
  [string]$Dominio = '',
  [int]$MaxMinutos = 0,
  [switch]$Desatacado
)

$ErrorActionPreference = "Stop"
$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "No pude cargar el modulo: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Pulsa Enter"; exit 1 }; Start-Sleep 2 }
}

Start-TunnelAiRemoteSession -Ruta $Ruta -Proveedor $Proveedor -Dominio $Dominio -MaxMinutos $MaxMinutos -Desatacado:$Desatacado
