#!/usr/bin/env pwsh
<#
  Monitor-TunnelAI.ps1 — SENTINEL for TunnelAI sessions
  It probes every N seconds and repairs the MINIMUM without killing the tunnel:
    · hung commands (server child shells older than -MaxEdadComandoSeg) -> kills ONLY those
    · giant logs                                                                        -> rotation
    · bottlenecks (latency, memory)                                                      -> warns, kills nothing
    · server down for 2 cycles (-AutoRecuperar)                                          -> restarts ONLY the server; tunnel and URL survive
    · cloudflared down (-AutoRecuperar)                                                  -> restarts ONLY cloudflared (the URL changes; it warns)
  It NEVER kills global node/dotnet processes or other ports. It closes by itself when the tunnel window closes (-ProcesoPadre).
#>

param(
  [int]$Puerto = 3001,
  [ValidateSet('chatgpt-local-mcp','expose-files-mcp')][string]$Servidor = 'chatgpt-local-mcp',
  [string]$Etiqueta = "TA-monitor",
  [int]$IntervaloSeg = 20,
  [int]$MaxEdadComandoSeg = 180,
  [int]$MaxLogMB = 15,
  [switch]$AutoRecuperar,
  [switch]$AutoTest,
  [int]$ProcesoPadre = 0
)

$raiz = $PSScriptRoot

function Write-Ok($m)  { Write-Host "$(Get-Date -Format 'HH:mm:ss') ✓ $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "$(Get-Date -Format 'HH:mm:ss') › $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "$(Get-Date -Format 'HH:mm:ss') ⚠ $m" -ForegroundColor Yellow }
function Write-Err2($m){ Write-Host "$(Get-Date -Format 'HH:mm:ss') ✗ $m" -ForegroundColor Red }

# ── own helpers (the sentinel doesn't depend on the module: its startup can never fail) ──
function Get-PortOwnerPids {
  param([int]$Puerto)
  try {
    Get-NetTCPConnection -LocalPort $Puerto -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty OwningProcess -Unique
  } catch { @() }
}

function Read-WebResponseBody {
  param($Response)
  try {
    $stream = $Response.GetResponseStream()
    if (-not $stream) { return '' }
    $reader = New-Object System.IO.StreamReader($stream)
    $txt = $reader.ReadToEnd()
    $reader.Close()
    return $txt
  } catch { return '' }
}

# ── MCP latency probe ──────────────────────────────────────────────────────────
function Measure-McpLatencia {
  param([int]$Puerto, [int]$TimeoutSeg = 8)
  $body = "{`"jsonrpc`":`"2.0`",`"id`":1,`"method`":`"initialize`",`"params`":{`"protocolVersion`":`"2025-03-26`",`"capabilities`":{},`"clientInfo`":{`"name`":`"TunnelAI-Vigia`",`"version`":`"1.0`"}}}"
  $headers = @{Accept='application/json, text/event-stream'}
  if ($env:AI_PC_MCP_TOKEN) { $headers['Authorization'] = "Bearer $env:AI_PC_MCP_TOKEN" }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:${Puerto}/mcp" -Method Post -Body $body `
      -ContentType 'application/json' -Headers $headers `
      -UseBasicParsing -TimeoutSeg $TimeoutSeg
    $sw.Stop()
    if ("$($r.Content)" -match '"protocolVersion"') { return @{ Ok=$true; Ms=[int]$sw.ElapsedMilliseconds } }
  } catch {
    $sw.Stop()
    $resp = $_.Exception.Response
    if ($resp) {
      $txt = Read-WebResponseBody $resp
      if ($txt -match '"protocolVersion"') { return @{ Ok=$true; Ms=[int]$sw.ElapsedMilliseconds } }
    }
  }
  return @{ Ok=$false; Ms=-1 }
}

function Get-CloudflaredExe {
  # the sentinel is a separate process: cloudflared is NOT in its PATH — it must be located
  $c = Get-Command cloudflared -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in @(
    (Join-Path $raiz 'bin\cloudflared.exe'),
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\bin\cloudflared.exe')
  )) { if (Test-Path -LiteralPath $p) { return $p } }
  return $null
}

function Get-CloudflaredPuerto {
  param([int]$Puerto)
  # WARNING! 'trycloudflare' does NOT appear in the command line: the marker is 'tunnel --url http://…:PORT'
  Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and $_.CommandLine -match 'tunnel\s+--url' -and
      ($_.CommandLine -match "localhost:$Puerto" -or $_.CommandLine -match "127\.0\.0\.1:$Puerto")
    } | Select-Object -First 1
}

function Get-RutaRecordada {
  $f = Join-Path $raiz '.ultima_ruta.txt'
  if (Test-Path -LiteralPath $f) {
    $r = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue).Trim()
    if ($r -and (Test-Path -LiteralPath $r)) { return $r }
  }
  return $env:USERPROFILE
}

# ── installation detection: NEVER killed, no matter what ──────────────────────
# Deliberately conservative policy: if it looks like an install/build, it is left to FINISH.
# It's better to leave a process alive than to kill the AI's build.
$NOMBRES_INSTALADOR = @('npm','npx','yarn','pnpm','node','dotnet','winget','msiexec','pip','cargo','go','deno','bun','tsc')
$MARCADORES_INSTALADOR = 'npm-cli\.js|npm\s+(i|install|ci|run|start|update|audit)|npx|yarn|pnpm|dotnet\s+(restore|build|publish|tool|add|new)|winget|pip\s+install|cargo\s+(build|install|update)|go\s+(build|get|install|mod)|deno|bun\s+(install|i|add)|tsc|Installing|Restoring|Downloading|Resolving|acquiring\s+lock|added\s+\d+\s+packages?'

$SHELL_HIJOS = @('powershell','pwsh','cmd','python','py','git','dotnet','npm','npx','node','yarn','pnpm','cargo','go','deno','bun','winget','tsc')

function Test-EsInstalacion {
  param($Proc)
  if ($null -eq $Proc) { return $false }
  # Win32_Process returns 'cmd.exe'; normalize without the extension
  $nombre = ("$($Proc.Name)") -replace '\.exe$',''
  $cmd = "$($Proc.CommandLine)"
  # by executable name
  if ($NOMBRES_INSTALADOR -contains $nombre) { return $true }
  # by markers in the command line (npm install, dotnet restore, winget…)
  if ($cmd -and $cmd -match $MARCADORES_INSTALADOR) { return $true }
  return $false
}

# ── banner ────────────────────────────────────────────────────────────────────
$hostExe = 'pwsh'
try { $p = Get-Process -Id $PID -ErrorAction Stop; if ($p.Path) { $hostExe = $p.Path } } catch {}
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { $hostExe = 'powershell' }

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        TunnelAI sentinel — watching :$Puerto           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Info "Server: $Servidor · probe every ${IntervaloSeg}s · auto-recovery: $(if ($AutoRecuperar) { 'YES' } else { 'no' })"
Write-Info "Hung commands > ${MaxEdadComandoSeg}s are killed (only them). Logs > ${MaxLogMB}MB are rotated."
Write-Info "Installations (npm/npx/dotnet/winget/pip/yarn/tsc…) are NEVER killed: they are left to finish."

$hijosPropios = @()
$urlPendiente = $null
$caidos = 0
$ciclo = 0
$reparaciones = 0
$script:AnunciadosInstalacion = @{}

# ── self-test: validates the detection logic without starting the loop ─────────
if ($AutoTest) {
  function NuevoProc([string]$n, [string]$c, [int]$edadSeg) {
    [pscustomobject]@{ Name = $n; CommandLine = $c; CreationDate = (Get-Date).AddSeconds(-$edadSeg) }
  }
  $casos = @(
    @{ Proc = (NuevoProc 'node.exe' 'node C:\...\npm\node_modules\npm\bin\npm-cli.js install express' 900); Instala = $true;  Desc = 'npm install (node.exe)' }
    @{ Proc = (NuevoProc 'pwsh.exe' 'pwsh -NoProfile -Command npm install' 45);                          Instala = $true;  Desc = 'pwsh -> npm install' }
    @{ Proc = (NuevoProc 'dotnet.exe' 'dotnet restore' 400);                                             Instala = $true;  Desc = 'dotnet restore' }
    @{ Proc = (NuevoProc 'winget.exe' 'winget install Microsoft.DotNet.SDK.8' 600);                      Instala = $true;  Desc = 'winget install' }
    @{ Proc = (NuevoProc 'python.exe' 'pip install requests' 300);                                       Instala = $true;  Desc = 'pip install' }
    @{ Proc = (NuevoProc 'node.exe' 'node build-server.js' 900);                                         Instala = $true;  Desc = 'node child (conservative: not killed)' }
    @{ Proc = (NuevoProc 'pwsh.exe' 'pwsh -Command npm run build' 900);                                  Instala = $true;  Desc = 'npm run build' }
    @{ Proc = (NuevoProc 'pwsh.exe' 'pwsh -Command dir' 900);                                            Instala = $false; Desc = 'dir hung 900s (IS killed)' }
    @{ Proc = (NuevoProc 'git.exe' 'git status' 900);                                                    Instala = $false; Desc = 'git status hung (IS killed)' }
    @{ Proc = (NuevoProc 'cmd.exe' 'cmd /c ping -t' 900);                                                Instala = $false; Desc = 'ping hung (IS killed)' }
    @{ Proc = (NuevoProc 'cmd.exe' 'cmd /c dotnet build' 900);                                           Instala = $true;  Desc = 'cmd -> dotnet build (marker)' }
  )
  Write-Host "── Self-test: installation detection ──" -ForegroundColor Cyan
  $fallos = 0
  foreach ($c in $casos) {
    $r = Test-EsInstalacion -Proc $c.Proc
    $ok = ($r -eq $c.Instala)
    if (-not $ok) { $fallos++ }
    Write-Host ("  {0} {1,-42} -> {2}" -f $(if ($ok) { '✓' } else { '✗' }), $c.Desc, $(if ($r) { 'installation (not killed)' } else { 'killable (killed)' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  }
  Write-Host ""
  if ($fallos -eq 0) { Write-Ok "Self-test OK ($($casos.Count) cases)" } else { Write-Err2 "Self-test with $fallos failure(s)" }
  return
}

try {
  while ($true) {
    $ciclo++

    # 0) if the tunnel window closed, the sentinel exits (leaves nothing behind)
    if ($ProcesoPadre -gt 0) {
      $vivo = $false
      try { Get-Process -Id $ProcesoPadre -ErrorAction Stop | Out-Null; $vivo = $true } catch {}
      if (-not $vivo) { Write-Info "The tunnel window closed — the sentinel exits."; break }
    }

    # 1) server children: installations (NEVER killed) vs hung commands
    $instalaciones = @()
    $srvPids = @(Get-PortOwnerPids -Puerto $Puerto)
    if ($srvPids.Count -gt 0) {
      $srvPid = $srvPids[0]
      $proc = Get-Process -Id $srvPid -ErrorAction SilentlyContinue
      if ($proc) {
        $rssMB = [int]($proc.WorkingSet64 / 1MB)
        if ($rssMB -gt 800) { Write-Warn "Server memory: ${rssMB}MB (check the root: maybe it's scanning huge folders)" }
      }
      $hijos = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ParentProcessId -eq $srvPid -and $SHELL_HIJOS -contains (($_.Name) -replace '\.exe$','') }
      $limite = (Get-Date).AddSeconds(-$MaxEdadComandoSeg)
      foreach ($h in $hijos) {
        try {
          $edad = (Get-Date) - $h.CreationDate
          if (Test-EsInstalacion -Proc $h) {
            # installation in progress: it is left to FINISH, never flagged or killed
            $clave = "$($h.Name):$($h.ProcessId)"
            $instalaciones += $h.Name
            $antes = $script:AnunciadosInstalacion[$clave]
            if ((-not $antes) -or ((Get-Date) - $antes).TotalSeconds -ge 300) {
              Write-Info "Installation in progress: $($h.Name) (PID $($h.ProcessId), running $([int]$edad.TotalSeconds)s) — letting it finish, NOT killed"
              $script:AnunciadosInstalacion[$clave] = Get-Date
            }
            continue
          }
          if ($h.CreationDate -lt $limite) {
            Write-Warn "Hung command $($h.Name) (PID $($h.ProcessId), $([int]$edad.TotalSeconds)s) — killing ONLY that process"
            Stop-Process -Id $h.ProcessId -Force -ErrorAction SilentlyContinue
            $reparaciones++
          }
        } catch {}
      }
    }

    # 2) MCP probe
    $m = Measure-McpLatencia -Puerto $Puerto
    if ($m.Ok) {
      $caidos = 0
      $extra = if ($instalaciones.Count -gt 0) { " · installing: $($instalaciones.Count)" } else { '' }
      if ($m.Ms -gt 5000) {
        if ($instalaciones.Count -gt 0) { Write-Info "MCP OK · slow: $($m.Ms) ms (installation/build in progress — normal, untouched)" }
        else { Write-Warn "High latency: $($m.Ms) ms — bottleneck (long build? huge search?)" }
      }
      elseif ($m.Ms -gt 1500) { Write-Info "MCP OK · slow: $($m.Ms) ms$extra" }
      else                    { Write-Ok "MCP OK · $($m.Ms) ms$extra" }
    } else {
      $caidos++
      Write-Warn "MCP not responding (cycle $caidos/2)"
      if ($AutoRecuperar -and $caidos -ge 2) {
        $root = Get-RutaRecordada
        $cf = Get-CloudflaredPuerto -Puerto $Puerto
        $conTunel = (-not $cf)
        Write-Warn "Restarting ONLY the server (tunnel $(if ($conTunel) { 'also down: a new one will be created' } else { 'and URL preserved' }))..."
        try {
          $out = Join-Path $env:TEMP "tunnelai-vigia-$Puerto.out"
          if ($Servidor -eq 'chatgpt-local-mcp') {
            $cmdInner = if ($conTunel) { "Set-Location -LiteralPath '$root'; & chatgpt-local-mcp --log" }
                        else           { "Set-Location -LiteralPath '$root'; & chatgpt-local-mcp --no-tunnel --log" }
          } else {
            $allowed = 'python,python3,py,pip,pip3,node,npm,npx,pnpm,yarn,dotnet,winget,git,cargo,rustup,go,deno,bun,tsc,make,cmake,powershell,pwsh,cmd,dir,ls,cat,type,echo,where,tar,unzip,7z,curl,wget,msiexec'
            $cmdInner = "& expose-files-mcp --transport http --host 127.0.0.1 --port $Puerto --root '$root' --files read-write --terminal true --shell pwsh --timeout-ms 30000 --allowed-commands $allowed"
            if ($conTunel) { $cmdInner += " --public true --provider cloudflared --no-auth true" }
          }
          $proc = Start-Process -FilePath $hostExe `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $cmdInner) `
            -WorkingDirectory $raiz -WindowStyle Hidden -RedirectStandardOutput $out -PassThru
          $hijosPropios += $proc.Id
          $reparaciones++
          if ($conTunel) { $urlPendiente = $out }
          Write-Ok "Server relaunched (PID $($proc.Id)). Watching recovery..."
        } catch { Write-Err2 "Couldn't relaunch the server: $($_.Exception.Message)" }
        $caidos = 0
      }
    }

    # 2b) if we started a new tunnel, announce the new URL
    if ($urlPendiente -and (Test-Path -LiteralPath $urlPendiente)) {
      $txt = Get-Content -LiteralPath $urlPendiente -Raw -ErrorAction SilentlyContinue
      if ($txt -and $txt -match '(https://[a-zA-Z0-9-]+\.trycloudflare\.com)') {
        Write-Warn "NEW URL (update your connector): $($Matches[1])/mcp"
        $urlPendiente = $null
      }
    }

    # 3) tunnel alive (children were already inspected in step 1)
    if ($m.Ok) {
      if (-not (Get-CloudflaredPuerto -Puerto $Puerto)) {
        if ($AutoRecuperar) {
          $cfExe = Get-CloudflaredExe
          if (-not $cfExe) {
            Write-Err2 "cloudflared is down and I can't find it to relaunch it (missing TunnelAI\bin\cloudflared.exe?)"
          } else {
            Write-Warn "cloudflared tunnel down — relaunching ONLY cloudflared (the URL will change)..."
            try {
              $out = Join-Path $env:TEMP "tunnelai-vigia-cf-$Puerto.out"
              $proc = Start-Process -FilePath $cfExe `
                -ArgumentList @('tunnel','--url',"http://127.0.0.1:$Puerto",'--no-autoupdate') `
                -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError "$out.err" -PassThru
              $hijosPropios += $proc.Id
              $reparaciones++
              $urlPendiente = $out
              Write-Ok "cloudflared relaunched (PID $($proc.Id))."
            } catch { Write-Err2 "Couldn't relaunch cloudflared: $($_.Exception.Message)" }
          }
        } else {
          Write-Warn "cloudflared tunnel not found for port $Puerto"
        }
      }
    }

    # 4) rotation of giant logs
    foreach ($lg in @("$env:USERPROFILE\.chatgpt-local-mcp\logs\server.log", "$env:USERPROFILE\.chatgpt-local-mcp\logs\cloudflared.log")) {
      if (Test-Path -LiteralPath $lg) {
        try {
          $mb = (Get-Item -LiteralPath $lg).Length / 1MB
          if ($mb -gt $MaxLogMB) {
            $dest = "$lg.1"
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $lg -Destination $dest -Force -ErrorAction Stop
            Write-Ok "Log rotated: $([System.IO.Path]::GetFileName($lg)) (${mb}MB -> .1)"
          }
        } catch { Write-Info "Couldn't rotate $([System.IO.Path]::GetFileName($lg)) (in use); will retry next cycle" }
      }
    }

    Start-Sleep -Seconds $IntervaloSeg
  }
} finally {
  # the sentinel cleans up ONLY what it started itself
  foreach ($id in $hijosPropios) { try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch {} }
  if ($hijosPropios.Count -gt 0) { Write-Info "Processes started by the sentinel closed ($($hijosPropios.Count))." }
  Write-Info "Sentinel stopped. Repairs this session: $reparaciones."
}
