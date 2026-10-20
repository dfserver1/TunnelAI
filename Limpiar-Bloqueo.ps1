#!/usr/bin/env pwsh
# Limpiar-Bloqueo.ps1 — frees the tunnel ports (3001/3002/3003) and closes quick cloudflared tunnels.
# SAFE by design: it only kills TUNNEL processes. It never kills global node/dotnet.
# Usage:
#   .\Limpiar-Bloqueo.ps1                      # frees 3001/3002/3003 + quick tunnels
#   .\Limpiar-Bloqueo.ps1 -Puertos 3001
#   .\Limpiar-Bloqueo.ps1 -IncluirNodeDotnet   # brute mode: asks for written confirmation

param(
  [int[]]$Puertos = @(3001, 3002, 3003),
  [switch]$IncluirNodeDotnet
)

$ErrorActionPreference = "SilentlyContinue"
$modulo = Join-Path $PSScriptRoot 'lib\TunnelAI.Common.psm1'
for ($i = 1; $i -le 3; $i++) {
  try { Import-Module -Name $modulo -Force -Global -ErrorAction Stop; break }
  catch { if ($i -eq 3) { Write-Host "✗ Couldn't load lib\TunnelAI.Common.psm1. Pause OneDrive for a moment and retry." -ForegroundColor Red; Read-Host "Press Enter"; exit 1 }; Start-Sleep 2 }
}

Write-Host "Clearing tunnel channels (ports: $($Puertos -join ', '))..." -ForegroundColor Cyan

foreach ($p in $Puertos) {
  $pids = @(Get-TunnelAiPortPids -Puerto $p)
  if ($pids.Count -gt 0) {
    Write-Host "  Port $p busy (PID $($pids -join ', ')) — freeing" -ForegroundColor Yellow
    # Stop-TunnelAiServidor also kills the launcher (otherwise the watchdog restarts the server)
    Stop-TunnelAiServidor -Puerto $p | Out-Null
  } else {
    Write-Host "  Port $p free" -ForegroundColor DarkGray
  }
}

$cf = 0
# quick tunnels = 'cloudflared tunnel --url …' (the word trycloudflare does NOT appear in the command line)
Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'tunnel\s+--url' } |
  ForEach-Object { $cf++; Stop-Process -Id $_.ProcessId -Force }
if ($cf -gt 0) { Write-Host "  $cf cloudflared tunnel(s) closed" -ForegroundColor Yellow }

# sentinels could revive the server: they are closed as well
$vig = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'Monitor-TunnelAI' })
foreach ($v in $vig) {
  Write-Host "  Closing sentinel (PID $($v.ProcessId))" -ForegroundColor Yellow
  try { Stop-Process -Id $v.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

# Tailscale Funnel (Gemini): turn it off only when it points at one of our ports
$ts = Resolve-TunnelAiBin -Nombre tailscale
if ($ts) {
  $funnel = (& $ts funnel status 2>&1) -join ' '
  if ($funnel -match 'Funnel on' -and $funnel -match '127\.0\.0\.1:300[123]') {
    (& $ts funnel --https=443 off 2>&1) | Out-Null
    Write-Host "  Tailscale Funnel closed" -ForegroundColor Yellow
  }
}

if ($IncluirNodeDotnet) {
  Write-Warn "BRUTE MODE: this closes ALL node and dotnet processes in your session (may affect your work)."
  $ok = Read-Host "Type SI to continue"
  if ($ok -eq 'SI') {
    Get-Process node, dotnet -ErrorAction SilentlyContinue | ForEach-Object {
      Write-Host "  killing PID $($_.Id) $($_.ProcessName)" -ForegroundColor DarkGray
      Stop-Process -Id $_.Id -Force
    }
    Start-Sleep 2
    Write-Ok "node/dotnet processes closed."
  } else {
    Write-Info "Cancelled. Only the tunnel ports were freed."
  }
}

Write-Host ""
Write-Ok "Done. Tunnel channels clear."
Write-Info "If a file is still locked (EPERM when deleting bin/obj), close VS/Rider and retry."
Read-Host "Press Enter" | Out-Null
