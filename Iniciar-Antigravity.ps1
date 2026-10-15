#!/usr/bin/env pwsh
# Iniciar-Antigravity.ps1 — connects GOOGLE ANTIGRAVITY to your PC, LOCALLY (no cloudflared tunnel)
# It writes the 'tunnelai' server into ~/.gemini/antigravity/mcp_config.json pointing to http://localhost:3003/mcp
# Advantages: nothing leaves the machine, no public URL, lower latency.
# Usage: double-click Iniciar-Antigravity.cmd. The window must stay open while you use Antigravity.
# Parameters: -Ruta <folder>  ·  -Puerto <n>  ·  -Token <key> (Bearer)  ·  -Detener (stops our local server only)

param([string]$Ruta, [int]$Puerto = 3003, [string]$Token = "", [switch]$Detener)

$ErrorActionPreference = "Stop"

# Import of the shared module with retry (OneDrive can lock the file for an instant)
$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "✗ No pude cargar lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Pulsa Enter"; exit 1 }; Start-Sleep 2 }
}

if ($Detener) {
  Stop-TunnelAiServidor -Puerto $Puerto -PatronServidor 'chatgpt-local-mcp'
  Write-Host ""
  Write-Ok "Servidor Antigravity detenido (puerto $Puerto)."
  Read-Host "Pulsa Enter" | Out-Null
  exit 0
}

Start-TunnelAiSession -Cliente Antigravity -Ruta $Ruta -Puerto $Puerto -Token $Token
