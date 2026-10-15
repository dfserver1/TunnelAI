# Changelog

All notable changes to TunnelAI are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.3.0] — 2026-10-15

### Fixed — the real reason Gemini never connected
Diagnosed with the live logs and reproduced with a minimal SSE server: **Cloudflare quick tunnels
buffer streaming responses and only forward them when the response ends.** Gemini web speaks the
legacy MCP HTTP+SSE transport (it opens `GET /mcp` and waits for an `event: endpoint` frame), so it
never received anything, waited ~10 s and dropped the request (`context canceled`). Proof:
2.9 KB locally vs **0 bytes** through the tunnel, on the package's own `/logs/live` endpoint too.

### Added
- **`Iniciar-Gemini-SSH.cmd` / `.ps1`** — Gemini over an SSH reverse tunnel (`localhost.run`, no
  account). It streams in real time, so the whole legacy flow works: `event: endpoint` →
  `POST /mcp?sessionId=…` (202) → replies on the stream. Verified end-to-end (53 tools).
- Legacy HTTP+SSE transport support in the patched server: `GET /mcp` now answers `event: endpoint`
  with a session id, `POST /mcp?sessionId=…` answers `202 Accepted` and pushes the JSON-RPC reply
  **on the SSE stream**, and `DELETE /mcp?sessionId=…` closes the session. Clients that POST
  directly to `/mcp` (ChatGPT, Claude, Antigravity) keep working unchanged.
- `Test-Conector-Gemini.ps1` now verifies the **SSE handshake** too and tells you which tunnel type
  is live, so you can tell a Cloudflare URL (will fail for Gemini) from an SSH one (works).

### Changed
- The console now warns when a Gemini session runs over Cloudflare, and recommends the SSH launcher.
## [1.2.0] — 2026-10-15

### Added
- **OAuth 2.1 for Gemini web**: the patched server now answers the full MCP authorization flow, so
  *Connect* finally completes instead of timing out after ~10 s with `context canceled`:
  `/.well-known/oauth-protected-resource` (RFC 9728), `/.well-known/oauth-authorization-server` (RFC 8414),
  dynamic client registration `POST /register` (RFC 7591), a consent page at `/authorize`, and
  `POST /token` with **PKCE (S256)** verification. Any `Client ID` / `Client Secret` you type in Gemini
  works (e.g. `tunnelai` / `tunnelai`). Issued tokens are accepted by `/mcp` **alongside** a static
  Bearer token, so `-Token` sessions keep working and still reject anything else with 401.
- `Test-Conector-Gemini.ps1` now verifies the whole OAuth handshake (discovery → registration →
  consent → token → `tools/list`), not just `initialize`.

### Fixed
- **Sentinel false alarms**: `Invoke-WebRequest` was called with a non-existent `-TimeoutSeg` parameter,
  so every probe threw and the sentinel restarted the server every 40 s. In ~20 minutes that produced
  **96 orphaned processes** (dead `EADDRINUSE` servers + extra `cloudflared`).
- **Sentinel recovery** now kills the old server (port owner + watchdog/launcher) *before* relaunching,
  waits for the port to be free, and suspends auto-recovery after 3 consecutive failures instead of
  looping forever. The tunnel and its URL are still never touched.
- Patch installer: the OAuth block is inserted **by line** before `app.listen(...)`, and an invariant
  guarantees `const server = app.listen(` survives (a broken earlier insertion had eaten the prefix,
  making the server exit with `ReferenceError: server is not defined`).

## [1.1.0] — 2026-10-15

### Added
- **Antigravity over the shared tunnel**: `Iniciar-Antigravity-Remoto.cmd` opens the same tunnel as
  ChatGPT/Gemini (port 3001) and writes the `tunnelai-remoto` server into Antigravity's `mcp_config.json`
  pointing at the public URL, with an optional **Bearer token** (verified: 401 without it, 200 with it).
  If a tunnel session is already live on port 3001, its URL is recovered from the cloudflared log and reused.
- `Get-TunnelUrlActual` helper: recovers the current quick-tunnel URL from the cloudflared logs.
- Bearer tokens are now also honoured for tunnel-mode clients that can send headers (Antigravity remote).

### Fixed
- Mermaid validator: no longer flags Markdown files without `mermaid` blocks; closing fences must start a line.
- `Config-Tunel-Estable.ps1 -Plan`: dry run works in non-interactive shells (CI) and without cloudflared installed.

## [1.0.0] — 2026-10-15

First public release.

### Added

**Multi-assistant access**
- `Iniciar-TunnelAI.cmd` — ChatGPT over a Cloudflare quick tunnel (port 3001)
- `Iniciar-Gemini.cmd` — Gemini (web/mobile) over the same tunnel (port 3001, URL can be shared with ChatGPT)
- `Iniciar-Claude.cmd` — Claude over a Cloudflare quick tunnel (port 3002) with `expose-files-mcp`
- `Iniciar-Antigravity.cmd` — Antigravity **locally without any tunnel** (`localhost:3003/mcp`), auto-writing `mcp_config.json`
- URL copied to the clipboard automatically; session reuse detection when a port is already serving

**15 AI skills** (`Agregar-Skill.cmd`, installed into the exposed folder as `TUNNELAI-SKILL-*.md`)
- Code auditing · Website development · **OCR and document vision** · Project onboarding ·
  Dependency & secret security · Automatic documentation · **Package installation**
  (npm/pip/dotnet/winget/cargo) · Legacy migration · Performance profiling · WCAG 2.2 AA accessibility ·
  Data analysis (CSV/Excel/JSON) · Testing & QA · Technical SEO · **PDF reports** · **Architecture diagrams**

**Local tools (no external services)**
- `Tools/OCR.ps1` — offline OCR with Windows.Media.Ocr (self-relaunches to Windows PowerShell 5.1 for WinRT),
  tesseract fallback, `-Json`, `-Carpeta`, `-Idioma`
- `Tools/HTML-a-PDF.ps1` — reports to PDF with Edge/Chrome headless
- `Tools/Nuevo-Diagrama.ps1` — Mermaid diagram scaffolding (flow, layers, sequence, C4, components) + syntax validator

**Sentinel (`Monitor-TunnelAI`)**
- Real MCP `initialize` probe every 20 s with latency in ms
- **Detects installations in progress and lets them finish** (npm/npx/dotnet/winget/pip/yarn/tsc…),
  never killing them; kills only hung non-installer commands
- Self-heals **without killing the tunnel**: restarts only the server (URL preserved) or only cloudflared
  (new URL announced), rotates logs > 15 MB, warns on bottlenecks (latency, memory)
- `-AutoTest` self-test for the installation-detection logic

**Security & control**
- Folder-scoped by default; server bound to `127.0.0.1` (never exposed to the LAN)
- Optional Bearer token for header-capable clients (`Iniciar-Antigravity.cmd -Token …`) — verified 401/200
- `Limpiar-Bloqueo.cmd` frees ports by PID, closes quick tunnels **and the sentinel**;
  never kills global node/dotnet processes
- `Verificar-Entorno.cmd` diagnostics
- Runtime patches on `chatgpt-local-mcp` verified after every launch and self-healing if the package is updated

**Optional: stable URL**
- `Config-Tunel-Estable.cmd` wizard for a named Cloudflare tunnel (login → tunnel → DNS route → `config.yml`)
- `Iniciar-TunnelAI.cmd -SinTunel` runs the MCP local-only so the named tunnel provides the public URL

**Ops**
- `-MaxMinutos` auto-close for the tunnel
- `.gitignore`, MIT `LICENSE`, GitHub Actions CI (PowerShell syntax, skills, tool smoke tests)

### Notes
- Console messages are in Spanish; documentation, skills and code comments are in English.
- Upstream servers `chatgpt-local-mcp` (1.0.3) and `expose-files-mcp` (1.1.1) are installed automatically.

[1.0.0]: https://github.com/dfserver1/TunnelAI/releases/tag/v1.0.0
