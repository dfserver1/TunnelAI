#!/usr/bin/env pwsh
<#
  Iniciar-Antigravity-Remoto.ps1 — Antigravity HERE, the tunnel THERE.
  Opens the SAME tunnel used by ChatGPT/Gemini (port 3001) and points Antigravity's
  mcp_config.json at the public URL — with an optional Bearer token.
  Use it when your Antigravity runs on another machine, or you prefer the public URL.
  On the same PC? Iniciar-Antigravity.cmd (local, no tunnel) is faster and safer.

  Usage: double-click Iniciar-Antigravity-Remoto.cmd
    -Ruta <folder>   folder to expose
    -Token <key>     Bearer token (Antigravity sends headers; web connectors can't)
    -MaxMinutos <n>  auto-close
#>

param([string]$Ruta, [string]$Token = "", [int]$MaxMinutos = 0)

$ErrorActionPreference = "Stop"

# Import of the shared module with retry (OneDrive can lock the file for an instant)
$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "✗ Couldn't load lib\TunnelAI.Common.psm1: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Press Enter"; exit 1 }; Start-Sleep 2 }
}

Start-TunnelAiSession -Cliente AntigravityRemoto -Ruta $Ruta -Token $Token -MaxMinutos $MaxMinutos
