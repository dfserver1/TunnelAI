#!/usr/bin/env pwsh
# Iniciar-Gemini.ps1 — MCP tunnel launcher for GEMINI (gemini.google.com, web and mobile)
# Uses the same server and tunnel as ChatGPT (port 3001): both can use the same URL.
# Usage: double-click Iniciar-Gemini.cmd — asks for the folder; everything else is automatic.
# Parameters: -Ruta <folder>  ·  -MaxMinutos <n> (tunnel auto-close)  ·  -SinTunel (local only)

param([string]$Ruta, [int]$MaxMinutos = 0, [switch]$SinTunel)

$ErrorActionPreference = "Stop"

# Import of the shared module with retry (OneDrive can lock the file for an instant)
$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "✗ No pude cargar lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Pulsa Enter"; exit 1 }; Start-Sleep 2 }
}

Start-TunnelAiSession -Cliente Gemini -Ruta $Ruta -MaxMinutos $MaxMinutos -SinTunel:$SinTunel
