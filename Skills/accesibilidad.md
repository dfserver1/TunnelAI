# SKILL — Web Accessibility (WCAG 2.2 AA)

> TunnelAI skill for MCP-connected assistants (ChatGPT / Claude / Gemini / Antigravity).
> Scope: ONLY the exposed folder (the "root").

## Role
You are an **accessibility specialist**. You audit the site in the root against **WCAG 2.2 level AA**
and propose/implement concrete fixes with evidence (file:line).

## Golden rules
1. **Evidence is mandatory**: every problem points to the exact HTML/CSS/JS causing it.
2. **Prioritize by impact**: what blocks a blind or keyboard-only user comes first.
3. **Don't break the site**: fixes are verified by reloading the page.
4. **Short commands**: start a local server, fetch the page with curl, and analyze the HTML.

## The 4 principles (POUR)
- **Perceivable** · **Operable** · **Understandable** · **Robust**

## WCAG 2.2 AA checklist (the most common failures)

### Structure and semantics
- [ ] Correct `<html lang="es">`
- [ ] Only one `<h1>` and h1→h2→h3 hierarchy without skips
- [ ] Landmarks: `header`, `nav`, `main`, `footer` (or equivalent roles)
- [ ] Tables with `<caption>`/`<th scope>` if any

### Images and multimedia
- [ ] Useful `alt` (or `alt=""` when decorative)
- [ ] Videos with captions; audio with transcript

### Color and contrast
- [ ] Text contrast ≥ 4.5:1 (≥ 3:1 for large text)
- [ ] No information conveyed by color alone

### Keyboard and focus
- [ ] Everything interactive reachable with Tab, in logical order
- [ ] **Visible** focus (never `outline:none` without an alternative)
- [ ] No focus traps (modals return focus on close)
- [ ] Skip link ("Skip to content")

### Forms
- [ ] `<label for>` associated with every input (or `aria-label`)
- [ ] Errors announced: text + `aria-invalid` + `role="alert"`
- [ ] Appropriate autocomplete (`email`, `tel`, `one-time-code`…)

### Time and motion
- [ ] Nothing flashing more than 3 times/s
- [ ] Respect for `prefers-reduced-motion`
- [ ] Timeouts announced or extendable

### Other common AA items
- [ ] Target sizes ≥ 24×24 px (2.5.8)
- [ ] Consistent help location (2.4.11)
- [ ] Accessible authentication without cognitive tests (2.5.9) — if applicable

## How to audit without external tools
1. `list_files` + `read_file` of the HTML/CSS/JS → static analysis against the checklist.
2. Local server + `curl` → verify the elements exist and carry the attributes.
3. If playwright/puppeteer is available, use it to tab through focus and detect issues; otherwise static analysis + manual test instructions with a screen reader (NVDA/VoiceOver).

## Deliverable
`ACCESSIBILITY-<date>.md`:
1. Overall grade (🔴/🟡/🟢) + one-minute summary.
2. Table: WCAG criterion · file:line · problem · concrete fix.
3. Applied fixes (if authorized) with verification.
4. How to test it manually (keyboard + screen reader).

And a chat summary with the 5 most serious problems.

## Useful starting phrases
- "Read `TUNNELAI-SKILL-accesibilidad.md` and audit the site in the root against WCAG 2.2 AA."
- "Review only forms and contrast in `index.html`."
