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
    # SSH tunnel (the one Gemini needs: Cloudflare quick tunnels cannot stream SSE)
    (Join-Path $env:TEMP 'tunnelai-ssh-3001.log'),
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\logs\cloudflared.log'),
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\logs\server.log')
  )
  foreach ($lg in $logs) {
    if (Test-Path -LiteralPath $lg) {
      $candidatos = Select-String -LiteralPath $lg -Pattern '(https://[a-zA-Z0-9][a-zA-Z0-9\-]{2,}(\.[a-zA-Z0-9\-]+)+)' -AllMatches |
                  ForEach-Object { $_.Matches } |
                  Where-Object { $_.Value -notmatch 'localhost\.run|localhost:|127\.0\.0\.1|example|docs' }
      $m = $candidatos | Select-Object -Last 1
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
  $sshVivo = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'ssh.exe' -and $_.CommandLine -and $_.CommandLine -match 'localhost\.run|serveo|localhost\.me' })
  if ($cfVivo.Count -eq 0 -and $sshVivo.Count -eq 0) {
    Write-Warn "No active tunnel detected — this URL belongs to a CLOSED session (the log keeps the last one)."
    Write-Warn "Run Iniciar-Gemini-SSH.cmd and try again to get the live URL."
    Read-Host "Press Enter" | Out-Null; exit 1
  }
  if ($Url -match 'trycloudflare') {
    Write-Ok "Active tunnel detected (Cloudflare quick tunnel)."
    Write-Warn "Cloudflare quick tunnels BUFFER streaming responses: Gemini speaks SSE and will"
    Write-Warn "never get the 'endpoint' frame (it gives up after ~10 s with 'context canceled')."
    Write-Warn "For Gemini use Iniciar-Gemini-SSH.cmd instead — it streams in real time."
  } else {
    Write-Ok "Active tunnel detected (SSH, streaming) — the right one for Gemini."
  }
}

$hdr = @{ Accept = 'application/json, text/event-stream'; 'MCP-Protocol-Version' = '2025-03-26' }
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"gemini-web","version":"1.0"}}}'


# ── SSE handshake: what Gemini ACTUALLY does (GET /mcp, waits for `event: endpoint`) ──
Write-Host ""
Write-Host "── SSE handshake (Gemini's transport) ──" -ForegroundColor Cyan
$okSse = $false
$curlOkSse = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
$BaseSse = ($Url -replace '/mcp/?$', '').TrimEnd('/')
if (-not $curlOkSse) {
  Write-Warn "curl.exe not found — skipping the SSE check."
} else {
  $sseOut = Join-Path $env:TEMP "tunnelai-sse-check.txt"
  Remove-Item -LiteralPath $sseOut -ErrorAction SilentlyContinue
  $sp = Start-Process -FilePath (Get-Command curl.exe).Source -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $sseOut `
    -ArgumentList @('-sN', '--max-time', '12', '-H', 'Accept: text/event-stream', "$BaseSse/mcp")
  Start-Sleep -Seconds 5
  $cabecera = Get-Content -LiteralPath $sseOut -Raw -ErrorAction SilentlyContinue
  $bytes = if ($cabecera) { $cabecera.Length } else { 0 }
  try { Stop-Process -Id $sp.Id -Force -ErrorAction SilentlyContinue } catch {}
  if ($cabecera -match 'event: endpoint' -and $cabecera -match 'sessionId=') {
    Write-Ok "GET /mcp -> 'event: endpoint' received ($bytes bytes)"
    $okSse = $true
  } elseif ($bytes -eq 0) {
    Write-Err2 "GET /mcp -> 0 bytes: the tunnel is buffering the SSE stream."
    Write-Err2 "Cloudflare quick tunnels do this by design: they forward the body only when"
    Write-Err2 "the response ENDS, so Gemini never sees 'endpoint' and aborts after ~10 s."
    Write-Info "Fix: start Iniciar-Gemini-SSH.cmd (real streaming tunnel)."
  } else {
    Write-Err2 "GET /mcp -> $bytes bytes but no 'event: endpoint' frame."
  }
}$okInit = $false; $okTools = $false
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

# ── OAuth 2.1 handshake: exactly what Gemini performs when you click "Connect" ──
Write-Host ""
Write-Host "── OAuth 2.1 handshake (the flow Gemini runs internally) ──" -ForegroundColor Cyan
$Base = ($Url -replace '/mcp/?$', '').TrimEnd('/')
$curlOk = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
$okOAuth = $false

if (-not $curlOk) {
  Write-Warn "curl.exe not found — skipping the redirect steps (discovery is still checked)."
}

function Curl([string[]]$CurlArgs) { ((& curl.exe -s -i --max-time 30 @CurlArgs 2>&1) -join "`n") }
function Partir([string]$Raw) {
  $i = $Raw.IndexOf("`n`n")
  if ($i -lt 0) { return @{ Head = $Raw; Body = '' } }
  return @{ Head = $Raw.Substring(0, $i); Body = $Raw.Substring($i + 2) }
}
function Codigo([string]$Head) { if ($Head -match 'HTTP/\S+\s+(\d{3})') { return [int]$Matches[1] }; 0 }
function Campo([string]$Body, [string]$Nombre) { if ($Body -match ('"' + $Nombre + '"\s*:\s*"([^"]+)"')) { return $Matches[1] }; $null }

# 1 + 2: discovery
$r = Partir (Curl @("$Base/.well-known/oauth-protected-resource"))
if ((Codigo $r.Head) -eq 200 -and $r.Body -match '"authorization_servers"') {
  Write-Ok "protected-resource    -> 200 (RFC 9728)"
  $r2 = Partir (Curl @("$Base/.well-known/oauth-authorization-server"))
  if ((Codigo $r2.Head) -eq 200 -and $r2.Body -match '"registration_endpoint"') {
    Write-Ok "authorization-server  -> 200 with /register, /authorize, /token"
  } else {
    Write-Err2 "authorization-server  -> $(Codigo $r2.Head) (OAuth metadata missing)"
  }
} else {
  Write-Err2 "protected-resource    -> $(Codigo $r.Head) (Gemini will refuse to connect)"
}

if ($curlOk) {
  # 3: dynamic client registration
  $regJson = '{"client_name":"gemini-web","redirect_uris":["https://gemini.google.com/auth/callback"],"grant_types":["authorization_code"],"response_types":["code"],"token_endpoint_auth_method":"client_secret_post"}'
  $r = Partir (Curl @('-X','POST','-H','Content-Type: application/json','-d',$regJson,"$Base/register"))
  $clientId = Campo $r.Body 'client_id'
  $clientSecret = Campo $r.Body 'client_secret'
  if ($clientId) { Write-Ok "register (DCR)         -> $(Codigo $r.Head) client_id=$clientId" }
  else { Write-Err2 "register (DCR)         -> $(Codigo $r.Head) (no client_id)" }

  if ($clientId) {
    # PKCE pair
    $verifier  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))).TrimEnd('=').Replace('+','-').Replace('/','_')
    $challenge = [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier))).TrimEnd('=').Replace('+','-').Replace('/','_')
    $redirect  = 'https://gemini.google.com/auth/callback'
    $state     = 'st-' + [guid]::NewGuid().ToString('N').Substring(0, 10)

    # 4: consent screen
    $authUrl = "$Base/authorize?response_type=code&client_id=$([uri]::EscapeDataString($clientId))&redirect_uri=$([uri]::EscapeDataString($redirect))&scope=mcp&state=$state&code_challenge=$challenge&code_challenge_method=S256"
    $r = Partir (Curl @($authUrl))
    if ($r.Body -match 'I understand') { Write-Ok "authorize (consent)    -> 200 with the consent screen" }
    else { Write-Err2 "authorize (consent)    -> $(Codigo $r.Head) (no consent screen)" }

    # 5: user consents -> 302 with the code
    $form = "response_type=code&client_id=$([uri]::EscapeDataString($clientId))&redirect_uri=$([uri]::EscapeDataString($redirect))&scope=mcp&state=$state&code_challenge=$challenge&code_challenge_method=S256"
    $r = Partir (Curl @('-X','POST','-H','Content-Type: application/x-www-form-urlencoded','-d',$form,"$Base/authorize"))
    $code = $null
    if ($r.Head -match '(?im)^Location:\s*(\S+)') {
      if ($Matches[1] -match 'code=([^&]+)') { $code = [uri]::UnescapeDataString($Matches[1]) }
      Write-Ok "POST /authorize        -> $(Codigo $r.Head) with code + state"
    } else { Write-Err2 "POST /authorize        -> $(Codigo $r.Head) without redirect" }

    # 6: token exchange
    if ($code) {
      $tokForm = "grant_type=authorization_code&code=$([uri]::EscapeDataString($code))&redirect_uri=$([uri]::EscapeDataString($redirect))&client_id=$([uri]::EscapeDataString($clientId))&code_verifier=$verifier"
      if ($clientSecret) { $tokForm += "&client_secret=$([uri]::EscapeDataString($clientSecret))" }
      $r = Partir (Curl @('-X','POST','-H','Content-Type: application/x-www-form-urlencoded','-d',$tokForm,"$Base/token"))
      $token = Campo $r.Body 'access_token'
      if ($token) {
        Write-Ok "POST /token            -> 200 access_token issued"
        # 7: MCP call with that token (what Gemini does after connecting)
        $rh = @('-X','POST','-H','Content-Type: application/json','-H','Accept: application/json, text/event-stream','-H',"Authorization: Bearer $token",'-d',$init,"$Base/mcp")
        $r = Partir (Curl @($rh))
        if ((Codigo $r.Head) -eq 200 -and $r.Body -match 'protocolVersion') {
          Write-Ok "initialize (Bearer)    -> 200 — Gemini can use the tools"
          $okOAuth = $true
        } else { Write-Err2 "initialize (Bearer)    -> $(Codigo $r.Head)" }
      } else { Write-Err2 "POST /token            -> $(Codigo $r.Head) $($r.Body)" }
    }
  }
}
if ($okInit -and $okTools -and $okOAuth -and $okSse) {
  Write-Ok "RESULT: the tunnel is Gemini-ready (MCP + OAuth 2.1 + SSE). If Google still refuses, the blocker is on their side (see the checklist)."
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
Write-Host "   1. Keep Iniciar-Gemini-SSH.cmd running (Gemini needs a streaming tunnel)"
Write-Host "   2. gemini.google.com -> Settings -> Connected Apps -> Custom apps -> Add"
Write-Host "   3. Paste: $Url"
Write-Host "   4. Open your Gem (e.g. Argon) and enable the connected app in its tools/settings"
Write-Host ""
Write-Info "If 'Custom apps' does not appear for you, it's a plan/region limitation, not the tunnel."
Read-Host "Press Enter" | Out-Null
