#!/usr/bin/env pwsh
# Iniciar-Claude.ps1 — MCP tunnel launcher for CLAUDE (expose-files-mcp)
# Usage: double-click Iniciar-Claude.cmd — asks for the folder; everything else is automatic.
# Parameters: -Ruta <folder>  ·  -MaxMinutos <n> (tunnel auto-close)  ·  -SinTunel (local only)

param([string]$Ruta, [int]$MaxMinutos = 0)

$ErrorActionPreference = "Stop"

# Import of the shared module with retry (OneDrive can lock the file for an instant)
$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "✗ No pude cargar lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Pulsa Enter"; exit 1 }; Start-Sleep 2 }
}

Start-TunnelAiSession -Cliente Claude -Ruta $Ruta -MaxMinutos $MaxMinutos
