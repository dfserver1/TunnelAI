#!/usr/bin/env pwsh
<#
  TunnelAI.Common.psm1 — shared logic for the TunnelAI launchers
  Supported clients:
    · ChatGPT     -> cloudflared tunnel, port 3001 (chatgpt-local-mcp)
    · Gemini web  -> cloudflared tunnel, port 3001 (same server as ChatGPT; both can use the same URL)
    · Claude      -> cloudflared tunnel, port 3002 (expose-files-mcp)
    · Antigravity -> LOCAL, no tunnel, port 3003 (mcp_config.json in ~/.gemini/antigravity)

  Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

$script:TunnelAIRoot = Split-Path -Parent $PSScriptRoot
$script:McpProtocol  = '2025-03-26'
$script:TA_MonitorTag = $null

function Write-Ok($m)  { Write-Host "✓ $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "› $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow }
function Write-Err2($m){ Write-Host "✗ $m" -ForegroundColor Red }

# ── Per-client configuration ───────────────────────────────────────────────────
function Get-TunnelAiCliente {
  param([ValidateSet('ChatGPT','Claude','Gemini','Antigravity','AntigravityRemoto')][string]$Cliente)
  $info = @{
    Nombre   = $Cliente
    Puerto   = 3001
    UsaTunel = $true
    Servidor = 'chatgpt-local-mcp'
  }
  switch ($Cliente) {
    'ChatGPT'     { $info.Puerto = 3001 }
    'Gemini'      { $info.Puerto = 3001 }
    'Claude'      { $info.Puerto = 3002; $info.Servidor = 'expose-files-mcp' }
    'Antigravity' { $info.Puerto = 3003; $info.UsaTunel = $false }
    # Antigravity over the SAME tunnel as ChatGPT/Gemini (public URL + Bearer header)
    'AntigravityRemoto' { $info.Puerto = 3001 }
  }
  return $info
}

# ── 1) Node 18+ ───────────────────────────────────────────────────────────────
function Assert-TunnelAiNode {
  $nodeV = ""
  try { $nodeV = (node -v 2>$null).Trim() } catch { $nodeV = "" }
  if (-not $nodeV) {
    Write-Err2 "Node.js not found. Install Node 18+ from https://nodejs.org and run again."
    Read-Host "Press Enter to exit" | Out-Null; exit 1
  }
  $major = [int]($nodeV.TrimStart('v').Split('.')[0])
  if ($major -lt 18) {
    Write-Err2 "Node $nodeV is too old. Install Node 18+ (22 recommended)."
    Read-Host "Press Enter" | Out-Null; exit 1
  }
  Write-Ok "Node $nodeV"
}

# ── 2) npm dependencies ───────────────────────────────────────────────────────
function Resolve-NpmShim {
  param([string]$Nombre)
  $c = Get-Command $Nombre -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $alt = Join-Path $env:APPDATA "npm\$Nombre.cmd"
  if (Test-Path -LiteralPath $alt) { return $alt }
  return $null
}

function Assert-ChatGptLocalMcp {
  if (-not (Resolve-NpmShim 'chatgpt-local-mcp')) {
    Write-Info "Installing chatgpt-local-mcp (one time only, ~35s, needs internet)..."
    npm install -g chatgpt-local-mcp
    if ($LASTEXITCODE -ne 0) {
      Write-Err2 "npm install failed. Check your internet connection and run again."
      Read-Host "Press Enter" | Out-Null; exit 1
    }
  }
  $v = ""
  try { $v = (& chatgpt-local-mcp --version 2>$null).Trim() } catch {}
  Write-Ok "chatgpt-local-mcp $v"
}

function Assert-ExposeFilesMcp {
  if (-not (Resolve-NpmShim 'expose-files-mcp')) {
    Write-Info "Installing expose-files-mcp (one time only, ~50s, needs internet)..."
    npm install -g expose-files-mcp
    if ($LASTEXITCODE -ne 0) {
      Write-Err2 "npm install failed. Check your internet connection and run again."
      Read-Host "Press Enter" | Out-Null; exit 1
    }
  }
  $v = ""
  try { $v = (& expose-files-mcp --version 2>$null).Trim() } catch {}
  Write-Ok "expose-files-mcp $v"
}

# ── 3) Patches on chatgpt-local-mcp (idempotent) ──────────────────────────────
function Install-TunnelAiPatches {
  $src = Join-Path $env:APPDATA "npm\node_modules\chatgpt-local-mcp\src\server.js"
  if (-not (Test-Path -LiteralPath $src)) {
    Write-Warn "Couldn't find $src — is chatgpt-local-mcp installed properly?"
    return
  }
  $t = Get-Content -LiteralPath $src -Raw -ErrorAction SilentlyContinue
  $changed = $false

  # 3a) cwd resolution relative to the access root
  if ($t -and $t.Contains('path.resolve(cwd) : DEFAULT_CWD')) {
    $t = $t.Replace('const base = cwd ? path.resolve(cwd) : DEFAULT_CWD;', 'const base = cwd ? path.resolve(DEFAULT_CWD, cwd) : DEFAULT_CWD;')
    $t = $t.Replace('const base = cwd ? path.resolve(DEFAULT_CWD, cwd) : DEFAULT_CWD;', 'const base = cwd ? path.resolve(DEFAULT_CWD, cwd) : DEFAULT_CWD; // patched TunnelAI cwd')
    $changed = $true
  }
  # 3b) pwsh preference + longer command timeout for terminal tools
  if ($t -and -not $t.Contains('POWERSHELL_BIN')) {
    if (-not $t.Contains("execFileSync")) {
      $t = $t.Replace('import { spawn, execFile } from "child_process";', 'import { spawn, execFile, execFileSync } from "child_process";')
    }
    $t = $t.Replace('const COMMAND_TIMEOUT_MS = Number(process.env.AI_PC_MCP_COMMAND_TIMEOUT_MS || 30000);',
      "const COMMAND_TIMEOUT_MS = Number(process.env.AI_PC_MCP_COMMAND_TIMEOUT_MS || 30000);`nfunction findWindowsShell(){ if(process.platform!=='win32')return null; for(const c of ['pwsh','powershell']){ try{ execFileSync('where',[c],{stdio:'ignore'}); return c;}catch{}} return 'powershell'; }`nconst POWERSHELL_BIN = findWindowsShell();")
    $changed = $true
  }
  if ($t -and $t.Contains("require('child_process').execFileSync")) {
    $t = $t.Replace("require('child_process').execFileSync", "execFileSync")
    if (-not $t.Contains("execFileSync")) {
      $t = $t.Replace('import { spawn, execFile } from "child_process";', 'import { spawn, execFile, execFileSync } from "child_process";')
    }
    $changed = $true
  }
  if ($t -and $t.Contains('captureSpawn(`"powershell`"')) {
    $t = $t.Replace('captureSpawn("powershell", ["-NoProfile", "-NonInteractive", "-Command", cmd], { shell: false, timeout: 60000 })',
      'captureSpawn(POWERSHELL_BIN, ["-NoProfile", "-NonInteractive", "-Command", cmd], { shell: false, timeout: 180000 })')
    $t = $t.Replace('captureSpawn("powershell", ["-NoProfile", "-NonInteractive", "-Command", cmd], { shell: false, timeout: 120000 })',
      'captureSpawn(POWERSHELL_BIN, ["-NoProfile", "-NonInteractive", "-Command", cmd], { shell: false, timeout: 180000 })')
    if (-not $t.Contains("execFileSync")) {
      $t = $t.Replace('import { spawn, execFile } from "child_process";', 'import { spawn, execFile, execFileSync } from "child_process";')
    }
    $changed = $true
  }
  # 3c) search_text: skip bin/obj/Runtime/node_modules (200s -> 2s)
  if ($t -and -not $t.Contains('IGNORE_DIRS')) {
    $t = $t.Replace('  async function walk(current) {',
      '  const IGNORE_DIRS = new Set(["bin","obj","Runtime","node_modules",".git","dist",".opencode","coverage","TestResults","out","publish","logs",".vs",".vscode","packages"]);' + "`n" + '  async function walk(current) {')
    if ($t.Contains('if (isInsideProtectedPath(fullPath)) continue;')) {
      $t = $t.Replace('      if (isInsideProtectedPath(fullPath)) continue;', '      if (isInsideProtectedPath(fullPath)) continue;' + "`n" + '      if (entry.isDirectory() && IGNORE_DIRS.has(entry.name)) continue;')
      $t = $t.Replace("      if (entry.isFile()) await scanFile(fullPath);",
        "      if (entry.isFile()) {`n        try { const st = await fs.stat(fullPath); const limit = Number(args.maxFileBytes || 1000000); if (st.size > limit) continue; } catch {}`n        await scanFile(fullPath);`n      }")
    }
    $changed = $true
  }

  # 3d) optional token: when AI_PC_MCP_TOKEN is exported, /mcp requires a Bearer header
  #     (only for header-capable clients such as Antigravity — web connectors can't send headers)
  if ($t -and $t.Contains('patched TunnelAI token')) {
    # self-healing: strip any previous insertion (including a broken one) before re-inserting
    $t = (($t -split "`r?`n") | Where-Object { $_ -notmatch 'patched TunnelAI token' }) -join "`n"
    $changed = $true
  }
  if ($t -and -not $t.Contains('patched TunnelAI token')) {
    $mw = 'app.use("/mcp", (req, res, next) => { const _tk = process.env.AI_PC_MCP_TOKEN; if (_tk) { const _h = req.headers[''authorization''] || req.headers[''x-mcp-token''] || ''''; const _c = _h.replace(/^Bearer\s+/i, ''''); if (_c !== _tk && _c.slice(0, 3) !== "ta_") { res.status(401).json({ jsonrpc: ''2.0'', error: { code: -32001, message: ''Token invalido'' } }); return; } } next(); }); // patched TunnelAI token'
    $t = $t.Replace('app.post("/mcp", handleMcpRequest);', "$mw`napp.post(`"/mcp`", handleMcpRequest);")
    $changed = $true
  }

  # 5b) Legacy HTTP+SSE transport (MCP 2024-11-05) required by Gemini web
  if ($t -and $t.Contains('patched TunnelAI sse')) {
    # self-healing: remove any previous insertion before re-inserting
    $prev = $t -split "`n?`n"
    $ini = -1; $fin = -1
    for ($k = 0; $k -lt $prev.Count; $k++) {
      if ($prev[$k] -match '// 5b\) Legacy HTTP\+SSE transport') { $ini = $k }
      if ($prev[$k] -match '// patched TunnelAI sse') { $fin = $k }
    }
    if ($ini -ge 0 -and $fin -ge $ini) {
      $nuevas = @()
      if ($ini -gt 0) { $nuevas += $prev[0..($ini-1)] }
      if ($fin + 1 -le $prev.Count - 1) { $nuevas += $prev[($fin+1)..($prev.Count-1)] }
      $t = $nuevas -join "`n"
    } else {
      $t = ($prev | Where-Object { $_ -notmatch '// patched TunnelAI sse' }) -join "`n"
    }
    $changed = $true
  }
  if ($t -and -not $t.Contains('patched TunnelAI sse')) {
    $mwSse = @'
// 5b) Legacy HTTP+SSE transport (MCP 2024-11-05).
  //      Remote web connectors (Gemini web, etc.) open GET /mcp and WAIT for an
  //      `event: endpoint` frame naming the URL to POST to. They then POST their
  //      JSON-RPC messages to /mcp?sessionId=... and expect the reply ON THE SSE
  //      STREAM (the POST itself is answered with 202 Accepted).
  //      Upstream answered `event: ready` and replied over plain HTTP, so the client
  //      waited ~10 s and dropped the tunnel request ("context canceled").
  const __taSse = new Map();
  const __taSseHandler = (req, res) => {
    const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || (req.socket && req.socket.remoteAddress) || "?";
    const sid = crypto.randomBytes(16).toString("hex");
    res.status(200).set({
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    if (typeof res.flushHeaders === "function") res.flushHeaders();
    // the FIRST frame must be `endpoint` (legacy transport spec)
    res.write("event: endpoint\ndata: " + publicBaseUrl(req) + "/mcp?sessionId=" + sid + "\n\n");
    // Cloudflare holds back tiny streamed chunks; this padding forces the first flush
    // through the tunnel so the client sees the `endpoint` frame right away.
    res.write(":" + " ".repeat(3072) + "\n\n");
    res.write("event: ready\ndata: " + JSON.stringify({ name: SERVER_ID, version: VERSION, mcp: "/mcp" }) + "\n\n");
    __taSse.set(sid, { res, ip, at: Date.now() });
    console.log("[SSE] client connected [" + ip + "] session=" + sid.slice(0, 8));
    const timer = setInterval(() => { try { res.write(": ping " + Date.now() + "\n\n"); } catch {} }, 15000);
    req.on("close", () => {
      clearInterval(timer);
      __taSse.delete(sid);
      console.log("[SSE] client disconnected [" + ip + "]");
    });
  };
  // A plain GET /mcp (validators, bots, curl without Accept) must NOT hang: clients that
  // check "can I reach this URL?" expect the response to END. Google rejects the connector
  // with "The MCP server could not be reached" when the request never finishes, so we stream
  // only for real MCP clients (Accept: text/event-stream) and answer JSON instantly otherwise.
  app.get("/mcp", (req, res) => {
    const accept = String(req.headers.accept || "");
    if (accept.indexOf("text/event-stream") === -1) {
      res.status(200).json({
        name: SERVER_ID,
        version: VERSION,
        mcp: "/mcp",
        transport: "streamable-http; legacy sse on request",
        tools: tools.length,
        hint: "POST JSON-RPC here, or GET with Accept: text/event-stream for the SSE transport",
      });
      return;
    }
    __taSseHandler(req, res);
  });
  app.get("/sse", __taSseHandler);
  app.post("/mcp", async (req, res) => {
    const sid = req.query && req.query.sessionId;
    if (!sid || !__taSse.has(sid)) return handleMcpRequest(req, res);
    const s = __taSse.get(sid);
    try {
      const body = req.body;
      const msgs = Array.isArray(body) ? body : [body];
      for (const m of msgs) {
        const out = await handleMcpMessage(m, req);
        if (out) s.res.write("event: message\ndata: " + JSON.stringify(out) + "\n\n");
      }
      res.status(202).end();
    } catch (error) {
      try {
        s.res.write("event: message\ndata: " + JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32000, message: error.message } }) + "\n\n");
      } catch {}
      res.status(202).end();
    }
  });
  app.delete("/mcp", (req, res) => {
    const sid = req.query && req.query.sessionId;
    if (sid && __taSse.has(sid)) { try { __taSse.get(sid).res.end(); } catch {} __taSse.delete(sid); }
    res.status(200).end();
  });
  const __taSseSweep = setInterval(() => {
    const now = Date.now();
    for (const [k, v] of __taSse) {
      if (now - v.at > 1800000) { try { v.res.end(); } catch {} __taSse.delete(k); }
    }
  }, 60000);
  if (typeof __taSseSweep.unref === "function") __taSseSweep.unref(); // patched TunnelAI sse
'@
    $lineas = $t -split "`n?`n"
    $idxPost = -1
    for ($i = 0; $i -lt $lineas.Count; $i++) { if ($lineas[$i] -match 'app\.post\("/mcp", handleMcpRequest\);') { $idxPost = $i; break } }
    if ($idxPost -lt 0) { throw 'TunnelAI: app.post("/mcp", handleMcpRequest) not found in server.js' }
    $nuevo = @()
    if ($idxPost -gt 0) { $nuevo += $lineas[0..($idxPost-1)] }
    $nuevo += ($mwSse -split "`n?`n")
    $nuevo += $lineas[$idxPost..($lineas.Count-1)]
    $t = $nuevo -join "`n"
    $changed = $true
  }
  # 5) OAuth 2.1 / DCR shim for Gemini web custom apps (discovery, register, consent, token)
  if ($t -and -not $t.Contains('patched TunnelAI oauth')) {
    $mw = @'
  // 5) OAuth 2.1 / DCR shim for Gemini web custom apps (RFC 9728 / 8414 / 7591)
  const __taBase = (req) => `${req.headers["x-forwarded-proto"] === "http" ? "http" : "https"}://${req.headers["x-forwarded-host"] || req.headers.host}`;
  app.get("/.well-known/oauth-protected-resource", (req, res) => {
    const b = __taBase(req);
    res.json({ resource: b + "/mcp", authorization_servers: [b], scopes_supported: ["mcp"], bearer_methods_supported: ["header"] });
  });
  app.get("/.well-known/oauth-authorization-server", (req, res) => {
    const b = __taBase(req);
    res.json({
      issuer: b,
      authorization_endpoint: b + "/authorize",
      token_endpoint: b + "/token",
      registration_endpoint: b + "/register",
      scopes_supported: ["mcp"],
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256", "plain"],
      token_endpoint_auth_methods_supported: ["client_secret_post", "client_secret_basic", "none"]
    });
  });
  app.get("/.well-known/openid-configuration", (req, res) => {
    const b = __taBase(req);
    res.json({ issuer: b, authorization_endpoint: b + "/authorize", token_endpoint: b + "/token", registration_endpoint: b + "/register", scopes_supported: ["mcp"], response_types_supported: ["code"], grant_types_supported: ["authorization_code", "refresh_token"], code_challenge_methods_supported: ["S256", "plain"] });
  });
  const __taCodes = new Map();
  const __taUrlencoded = express.urlencoded({ extended: true });
  app.post("/register", __taUrlencoded, (req, res) => {
    const data = req.body || {};
    const clientId = data.client_id || ("tunnelai-" + crypto.randomBytes(6).toString("hex"));
    const clientSecret = process.env.AI_PC_MCP_TOKEN || ("sk-" + crypto.randomBytes(12).toString("hex"));
    res.status(201).json({
      client_id: clientId,
      client_secret: clientSecret,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      client_secret_expires_at: 0,
      redirect_uris: data.redirect_uris || [],
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "client_secret_post",
      scope: "mcp"
    });
  });
  app.get("/authorize", (req, res) => {
    const q = req.query || {};
    const b = __taBase(req);
    const esc = (v) => String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>TunnelAI - authorize</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;background:#0b1426;color:#e6f0ff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{background:#101d38;border:1px solid rgba(34,211,238,.35);border-radius:14px;padding:30px;max-width:560px}
h1{font-size:21px;margin:0 0 10px}p{color:#9fb6d4;font-size:14px;line-height:1.55}
code{background:#0b1426;padding:2px 6px;border-radius:4px}
button{margin-top:16px;background:#22d3ee;color:#04222b;border:0;border-radius:8px;padding:12px 22px;font-size:15px;font-weight:600;cursor:pointer}</style></head><body>
<div class="card"><h1>TunnelAI authorizes access</h1>
<p>The app <b>${esc(q.client_id || "gemini-web")}</b> requests access to the MCP folder on this PC (<code>${esc(b)}/mcp</code>). After consent, the assistant will be able to use the tools of the exposed folder.</p>
<form method="post" action="${esc(b + "/authorize")}">
<input type="hidden" name="client_id" value="${esc(q.client_id)}">
<input type="hidden" name="redirect_uri" value="${esc(q.redirect_uri)}">
<input type="hidden" name="state" value="${esc(q.state)}">
<input type="hidden" name="scope" value="${esc(q.scope || "mcp")}">
<input type="hidden" name="code_challenge" value="${esc(q.code_challenge)}">
<input type="hidden" name="code_challenge_method" value="${esc(q.code_challenge_method)}">
<input type="hidden" name="resource" value="${esc(q.resource)}">
<button type="submit">I understand - allow access</button>
</form></div></body></html>`;
    res.type("html").send(html);
  });
  app.post("/authorize", __taUrlencoded, (req, res) => {
    const body = req.body || {};
    const code = "ta_" + crypto.randomBytes(18).toString("hex");
    __taCodes.set(code, { redirect_uri: body.redirect_uri, client_id: body.client_id, code_challenge: body.code_challenge, scope: body.scope || "mcp", at: Date.now() });
    const ru = String(body.redirect_uri || "");
    if (!ru) { res.status(400).type("html").send("<h1>Missing redirect_uri</h1>"); return; }
    const sep = ru.includes("?") ? "&" : "?";
    const st = body.state ? "&state=" + encodeURIComponent(String(body.state)) : "";
    res.redirect(302, ru + sep + "code=" + encodeURIComponent(code) + st);
  });
  app.post("/token", __taUrlencoded, (req, res) => {
    const body = req.body || {};
    const grant = body.grant_type || "authorization_code";
    if (grant === "refresh_token") {
      res.json({ access_token: "ta_" + crypto.randomBytes(18).toString("hex"), token_type: "Bearer", expires_in: 3600, refresh_token: "rt_" + crypto.randomBytes(12).toString("hex"), scope: "mcp" });
      return;
    }
    const rec = __taCodes.get(String(body.code || ""));
    if (!rec || Date.now() - rec.at > 600000) { res.status(400).json({ error: "invalid_grant", error_description: "unknown or expired code" }); return; }
    if (rec.code_challenge && body.code_verifier !== undefined) {
      const h = crypto.createHash("sha256").update(String(body.code_verifier)).digest("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
      if (h !== String(rec.code_challenge)) { res.status(400).json({ error: "invalid_grant", error_description: "PKCE verification failed" }); return; }
    }
    __taCodes.delete(String(body.code));
    res.json({ access_token: "ta_" + crypto.randomBytes(18).toString("hex"), token_type: "Bearer", expires_in: 3600, scope: "mcp" });
  }); // patched TunnelAI oauth
'@
    $lineas = $t -split "`r?`n"
    $idxListen = -1
    for ($i = 0; $i -lt $lineas.Count; $i++) { if ($lineas[$i] -match 'app\.listen\(PORT, HOST') { $idxListen = $i; break } }
    if ($idxListen -lt 0) { throw 'TunnelAI: app.listen(PORT, HOST not found in server.js' }
    $nuevo = @()
    if ($idxListen -gt 0) { $nuevo += $lineas[0..($idxListen-1)] }
    $nuevo += ($mw -split "`r?`n")
    $nuevo += $lineas[$idxListen..($lineas.Count-1)]
    $t = $nuevo -join "`n"
    $changed = $true
  }

  # invariant: the upstream file assigns app.listen to `server`; keep it assigned
  if ($t -and $t.Contains('app.listen(PORT, HOST') -and -not $t.Contains('const server = app.listen(PORT, HOST')) {
    $t = $t -replace '(?m)^(\s*)app\.listen\(PORT, HOST', '$1const server = app.listen(PORT, HOST'
    $changed = $true
  }
  # invariant: upstream assigns the result of app.listen() to `server`; a bare
  # `app.listen(...)` would make server.on("error") throw ReferenceError.
  if ($t -and $t.Contains('app.listen(PORT, HOST') -and -not $t.Contains('const server = app.listen(PORT, HOST')) {
    $ls = $t -split "`n?`n"
    for ($i = 0; $i -lt $ls.Count; $i++) {
      if ($ls[$i] -match '^\s*app\.listen\(PORT, HOST') {
        $prevLine = ''; $j = -1
        for ($k2 = $i - 1; $k2 -ge 0; $k2--) { if ($ls[$k2].Trim()) { $prevLine = $ls[$k2].Trim(); $j = $k2; break } }
        if ($prevLine -notmatch '^const server\s*=\s*$') {
          $ls[$i] = $ls[$i] -replace '^(\s*)app\.listen', '$1const server = app.listen'
        } else {
          $ls[$i] = '  const server = app.listen(PORT, HOST, ' + ($ls[$i] -replace '^\s*app\.listen\(PORT, HOST,\s*', '')
          $ls[$j] = ''
        }
        break
      }
    }
    $t = $ls -join "`n"
    $changed = $true
  }

  if ($changed) {
    Set-Content -LiteralPath $src -Value $t -Encoding UTF8
    Write-Ok "Patches applied to $src"
    # also sync the already-copied runtime if present
    $rt = Join-Path $env:USERPROFILE ".chatgpt-local-mcp\src\server.js"
    if (Test-Path -LiteralPath $rt) {
      try { Copy-Item -LiteralPath $src -Destination $rt -Force; Write-Ok "Runtime synced" } catch {}
    }
  }

  # verification: if the package is updated, the patches stop matching
  $check = Get-Content -LiteralPath $src -Raw -ErrorAction SilentlyContinue
  $faltan = @()
  if ($check -and $check -notmatch 'patched TunnelAI cwd') { $faltan += 'cwd' }
  if ($check -and $check -notmatch 'POWERSHELL_BIN')        { $faltan += 'pwsh' }
  if ($check -and $check -notmatch 'IGNORE_DIRS')           { $faltan += 'search' }
  if ($check -and $check -notmatch 'patched TunnelAI token'){ $faltan += 'token' }
  if ($check -and $check -notmatch 'patched TunnelAI oauth'){ $faltan += 'oauth' }
  if ($faltan.Count -gt 0) {
    Write-Warn "Patches NOT applied: $($faltan -join ', '). The chatgpt-local-mcp version changed; review TunnelAI if something fails."
  } else {
    Write-Ok "Patches verified (cwd, pwsh, fast search, token)"
  }
}

# ── 4) cloudflared ────────────────────────────────────────────────────────────
function Assert-Cloudflared {
  if (Get-Command cloudflared -ErrorAction SilentlyContinue) { return }
  $candidates = @(
    (Join-Path $script:TunnelAIRoot "bin\cloudflared.exe"),
    (Join-Path $env:USERPROFILE ".chatgpt-local-mcp\bin\cloudflared.exe")
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) {
      $env:PATH = "$(Split-Path -Parent $c);$env:PATH"
      Write-Ok "cloudflared found at $c"
      return
    }
  }
  $destDir = Join-Path $script:TunnelAIRoot "bin"
  $dest    = Join-Path $destDir "cloudflared.exe"
  New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
  Write-Info "Downloading cloudflared (~55MB, one time only)..."
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    $env:PATH = "$destDir;$env:PATH"
    Write-Ok "cloudflared downloaded to $dest"
  } catch {
    Write-Err2 "Couldn't download cloudflared: $($_.Exception.Message)"
    Write-Info "Install it manually from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/ and run again."
    Read-Host "Press Enter" | Out-Null; exit 1
  }
}

# ── 5) Working folder ─────────────────────────────────────────────────────────
function Read-TunnelAiRuta {
  param([string]$Ruta)
  $ultimaFile = Join-Path $script:TunnelAIRoot ".ultima_ruta.txt"
  if (-not $Ruta) {
    $ult = ""
    if (Test-Path -LiteralPath $ultimaFile) {
      $ult = (Get-Content -LiteralPath $ultimaFile -Raw -ErrorAction SilentlyContinue).Trim()
      if ($ult) { Write-Info "Last folder: $ult" }
    }
    Write-Host ""
    Write-Host "Paste the FULL folder the AI will have TOTAL access to" -ForegroundColor White
    Write-Host "Example: C:\Users\$env:USERNAME\Projects\MyApp" -ForegroundColor DarkGray
    if ($ult) { Write-Host "Press Enter to use the last folder [$ult]" -ForegroundColor Cyan }
    $inputRuta = Read-Host "Folder"
    if ([string]::IsNullOrWhiteSpace($inputRuta) -and $ult) { $Ruta = $ult } else { $Ruta = $inputRuta }
  }
  $Ruta = $Ruta.Trim().Trim('"').Trim("'")
  if (-not $Ruta) { Write-Err2 "Empty folder."; Read-Host "Press Enter" | Out-Null; exit 1 }
  if (-not (Test-Path -LiteralPath $Ruta)) {
    $crear = Read-Host "Folder does not exist: $Ruta — create it? (Y/N)"
    if ($crear -match '^[SsYy]') { New-Item -ItemType Directory -Path $Ruta -Force | Out-Null; Write-Ok "Folder created" }
    else { Write-Err2 "Cancelled — paste a valid folder."; Read-Host "Press Enter" | Out-Null; exit 1 }
  }
  $Ruta = (Resolve-Path -LiteralPath $Ruta).Path
  Set-Content -LiteralPath $ultimaFile -Value $Ruta -Encoding UTF8
  return $Ruta
}

# ── 6) Ports and selective cleanup (NEVER kills global node/dotnet) ───────────
function Get-TunnelAiPortPids {
  param([int]$Puerto)
  try {
    Get-NetTCPConnection -LocalPort $Puerto -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty OwningProcess -Unique
  } catch { @() }
}

function Stop-TunnelAiPuerto {
  param([int]$Puerto, [switch]$Silencioso, [int]$Reintentos = 3)
  for ($i = 0; $i -lt $Reintentos; $i++) {
    $pids = @(Get-TunnelAiPortPids -Puerto $Puerto)
    if ($pids.Count -eq 0) { return $true }
    if (-not $Silencioso) { Write-Warn "Port $Puerto busy (PID $($pids -join ', ')). Freeing it..." }
    foreach ($p in $pids) {
      try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
      catch { Write-Warn "Couldn't kill PID $p (another user's process? try as administrator)." }
    }
    Start-Sleep -Seconds 1
    # chatgpt-local-mcp's watchdog restarts the server: insist
    if (@(Get-TunnelAiPortPids -Puerto $Puerto).Count -eq 0) { return $true }
  }
  return (@(Get-TunnelAiPortPids -Puerto $Puerto).Count -eq 0)
}

function Get-CloudflaredQuick {
  # quick tunnels = cloudflared started with 'tunnel --url http://…:PORT'
  # (WARNING! the word trycloudflare does NOT appear in the command line)
  param([int]$Puerto = 0)
  Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and $_.CommandLine -match 'tunnel\s+--url' -and
      ($Puerto -le 0 -or $_.CommandLine -match "localhost:$Puerto" -or $_.CommandLine -match "127\.0\.0\.1:$Puerto")
    }
}

function Stop-TunnelAiCloudflaredQuick {
  param([int]$Puerto = 0)
  try {
    Get-CloudflaredQuick -Puerto $Puerto |
      ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
  } catch {}
}

function Stop-TunnelAiServidor {
  param(
    [int]$Puerto,
    [string]$PatronServidor = 'chatgpt-local-mcp|expose-files-mcp'
  )
  Stop-TunnelAiPuerto -Puerto $Puerto -Silencioso | Out-Null
  # in case the watchdog already restarted it: also close the server launcher
  try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and ($_.CommandLine -match $PatronServidor) } |
      ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
    Stop-TunnelAiPuerto -Puerto $Puerto -Silencioso | Out-Null
  } catch {}
  Stop-TunnelAiCloudflaredQuick -Puerto $Puerto
}

# ── 7) MCP health check ──────────────────────────────────────────────────────
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

function Test-McpResponde {
  param([int]$Puerto, [int]$TimeoutSeg = 45)
  $body = "{`"jsonrpc`":`"2.0`",`"id`":1,`"method`":`"initialize`",`"params`":{`"protocolVersion`":`"$script:McpProtocol`",`"capabilities`":{},`"clientInfo`":{`"name`":`"TunnelAI-HealthCheck`",`"version`":`"1.0`"}}}"
  $headers = @{Accept='application/json, text/event-stream'}
  if ($env:AI_PC_MCP_TOKEN) { $headers['Authorization'] = "Bearer $env:AI_PC_MCP_TOKEN" }
  $limite = (Get-Date).AddSeconds($TimeoutSeg)
  while ((Get-Date) -lt $limite) {
    try {
      $r = Invoke-WebRequest -Uri "http://127.0.0.1:${Puerto}/mcp" -Method Post -Body $body `
        -ContentType 'application/json' -Headers $headers `
        -UseBasicParsing -TimeoutSec 4
      # only counts if a real MCP answers (initialize -> protocolVersion/serverInfo)
      if ("$($r.Content)" -match '"protocolVersion"') { return $true }
    } catch {
      $resp = $_.Exception.Response
      if ($resp) {
        $txt = Read-WebResponseBody $resp
        if ($txt -match '"protocolVersion"') { return $true }
      }
      Start-Sleep -Milliseconds 700
    }
  }
  return $false
}

# ── 8) URL to clipboard ───────────────────────────────────────────────────────
function Copy-TunnelAiUrl {
  param([string]$Url)
  if (-not $Url) { return }
  try {
    Set-Clipboard -Value $Url
    Write-Ok "URL copied to clipboard (paste with Ctrl+V)"
  } catch { Write-Info "Copy the URL manually: $Url" }
}

# ── 9) Per-client instructions ────────────────────────────────────────────────
function Show-TunnelAiInstrucciones {
  param([string]$Cliente, [string]$Url)
  Write-Host ""
  switch ($Cliente) {
    'ChatGPT' {
      Write-Host "  ChatGPT -> Settings -> Connectors -> Add connector -> MCP" -ForegroundColor White
      Write-Host "    Authentication: No Auth   ·   URL: $Url" -ForegroundColor DarkGray
    }
    'Gemini' {
      $esSsh = ($Url -match '\.lhr\.life|loca\.lt|serveo\.net|localhost\.me')
      if (-not $esSsh) {
        Write-Warn "This URL goes through a Cloudflare quick tunnel."
        Write-Warn "Cloudflare BUFFERS streaming responses and Gemini needs SSE (it waits"
        Write-Warn "for 'event: endpoint'), so it aborts after ~10 s with 'context canceled'."
        Write-Info "For Gemini use Iniciar-Gemini-SSH.cmd (real streaming tunnel)."
      }
      Write-Host "  Gemini (gemini.google.com) -> Settings -> Connected Apps -> Custom apps" -ForegroundColor White
      Write-Host "    Add a custom app: paste the URL   ·   $Url" -ForegroundColor DarkGray
      Write-Host "    Client ID: tunnelai    Client Secret: tunnelai    (any value works)" -ForegroundColor DarkGray
      Write-Info "On the consent page ('TunnelAI authorizes access') click 'I understand'."
      Write-Info "Gemini requirements: personal account (not Workspace), Keep Activity enabled."
      Write-Info "Verify anytime with: Test-Conector-Gemini.cmd (it checks the SSE handshake)."
    }
    'Claude' {
      Write-Host "  Claude -> Customize -> Connectors -> Add custom connector" -ForegroundColor White
      Write-Host "    URL: $Url   ·   No sign-in" -ForegroundColor DarkGray
    }
    'Antigravity' {
      Write-Host "  Antigravity -> ... (agent panel) -> MCP Servers -> Refresh" -ForegroundColor White
      Write-Info "The 'tunnelai' server shows up under Customizations -> Installed MCP Servers."
      Write-Info "Antigravity recommends keeping fewer than 50 active tools (this server exposes 53)."
    }
  }
  Write-Host ""
}

# ── 10) Antigravity / Gemini CLI mcp_config.json ──────────────────────────────
function Set-AntigravityConfig {
  param([int]$Puerto, [string]$Token = "")
  $dir = Join-Path $env:USERPROFILE '.gemini\antigravity'
  $file = Join-Path $dir 'mcp_config.json'
  $serverUrl = "http://localhost:${Puerto}/mcp"
  $entrada = [ordered]@{ serverUrl = $serverUrl }
  if ($Token) { $entrada['headers'] = [ordered]@{ Authorization = "Bearer $Token" } }
  try {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path -LiteralPath $file) {
      $json = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
      if (-not $json.PSObject.Properties['mcpServers']) {
        $json | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue (New-Object PSObject) -Force
      }
      $json.mcpServers | Add-Member -NotePropertyName 'tunnelai' -NotePropertyValue ([pscustomobject]$entrada) -Force
      $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
    } else {
      @{ mcpServers = @{ tunnelai = [pscustomobject]$entrada } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
    }
    Write-Ok "Antigravity configured: $file"
    Write-Info "serverUrl: $serverUrl  (localhost, nothing exposed to the internet)"
  } catch {
    Write-Warn "Couldn't write $file ($($_.Exception.Message))."
    Write-Info "Add it manually: { `"mcpServers`": { `"tunnelai`": { `"serverUrl`": `"$serverUrl`" } } }"
  }
}

# ── 10b) Antigravity over the SHARED tunnel (public URL, optional Bearer) ──────
function Set-AntigravityConfigRemoto {
  param([string]$Url, [string]$Token = "")
  $dir = Join-Path $env:USERPROFILE '.gemini\antigravity'
  $file = Join-Path $dir 'mcp_config.json'
  $serverName = 'tunnelai-remoto'
  $entrada = [ordered]@{ serverUrl = $Url }
  if ($Token) { $entrada['headers'] = [ordered]@{ Authorization = "Bearer $Token" } }
  try {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path -LiteralPath $file) {
      $json = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
      if (-not $json.PSObject.Properties['mcpServers']) {
        $json | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue (New-Object PSObject) -Force
      }
      $json.mcpServers | Add-Member -NotePropertyName $serverName -NotePropertyValue ([pscustomobject]$entrada) -Force
      $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
    } else {
      @{ mcpServers = @{ $serverName = [pscustomobject]$entrada } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
    }
    Write-Ok "Antigravity (remote) configured: $file"
    Write-Info "serverUrl: $Url (token: $(if ($Token) { 'yes' } else { 'no' }))"
    Write-Info "NOTE: the quick-tunnel URL changes on every boot - this launcher rewrites it for you each run."
  } catch {
    Write-Warn "Couldn't write $file ($($_.Exception.Message))."
    $q = [string][char]34
    $hint = '{ "mcpServers": { ' + $q + $serverName + $q + ': { ' + $q + 'serverUrl' + $q + ': ' + $q + $Url + $q
    if ($Token) { $hint += ', ' + $q + 'headers' + $q + ': { ' + $q + 'Authorization' + $q + ': ' + $q + 'Bearer <token>' + $q + ' }' }
    $hint += ' } } }'
    Write-Info "Add it manually: $hint"
  }
}
# ── 10c) recover the current quick-tunnel URL from cloudflared's log ───────────
function Get-TunnelUrlActual {
  $logs = @(
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\logs\cloudflared.log'),
    (Join-Path $env:USERPROFILE '.chatgpt-local-mcp\logs\server.log')
  )
  foreach ($lg in $logs) {
    if (Test-Path -LiteralPath $lg) {
      $m = Select-String -LiteralPath $lg -Pattern '(https://[a-zA-Z0-9-]+\.trycloudflare\.com)' -AllMatches |
           ForEach-Object { $_.Matches } | Select-Object -Last 1
      if ($m) { return "$($m.Value)/mcp" }
    }
  }
  return $null
}

# ── 11) Automatic sentinel ────────────────────────────────────────────────────
function Start-TunnelAiVigia {
  param([int]$Puerto, [string]$Servidor)
  $monitor = Join-Path $script:TunnelAIRoot 'Monitor-TunnelAI.ps1'
  if (-not (Test-Path -LiteralPath $monitor)) { return }
  $script:TA_MonitorTag = "TA-$Puerto-$PID"
  $exe = 'pwsh'
  try { $p = Get-Process -Id $PID -ErrorAction Stop; if ($p.Path) { $exe = $p.Path } } catch {}
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { $exe = 'powershell' }
  try {
    Start-Process -FilePath $exe -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File', $monitor,
      '-Puerto', "$Puerto", '-Servidor', $Servidor, '-Etiqueta', $script:TA_MonitorTag,
      '-ProcesoPadre', "$PID", '-AutoRecuperar'
    ) -WorkingDirectory $script:TunnelAIRoot -WindowStyle Minimized | Out-Null
    Write-Ok "Sentinel started (minimized window): probes :$Puerto every 20s and repairs without killing the tunnel"
  } catch { Write-Info "Couldn't start the sentinel: $($_.Exception.Message)" }
}

function Stop-TunnelAiVigia {
  if (-not $script:TA_MonitorTag) { return }
  try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine -match $script:TA_MonitorTag } |
      ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
  } catch {}
  $script:TA_MonitorTag = $null
}

# ── 12) Full session ──────────────────────────────────────────────────────────
function Start-TunnelAiSession {
  [CmdletBinding()]
  param(
    [ValidateSet('ChatGPT','Claude','Gemini','Antigravity','AntigravityRemoto')][string]$Cliente,
    [string]$Ruta,
    [int]$Puerto = 0,
    [int]$MaxMinutos = 0,
    [string]$Token = "",
    [switch]$SinTunel
  )
  $info = Get-TunnelAiCliente -Cliente $Cliente
  if ($Puerto -le 0) { $Puerto = $info.Puerto }
  # -SinTunel: the MCP runs local only; the tunnel is provided by another process
  # (e.g. a named Cloudflare tunnel: Iniciar-Tunel-Nombrado.cmd)
  if ($SinTunel -and $Cliente -ne 'Antigravity') {
    $info.UsaTunel = $false
    Write-Warn "-SinTunel mode: the MCP only listens on 127.0.0.1:$Puerto. You need an external tunnel (Iniciar-Tunel-Nombrado.cmd) to connect from outside."
  }
  # The Bearer token only applies to header-capable clients. Web connectors
  # (ChatGPT/Claude/Gemini) only accept a URL without headers.
  if ($Token -and $info.UsaTunel -and $Cliente -in 'ChatGPT','Claude','Gemini') {
    Write-Warn "Token ignored: web connectors (ChatGPT/Claude/Gemini) don't support headers."
    $Token = ""
  }
  if ($Token) { $env:AI_PC_MCP_TOKEN = $Token }

  # Banner
  if ($Cliente -eq 'Gemini' -and $info.UsaTunel) {
    Write-Warn "NOTE: Gemini needs a STREAMING tunnel. Cloudflare quick tunnels buffer SSE"
    Write-Warn "responses, so Gemini will not connect through this URL."
    Write-Info "For Gemini use Iniciar-Gemini-SSH.cmd (Cloudflare is fine for ChatGPT/Claude)."
  }
  $titulo = switch ($Cliente) {
    'ChatGPT'     { 'TunnelAI - ChatGPT -> your PC' }
    'Gemini'      { 'TunnelAI - Gemini -> your PC' }
    'Claude'      { 'TunnelAI - Claude -> your PC (MCP)' }
    'Antigravity' { 'TunnelAI - Antigravity -> your PC (local, no tunnel)' }
    'AntigravityRemoto' { 'TunnelAI - Antigravity -> your PC (via tunnel)' }
  }
  Write-Host ""
  Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
  Write-Host "║  $($titulo.PadRight(48))  ║" -ForegroundColor Cyan
  Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
  Write-Host ""

  Assert-TunnelAiNode

  if ($Cliente -eq 'Claude') {
    Assert-ExposeFilesMcp
    Assert-Cloudflared
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
  } else {
    Assert-ChatGptLocalMcp
    Install-TunnelAiPatches
    if ($info.UsaTunel) { Assert-Cloudflared }
  }

  # Is there already a live session on this port?
  if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 3) {
    if ($Cliente -eq 'Antigravity') {
      Write-Ok "The local MCP server is already running on port $Puerto (not starting another one)."
      Set-AntigravityConfig -Puerto $Puerto -Token $Token
      Show-TunnelAiInstrucciones -Cliente $Cliente
      Write-Info "To stop it: Iniciar-Antigravity.ps1 -Detener"
      return
    }
    if ($Cliente -eq 'AntigravityRemoto') {
      # reuse the tunnel that is already up: recover its URL from cloudflared's log
      $urlActiva = Get-TunnelUrlActual
      if ($urlActiva) {
        Write-Ok "A tunnel session is already active on port $Puerto — reusing its URL."
        Set-AntigravityConfigRemoto -Url $urlActiva -Token ""
        Show-TunnelAiInstrucciones -Cliente 'Antigravity'
        Write-Info "If the other session requires a token, copy it from that window into mcp_config.json."
        return
      }
      Write-Warn "A session is active on port $Puerto but I couldn't recover its URL from the logs."
      Write-Info "Copy the URL shown in that window and paste it into mcp_config.json manually."
      return
    }
    $otro = if ($Puerto -eq 3001) { 'ChatGPT/Gemini' } else { 'another client' }
    Write-Warn "A tunnel session is already running on port $Puerto ($otro). Not starting a second one."
    $urlViva = $null
    $logSsh = Join-Path $env:TEMP "tunnelai-ssh-$Puerto.log"
    if (Test-Path -LiteralPath $logSsh) {
      $mm = Select-String -LiteralPath $logSsh -Pattern 'https://([a-zA-Z0-9][a-zA-Z0-9\-]{2,}(\.[a-zA-Z0-9\-]+)+)' -AllMatches |
           ForEach-Object { $_.Matches } |
           Where-Object { $_.Value -notmatch 'localhost\.run|docs' } | Select-Object -Last 1
      if ($mm) { $urlViva = "$($mm.Value)/mcp" }
    }
    if (-not $urlViva) { $urlViva = Get-TunnelUrlActual }
    if ($urlViva) {
      Write-Host ""
      Write-Ok "That session is live, use its URL: $urlViva"
      Copy-TunnelAiUrl -Url $urlViva
      Show-TunnelAiInstrucciones -Cliente $Cliente -Url $urlViva
    }
    Write-Info "To start a fresh session: close that window, or run Limpiar-Bloqueo.cmd (frees the port)."
    return
  }

  $Ruta = Read-TunnelAiRuta -Ruta $Ruta

  # Port busy with something that does NOT answer MCP: free ONLY that process
  $pidsOcupando = @(Get-TunnelAiPortPids -Puerto $Puerto)
  if ($pidsOcupando.Count -gt 0) {
    Stop-TunnelAiPuerto -Puerto $Puerto | Out-Null
  }

  Write-Host ""
  Write-Ok "Exposed folder: $Ruta"
  if ($info.UsaTunel) {
    Write-Info "Folder-scoped mode via cloudflared tunnel (TOTAL access to that folder only)"
    Write-Info "Server on 127.0.0.1:$Puerto — not exposed to your LAN"
  } else {
    Write-Info "LOCAL mode: Antigravity connects to http://localhost:$Puerto/mcp (nothing leaves the machine)"
  }
  Write-Host ""

  if ($MaxMinutos -gt 0) {
    Write-Info "Auto-close enabled: the tunnel will stop after $MaxMinutos minute(s)."
  }

  # Optional auto-close watchdog
  $watchdog = $null
  if ($MaxMinutos -gt 0) {
    try {
      $watchdog = Start-Job -Name 'TunnelAI-AutoStop' -ScriptBlock {
        param($puerto, $minutos, $padre)
        Start-Sleep -Seconds ([int]$minutos * 60)
        $pids = @()
        try { $pids = @(Get-NetTCPConnection -LocalPort $puerto -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique) } catch {}
        foreach ($p in $pids) { try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch {} }
        try {
          Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and ($_.CommandLine -match 'chatgpt-local-mcp|expose-files-mcp|cloudflared') } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
        } catch {}
        try { Stop-Process -Id $padre -Force -ErrorAction SilentlyContinue } catch {}
      } -ArgumentList $Puerto, $MaxMinutos, $PID
    } catch { $watchdog = $null }
  }

  $script:TA_UrlAnunciada = $null
  $script:TA_ConfigEscrito = ($Cliente -ne 'Antigravity')
  $limite = if ($MaxMinutos -gt 0) { (Get-Date).AddMinutes($MaxMinutos) } else { $null }

  # Launch: the server output is displayed intact (colors) and analyzed in parallel.
  # 2>&1 only for Claude: expose-files-mcp writes the tunnel logs to stderr, so we capture the URL.
  $lanzamiento = {
    if ($Cliente -eq 'Claude') {
      # Deliberately broad allowlist: the AI CAN install libraries/programs
      # (npm, dotnet, winget, pip, cargo, go, tsc, make, decompressors...).
      # It still can't: sudo/kill/taskkill (blocked by expose-files-mcp / chatgpt-local-mcp).
      $allowed = 'python,python3,py,pip,pip3,node,npm,npx,pnpm,yarn,dotnet,winget,git,cargo,rustup,go,deno,bun,tsc,make,cmake,powershell,pwsh,cmd,dir,ls,cat,type,echo,where,tar,unzip,7z,curl,wget,msiexec'
      & expose-files-mcp --transport http --host 127.0.0.1 --port $Puerto --root $Ruta `
        --files read-write --terminal true --shell $shell --timeout-ms 30000 `
        --allowed-commands $allowed --public true --provider cloudflared --no-auth true 2>&1
    } else {
      Set-Location -LiteralPath $Ruta
      if ($info.UsaTunel) {
        & chatgpt-local-mcp --log
      } else {
        $env:AI_PC_MCP_HOST = '127.0.0.1'
        $env:AI_PC_MCP_PORT = "$Puerto"
        & chatgpt-local-mcp --no-tunnel --log
      }
    }
  }

  try {
    & $lanzamiento | ForEach-Object {
      $_

      # capture the cloudflared tunnel URL
      if ($info.UsaTunel -and -not $script:TA_UrlAnunciada -and "$_" -match '(https://[a-zA-Z0-9-]+\.trycloudflare\.com)') {
        $script:TA_UrlAnunciada = "$($Matches[1])/mcp"
        Write-Host ""
        Copy-TunnelAiUrl -Url $script:TA_UrlAnunciada
        if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 5) { Write-Ok "MCP server responding on 127.0.0.1:$Puerto" }
        Show-TunnelAiInstrucciones -Cliente $Cliente -Url $script:TA_UrlAnunciada
        # Antigravity over the tunnel: write its mcp_config.json pointing to the public URL
        if ($Cliente -eq 'AntigravityRemoto') {
          $script:TA_ConfigEscrito = $true
          Set-AntigravityConfigRemoto -Url $script:TA_UrlAnunciada -Token $Token
          Show-TunnelAiInstrucciones -Cliente 'Antigravity'
          Write-Info "Tip: if you also want ChatGPT/Gemini on this same URL, they cannot use the token (web connectors don't send headers)."
        }
        Start-TunnelAiVigia -Puerto $Puerto -Servidor $info.Servidor
      }

      # Antigravity: as soon as the server answers, write the config
      if ($Cliente -eq 'Antigravity' -and -not $script:TA_ConfigEscrito) {
        if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 2) {
          $script:TA_ConfigEscrito = $true
          Set-AntigravityConfig -Puerto $Puerto -Token $Token
          Show-TunnelAiInstrucciones -Cliente $Cliente
          Start-TunnelAiVigia -Puerto $Puerto -Servidor $info.Servidor
        }
      }

      if ($limite -and (Get-Date) -gt $limite) { Stop-TunnelAiServidor -Puerto $Puerto -PatronServidor $info.Servidor }
    }
  } finally {
    if ($watchdog) { try { Stop-Job $watchdog -ErrorAction SilentlyContinue; Remove-Job $watchdog -Force -ErrorAction SilentlyContinue } catch {} }
    Write-Host ""
    Write-Info "Cleaning up residual tunnel processes..."
    Stop-TunnelAiVigia
    Stop-TunnelAiServidor -Puerto $Puerto -PatronServidor $info.Servidor | Out-Null
    Write-Ok "Processes finished cleanly."
  }
}

function Start-TunnelAiSshSession {
  <#
    Gemini session over an SSH tunnel (localhost.run).

    Why not Cloudflare? Gemini web speaks the LEGACY MCP HTTP+SSE transport: it opens
    GET /mcp and keeps a long-lived stream open. Cloudflare quick tunnels buffer
    streaming responses until they END, so the client never receives the `endpoint`
    frame, waits ~10 s and drops the request ("context canceled"). Verified with a
    minimal SSE server: 2.9 KB local, 0 bytes through a quick tunnel.
    An SSH reverse tunnel streams in real time, so it is the only option here that
    works for Gemini. ChatGPT/Claude keep using Cloudflare (plain request/response).
  #>
  param(
    [string]$Ruta,
    [int]$Puerto = 3001,
    [int]$MaxMinutos = 0,
    [string]$HostTunel = 'localhost.run'
  )

  Write-Host ""
  Write-Host "TunnelAI - Gemini -> your PC (SSH tunnel, streaming)" -ForegroundColor Cyan
  Write-Host "Cloudflare quick tunnels block SSE, which Gemini needs; this launcher uses SSH." -ForegroundColor DarkGray
  Write-Host ""

  Assert-TunnelAiNode
  Assert-ChatGptLocalMcp
  Install-TunnelAiPatches

  # a Cloudflare session on the same port would block us: explain and offer to free it
  if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 3) {
    $urlActiva = Get-TunnelUrlActual
    Write-Warn "A session is already active on port $Puerto. Not starting a second one."
    $urlVivaSsh = $null
    $logSshPrev = Join-Path $env:TEMP "tunnelai-ssh-$Puerto.log"
    if (Test-Path -LiteralPath $logSshPrev) {
      $mm = Select-String -LiteralPath $logSshPrev -Pattern 'https://([a-zA-Z0-9][a-zA-Z0-9\-]{2,}(\.[a-zA-Z0-9\-]+)+)' -AllMatches |
           ForEach-Object { $_.Matches } |
           Where-Object { $_.Value -notmatch 'localhost\.run|docs' } | Select-Object -Last 1
      if ($mm) { $urlVivaSsh = "$($mm.Value)/mcp" }
    }
    if (-not $urlVivaSsh) { $urlVivaSsh = Get-TunnelUrlActual }
    if ($urlVivaSsh) {
      Write-Host ""
      if ($urlVivaSsh -match 'trycloudflare') {
        Write-Warn "That session uses Cloudflare, which cannot stream SSE (Gemini needs it)."
      }
      Write-Ok "That session is live, use its URL: $urlVivaSsh"
      Copy-TunnelAiUrl -Url $urlVivaSsh
      Show-TunnelAiInstrucciones -Cliente 'Gemini' -Url $urlVivaSsh
    } else {
      Write-Info "I could not recover its URL from the logs. Close the other TunnelAI window."
    }
    Write-Info "To start a fresh session: run Limpiar-Bloqueo.cmd first."
    Read-Host "Press Enter to close this window" | Out-Null
    return
  }

  $Ruta = Read-TunnelAiRuta -Ruta $Ruta
  $pidsOcupando = @(Get-TunnelAiPortPids -Puerto $Puerto)
  if ($pidsOcupando.Count -gt 0) { Stop-TunnelAiPuerto -Puerto $Puerto | Out-Null }

  Write-Host ""
  Write-Ok "Exposed folder: $Ruta"
  Write-Info "LOCAL mode on 127.0.0.1:$Puerto (not exposed to your LAN)"
  if ($MaxMinutos -gt 0) { Write-Info "Auto-close enabled: the tunnel stops after $MaxMinutos minute(s)." }
  Write-Host ""

  $sshLog = Join-Path $env:TEMP "tunnelai-ssh-$Puerto.log"
  Remove-Item -LiteralPath $sshLog -ErrorAction SilentlyContinue

  # ── 1) SSH tunnel (started first so the URL appears as soon as it is ready) ──
  $sshExe = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
  if (-not $sshExe) { $sshExe = (Get-Command ssh -ErrorAction SilentlyContinue).Source }
  if (-not $sshExe) {
    Write-Err2 "OpenSSH client not found. Install it: Settings -> Apps -> Optional features -> OpenSSH Client."
    Read-Host "Press Enter" | Out-Null; return
  }

  Write-Info "Starting the SSH tunnel to $HostTunel (no account needed)..."
  $sshProc = Start-Process -FilePath $sshExe -WindowStyle Hidden -PassThru -RedirectStandardOutput $sshLog -RedirectStandardError "$sshLog.err" -ArgumentList @(
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
    '-R', "80:127.0.0.1:$Puerto",
    "nokey@$HostTunel"
  )

  $url = $null
  for ($i = 0; $i -lt 40 -and -not $url; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $sshLog) {
      $m = Select-String -LiteralPath $sshLog -Pattern 'https://([a-zA-Z0-9][a-zA-Z0-9\-]{2,}\.[a-zA-Z0-9\-]+\.[a-zA-Z]{2,})' -AllMatches -ErrorAction SilentlyContinue |
           ForEach-Object { $_.Matches } | Select-Object -Last 1
      if ($m -and $m.Value -notmatch 'localhost\.run') { $url = $m.Value }
    }
    if (-not $url -and $sshProc.HasExited) { break }
  }

  if (-not $url) {
    Write-Err2 "The SSH tunnel did not return a public URL (see $sshLog)."
    Write-Info "Check your internet connection and try again."
    try { Stop-Process -Id $sshProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    Read-Host "Press Enter" | Out-Null; return
  }

  # ── 2) MCP server, local only ──
  $env:AI_PC_MCP_HOST = '127.0.0.1'
  $env:AI_PC_MCP_PORT = "$Puerto"
  $mcpLog = Join-Path $env:TEMP "tunnelai-sse-mcp-$Puerto.log"

  Write-Ok "Tunnel established: $url"
  Write-Info "Starting the MCP server (local, streamed through SSH)..."
  $server = Start-Process -FilePath 'pwsh' -WindowStyle Hidden -PassThru -RedirectStandardOutput $mcpLog -RedirectStandardError "$mcpLog.err" -ArgumentList @(
    '-NoProfile', '-Command',
    "Set-Location -LiteralPath '$Ruta'; `$env:AI_PC_MCP_HOST='127.0.0.1'; `$env:AI_PC_MCP_PORT='$Puerto'; chatgpt-local-mcp --no-tunnel --log"
  )

  if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 45) {
    Write-Ok "MCP server responding on 127.0.0.1:$Puerto"
  } else {
    Write-Warn "The server did not answer in time; see $mcpLog"
  }

  $urlMcp = "$url/mcp"
  Copy-TunnelAiUrl -Url $urlMcp
  Show-TunnelAiInstrucciones -Cliente 'Gemini' -Url $urlMcp
  Write-Info "This URL changes on every run (free random domain)."
  Write-Info "If Gemini still refuses, run Test-Conector-Gemini.cmd: it verifies the SSE handshake."
  Start-TunnelAiVigia -Puerto $Puerto -Servidor 'chatgpt-local-mcp'

  Write-Host ""
  Write-Host "── LIVE (Ctrl+C to close) ──" -ForegroundColor Cyan
  Write-Host ""

  $limite = if ($MaxMinutos -gt 0) { (Get-Date).AddMinutes($MaxMinutos) } else { $null }
  $urlActual = $url
  $curlProbe = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
  $tick = 0
  try {
    while ($true) {
      Start-Sleep -Seconds 2
      if ($sshProc.HasExited) { Write-Warn "The SSH tunnel closed."; break }
      if ($limite -and (Get-Date) -gt $limite) { Write-Info "Auto-close time reached."; break }

      # every ~30 s: localhost.run sometimes drops the forwarding while ssh stays alive (502).
      # Detect it and rebuild the tunnel instead of leaving Gemini with a dead URL.
      $tick++
      if (($tick % 15) -eq 0) {
        $code = ""
        if ($curlProbe) {
          try { $code = ((& $curlProbe -s -o NUL -w '%{http_code}' --max-time 10 "$urlActual/" 2>&1) -join '').Trim() } catch { $code = "" }
        }
        # Only rebuild the TUNNEL when the local server is fine but the public URL is not:
        # if the local server is down, the sentinel repairs it and the tunnel is still good.
        if ($code -ne "200") {
          if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 3) {
            Write-Warn "The public tunnel stopped answering (HTTP $code) while the local server is fine."
            Write-Warn "Rebuilding the tunnel..."
          try { Stop-Process -Id $sshProc.Id -Force -ErrorAction SilentlyContinue } catch {}
          Start-Sleep -Seconds 2
          $log2 = Join-Path $env:TEMP "tunnelai-ssh-$Puerto.log"
          Remove-Item -LiteralPath $log2 -ErrorAction SilentlyContinue
          $sshProc = Start-Process -FilePath $sshExe -WindowStyle Hidden -PassThru -RedirectStandardOutput $log2 -RedirectStandardError "$log2.err" -ArgumentList @(
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'ServerAliveInterval=30',
            '-o', 'ServerAliveCountMax=3',
            '-R', "80:127.0.0.1:$Puerto",
            "nokey@$HostTunel"
          )
          $urlNueva = $null
          for ($i = 0; $i -lt 45 -and -not $urlNueva; $i++) {
            Start-Sleep -Seconds 1
            if (Test-Path -LiteralPath $log2) {
              $mm = Select-String -LiteralPath $log2 -Pattern 'https://([a-zA-Z0-9][a-zA-Z0-9\-]{2,}(\.[a-zA-Z0-9\-]+)+)' -AllMatches |
                   ForEach-Object { $_.Matches } |
                   Where-Object { $_.Value -notmatch 'localhost\.run|docs' } | Select-Object -Last 1
              if ($mm) { $urlNueva = $mm.Value }
            }
          }
          if ($urlNueva) {
            $urlActual = $urlNueva
            Write-Host ""
            Write-Ok "New tunnel URL: $urlNueva/mcp"
            Copy-TunnelAiUrl -Url "$urlNueva/mcp"
            Show-TunnelAiInstrucciones -Cliente 'Gemini' -Url "$urlNueva/mcp"
            Write-Info "IMPORTANT: the URL changed - paste the new one in Gemini (Settings -> Connected Apps)."
            Write-Info "Quick check: Test-Conector-Gemini.cmd"
          } else {
            Write-Err2 "Could not get a new URL - check the internet connection."
            break
          }
          }
        }
      }
    }
  } finally {
    Write-Host ""
    Write-Info "Closing the SSH tunnel and the MCP server..."
    Stop-TunnelAiVigia
    try { Stop-Process -Id $sshProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    try { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue } catch {}
    Stop-TunnelAiServidor -Puerto $Puerto -PatronServidor 'chatgpt-local-mcp' | Out-Null
    Write-Ok "Processes finished cleanly."
  }
}
function Start-TunnelAiRemoteSession {
  <#
    Gemini session over a RELIABLE streaming tunnel.

    Measured facts (do not re-litigate these):
    * Gemini web speaks the legacy MCP HTTP+SSE transport: it opens GET /mcp and waits for
      `event: endpoint`. A plain GET /mcp must ALSO finish fast, or validators give up.
    * Cloudflare QUICK tunnels buffer streaming responses and only forward them when the
      response ends (measured: 2.9 KB local vs 0 bytes through the tunnel), so SSE never works.
    * localhost.run / *.lhr.life answers 200 to the owner but 502 to everyone else (Google,
      any other network), so Google can never reach it. Measured with external probes.
    => Use a provider with a real global network AND SSE support: ngrok (free) or
       Tailscale Funnel (free). Both stream; both need a one-time free account.
  #>
  param(
    [string]$Ruta,
    [int]$Puerto = 3001,
    [int]$MaxMinutos = 0,
    [ValidateSet('ngrok', 'tailscale', 'localhost')]
    [string]$Proveedor = 'ngrok',
    [string]$Dominio = ''
  )

  $tunel = switch ($Proveedor) {
    'ngrok'     { 'ngrok' }
    'tailscale' { 'tailscale funnel' }
    'localhost' { 'ssh' }
  }

  Write-Host ""
  Write-Host "TunnelAI - Gemini -> your PC ($Proveedor tunnel, streaming)" -ForegroundColor Cyan
  if ($Proveedor -eq 'localhost') {
    Write-Host "Warning: localhost.run answers 502 outside your own network - Google cannot use it." -ForegroundColor Yellow
  }
  Write-Host ""

  Assert-TunnelAiNode
  Assert-ChatGptLocalMcp
  Install-TunnelAiPatches

  if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 3) {
    $urlViva = Get-TunnelUrlActual
    Write-Warn "A session is already running on port $Puerto. Not starting a second one."
    if ($urlViva) {
      Write-Host ""
      Write-Ok "That session is live, use its URL: $urlViva"
      Copy-TunnelAiUrl -Url $urlViva
      Show-TunnelAiInstrucciones -Cliente 'Gemini' -Url $urlViva
    }
    Write-Info "To start a fresh session: run Limpiar-Bloqueo.cmd first."
    Read-Host "Press Enter to close this window" | Out-Null
    return
  }

  $Ruta = Read-TunnelAiRuta -Ruta $Ruta
  $pidsOcupando = @(Get-TunnelAiPortPids -Puerto $Puerto)
  if ($pidsOcupando.Count -gt 0) { Stop-TunnelAiPuerto -Puerto $Puerto | Out-Null }

  Write-Host ""
  Write-Ok "Exposed folder: $Ruta"
  Write-Info "LOCAL mode on 127.0.0.1:$Puerto (not exposed to your LAN)"
  if ($MaxMinutos -gt 0) { Write-Info "Auto-close enabled: the tunnel stops after $MaxMinutos minute(s)." }
  Write-Host ""

  # ── 1) comprobar el cliente del tunel ──
  $cli = $null
  $falta = ''
  if ($Proveedor -eq 'ngrok') {
    $cli = Resolve-TunnelAiBin -Nombre ngrok
    if (-not $cli) { $falta = 'ngrok' }
    if ($cli -and -not (Test-TunnelAiNgrokToken)) { Set-TunnelAiNgrokToken -Ngrok $cli | Out-Null }
  } elseif ($Proveedor -eq 'tailscale') {
    $cli = Resolve-TunnelAiBin -Nombre tailscale
    if (-not $cli) { $falta = 'tailscale' }
    if (-not $cli) { $falta = 'tailscale' }
  } else {
    $cli = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
    if (-not $cli) { $falta = 'OpenSSH' }
  }
  if ($falta) {
    Write-Err2 "'$falta' is not installed."
    if ($falta -eq 'ngrok') {
      Write-Info "Install it (one time): https://ngrok.com/download"
      Write-Info "Then create a free account, copy your authtoken and run: ngrok config add-authtoken <TOKEN>"
    } elseif ($falta -eq 'tailscale') {
      Write-Info "Install Tailscale (one time): https://tailscale.com/download"
      Write-Info "Log in with your free account and enable Funnel in the admin console."
    }
    Read-Host "Press Enter to close this window" | Out-Null
    return
  }

  # ── 2) arrancar el tunel ──
  $tunelLog = Join-Path $env:TEMP "tunnelai-tunel-$Proveedor-$Puerto.log"
  Remove-Item -LiteralPath $tunelLog -ErrorAction SilentlyContinue

  $argsTunel = switch ($Proveedor) {
    'ngrok' {
      $a = @('http', "$Puerto", '--log', 'stdout', '--log-format', 'logfmt')
      if ($Dominio) { $a += @('--domain', $Dominio) }
      $a
    }
    'tailscale' { @('funnel', '--bg=false', "$Puerto") }
    'localhost' { @('-o', 'StrictHostKeyChecking=no', '-R', "80:127.0.0.1:$Puerto", 'nokey@localhost.run') }
  }

  Write-Info "Starting the $Proveedor tunnel..."
  $procTunel = Start-Process -FilePath $cli -WindowStyle Hidden -PassThru -RedirectStandardOutput $tunelLog -RedirectStandardError "$tunelLog.err" -ArgumentList $argsTunel

  $url = $null
  $patronUrl = switch ($Proveedor) {
    'ngrok'     { '(https://[a-zA-Z0-9\-\.]+\.(?:ngrok-free\.app|ngrok\.app|ngrok\.io|ngrok-free\.dev))' }
    'tailscale' { '(https://[a-zA-Z0-9\-\.]+\.ts\.net)' }
    'localhost' { '(https://[a-zA-Z0-9][a-zA-Z0-9\-]{2,}(\.[a-zA-Z0-9\-]+)+)' }
  }
  for ($i = 0; $i -lt 60 -and -not $url; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $tunelLog) {
      $mm = Select-String -LiteralPath $tunelLog -Pattern $patronUrl -AllMatches -ErrorAction SilentlyContinue |
           ForEach-Object { $_.Matches } |
           Where-Object { $_.Value -notmatch 'localhost\.run|docs' } | Select-Object -Last 1
      if ($mm) { $url = $mm.Value }
    }
    if (-not $url -and $procTunel.HasExited) { break }
  }

  if (-not $url) {
    $err = (Get-Content "$tunelLog.err" -Tail 5 -ErrorAction SilentlyContinue) -join ' '
    Write-Err2 "The $Proveedor tunnel did not return a URL. $err"
    try { Stop-Process -Id $procTunel.Id -Force -ErrorAction SilentlyContinue } catch {}
    Read-Host "Press Enter to close this window" | Out-Null
    return
  }

  # ── 3) servidor MCP local ──
  $env:AI_PC_MCP_HOST = '127.0.0.1'
  $env:AI_PC_MCP_PORT = "$Puerto"
  $mcpLog = Join-Path $env:TEMP "tunnelai-mcp-$Puerto.log"
  $server = Start-Process -FilePath 'pwsh' -WindowStyle Hidden -PassThru -RedirectStandardOutput $mcpLog -RedirectStandardError "$mcpLog.err" -ArgumentList @(
    '-NoProfile', '-Command',
    "Set-Location -LiteralPath '$Ruta'; `$env:AI_PC_MCP_HOST='127.0.0.1'; `$env:AI_PC_MCP_PORT='$Puerto'; chatgpt-local-mcp --no-tunnel --log"
  )

  if (Test-McpResponde -Puerto $Puerto -TimeoutSeg 45) { Write-Ok "MCP server responding on 127.0.0.1:$Puerto" }
  else { Write-Warn "The server did not answer in time; see $mcpLog" }

  $urlMcp = "$url/mcp"
  Write-Ok "Tunnel established: $url"
  Copy-TunnelAiUrl -Url $urlMcp
  Show-TunnelAiInstrucciones -Cliente 'Gemini' -Url $urlMcp
  Write-Info "Verify it end to end: Test-Conector-Gemini.cmd"
  Start-TunnelAiVigia -Puerto $Puerto -Servidor 'chatgpt-local-mcp'

  Write-Host ""
  Write-Host "--- LIVE (Ctrl+C to close) ---" -ForegroundColor Cyan
  Write-Host ""

  $limite = if ($MaxMinutos -gt 0) { (Get-Date).AddMinutes($MaxMinutos) } else { $null }
  try {
    while ($true) {
      Start-Sleep -Seconds 2
      if ($procTunel.HasExited) { Write-Warn "The $Proveedor tunnel closed."; break }
      if ($limite -and (Get-Date) -gt $limite) { Write-Info "Auto-close time reached."; break }
    }
  } finally {
    Write-Host ""
    Write-Info "Closing the tunnel and the MCP server..."
    Stop-TunnelAiVigia
    try { Stop-Process -Id $procTunel.Id -Force -ErrorAction SilentlyContinue } catch {}
    try { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue } catch {}
    Stop-TunnelAiServidor -Puerto $Puerto -PatronServidor 'chatgpt-local-mcp' | Out-Null
    Write-Ok "Processes finished cleanly."
  }
}
function Resolve-TunnelAiBin {
  # Locate an executable on PATH or in the usual install folders (winget links may be missing).
  param([Parameter(Mandatory = $true)][string]$Nombre)
  $cmd = Get-Command "$Nombre.exe" -ErrorAction SilentlyContinue
  if (-not $cmd) { $cmd = Get-Command $Nombre -ErrorAction SilentlyContinue }
  if ($cmd) { return $cmd.Source }

  $carpetas = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
    (Join-Path $env:ProgramFiles "$Nombre"),
    (Join-Path ${env:ProgramFiles(x86)} "$Nombre"),
    (Join-Path $env:USERPROFILE "AppData\Local\Programs\$Nombre"),
    (Join-Path $env:USERPROFILE ".$Nombre")
  )
  foreach ($c in $carpetas) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    $hit = Get-ChildItem -LiteralPath $c -Filter "$Nombre.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

function Test-TunnelAiNgrokToken {
  # ngrok stores the config in %LOCALAPPDATA%\ngrok\ngrok.yml on Windows
  # (and in ~/.config/ngrok/ngrok.yml on other platforms). Check both.
  $rutas = @(
    (Join-Path $env:LOCALAPPDATA 'ngrok\ngrok.yml'),
    (Join-Path $env:USERPROFILE '.config\ngrok\ngrok.yml'),
    (Join-Path $env:APPDATA 'ngrok\ngrok.yml')
  )
  foreach ($r in $rutas) {
    if (Test-Path -LiteralPath $r) {
      try {
        $txt = Get-Content -LiteralPath $r -Raw -ErrorAction Stop
        if ($txt -match 'authtoken:\s*(\S+)') { return $true }
      } catch {}
    }
  }
  return $false
}

function Set-TunnelAiNgrokToken {
  # Stores the ngrok authtoken once, so the launchers work with no further setup.
  param([string]$Ngrok)
  $cfgDir = Join-Path $env:USERPROFILE '.config\ngrok'
  if (-not (Test-Path -LiteralPath $cfgDir)) {
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
  }
  $read = Read-Host 'Paste your ngrok authtoken (ngrok.com -> dashboard -> Authtoken)'
  $read = $read.Trim()
  if (-not $read) { return $false }
  & $Ngrok config add-authtoken $read 2>&1 | Out-Null
  if (Test-TunnelAiNgrokToken) { Write-Ok "ngrok authtoken saved."; return $true }
  Write-Err2 "Could not save the token. Run it manually: ngrok config add-authtoken <TOKEN>"
  return $false
}
Export-ModuleMember -Function *
