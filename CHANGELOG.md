# Changelog

All notable changes to TunnelAI are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.6.1] — 2026-10-20

### Fixed
- `Test-Conector-Gemini` gave a false negative in the SSE check: `Start-Process` split the
  `Accept: text/event-stream` header on the space, so curl sent an empty Accept and received the
  JSON banner. The header is now sent without a space (`Accept:text/event-stream`) and the SSE
  check passes on a healthy tunnel.

## [1.6.0] — 2026-10-19

### Added
- **`TunnelAI.cmd` — one menu for every assistant.** Pick 1-7 and it creates the right session:
  ChatGPT (Cloudflare), Gemini (Tailscale Funnel, detached), Claude (Cloudflare), Antigravity
  (local) or Antigravity remote (shared tunnel + Bearer). Options 6 and 7 verify and stop everything.
- The menu installs the **15 skills** into the exposed folder before opening the tunnel (default on,
  toggle with `s`), so the AI reads `TUNNELAI-SKILL-*.md` through that same tunnel.
- `TunnelAI.ps1` accepts `-Opcion <n> -Ruta <folder> [-SinSkills]` for shortcuts and scripts, plus
  `-Ventana` for a watched Gemini session.
- `Agregar-Skill.ps1 -Silencioso`: installs without the clipboard copy and without the final pause,
  so the menu can call it unattended.

### Changed
- `Limpiar-Bloqueo.cmd` now also turns off the **Tailscale Funnel** when it points at one of our
  ports (3001/3002/3003), so "stop everything" really stops everything.

## [1.5.0] — 2026-10-18

### Added
- **Durable tunnel**: the Gemini tunnel now runs with `tailscale funnel --bg`, inside the Tailscale
  service instead of a foreground process. Measured: 0 foreground processes and the session still
  serving — closing the launcher window no longer kills the tunnel.
- **Detached mode** (the default for `Iniciar-Gemini.cmd`): starts the MCP server, the sentinel and
  the tunnel, prints the URL and exits. Close the window and everything keeps running; `-Ventana`
  keeps the live session visible instead. `Limpiar-Bloqueo.cmd` stops it all.
- The live loop watches `tailscale funnel status` and re-establishes the funnel if it ever drops
  (network changes, Tailscale service restarts).

### Changed
- **One Gemini launcher**: `Iniciar-Gemini.cmd` is now the only one and uses **Tailscale Funnel**,
  the only provider of the four tested that streams SSE, serves no interstitial to browsers and
  keeps a stable URL. It replaces the three variants (Cloudflare / localhost.run / ngrok) that
  could not work.
- "Session already running" now shows the URL of the tunnel that is actually live (Tailscale first,
  then ngrok) and only falls back to the logs, so it can no longer display a stale URL.

### Removed
- `Iniciar-Gemini-SSH.cmd` / `.ps1` — `localhost.run` answers 502 to everyone outside your network,
  so Google can never reach it.
- `Iniciar-Gemini-Remoto.cmd` / `.ps1` — ngrok's free tier serves a browser-warning interstitial to
  browser user-agents (Gemini sends one) and the free tier cannot disable it.
- The dead `Start-TunnelAiSshSession` helper.

### Fixed
- The Cloudflare streaming warning no longer appears for Tailscale/ngrok URLs: it only fires for
  `trycloudflare.com` URLs now.

## [1.4.0] — 2026-10-15

### Fixed
- **Plain `GET /mcp` no longer hangs.** It now answers immediately with server info unless the
  client sends `Accept: text/event-stream`. Connectors that only check "can I reach this URL?"
  (Google does exactly that) previously waited forever and reported
  *"The MCP server could not be reached. Check the URL."*
- Added `Iniciar-Gemini-SSH.cmd` watchdog: probes the public URL every 30 s and rebuilds the
  tunnel when the local server is healthy but the public one is not.

### Measured and documented (why the other tunnels cannot work for Gemini)
- Cloudflare quick tunnels buffer SSE and forward the body only when the response ends
  (2.9 KB local vs 0 bytes through the tunnel).
- `localhost.run` answers **200 to you and 502 to everyone else**, so Google never reaches it.
- `serveo.net` serves an HTML warning page instead of the MCP endpoint.

### Added
- **`Iniciar-Gemini-Remoto.cmd`** — Gemini over **ngrok** (or Tailscale Funnel): providers with a
  real global network that support streaming. First run asks for the free ngrok authtoken and
  stores it in the standard ngrok config.
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
