# Landing Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `Docs/index.html` editorial marketing page with a shorter, demo-first page in a macOS-native visual language, and fix the GitHub Pages deploy (`Docs/` → `docs/` case rename).

**Architecture:** Pure static site under `docs/`. One HTML file, one CSS file, one JS file, a handful of static assets (SVG + mp3 + JSON). No build step, no framework, no external fonts. Deploy via the existing `.github/workflows/pages.yml` (which already expects `docs/`).

**Tech Stack:** HTML5 / CSS custom properties / vanilla ES modules. Web Audio API (`AudioContext` + `AnalyserNode`) for waveform. `say` + `afconvert` for placeholder audio. Git for case-rename.

**Spec:** `docs/superpowers/specs/2026-04-19-landing-redesign-design.md`

---

## File Structure

Files created or modified by this plan (paths reflect the **post-rename** layout — Task 1 does the rename):

- `docs/CNAME` — unchanged
- `docs/index.html` — **rewritten** (replaces current `Docs/index.html`)
- `docs/favicon.svg` — **new**
- `docs/assets/styles.css` — **new**
- `docs/assets/demo.js` — **new**
- `docs/assets/email-mock.svg` — **new**
- `docs/assets/demos/en-sample.mp3` — **new**
- `docs/assets/demos/zh-sample.mp3` — **new**
- `docs/assets/demos/voice-cmd-sample.mp3` — **new**
- `docs/assets/demos/en-sample.json` — **new**
- `docs/assets/demos/zh-sample.json` — **new**
- `docs/assets/demos/voice-cmd-sample.json` — **new**
- `docs/menubar-popover.png` — **deleted** (not referenced by new page)
- `.github/workflows/pages.yml` — **no changes needed** after the rename

The spec file `docs/superpowers/specs/2026-04-19-landing-redesign-design.md` is committed already and carries through the folder rename.

---

## Notes on Testing Approach

This is a static landing page. There is no test framework. Verification is:
1. Local serve with `python3 -m http.server -d docs 8000` and manual browser checks.
2. A written checklist at the end of the plan (Task 10).
3. Post-merge: observe `pages.yml` run and check `https://opentype.idevlab.cn`.

Each task ends with a commit so rollback is cheap.

---

### Task 1: Rename `Docs/` → `docs/` (case rename, two commits)

**Why first:** unblocks the GitHub Pages workflow (which references lowercase `docs/`), and gives every subsequent task the correct final path. Git on a case-insensitive filesystem (macOS) won't record a direct case-only rename — we go through a scratch name.

**Files:**
- Rename: `Docs/` → `docs/` (directory, all contents including spec + plan + CNAME + current index.html + menubar-popover.png)
- Modify: nothing else

- [ ] **Step 1: Inspect current state**

Run:
```bash
ls -la Docs/
git status
```
Expected: `Docs/` contains `CNAME`, `index.html`, `menubar-popover.png`, `superpowers/`. Working tree clean.

- [ ] **Step 2: Rename via a scratch name (first half of case rename)**

Run:
```bash
git mv Docs docs.tmp
```
Expected: no output; `git status` shows `Docs/*` renamed to `docs.tmp/*`.

- [ ] **Step 3: Rename scratch to final lowercase name**

Run:
```bash
git mv docs.tmp docs
```
Expected: no output; `git status` now shows the rename as `Docs/*` → `docs/*` (file contents unchanged).

- [ ] **Step 4: Verify lowercase**

Run:
```bash
ls -la docs/
git ls-files | grep -E '^(D|d)ocs/' | head
```
Expected: folder shows as `docs` lowercase; `git ls-files` shows only `docs/...` (no `Docs/...`).

- [ ] **Step 5: Commit the rename on its own**

```bash
git add -A
git commit -m "Rename Docs/ to docs/ to match Pages workflow path

The pages.yml workflow uses lowercase 'docs/' as both its trigger path
and its artifact upload path. On GitHub's case-sensitive runner this
never matched the existing Docs/ folder, so deploys weren't firing.
Rename is a pure case change; contents unchanged."
```

Why separate commit: if the rename surfaces tooling issues (symlinks, CI caches, client checkouts on case-sensitive FS), it can be reverted without also reverting the new page content.

- [ ] **Step 6: Confirm workflow still references `docs`**

Run:
```bash
grep -n docs .github/workflows/pages.yml
```
Expected (unchanged, lowercase in both places):
```
5:    paths: [docs/**]
29:          path: docs
```
No file edits required.

---

### Task 2: Create `docs/assets/styles.css`

**Files:**
- Create: `docs/assets/styles.css`

- [ ] **Step 1: Create the assets directory**

```bash
mkdir -p docs/assets/demos
```
Expected: no output.

- [ ] **Step 2: Write `docs/assets/styles.css` with full content below**

```css
/* ================================================================
   OpenType — landing page
   macOS system-panel feel. System fonts, system blue accent.
   ================================================================ */

:root {
  --bg: #FAFAFA;
  --panel: #FFFFFF;
  --panel-2: #F2F2F7;
  --text: #1C1C1E;
  --text-secondary: #636366;
  --text-tertiary: #8E8E93;
  --separator: rgba(0, 0, 0, 0.08);
  --accent: #007AFF;
  --accent-hover: #0066D6;
  --accent-subtle: rgba(0, 122, 255, 0.08);
  --shadow-panel: 0 1px 2px rgba(0, 0, 0, 0.04);
  --radius-panel: 12px;
  --radius-button: 8px;
  --max-width: 880px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1C1C1E;
    --panel: #2C2C2E;
    --panel-2: #3A3A3C;
    --text: #F2F2F7;
    --text-secondary: #AEAEB2;
    --text-tertiary: #636366;
    --separator: rgba(255, 255, 255, 0.08);
    --accent: #0A84FF;
    --accent-hover: #1A94FF;
    --accent-subtle: rgba(10, 132, 255, 0.12);
    --shadow-panel: none;
  }
}

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

html { scroll-behavior: smooth; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
               "Helvetica Neue", sans-serif;
  background: var(--bg);
  color: var(--text);
  font-size: 15px;
  line-height: 1.55;
  -webkit-font-smoothing: antialiased;
}

a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }

.wrap { max-width: var(--max-width); margin: 0 auto; padding: 0 24px; }
section { padding: 72px 0; }

/* ── NAV ── */
nav.top {
  position: sticky;
  top: 0;
  z-index: 10;
  background: rgba(250, 250, 250, 0.85);
  backdrop-filter: saturate(180%) blur(16px);
  -webkit-backdrop-filter: saturate(180%) blur(16px);
  border-bottom: 1px solid var(--separator);
}
@media (prefers-color-scheme: dark) {
  nav.top { background: rgba(28, 28, 30, 0.85); }
}
nav.top .wrap {
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.nav-logo { color: var(--text); font-weight: 600; font-size: 15px; letter-spacing: -0.01em; }
.nav-logo:hover { text-decoration: none; }
.nav-right { display: flex; gap: 12px; align-items: center; }

/* ── HERO ── */
#hero { padding: 96px 0; text-align: center; }
h1.tagline {
  font-size: clamp(40px, 7vw, 56px);
  font-weight: 600;
  letter-spacing: -0.02em;
  line-height: 1.05;
  margin-bottom: 16px;
}
.sub { font-size: 17px; color: var(--text-secondary); max-width: 520px; margin: 0 auto 40px; }

/* ── BUTTONS ── */
.btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  border-radius: var(--radius-button);
  font-size: 14px;
  font-weight: 500;
  border: 1px solid var(--separator);
  background: var(--panel);
  color: var(--text);
  cursor: pointer;
  transition: background 0.12s ease;
}
.btn:hover { background: var(--panel-2); text-decoration: none; }
.btn-primary { background: var(--accent); color: #FFFFFF; border-color: transparent; }
.btn-primary:hover { background: var(--accent-hover); color: #FFFFFF; }
.btn-large { padding: 12px 24px; font-size: 15px; }

/* ── TRANSCRIPT DEMO ── */
.demo {
  max-width: 640px;
  margin: 0 auto;
  background: var(--panel);
  border: 1px solid var(--separator);
  border-radius: var(--radius-panel);
  box-shadow: var(--shadow-panel);
  overflow: hidden;
}
.demo-titlebar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 14px;
  background: var(--panel-2);
  border-bottom: 1px solid var(--separator);
}
.demo-dots { display: flex; gap: 6px; }
.demo-dots span {
  width: 10px; height: 10px; border-radius: 50%;
  background: var(--text-tertiary); opacity: 0.5;
}
.mode-toggle {
  display: inline-flex;
  padding: 2px;
  background: var(--bg);
  border-radius: 6px;
  border: 1px solid var(--separator);
}
.mode-toggle button {
  padding: 3px 10px;
  font-size: 12px;
  font-weight: 500;
  background: transparent;
  color: var(--text-secondary);
  border: none;
  border-radius: 4px;
  cursor: pointer;
}
.mode-toggle button[aria-pressed="true"] {
  background: var(--panel);
  color: var(--text);
  box-shadow: var(--shadow-panel);
}

.demo-body {
  padding: 32px 32px 24px;
  min-height: 220px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.waveform {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 3px;
  height: 48px;
}
.waveform .bar {
  width: 3px;
  height: 8px;
  background: var(--accent);
  border-radius: 2px;
  opacity: 0.5;
  transition: height 0.05s linear, opacity 0.2s;
}
.waveform.playing .bar { opacity: 0.85; }

.transcript {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 15px;
  line-height: 1.6;
  color: var(--text);
  min-height: 56px;
  text-align: left;
}
.transcript.placeholder { color: var(--text-tertiary); font-style: italic; }
.verbatim-text { display: block; }
.smart-result {
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  font-size: 17px;
  margin-top: 10px;
  opacity: 0;
  transition: opacity 0.4s ease;
  font-style: normal;
}
.transcript.show-smart .smart-result { opacity: 1; }
.transcript.show-smart .verbatim-text { opacity: 0.35; font-size: 13px; }

.demo-controls {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 20px;
  background: var(--panel-2);
  border-top: 1px solid var(--separator);
}
.demo-play {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  background: var(--accent);
  color: #FFFFFF;
  border: none;
  border-radius: var(--radius-button);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
}
.demo-samples { display: flex; gap: 4px; margin-left: auto; }
.demo-samples button {
  padding: 4px 10px;
  font-size: 12px;
  background: transparent;
  border: none;
  color: var(--text-secondary);
  border-radius: 4px;
  cursor: pointer;
}
.demo-samples button[aria-pressed="true"] {
  background: var(--accent-subtle);
  color: var(--accent);
}

.demo-context {
  display: none;
  margin-top: 12px;
  padding: 10px 12px;
  border: 1px solid var(--separator);
  border-radius: var(--radius-button);
  background: var(--bg);
  gap: 12px;
  align-items: center;
}
.demo-context.visible { display: flex; }
.demo-context .label {
  font-size: 11px;
  color: var(--text-tertiary);
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.demo-context img {
  width: 64px; height: 48px; border-radius: 4px;
  border: 1px solid var(--separator);
}

/* ── THREE-BEAT ── */
.three-beat {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
}
.beat {
  padding: 24px;
  background: var(--panel);
  border: 1px solid var(--separator);
  border-radius: var(--radius-panel);
}
.beat-icon {
  width: 24px; height: 24px; color: var(--text-secondary);
  margin-bottom: 12px;
}
.beat h3 {
  font-size: 17px; font-weight: 600;
  margin-bottom: 6px;
  display: flex; align-items: center; gap: 8px;
}
.keycap {
  display: inline-block;
  padding: 1px 8px;
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 11px;
  background: var(--panel-2);
  border: 1px solid var(--separator);
  border-radius: 4px;
  color: var(--text-secondary);
  font-weight: 400;
}
.beat p { color: var(--text-secondary); font-size: 14px; }

/* ── PRIVACY ── */
.privacy {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 32px;
  align-items: center;
  padding: 32px;
  background: var(--panel);
  border: 1px solid var(--separator);
  border-radius: var(--radius-panel);
}
.privacy strong { display: block; font-size: 20px; font-weight: 600; margin-bottom: 6px; }
.privacy p { color: var(--text-secondary); }
.privacy svg { width: 60px; height: 60px; color: var(--text-tertiary); }

/* ── UNDER THE HOOD ── */
.section-title { font-size: 24px; font-weight: 600; margin-bottom: 24px; letter-spacing: -0.01em; }
.tech-dl {
  display: grid;
  grid-template-columns: 180px 1fr;
  gap: 8px 24px;
  padding: 24px 32px;
  background: var(--panel);
  border: 1px solid var(--separator);
  border-radius: var(--radius-panel);
}
.tech-dl dt {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 13px; font-weight: 500; color: var(--text);
}
.tech-dl dd { font-size: 13px; color: var(--text-secondary); }
.requirements { margin-top: 16px; font-size: 12px; color: var(--text-tertiary); text-align: center; }
.requirements strong { color: var(--text-secondary); font-weight: 500; }

/* ── INSTALL ── */
#install { text-align: center; }
#install h2 { font-size: 32px; font-weight: 600; margin-bottom: 32px; letter-spacing: -0.02em; }
.install-code {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  margin-top: 24px;
  padding: 8px 12px;
  background: var(--panel);
  border: 1px solid var(--separator);
  border-radius: var(--radius-button);
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 13px;
  color: var(--text);
  cursor: pointer;
}
.install-code .copy-label {
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  font-size: 11px;
  color: var(--text-tertiary);
}
.install-caption { margin-top: 8px; font-size: 12px; color: var(--text-tertiary); }
.providers-line {
  margin: 40px auto 0;
  font-size: 12px;
  color: var(--text-tertiary);
  max-width: 600px;
}

/* ── FOOTER ── */
footer { padding: 40px 0; border-top: 1px solid var(--separator); }
footer .wrap {
  display: flex;
  justify-content: center;
  gap: 20px;
  font-size: 12px;
  color: var(--text-secondary);
  flex-wrap: wrap;
}
footer a { color: var(--text-secondary); }
footer a:hover { color: var(--text); text-decoration: none; }

/* ── RESPONSIVE ── */
@media (max-width: 720px) {
  .three-beat { grid-template-columns: 1fr; }
  .privacy { grid-template-columns: 1fr; text-align: center; }
  .privacy svg { margin: 0 auto; }
  .tech-dl { grid-template-columns: 1fr; gap: 4px 0; }
  .tech-dl dt { margin-top: 12px; }
  .tech-dl dt:first-of-type { margin-top: 0; }
  .demo-controls { flex-wrap: wrap; }
  .demo-samples { margin-left: 0; width: 100%; justify-content: center; }
}

/* ── REDUCED MOTION ── */
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after {
    transition-duration: 0.01ms !important;
    animation-duration: 0.01ms !important;
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add docs/assets/styles.css
git commit -m "Add landing page stylesheet tokens and base rules"
```

---

### Task 3: Create `docs/favicon.svg` and `docs/assets/email-mock.svg`

**Files:**
- Create: `docs/favicon.svg`
- Create: `docs/assets/email-mock.svg`

- [ ] **Step 1: Write `docs/favicon.svg`**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#007AFF" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
  <rect x="9" y="2" width="6" height="12" rx="3" fill="#007AFF" stroke="none"/>
  <path d="M5 11a7 7 0 0 0 14 0"/>
  <path d="M12 18v4"/>
  <path d="M8 22h8"/>
</svg>
```

- [ ] **Step 2: Write `docs/assets/email-mock.svg`**

A small fake email thumbnail (120×90). Rendered at 64×48px on the page.

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 90">
  <rect width="120" height="90" fill="#F2F2F7"/>
  <rect x="8" y="8" width="104" height="14" rx="2" fill="#D1D1D6"/>
  <rect x="12" y="12" width="36" height="3" rx="1.5" fill="#636366"/>
  <rect x="12" y="17" width="64" height="2" rx="1" fill="#8E8E93"/>
  <rect x="8" y="28" width="104" height="2" rx="1" fill="#C7C7CC"/>
  <rect x="8" y="34" width="96" height="2" rx="1" fill="#C7C7CC"/>
  <rect x="8" y="40" width="88" height="2" rx="1" fill="#C7C7CC"/>
  <rect x="8" y="46" width="72" height="2" rx="1" fill="#C7C7CC"/>
  <rect x="8" y="58" width="48" height="2" rx="1" fill="#C7C7CC"/>
  <rect x="8" y="72" width="32" height="10" rx="2" fill="#007AFF"/>
</svg>
```

- [ ] **Step 3: Verify size**

```bash
wc -c docs/favicon.svg docs/assets/email-mock.svg
```
Expected: each file < 1500 bytes.

- [ ] **Step 4: Commit**

```bash
git add docs/favicon.svg docs/assets/email-mock.svg
git commit -m "Add favicon and email-mock SVG assets"
```

---

### Task 4: Generate demo audio files with `say` + `afconvert`

These are placeholder voices. They are committed to the repo so GitHub Pages can serve them.

**Files:**
- Create: `docs/assets/demos/en-sample.mp3`
- Create: `docs/assets/demos/zh-sample.mp3`
- Create: `docs/assets/demos/voice-cmd-sample.mp3`

- [ ] **Step 1: Generate English sample via `say`**

```bash
say -v Samantha -r 170 -o /tmp/en-sample.aiff "hey so um, i wanted to— i wanted to follow up on the design doc we talked about"
```
Expected: `/tmp/en-sample.aiff` exists, ~200KB.

- [ ] **Step 2: Convert to AAC in `.mp4` container (served as `audio/mp4`, small enough)**

We use `afconvert` to get AAC. The file extension `.mp3` is kept so paths match the JSON; browsers identify by content, not extension. If an `.mp3` extension is strictly required by a future CDN, these commands can be replaced with `lame` — but for GitHub Pages, the served `Content-Type` doesn't depend on extension for `<audio src>`.

> **Decision:** keep the `.mp3` filename in the spec/JSON, but the actual bytes are AAC-in-MP4 (what `afconvert` produces easily on macOS). All major browsers play it via `<audio>` regardless of extension. This avoids adding an `lame` dependency.

```bash
afconvert -f mp4f -d aac -b 24000 -c 1 /tmp/en-sample.aiff docs/assets/demos/en-sample.mp3
```
Expected: `docs/assets/demos/en-sample.mp3` exists, < 80KB.

- [ ] **Step 3: Generate Chinese sample**

```bash
say -v Tingting -r 180 -o /tmp/zh-sample.aiff "那个，我想问一下，这个接口，呃，是不是周五之前能 review 一下"
afconvert -f mp4f -d aac -b 24000 -c 1 /tmp/zh-sample.aiff docs/assets/demos/zh-sample.mp3
```
Expected: `docs/assets/demos/zh-sample.mp3` exists, < 80KB.

- [ ] **Step 4: Generate Voice Command sample**

```bash
say -v Tingting -r 180 -o /tmp/voice-cmd-sample.aiff "总结一下屏幕上的内容"
afconvert -f mp4f -d aac -b 24000 -c 1 /tmp/voice-cmd-sample.aiff docs/assets/demos/voice-cmd-sample.mp3
```
Expected: `docs/assets/demos/voice-cmd-sample.mp3` exists, < 60KB.

- [ ] **Step 5: Clean up temp files**

```bash
rm /tmp/en-sample.aiff /tmp/zh-sample.aiff /tmp/voice-cmd-sample.aiff
```

- [ ] **Step 6: Verify total size**

```bash
du -k docs/assets/demos/*.mp3
```
Expected: each < 80KB; total < 220KB.

- [ ] **Step 7: Quick playback check**

```bash
afinfo docs/assets/demos/en-sample.mp3 | head -5
```
Expected: "AAC", 1 channel, sample rate stated, duration ~7–9s.

- [ ] **Step 8: Commit**

```bash
git add docs/assets/demos/*.mp3
git commit -m "Add placeholder demo audio clips (en, zh, voice-cmd)"
```

---

### Task 5: Write timing JSON files

Per-sample timestamp metadata drives the per-word reveal in the demo.

**Files:**
- Create: `docs/assets/demos/en-sample.json`
- Create: `docs/assets/demos/zh-sample.json`
- Create: `docs/assets/demos/voice-cmd-sample.json`

- [ ] **Step 1: Write `docs/assets/demos/en-sample.json`**

```json
{
  "sampleId": "en",
  "audio": "en-sample.mp3",
  "verbatim": [
    { "w": "hey",    "t": 0.00 },
    { "w": "so",     "t": 0.35 },
    { "w": "um",     "t": 0.65 },
    { "w": "i",      "t": 1.15 },
    { "w": "wanted", "t": 1.35 },
    { "w": "to—",    "t": 1.75 },
    { "w": "i",      "t": 2.20 },
    { "w": "wanted", "t": 2.40 },
    { "w": "to",     "t": 2.80 },
    { "w": "follow", "t": 3.05 },
    { "w": "up",     "t": 3.50 },
    { "w": "on",     "t": 3.75 },
    { "w": "the",    "t": 3.95 },
    { "w": "design", "t": 4.15 },
    { "w": "doc",    "t": 4.60 },
    { "w": "we",     "t": 4.90 },
    { "w": "talked", "t": 5.10 },
    { "w": "about",  "t": 5.50 }
  ],
  "smart": "Hey, I wanted to follow up on the design doc we talked about."
}
```

- [ ] **Step 2: Write `docs/assets/demos/zh-sample.json`**

```json
{
  "sampleId": "zh",
  "audio": "zh-sample.mp3",
  "verbatim": [
    { "w": "那个",     "t": 0.00 },
    { "w": "我",       "t": 0.55 },
    { "w": "想",       "t": 0.75 },
    { "w": "问",       "t": 0.95 },
    { "w": "一下",     "t": 1.15 },
    { "w": "这个",     "t": 1.55 },
    { "w": "接口",     "t": 1.90 },
    { "w": "呃",       "t": 2.35 },
    { "w": "是不是",   "t": 2.85 },
    { "w": "周五",     "t": 3.50 },
    { "w": "之前",     "t": 3.95 },
    { "w": "能",       "t": 4.35 },
    { "w": "review",   "t": 4.55 },
    { "w": "一下",     "t": 5.20 }
  ],
  "smart": "我想问一下这个接口周五之前能否 review。"
}
```

- [ ] **Step 3: Write `docs/assets/demos/voice-cmd-sample.json`**

```json
{
  "sampleId": "voice-cmd",
  "audio": "voice-cmd-sample.mp3",
  "verbatim": [
    { "w": "总结", "t": 0.30 },
    { "w": "一下", "t": 0.80 },
    { "w": "屏幕", "t": 1.30 },
    { "w": "上的", "t": 1.80 },
    { "w": "内容", "t": 2.20 }
  ],
  "smart": "This email is confirming your flight on Tuesday at 9 AM."
}
```

- [ ] **Step 4: Validate JSON parseability**

```bash
for f in docs/assets/demos/*.json; do
  python3 -c "import json,sys; json.load(open('$f')); print('ok', '$f')"
done
```
Expected: `ok docs/assets/demos/en-sample.json` etc., three `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add docs/assets/demos/*.json
git commit -m "Add per-sample timing JSON for transcript reveal"
```

---

### Task 6: Write `docs/assets/demo.js`

**Files:**
- Create: `docs/assets/demo.js`

- [ ] **Step 1: Write `docs/assets/demo.js`**

```js
// OpenType — Transcript Demo
// Zero dependencies. Reads pre-recorded audio + timing JSON and drives
// the waveform (Web Audio API) + per-word reveal (setTimeout chain).

(() => {
  const SAMPLES = {
    en: 'assets/demos/en-sample.json',
    zh: 'assets/demos/zh-sample.json',
    'voice-cmd': 'assets/demos/voice-cmd-sample.json'
  };

  const $play      = document.getElementById('demo-play');
  const $playLabel = document.getElementById('demo-play-label');
  const $audio     = document.getElementById('demo-audio');
  const $wave      = document.querySelector('.waveform');
  const $bars      = $wave.querySelectorAll('.bar');
  const $trans     = document.querySelector('.transcript');
  const $verb      = $trans.querySelector('.verbatim-text');
  const $smart     = $trans.querySelector('.smart-result');
  const $context   = document.getElementById('demo-context');
  const $samples   = document.querySelectorAll('.demo-samples button');
  const $modes     = document.querySelectorAll('.mode-toggle button');

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let currentSampleId = 'en';
  let currentMode     = 'smart';
  let currentData     = null;
  let audioCtx        = null;
  let analyser        = null;
  let rafId           = null;
  let revealTimers    = [];
  let playing         = false;

  async function loadSample(id) {
    const res = await fetch(SAMPLES[id]);
    return res.json();
  }

  function setSample(id) {
    currentSampleId = id;
    $samples.forEach(b => b.setAttribute('aria-pressed', b.dataset.sample === id ? 'true' : 'false'));
    $context.classList.toggle('visible', id === 'voice-cmd');
    stop();
    loadSample(id).then(data => {
      currentData = data;
      $audio.src = 'assets/demos/' + data.audio;
      resetTranscript();
    });
  }

  function setMode(mode) {
    currentMode = mode;
    $modes.forEach(b => b.setAttribute('aria-pressed', b.dataset.mode === mode ? 'true' : 'false'));
    if (playing) restart();
  }

  function resetTranscript() {
    $trans.classList.remove('show-smart');
    $trans.classList.add('placeholder');
    $verb.textContent  = 'Click play to see it transcribe.';
    $smart.textContent = '';
  }

  function clearTimers() {
    revealTimers.forEach(t => clearTimeout(t));
    revealTimers = [];
  }

  function setupAudioGraph() {
    if (audioCtx) return;
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      audioCtx = new Ctx();
      const source = audioCtx.createMediaElementSource($audio);
      analyser = audioCtx.createAnalyser();
      analyser.fftSize = 64;
      source.connect(analyser);
      analyser.connect(audioCtx.destination);
    } catch (_) {
      audioCtx = null;
      analyser = null;
    }
  }

  function pumpWaveform() {
    if (!analyser) return;
    const bins = analyser.frequencyBinCount;
    const data = new Uint8Array(bins);
    const step = () => {
      analyser.getByteFrequencyData(data);
      $bars.forEach((bar, i) => {
        const v = data[i % bins] / 255;
        const h = Math.max(4, Math.round(v * 44));
        bar.style.height = h + 'px';
      });
      rafId = requestAnimationFrame(step);
    };
    step();
  }

  function stopWaveform() {
    if (rafId) cancelAnimationFrame(rafId);
    rafId = null;
    $bars.forEach(b => { b.style.height = ''; });
  }

  function revealVerbatim() {
    $verb.textContent = '';
    $trans.classList.remove('placeholder');
    for (const { w, t } of currentData.verbatim) {
      revealTimers.push(setTimeout(() => {
        $verb.textContent += (w + ' ');
      }, t * 1000));
    }
  }

  function showSmart() {
    $smart.textContent = currentData.smart;
    $trans.classList.add('show-smart');
  }

  function play() {
    if (!currentData) return;
    if (reducedMotion) {
      resetTranscript();
      $trans.classList.remove('placeholder');
      $verb.textContent = currentData.verbatim.map(v => v.w).join(' ');
      if (currentMode === 'smart') showSmart();
      return;
    }
    setupAudioGraph();
    if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
    clearTimers();
    $wave.classList.add('playing');
    resetTranscript();
    $audio.currentTime = 0;
    $audio.play().catch(() => {});
    pumpWaveform();
    revealVerbatim();
    if (currentMode === 'smart') {
      const lastT = currentData.verbatim[currentData.verbatim.length - 1].t;
      revealTimers.push(setTimeout(showSmart, (lastT + 0.6) * 1000));
    }
    playing = true;
    $playLabel.textContent = 'Stop';
  }

  function stop() {
    clearTimers();
    $audio.pause();
    stopWaveform();
    $wave.classList.remove('playing');
    playing = false;
    $playLabel.textContent = 'Play';
  }

  function restart() { stop(); play(); }

  $play.addEventListener('click', () => (playing ? stop() : play()));
  $audio.addEventListener('ended', () => stop());
  $samples.forEach(b => b.addEventListener('click', () => setSample(b.dataset.sample)));
  $modes.forEach(b => b.addEventListener('click', () => setMode(b.dataset.mode)));

  document.addEventListener('keydown', (e) => {
    const onSampleChip = e.target.matches && e.target.matches('.demo-samples button');
    if (onSampleChip && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
      e.preventDefault();
      const ids  = ['en', 'zh', 'voice-cmd'];
      const i    = ids.indexOf(currentSampleId);
      const next = (i + (e.key === 'ArrowRight' ? 1 : ids.length - 1)) % ids.length;
      setSample(ids[next]);
      document.querySelector('[data-sample="' + ids[next] + '"]').focus();
    }
    if ((e.metaKey || e.ctrlKey) && (e.key === 'm' || e.key === 'M')) {
      e.preventDefault();
      setMode(currentMode === 'smart' ? 'verbatim' : 'smart');
    }
  });

  // install command copy
  const $code  = document.getElementById('install-code');
  const $label = document.getElementById('copy-label');
  if ($code) {
    const copy = async () => {
      const txt = $code.querySelector('code').textContent;
      try { await navigator.clipboard.writeText(txt); } catch (_) {}
      $label.textContent = 'copied';
      setTimeout(() => { $label.textContent = 'copy'; }, 1800);
    };
    $code.addEventListener('click', copy);
    $code.addEventListener('keydown', (e) => { if (e.key === 'Enter') copy(); });
  }

  setSample('en');
})();
```

- [ ] **Step 2: Verify line count stays under budget**

```bash
wc -l docs/assets/demo.js
```
Expected: ≤ 250.

- [ ] **Step 3: Commit**

```bash
git add docs/assets/demo.js
git commit -m "Add transcript demo script (sample loading, Web Audio, reveal)"
```

---

### Task 7: Rewrite `docs/index.html`

**Files:**
- Modify: `docs/index.html` (complete rewrite; replaces the current ~1100-line file)

- [ ] **Step 1: Replace the file contents**

Overwrite `docs/index.html` with:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>OpenType — Voice input for macOS</title>
  <meta name="description" content="Speak. Your Mac types. Privacy-first voice input for the macOS menu bar — runs entirely on-device." />
  <meta name="theme-color" content="#FAFAFA" media="(prefers-color-scheme: light)" />
  <meta name="theme-color" content="#1C1C1E" media="(prefers-color-scheme: dark)" />
  <meta property="og:title" content="OpenType — Voice input for macOS" />
  <meta property="og:description" content="Speak. Your Mac types. Privacy-first voice input that runs entirely on your Mac." />
  <meta property="og:type" content="website" />
  <link rel="icon" type="image/svg+xml" href="favicon.svg" />
  <link rel="stylesheet" href="assets/styles.css" />
</head>
<body>

  <nav class="top">
    <div class="wrap">
      <a href="#" class="nav-logo">OpenType</a>
      <div class="nav-right">
        <a class="btn" href="https://github.com/IchenDEV/opentype">GitHub</a>
        <a class="btn btn-primary" href="https://github.com/IchenDEV/opentype/releases/latest">Download</a>
      </div>
    </div>
  </nav>

  <section id="hero">
    <div class="wrap">
      <h1 class="tagline">Speak.<br/>Your Mac types.</h1>
      <p class="sub">Voice input that lives in your menu bar. Hold a key, speak naturally — polished text appears at your cursor, entirely on-device.</p>

      <div class="demo" role="region" aria-label="Live transcript demo">
        <div class="demo-titlebar">
          <div class="demo-dots" aria-hidden="true"><span></span><span></span><span></span></div>
          <div class="mode-toggle" role="group" aria-label="Output mode">
            <button type="button" data-mode="verbatim" aria-pressed="false">Verbatim</button>
            <button type="button" data-mode="smart" aria-pressed="true">Smart Format</button>
          </div>
        </div>
        <div class="demo-body">
          <div class="waveform" aria-hidden="true">
            <span class="bar"></span><span class="bar"></span><span class="bar"></span><span class="bar"></span>
            <span class="bar"></span><span class="bar"></span><span class="bar"></span><span class="bar"></span>
            <span class="bar"></span><span class="bar"></span><span class="bar"></span><span class="bar"></span>
            <span class="bar"></span><span class="bar"></span><span class="bar"></span><span class="bar"></span>
            <span class="bar"></span><span class="bar"></span><span class="bar"></span><span class="bar"></span>
            <span class="bar"></span><span class="bar"></span><span class="bar"></span><span class="bar"></span>
          </div>
          <div class="transcript placeholder" aria-live="polite">
            <span class="verbatim-text">Click play to see it transcribe.</span>
            <div class="smart-result"></div>
          </div>
          <div class="demo-context" id="demo-context">
            <span class="label">Screen context</span>
            <img src="assets/email-mock.svg" alt="Fake email thumbnail showing flight confirmation"/>
          </div>
        </div>
        <div class="demo-controls">
          <button class="demo-play" id="demo-play" type="button">
            <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path fill="currentColor" d="M1 0v10l8-5z"/></svg>
            <span id="demo-play-label">Play</span>
          </button>
          <div class="demo-samples" role="group" aria-label="Sample">
            <button type="button" data-sample="en" aria-pressed="true">EN sample</button>
            <button type="button" data-sample="zh" aria-pressed="false">ZH sample</button>
            <button type="button" data-sample="voice-cmd" aria-pressed="false">Voice cmd</button>
          </div>
        </div>
        <audio id="demo-audio" preload="auto" aria-hidden="true"></audio>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap">
      <div class="three-beat">
        <div class="beat">
          <svg class="beat-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="2" y="6" width="20" height="12" rx="2"/>
            <path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M6 14h12"/>
          </svg>
          <h3>Hold <span class="keycap">fn</span></h3>
          <p>Press and hold your configured key — fn, ⌃, ⇧, or ⌥. Recording starts instantly.</p>
        </div>
        <div class="beat">
          <svg class="beat-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="9" y="2" width="6" height="12" rx="3"/>
            <path d="M5 11a7 7 0 0 0 14 0"/>
            <path d="M12 18v4"/>
            <path d="M8 22h8"/>
          </svg>
          <h3>Speak</h3>
          <p>Talk like you would to a person. Audio never leaves your Mac.</p>
        </div>
        <div class="beat">
          <svg class="beat-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M12 3v18"/>
            <path d="M9 3h6"/>
            <path d="M9 21h6"/>
          </svg>
          <h3>Release</h3>
          <p>Let go. Polished text appears at your cursor, in any app.</p>
        </div>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap">
      <div class="privacy">
        <div>
          <strong>Nothing leaves your Mac.</strong>
          <p>WhisperKit transcribes locally. MLX-Qwen refines locally. Audio is never uploaded, never stored.</p>
        </div>
        <svg viewBox="0 0 60 60" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
          <rect x="8" y="12" width="44" height="28" rx="3"/>
          <path d="M4 44h52l-4 6H8z"/>
          <rect x="24" y="22" width="12" height="10" rx="1"/>
          <path d="M26 22v-3a4 4 0 0 1 8 0v3" stroke-linecap="round"/>
        </svg>
      </div>
    </div>
  </section>

  <section>
    <div class="wrap">
      <h2 class="section-title">Under the hood</h2>
      <dl class="tech-dl">
        <dt>WhisperKit</dt><dd>Offline speech recognition</dd>
        <dt>MLX-Swift-LM</dt><dd>On-device LLM inference</dd>
        <dt>Swift 6</dt><dd>Native, no cross-platform wrappers</dd>
        <dt>ScreenCaptureKit</dt><dd>Screen context via OCR</dd>
        <dt>AVAudioEngine</dt><dd>Low-latency mic capture</dd>
        <dt>Vision</dt><dd>On-device OCR for homophone correction</dd>
      </dl>
      <p class="requirements">
        Runs on <strong>macOS 26+</strong> · <strong>Apple Silicon</strong> only · <strong>MIT licensed</strong>
      </p>
    </div>
  </section>

  <section id="install">
    <div class="wrap">
      <h2>Ready to try?</h2>
      <a class="btn btn-primary btn-large" href="https://github.com/IchenDEV/opentype/releases/latest">
        Download for macOS
      </a>
      <div class="install-code" id="install-code" role="button" tabindex="0" aria-label="Copy Gatekeeper command">
        <code>xattr -cr /Applications/OpenType.app</code>
        <span class="copy-label" id="copy-label">copy</span>
      </div>
      <p class="install-caption">Run once if macOS shows a Gatekeeper prompt.</p>
      <p class="providers-line">
        Works with OpenAI, Claude, Gemini, OpenRouter, SiliconFlow, Doubao, Bailian, MiniMax — or any OpenAI-compatible endpoint.
      </p>
    </div>
  </section>

  <footer>
    <div class="wrap">
      <a href="https://github.com/IchenDEV/opentype">GitHub</a>
      <a href="https://github.com/IchenDEV/opentype/releases">Releases</a>
      <a href="https://github.com/IchenDEV/opentype/issues">Issues</a>
      <a href="https://github.com/IchenDEV/opentype/blob/main/LICENSE">MIT</a>
      <span>Built for Apple Silicon</span>
    </div>
  </footer>

  <script src="assets/demo.js" defer></script>
</body>
</html>
```

- [ ] **Step 2: Check file size budget**

```bash
wc -l docs/index.html
```
Expected: ≤ 250 lines.

- [ ] **Step 3: Serve locally and open**

```bash
python3 -m http.server -d docs 8000
```
In another terminal / browser, open http://localhost:8000

Visually confirm:
- Nav with logo + GitHub + Download
- Hero h1 "Speak. / Your Mac types." + demo panel with ● ● ● titlebar
- Three-beat row (Hold / Speak / Release)
- Privacy callout panel
- Under the hood table
- Install section with button + `xattr` box
- Footer row

Don't worry about demo interactivity yet (next task verifies it). Kill server with Ctrl+C.

- [ ] **Step 4: Commit**

```bash
git add docs/index.html
git commit -m "Rewrite landing page with demo-first layout"
```

---

### Task 8: End-to-end manual verification of the demo

**Files:** none (verification only)

- [ ] **Step 1: Serve locally**

```bash
python3 -m http.server -d docs 8000
```

- [ ] **Step 2: Verify EN sample**

In the browser at http://localhost:8000:

- Click `▶ Play` with toggle on `Smart Format` (default).
- Expected: waveform animates driven by audio; the verbatim text reveals word-by-word ("hey so um i wanted to— ..."); about 0.6s after the last word, the smart-format sentence ("Hey, I wanted to follow up on the design doc we talked about.") fades in below.
- Click ▶ again to stop. The button label toggles Play ↔ Stop.

- [ ] **Step 3: Verify Verbatim mode**

- Click the `Verbatim` toggle.
- Click Play.
- Expected: verbatim reveals the same as before, but no smart-format line appears after.

- [ ] **Step 4: Verify ZH sample**

- Click `ZH sample` chip.
- Audio changes (Tingting voice); transcript area resets; click Play.
- Expected: Chinese verbatim reveals character-by-character; smart sentence "我想问一下这个接口周五之前能否 review。" fades in after.

- [ ] **Step 5: Verify Voice Command sample**

- Click `Voice cmd` chip.
- Expected: below the demo body, a "Screen context" thumbnail appears showing the fake email (`email-mock.svg`).
- Click Play.
- Expected: verbatim shows "总结 一下 屏幕 上的 内容"; smart-format line shows the English email summary.
- Click another sample chip — the screen-context thumbnail disappears.

- [ ] **Step 6: Verify keyboard access**

- Tab through the page. Confirm Tab order:
  nav logo → GitHub link → Download link → Verbatim → Smart Format → Play → EN chip → ZH chip → Voice cmd chip → (subsequent page links).
- With focus on a sample chip, press `→`. Focus and selection move to the next sample.
- Press `⌘M` (macOS) or `CtrlM` (other). The mode toggle flips.

- [ ] **Step 7: Verify reduced motion**

In Safari: Develop → Experimental Features → toggle "Reduced Motion" → reload.
Or: macOS Settings → Accessibility → Display → Reduce Motion → reload.

- Click Play on any sample. Expected: no waveform animation, no audio playback, the verbatim + smart-format text appear immediately as final strings.

- [ ] **Step 8: Verify dark mode**

macOS Settings → Appearance → Dark. Reload page.
Expected: all panels use dark tokens (`#1C1C1E`, `#2C2C2E`, etc.); text is readable; accent stays blue; no amber / orange anywhere.

- [ ] **Step 9: Verify narrow viewport**

Devtools → toggle device emulation → iPhone 12 (390×844).
Expected:
- Three-beat row stacks vertically.
- Privacy callout stacks (icon below text, centered).
- Under-the-hood dl collapses to one column.
- Demo panel remains usable; controls wrap to two rows.

- [ ] **Step 10: Stop server**

Ctrl+C in the terminal running `python3 -m http.server`.

- [ ] **Step 11: Commit a note file**

No files change in this task. If earlier tasks missed any fix, add it now and commit before moving on. Otherwise skip.

---

### Task 9: Delete the now-unused `menubar-popover.png`

**Why:** the spec explicitly states the screenshot is not used on this page. Leaving it in `docs/` adds ~200KB to the Pages artifact and causes confusion about whether it's rendered.

**Files:**
- Delete: `docs/menubar-popover.png`

- [ ] **Step 1: Confirm no reference**

```bash
grep -r "menubar-popover" docs/ || echo "no references"
```
Expected: `no references`.

- [ ] **Step 2: Delete and commit**

```bash
git rm docs/menubar-popover.png
git commit -m "Remove unused menubar-popover screenshot"
```

---

### Task 10: Lighthouse + deploy verification

**Files:** none (verification + push).

- [ ] **Step 1: Run Lighthouse locally (optional but recommended)**

Serve `docs/` again:
```bash
python3 -m http.server -d docs 8000
```

Open Chrome → devtools → Lighthouse tab → Mobile → Run.

Expected thresholds:
- Performance ≥ 90
- Accessibility ≥ 95
- Best Practices ≥ 95
- SEO ≥ 90

If Accessibility < 95, check the devtools console for missing labels / contrast issues and fix in a follow-up commit before proceeding.

Stop server (Ctrl+C).

- [ ] **Step 2: Push branch & open PR**

```bash
git push -u origin HEAD
```
Expected: branch pushed to origin; terminal outputs a PR creation URL.

Open PR on GitHub. Title: `Redesign landing page (demo-first, macOS-native)`. Body should point at the spec (`docs/superpowers/specs/2026-04-19-landing-redesign-design.md`).

- [ ] **Step 3: After merge, watch Pages deploy**

```bash
gh run watch --workflow=pages.yml
```
Expected: workflow triggered by merge to `main`, runs in < 1 minute, deploy succeeds with artifact upload from `docs/`.

- [ ] **Step 4: Verify live URL**

Open `https://opentype.idevlab.cn` — may take up to 5 minutes to propagate Pages + CDN.

Check:
- [ ] New tagline "Speak. / Your Mac types." visible
- [ ] Clicking `▶ Play` plays audio and reveals transcript
- [ ] Sample chips swap content
- [ ] Favicon (blue mic) visible in tab
- [ ] No console errors

- [ ] **Step 5: Close out**

If live verification passes, the feature is done. If live URL still shows the old page after 10 minutes, check:
1. Pages settings in repo → Source must be "GitHub Actions" (not "Deploy from branch").
2. `.github/workflows/pages.yml` run logs for artifact upload errors.
3. Browser cache / Cloudflare cache (`opentype.idevlab.cn` may be behind one).

---

## Self-Review

Spec coverage check:

| Spec requirement | Task |
|---|---|
| Rename `Docs/` → `docs/` | Task 1 |
| Light/dark tokens, typography, spacing | Task 2 |
| Favicon, email-mock SVG | Task 3 |
| Three sample mp3s via `say` + `afconvert` | Task 4 |
| Timing JSON shape + all three samples | Task 5 |
| `demo.js` sample loading, Web Audio, reveal, reduced-motion, keyboard | Task 6 |
| Hero / three-beat / privacy / tech / install / footer markup | Task 7 |
| Voice Command sample shows screen-context thumbnail | Task 6 (logic) + Task 7 (markup) + Task 8 Step 5 (verify) |
| Copy-to-clipboard on `xattr` command | Task 6 (handler) + Task 7 (markup) |
| Removed: Modes section, features grid, providers grid, emoji, Google Fonts | Task 7 (by construction) |
| No build step / no frameworks / no JS deps | Tasks 2, 6 (by construction) |
| Accessibility: aria-live, `aria-pressed`, keyboard | Tasks 6 and 7 |
| `prefers-reduced-motion` fallback | Task 2 (CSS) + Task 6 (JS) |
| `prefers-color-scheme` dark mode | Task 2 |
| Lighthouse ≥ 90/95/95 | Task 10 |
| Delete `menubar-popover.png` | Task 9 |
| Pages workflow: no edit needed | Task 1 Step 6 |

No placeholders. No "TBD". Every step has either exact code or an exact command with expected output. Type/name consistency: `currentMode`, `currentSampleId`, `currentData`, `revealTimers`, element IDs (`demo-play`, `demo-play-label`, `demo-audio`, `install-code`, `copy-label`) all match between Task 6 (`demo.js`) and Task 7 (`index.html`). CSS classes (`.demo`, `.demo-titlebar`, `.mode-toggle`, `.waveform`, `.transcript`, `.verbatim-text`, `.smart-result`, `.demo-context`, `.demo-play`, `.demo-samples`) match between Task 2 (styles) and Task 7 (markup).
