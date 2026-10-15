#!/usr/bin/env pwsh
# Verificar-Entorno.ps1 — generic diagnostics of the TunnelAI environment (no other-PC paths)
# Checks: PowerShell, Node 18+, npm, git (optional), cloudflared, MCP packages and ports.

Write-Host "=== TunnelAI environment check ===" -ForegroundColor Cyan
Write-Host "Clients: ChatGPT (3001) · Claude (3002) · Gemini (3001) · Antigravity (3003, local)" -ForegroundColor DarkGray
Write-Host ""

$script:TunnelAIRoot = $PSScriptRoot
$ok = $true

function Test-Cmd($name, $cmd) {
  try {
    $v = & $cmd 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -eq 0 -or $v) { Write-Host "✓ $name $v" -ForegroundColor Green; return $true }
    throw
  } catch { Write-Host "✗ $name not found" -ForegroundColor Yellow; return $false }
}

$okNode = Test-Cmd "Node" { node --version }
$okNpm  = Test-Cmd "npm"  { npm --version }
$okGit  = Test-Cmd "Git"  { git --version }
if (-not $okGit) {
  Write-Host "   (Git is optional: if you don't use it, ignore the 'not a git repository' error)" -ForegroundColor DarkGray
}

# cloudflared (portable in TunnelAI\bin or in ~/.chatgpt-local-mcp\bin)
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cf) {
  foreach ($c in @(
    (Join-Path $script:TunnelAIRoot "bin\cloudflared.exe"),
    (Join-Path $env:USERPROFILE ".chatgpt-local-mcp\bin\cloudflared.exe")
  )) { if (Test-Path -LiteralPath $c) { $cf = Get-Item $c; break } }
}
if ($cf) {
  $donde = if ($cf.Source) { $cf.Source } else { $cf.FullName }
  Write-Host "✓ cloudflared ($donde)" -ForegroundColor Green
} else { Write-Host "✗ cloudflared not found (the launchers download it automatically the first time)" -ForegroundColor Yellow }

# MCP packages (npm global or shim in %APPDATA%\npm)
function Resolve-Command {
  param([string]$Nombre)
  $c = Get-Command $Nombre -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $alt = Join-Path $env:APPDATA "npm\$Nombre.cmd"
  if (Test-Path -LiteralPath $alt) { return $alt }
  return $null
}
foreach ($pkg in 'chatgpt-local-mcp','expose-files-mcp') {
  $r = Resolve-Command $pkg
  if ($r) { Write-Host "✓ $pkg" -ForegroundColor Green } else { Write-Host "✗ $pkg not installed (the matching launcher installs it automatically)" -ForegroundColor Yellow }
}

# ports in use
foreach ($p in 3001,3002,3003) {
  $pids = @(Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
  if ($pids.Count -gt 0) { Write-Host "⚠ Port $p busy (PID $($pids -join ', ')) — use Limpiar-Bloqueo.cmd if it causes problems" -ForegroundColor Yellow }
  else { Write-Host "✓ Port $p free" -ForegroundColor Green }
}

# last remembered folder
$ult = Join-Path $script:TunnelAIRoot ".ultima_ruta.txt"
if (Test-Path -LiteralPath $ult) {
  $r = (Get-Content -LiteralPath $ult -Raw).Trim()
  if (Test-Path -LiteralPath $r) { Write-Host "✓ Last folder valid: $r" -ForegroundColor Green }
  else { Write-Host "⚠ Last folder no longer exists: $r" -ForegroundColor Yellow }
}

if (-not $okNode -or -not $okNpm) {
  Write-Host ""
  Write-Host "→ Install Node.js (includes npm):" -ForegroundColor Yellow
  Write-Host "  winget install OpenJS.NodeJS.LTS --silent" -ForegroundColor White
  Write-Host "  or download: https://nodejs.org (LTS)" -ForegroundColor White
  $ok = $false
}
if (-not $okGit) {
  Write-Host "→ Git (optional): winget install Git.Git --silent" -ForegroundColor Yellow
}

Write-Host ""
if ($ok) { Write-Host "Environment OK. You can use the launchers now." -ForegroundColor Green }
else { Write-Host "Node.js is missing. Install it and run this check again." -ForegroundColor Red }
Read-Host "Press Enter" | Out-Null
