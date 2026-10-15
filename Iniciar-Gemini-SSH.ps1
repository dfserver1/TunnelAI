#!/usr/bin/env pwsh
# Iniciar-Gemini-SSH.ps1 - MCP tunnel launcher for GEMINI over an SSH tunnel.
# Gemini web speaks the legacy HTTP+SSE transport, which needs a REAL streaming tunnel:
# Cloudflare quick tunnels buffer SSE responses until they end, so Gemini never receives
# the `endpoint` frame and gives up after ~10 s ("context canceled"). SSH streams fine.
# Usage: double-click Iniciar-Gemini-SSH.cmd - asks for the folder; everything else is automatic.
# Parameters: -Ruta <folder>  ·  -MaxMinutos <n>  ·  -HostTunel <host> (default localhost.run)

param([string]$Ruta, [int]$MaxMinutos = 0, [string]$HostTunel = 'localhost.run')

$ErrorActionPreference = "Stop"

$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "No pude cargar lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Pulsa Enter"; exit 1 }; Start-Sleep 2 }
}

Start-TunnelAiSshSession -Ruta $Ruta -MaxMinutos $MaxMinutos -HostTunel $HostTunel
