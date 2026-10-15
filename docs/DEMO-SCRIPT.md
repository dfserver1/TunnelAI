# Demo script — 60 seconds (TunnelAI)

Ready-to-record script. You record your screen for ~1 minute and the result looks professional.
This file lives in the repo so anyone can re-record their own demo.

## Before you start (2 minutes)

1. Close unneeded windows; use a dark terminal if possible.
2. Have ready: `C:\Proyectos\TunnelAI`, a demo folder with a few real files (e.g. a small project).
3. Open on your phone/second screen: `https://chatgpt.com/#settings/Connectors` (so the connector dialog is one click away).
4. Optional: set the terminal font bigger (Ctrl + mouse wheel) so the text is readable on mobile.

## Recording setup (free, already on Windows)

- Press **Win + G** → open *Capture* → click *Record* (or **Win + Alt + R** to start/stop).
- Or install OBS Studio (free) and record window + microphone.
- Keep it **under 90 seconds**. Silence the notifications.

## The script (second by second)

| Time | What you do | What you say (narration) |
|---|---|---|
| 0:00–0:06 | Show the repo/README on screen, scroll the top. | "TunnelAI connects ChatGPT, Claude, Gemini and Antigravity directly to my Windows PC over MCP. Portable, folder-scoped, MIT." |
| 0:06–0:14 | Double-click `Verificar-Entorno.cmd`. | "First it checks everything: Node, cloudflared, the MCP packages and the ports." |
| 0:14–0:24 | Double-click `Iniciar-TunnelAI.cmd`, paste a folder, Enter. Wait for the URL box. | "Double-click, paste the folder, and the tunnel comes up. The URL is already on my clipboard." |
| 0:24–0:36 | In ChatGPT: Settings → Connectors → Add connector → MCP → No Auth → paste (Ctrl+V). Name it "Mi PC". | "In ChatGPT I add it as an MCP connector with no auth, and paste the URL. Done — the AI can now list my files and run commands in that folder." |
| 0:36–0:46 | Ask ChatGPT: "Lista los archivos del proyecto y dime qué hace". | "It sees only that folder — not my whole disk." |
| 0:46–0:56 | Run `Agregar-Skill.cmd`, install the audit skill, then tell the AI: "Lee TUNNELAI-SKILL-auditoria.md y ejecuta la auditoría". | "And with one command I install one of 15 skills — now it audits my code, or reads invoices with offline OCR, or generates PDF reports." |
| 0:56–1:00 | Close the tunnel window; show the sentinel window closing too. | "And the sentinel repairs the tunnel if anything dies. Link in the description." |

## After recording

- Trim to 60–75 s (Photos app on Windows: *Edit*, or OBS).
- Export as **MP4 1080p** and optionally a short **GIF** (first 6 seconds) for the README.

## Publishing the video

1. Upload the MP4 to **YouTube** (unlisted or public), **Loom** or **Google Drive**.
2. Copy the link and put it in the README section "See it in action" (it already has a placeholder).
3. For the GIF: drag it into the release page (`/releases`) as an asset, or commit it under `assets/`.

## Alternative: 6-second GIF (no audio)

1. Start the tunnel with `Iniciar-TunnelAI.cmd`.
2. Win + Alt + R, let the URL box appear, stop after 6 s.
3. Convert to GIF (ezgif.com, or `ffmpeg -i demo.mp4 demo.gif`) and save it as `assets/demo.gif`.
4. Reference it in the README with:
   `![TunnelAI demo](assets/demo.gif)`
