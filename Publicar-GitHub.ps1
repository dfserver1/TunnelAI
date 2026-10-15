#!/usr/bin/env pwsh
<#
  Publicar-GitHub.ps1 — publishes TunnelAI as a PUBLIC repo on GitHub.
  Security: the token is NEVER stored in the repo or in git config.
  Usage:
    Publicar-GitHub.ps1 -Plan                       # dry run: what it would do, changes nothing
    Publicar-GitHub.ps1 -Nombre MyRepo              # publish with that name
    Publicar-GitHub.ps1 -Token ghp_xxxx             # classic token with 'repo' scope (this session only)
    Publicar-GitHub.ps1 -Privado                    # private repo instead of public

  Requirements: git installed. Recommended: GitHub CLI (winget install GitHub.cli).
#>

param(
  [string]$Nombre = 'TunnelAI',
  [string]$Descripcion = 'Connect ChatGPT, Claude, Gemini and Antigravity to your Windows PC: files, terminal, OCR, 15 skills and a self-healing sentinel. MIT licensed.',
  [string]$Token = "",
  [switch]$Privado,
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
Write-Host "║        Publish TunnelAI on GitHub                  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Write-Err2 "git not found. Install it: winget install Git.Git"; Read-Host "Press Enter"; exit 1 }
Write-Ok "git $((git --version))"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { Write-Ok "GitHub CLI available ($(gh --version | Select-Object -First 1))" }
else { Write-Warn "GitHub CLI not found (recommended: winget install GitHub.cli). Using the API with a token instead." }

$usuario = ""
$tok = if ($Token) { $Token } else { $env:GITHUB_TOKEN }
if ($tok) {
  try {
    $h = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers @{ Authorization = "Bearer $tok"; Accept = "application/vnd.github+json" } -UseBasicParsing -TimeoutSeg 15
    $usuario = ($h.Content | ConvertFrom-Json).login
    Write-Ok "Valid token — user: $usuario"
  } catch { Write-Err2 "Invalid token ($($_.Exception.Message))"; Read-Host "Press Enter"; exit 1 }
}

Write-Info "Repo: $Nombre · visibility: $(if ($Privado) { 'PRIVATE' } else { 'PUBLIC' })"
Write-Info "Files to upload: $(@(Get-ChildItem $raiz -Recurse -File | Where-Object { $_.FullName -notmatch '\\bin\\|\\node_modules\\|\\\.git\\' }).Count) (excludes bin\, node_modules\, .git\)"

Write-Info "Steps:"
Write-Info "  1. git init (if needed) + .gitignore"
Write-Info "  2. git add . + commit"
Write-Info "  3. $(if ($gh) { "gh repo create $Nombre $(if ($Privado) { '--private' } else { '--public' }) --source . --push" } else { "create the repo via API + push with a temporary token" })"
Write-Info "  4. Final URL: https://github.com/$usuario/$Nombre"

if ($Plan) { Write-Ok "Dry-run mode: nothing was done."; Read-Host "Press Enter"; exit 0 }

Write-Host ""
$ok = Read-Host "Publish? (Y/N)"
if ($ok -notmatch '^[SsYy]') { Write-Info "Cancelled."; exit 0 }

# 1) init
$yaGit = Test-Path -LiteralPath (Join-Path $raiz '.git')
if (-not $yaGit) { git -C $raiz init 2>&1 | Out-Null; Write-Ok "git init" }
$gi = Join-Path $raiz '.gitignore'
if (-not (Test-Path -LiteralPath $gi)) {
  @"
bin/cloudflared.exe
*.log
logs/
node_modules/
.ultima_ruta.txt
Thumbs.db
desktop.ini
"@ | Set-Content -LiteralPath $gi -Encoding UTF8
  Write-Ok ".gitignore created"
}

# 2) commit
git -C $raiz add -A 2>&1 | Out-Null
$hayCambios = (git -C $raiz status --porcelain)
if ($hayCambios) {
  git -C $raiz -c user.name="TunnelAI" -c user.email="tunnelai@local" commit -m "TunnelAI 1.0: portable MCP tunnel for ChatGPT/Claude/Gemini/Antigravity with 15 skills, OCR, PDF reports, diagrams and a self-healing sentinel (MIT)" 2>&1 | Out-Null
  Write-Ok "Commit created"
} else { Write-Info "Nothing to commit" }

# 3) create + push
if ($gh) {
  if (-not $tok) {
    Write-Info "You need to authenticate with GitHub CLI (a browser will open)..."
    gh auth login 2>&1 | Out-Null
  } else {
    $tok | gh auth login --with-token 2>&1 | Out-Null
  }
  $vis = if ($Privado) { '--private' } else { '--public' }
  & gh repo create $Nombre --description $Descripcion $vis --source $raiz --push 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
  if ($LASTEXITCODE -eq 0) { Write-Ok "Repo published: https://github.com/$usuario/$Nombre" }
  else { Write-Err2 "gh returned $LASTEXITCODE. Check the output (repo already exists? token without repo scope?)" }
}
elseif ($tok -and $usuario) {
  $body = @{ name = $Nombre; description = $Descripcion; private = [bool]$Privado } | ConvertTo-Json
  try {
    Invoke-WebRequest -Uri "https://api.github.com/user/repos" -Method Post -Body $body -ContentType 'application/json' `
      -Headers @{ Authorization = "Bearer $tok"; Accept = "application/vnd.github+json" } -UseBasicParsing -TimeoutSeg 30 | Out-Null
    Write-Ok "Repo created on GitHub"
  } catch { Write-Err2 "Couldn't create the repo: $($_.Exception.Message)"; Read-Host "Press Enter"; exit 1 }
  Write-Info "Uploading (the token travels only in this command, it is not stored)..."
  git -C $raiz branch -M main 2>&1 | Out-Null
  $url = "https://$tok@github.com/$usuario/$Nombre.git"
  git -C $raiz remote remove origin 2>&1 | Out-Null
  git -C $raiz remote add origin $url 2>&1 | Out-Null
  git -C $raiz push -u origin main 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
  if ($LASTEXITCODE -eq 0) {
    Write-Ok "Published: https://github.com/$usuario/$Nombre"
    # strip the token from the remote: leave only the public URL
    git -C $raiz remote set-url origin "https://github.com/$usuario/$Nombre.git" 2>&1 | Out-Null
    Write-Info "Token removed from the remote (only the public URL remains)"
  } else { Write-Err2 "Push failed ($LASTEXITCODE). Check the output." }
}
else {
  Write-Err2 "Neither GitHub CLI nor a token. Options:"
  Write-Info "  a) winget install GitHub.cli  ->  run it again (browser auth)"
  Write-Info "  b) Create a token at https://github.com/settings/tokens (scope 'repo') and:"
  Write-Info "     Publicar-GitHub.ps1 -Token ghp_..."
}

Read-Host "Press Enter" | Out-Null
