#!/usr/bin/env pwsh
<#
  Config-Tunel-Estable.ps1 — sets up a NAMED Cloudflare tunnel (permanent stable URL).
  Requirements: a FREE Cloudflare account + a domain pointing to Cloudflare (NS).

  Usage:
    Config-Tunel-Estable.ps1 -Plan                 # dry run: shows what it would do, changes nothing
    Config-Tunel-Estable.ps1                       # interactive (walks you through it)
    Config-Tunel-Estable.ps1 -Hostname mcp.mydomain.com

  What it does:
    1) Checks cloudflared is installed and you're logged in (cert.pem)
    2) Creates the 'tunnelai' tunnel (or reuses the existing one)
    3) Creates the DNS route mcp.yourdomain.com -> tunnel
    4) Writes ~/.cloudflared/config.yml pointing to http://127.0.0.1:3001
    5) Tells you how to start it: Iniciar-Tunel-Nombrado.cmd + Iniciar-TunnelAI.cmd -SinTunel
#>

param(
  [string]$Hostname,
  [string]$Nombre = 'tunnelai',
  [int]$Puerto = 3001,
  [switch]$Plan
)

$ErrorActionPreference = "Continue"
$raiz = $PSScriptRoot

function Write-Ok($m)  { Write-Host "✓ $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "› $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow }
function Write-Err2($m){ Write-Host "✗ $m" -ForegroundColor Red }

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     TunnelAI — Named tunnel (stable URL)           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cf) {
  foreach ($c in @((Join-Path $raiz 'bin\cloudflared.exe'), (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\bin\cloudflared.exe'))) {
    if (Test-Path -LiteralPath $c) { $env:PATH = "$(Split-Path -Parent $c);$env:PATH"; $cf = Get-Item $c; break }
  }
}
if (-not $cf) { Write-Err2 "cloudflared not found. Run any Iniciar-*.cmd first (it downloads it automatically)."; Read-Host "Press Enter"; exit 1 }

$cert = Join-Path $env:USERPROFILE '.cloudflared\cert.pem'
$loginOk = Test-Path -LiteralPath $cert
$cfg = Join-Path $env:USERPROFILE '.cloudflared\config.yml'

Write-Info "cloudflared: $(if ($cf.Source) { $cf.Source } else { $cf.FullName })"
Write-Info "Cloudflare login: $(if ($loginOk) { 'OK (cert.pem found)' } else { 'NO — login required' })"

# existing tunnels
$existentes = @()
if ($loginOk) {
  $lista = & cloudflared tunnel list 2>$null
  if ($lista) {
    foreach ($l in $lista) { if ($l -match "^([0-9a-f\-]{36})\s+(\S+)") { $existentes += @{ Uuid = $Matches[1]; Nombre = $Matches[2] } } }
  }
}
if ($existentes.Count -gt 0) { Write-Info "Existing tunnels: $(($existentes | ForEach-Object { $_.Nombre }) -join ', ')" }
else { Write-Info "Existing tunnels: none" }

if (-not $Hostname) {
  Write-Host ""
  Write-Host "  Type the hostname that will point to your PC (it must be on a domain you have in Cloudflare):" -ForegroundColor White
  Write-Host "  Example: mcp.mydomain.com" -ForegroundColor DarkGray
  $Hostname = (Read-Host "Hostname").Trim()
}
if (-not $Hostname) { Write-Err2 "Hostname is required."; Read-Host "Press Enter"; exit 1 }

Write-Host ""
Write-Info "Plan:"
Write-Info "  1. $(if ($loginOk) { 'Already logged in' } else { 'cloudflared tunnel login (a browser will open)' })"
Write-Info "  2. Create/reuse tunnel '$Nombre'"
Write-Info "  3. cloudflared tunnel route dns $Nombre $Hostname"
Write-Info "  4. Write $cfg with ingress -> http://127.0.0.1:$Puerto"
Write-Info "  5. Final stable URL: https://$Hostname/mcp"

if ($Plan) {
  Write-Host ""
  Write-Ok "Dry-run mode: nothing was changed. Run it without -Plan to apply."
  Read-Host "Press Enter" | Out-Null
  return
}

Write-Host ""
$ok = Read-Host "Continue? (Y/N)"
if ($ok -notmatch '^[SsYy]') { Write-Info "Cancelled."; Read-Host "Press Enter"; exit 0 }

# 1) login if needed
if (-not $loginOk) {
  Write-Info "Opening the browser to authorize Cloudflare (free, you just need an account)..."
  & cloudflared tunnel login
  Start-Sleep 2
  if (-not (Test-Path -LiteralPath $cert)) { Write-Err2 "Login not completed ($cert missing)."; Read-Host "Press Enter"; exit 1 }
  Write-Ok "Login correct"
}

# 2) create tunnel
$uuid = ($existentes | Where-Object { $_.Nombre -eq $Nombre } | Select-Object -First 1).Uuid
if (-not $uuid) {
  Write-Info "Creating tunnel '$Nombre'..."
  & cloudflared tunnel create $Nombre 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
  $existentes = @()
  $lista = & cloudflared tunnel list 2>$null
  if ($lista) { foreach ($l in $lista) { if ($l -match "^([0-9a-f\-]{36})\s+$Nombre") { $existentes += @{ Uuid = $Matches[1]; Nombre = $Nombre } } } }
  $uuid = ($existentes | Select-Object -First 1).Uuid
}
if (-not $uuid) { Write-Err2 "Couldn't get the tunnel UUID. Check the cloudflared output."; Read-Host "Press Enter"; exit 1 }
Write-Ok "Tunnel '$Nombre' (UUID $uuid)"

# 3) DNS route
Write-Info "Creating DNS route $Hostname -> tunnel..."
& cloudflared tunnel route dns $Nombre $Hostname 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
if ($LASTEXITCODE -eq 0) { Write-Ok "DNS route created (may take a few minutes to propagate)" }
else { Write-Warn "cloudflared returned $LASTEXITCODE (the route may already exist — not a problem)" }

# 4) config.yml
$credFiles = @(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.cloudflared') -Filter "$uuid.json" -ErrorAction SilentlyContinue)
$cred = if ($credFiles.Count) { $credFiles[0].FullName } else { Join-Path $env:USERPROFILE ".cloudflared\$uuid.json" }
$yml = @"
tunnel: $uuid
credentials-file: $cred

ingress:
  - hostname: $Hostname
    service: http://127.0.0.1:$Puerto
  - service: http_status:404
"@
New-Item -ItemType Directory -Path (Split-Path -Parent $cfg) -Force | Out-Null
$yml | Set-Content -LiteralPath $cfg -Encoding UTF8
Write-Ok "Config written: $cfg"

# 5) runner
$runner = Join-Path $raiz 'Iniciar-Tunel-Nombrado.cmd'
@"
@echo off
REM Iniciar-Tunel-Nombrado.cmd — named Cloudflare tunnel (stable URL) — generated by Config-Tunel-Estable.ps1
cloudflared tunnel run $Nombre
echo.
echo Tunnel closed.
pause
"@ | Set-Content -LiteralPath $runner -Encoding ASCII
Write-Ok "Runner created: Iniciar-Tunel-Nombrado.cmd"

Write-Host ""
Write-Host "── How to use it ────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  1. `Iniciar-Tunel-Nombrado.cmd`   (keep this window open: it's the tunnel)" -ForegroundColor White
Write-Host "  2. `Iniciar-TunnelAI.cmd -SinTunel` (starts the local MCP WITHOUT a quick tunnel)" -ForegroundColor White
Write-Host "     - Antigravity needs none of this: use Iniciar-Antigravity.cmd" -ForegroundColor DarkGray
Write-Host "  3. In ChatGPT/Claude/Gemini paste: https://$Hostname/mcp" -ForegroundColor White
Write-Host "     - The advantage: this URL NEVER changes between runs" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Note: the hostname takes 1-5 min to propagate the first time." -ForegroundColor DarkGray
Read-Host "Press Enter" | Out-Null
