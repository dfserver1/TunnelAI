# Changelog

All notable changes to TunnelAI are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
