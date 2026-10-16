#!/usr/bin/env pwsh
# Iniciar-Gemini.ps1 - MCP launcher for GEMINI (gemini.google.com, web and mobile).
#
# Runs DETACHED: double-click, read the URL, close the window. Everything keeps
# working (tunnel inside the Tailscale service, MCP server and sentinel hidden).
#
# Why this tunnel:
#   * Cloudflare quick tunnels buffer streaming responses until they end, so the
#     SSE frame Gemini waits for never arrives (it aborts after ~10 s).
#   * localhost.run answers 200 to you and 502 to everyone else, Google included.
#   * ngrok's free tier serves a browser-warning page instead of the MCP endpoint.
#   * Tailscale Funnel streams in real time, needs no interstitial and keeps a
#     stable URL. Measured: https://<pc>.<tailnet>.ts.net/mcp
#
# Usage:  Iniciar-Gemini.cmd [-Ruta <folder>] [-Ventana]
#   -Ruta    folder to expose to the AI (prompted if omitted)
#   -Ventana keep this window open to watch the session instead of detaching
# Stop everything: Limpiar-Bloqueo.cmd
param([string]$Ruta, [switch]$Ventana)

$ErrorActionPreference = "Stop"

$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch {
    if ($i -eq 3) { Write-Host "No pude cargar lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Pulsa Enter"; exit 1 }
    Start-Sleep 2
  }
}

Start-TunnelAiRemoteSession -Ruta $Ruta -Proveedor 'tailscale' -Desatacado:(-not $Ventana)
