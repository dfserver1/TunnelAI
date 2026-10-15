#!/usr/bin/env pwsh
<#
  Test-Conector-Gemini.ps1 — verifies that your tunnel speaks exactly what Gemini web expects.
  It answers the question "why doesn't my Gem (Argon) connect?": our side, verified.

  Usage:
    Test-Conector-Gemini.ps1              # reuses the live tunnel (or tells you to start one)
    Test-Conector-Gemini.ps1 -Url https://xxx.trycloudflare.com/mcp
#>

param([string]$Url)

$ErrorActionPreference = "Stop"

function Write-Ok($m)  { Write-Host "✓ $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "› $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow }
function Write-Err2($m){ Write-Host "✗ $m" -ForegroundColor Red }

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      Is my tunnel Gemini-ready? (verify + guide)   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-not $Url) {
  # look for the URL of the live session in the cloudflared logs
  $logs = @(
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\logs\cloudflared.log'),
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\logs\server.log')
  )
  foreach ($lg in $logs) {
    if (Test-Path -LiteralPath $lg) {
      $m = Select-String -LiteralPath $lg -Pattern '(https://[a-zA-Z0-9-]+\.trycloudflare\.com)' -AllMatches |
           ForEach-Object { $_.Matches } | Select-Object -Last 1
      if ($m) { $Url = "$($m.Value)/mcp"; break }
    }
  }
  if (-not $Url) {
    Write-Err2 "No tunnel URL found. Run Iniciar-Gemini.cmd (or Iniciar-TunnelAI.cmd) first and try again."
    Read-Host "Press Enter" | Out-Null; exit 1
  }
  Write-Info "URL found in the logs: $Url"
  $cfVivo = @(Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'tunnel\s+--url' })
  if ($cfVivo.Count -eq 0) {
    Write-Warn "No active tunnel detected — this URL belongs to a CLOSED session (the log keeps the last one)."
    Write-Warn "Run Iniciar-Gemini.cmd and try again to get the live URL."
    Read-Host "Press Enter" | Out-Null; exit 1
  }
  Write-Info "Active tunnel detected."
}

$hdr = @{ Accept = 'application/json, text/event-stream'; 'MCP-Protocol-Version' = '2025-03-26' }
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"gemini-web","version":"1.0"}}}'

$okInit = $false; $okTools = $false
try {
  $r1 = Invoke-WebRequest -Uri $Url -Method Post -Body $init -ContentType 'application/json' -Headers $hdr -UseBasicParsing -TimeoutSec 20
  if ($r1.Content -match '"protocolVersion"') { $okInit = $true; Write-Ok "initialize           -> 200 + protocolVersion" }
  else { Write-Warn "initialize answered $($r1.StatusCode) but without protocolVersion" }
  $sid = $r1.Headers['Mcp-Session-Id']
  $hdr2 = $hdr.Clone(); if ($sid) { $hdr2['Mcp-Session-Id'] = $sid }
  $r2 = Invoke-WebRequest -Uri $Url -Method Post -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' -ContentType 'application/json' -Headers $hdr2 -UseBasicParsing -TimeoutSec 20
  $j = $r2.Content | ConvertFrom-Json
  if ($j.result.tools.Count -gt 0) { $okTools = $true; Write-Ok "tools/list            -> $($j.result.tools.Count) tools (read_file present: $([bool]($j.result.tools | Where-Object { $_.name -eq 'read_file' })))" }
} catch {
  Write-Err2 "Handshake failed: $($_.Exception.Message)"
}

Write-Host ""
if ($okInit -and $okTools) {
  Write-Ok "RESULT: the tunnel is Gemini-ready. The blocker is on Google's side (see the checklist)."
} else {
  Write-Err2 "RESULT: the tunnel does NOT answer like Gemini expects. Check that the session is still open."
}

Write-Host ""
Write-Host "── Google's requirements for Custom apps (gemini.google.com) ──" -ForegroundColor Cyan
Write-Host "   1. Personal Google account (NOT Workspace/school)"
Write-Host "   2. 18+ and located in the United States"
Write-Host "   3. 'Keep Activity' ON (Google Account -> Data & privacy) — else the option does not appear"
Write-Host "   4. Interface in English"
Write-Host "   5. Gemini Spark access (custom apps reportedly run inside Spark tasks)"
Write-Host ""
Write-Host "── Exact steps (a Gem CANNOT be connected directly) ──" -ForegroundColor Cyan
Write-Host "   The MCP link is configured at the ACCOUNT level, then used by your Gem:"
Write-Host "   1. Keep Iniciar-Gemini.cmd (or Iniciar-TunnelAI.cmd) running"
Write-Host "   2. gemini.google.com -> Settings -> Connected Apps -> Custom apps -> Add"
Write-Host "   3. Paste: $Url"
Write-Host "   4. Open your Gem (e.g. Argon) and enable the connected app in its tools/settings"
Write-Host ""
Write-Info "If 'Custom apps' does not appear for you, it's a plan/region limitation, not the tunnel."
Read-Host "Press Enter" | Out-Null
