# Landing page redesign — "Live Transcript, macOS-native feel"

**Date:** 2026-04-19
**Status:** Draft, awaiting user sign-off
**Replaces:** `Docs/index.html` (current editorial/amber marketing page)
**Deploys to:** `https://opentype.idevlab.cn` via GitHub Pages (`.github/workflows/pages.yml`)

## Goals

1. Replace the existing ~1100-line editorial landing page with a shorter, demo-first page that feels like a macOS system panel.
2. Fix the broken GitHub Pages deploy: workflow references lowercase `docs/` while the folder is `Docs/` (case-sensitive runner likely breaks deploys).
3. Keep the site as pure static HTML/CSS/JS — no build step, no framework, no external font/JS dependencies except three small audio files for the demo.

## Non-goals

- No Chinese-localized page (`index.zh.html`) this round.
- No build tooling (Vite/Parcel/PostCSS).
- No analytics, cookie banner, newsletter.
- No manual dark/light toggle UI — rely on `prefers-color-scheme`.
- No changes to `README.md` or in-app content.
- No real Whisper/MLX inference in the browser — the demo is a scripted reveal driven by pre-recorded audio + timing JSON.

## Direction

**Live Transcript, macOS-native feel.** The product's core claim is "speak and text appears." The most honest presentation is to make that act the hero of the page, not wrap it in marketing copy. Visual language drops the current amber/Cormorant editorial style for a restrained macOS Sequoia/Tahoe system-panel look.

## Information architecture

| # | Block | Purpose | ~Height |
|---|---|---|---|
| 0 | Nav | logo · Download · GitHub. 3 items, no menu. | 56px |
| 1 | Hero + Transcript Demo | tagline + playable demo component | ~100vh |
| 2 | Three-beat row | Hold → Speak → Release, one sentence each | ~40vh |
| 3 | Privacy callout | "Nothing leaves your Mac" with small MacBook+lock icon | ~30vh |
| 4 | Under the hood | 6-row `<dl>` tech list | ~50vh |
| 5 | Install | Download button + `xattr` command + provider-support line | ~50vh |
| 6 | Footer | single-line links, 12px secondary | 60px |

Total: 3–3.5 viewports (current page is ~8).

**Removed from current page:** Modes section (folded into demo toggle), Features 9-cell grid, Providers chips grid (merged into Install line), scroll-reveal animations everywhere, Google Fonts (Cormorant Garamond + IBM Plex), emoji icons.

## Visual language

**Font stack (no Google Fonts request):**
```
-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
"Helvetica Neue", sans-serif
```
Code block uses `ui-monospace`. No uppercase text-transform anywhere — macOS HIG avoids all-caps.

**Type scale:**
- Display (hero tagline): 48–56px, weight 600, letter-spacing −0.02em
- Body: 15px / line-height 1.55, weight 400
- Caption / meta: 12px, weight 500, color secondary

**Color tokens:**

| Token | Light | Dark |
|---|---|---|
| `--bg` | `#FAFAFA` | `#1C1C1E` |
| `--panel` | `#FFFFFF` | `#2C2C2E` |
| `--panel-2` | `#F2F2F7` | `#3A3A3C` |
| `--text` | `#1C1C1E` | `#F2F2F7` |
| `--text-secondary` | `#636366` | `#AEAEB2` |
| `--text-tertiary` | `#8E8E93` | `#636366` |
| `--separator` | `rgba(0,0,0,0.08)` | `rgba(255,255,255,0.08)` |
| `--accent` | `#007AFF` | `#0A84FF` |
| `--accent-subtle` | `rgba(0,122,255,0.08)` | `rgba(10,132,255,0.12)` |

Dark mode via `@media (prefers-color-scheme: dark)` — no toggle.

**Shape & spacing:**
- Radii: panel 12px, button 8px, chip 6px.
- Borders: 1px `--separator`. Optional `0 1px 2px rgba(0,0,0,0.04)` shadow on light mode only.
- Grid unit: 4px. All padding/margin is a multiple of 4.
- Max content width: 880px.

**Motion:**
- Only the Transcript Demo animates (waveform + per-word reveal).
- No scroll-reveal, no hover transforms, no fade-ups anywhere else.
- `prefers-reduced-motion: reduce` → demo shows final transcript immediately, no audio autoplay, no waveform animation.

**Icons:** inline SF-Symbols-style line SVGs (single stroke, currentColor). No emoji.

## Transcript Demo component (core)

Panel ~640 × 380px, rounded 12px, `--panel` background, 1px `--separator` border.

### Layout

```
┌─────────────────────────────────────────────────────┐
│  ● ● ●                              [Verbatim|Smart]│ title bar
├─────────────────────────────────────────────────────┤
│   ┃┃┃┃▌▌▌▌▊▊▊▋▋▋▌▌▌▌▌▌▌▎▎▎▎┃┃┃   waveform (40px) │
│                                                     │
│   "Hey so um I wanted to— I wanted to follow up"    │ transcript
│    (appearing character-by-character)               │ (16px mono)
├─────────────────────────────────────────────────────┤
│   [▶ Play]   EN sample · ZH sample · Voice cmd      │ controls
└─────────────────────────────────────────────────────┘
```

### Samples

Assets live under `docs/assets/demos/`. Each sample has one `.mp3` plus one `.json` timing file.

| Sample | Audio (~duration) | Verbatim output | Smart Format output |
|---|---|---|---|
| **EN** | `en-sample.mp3` (~8s) | "hey so um i wanted to— i wanted to follow up on the design doc we talked about" | "Hey, I wanted to follow up on the design doc we talked about." |
| **ZH** | `zh-sample.mp3` (~8s) | "那个 我想问一下 这个接口 呃 是不是周五之前能 review 一下" | "我想问一下这个接口周五之前能否 review。" |
| **Voice Command** | `voice-cmd-sample.mp3` (~6s) | "总结一下屏幕上的内容" | "This email is confirming your flight on Tuesday at 9 AM." (with email-mock.svg shown as screen-context hint) |

Timing JSON shape:
```json
{
  "sampleId": "en",
  "audio": "en-sample.mp3",
  "verbatim": [{ "w": "hey", "t": 0.0 }, { "w": "so", "t": 0.3 }, ...],
  "smart": "Hey, I wanted to follow up on the design doc we talked about."
}
```

### Interaction

1. **Default state** — waveform static (flat low-amplitude gray bars). Transcript area shows placeholder `Click play to see it transcribe.`. Toggle defaults to `Smart Format`.
2. **Click ▶** — audio plays, waveform driven by `AudioContext` + `AnalyserNode` (real amplitude, not CSS keyframes), verbatim text reveals word-by-word per timing JSON. When audio ends, if toggle is `Smart Format`, the verbatim text fades out and the `smart` string fades in.
3. **Toggle while playing** — restart current sample from zero with new output behavior.
4. **Switch sample** — audio and timing swap, waveform resets, auto-plays once from zero.
5. **Voice Command sample only** — below the demo a small "Screen context" thumbnail appears showing `email-mock.svg`. Hidden for the other two samples.

### Tech

- Zero framework. One `demo.js` file, zero JS dependencies, target ≤ 250 lines.
- Web Audio API: `AudioContext` → `AnalyserNode` (fftSize 64) → read 8 frequency bins → set bar heights.
- Each mp3 ≤ 80KB, mono 8kHz. Total audio payload < 220KB.

### Fallback & accessibility

- No Web Audio → waveform falls back to CSS keyframe animation on play.
- `prefers-reduced-motion: reduce` → clicking ▶ immediately sets transcript to final result, skipping animation and audio playback.
- Keyboard: Tab reaches ▶ and all three sample chips; Enter plays; Left/Right arrows cycle samples; Cmd/Ctrl+M toggles Verbatim/Smart.
- `<audio>` element is real and has `<track kind="captions">` pointing at the Smart Format text as WebVTT.
- Transcript container has `aria-live="polite"`; screen readers announce the final result, not every word flicker.

## Other section content

### Three-beat row

Three equal-width panels, one line each. No animation, no hover.

| # | SF-Symbols icon | Keycap | Title | Body |
|---|---|---|---|---|
| 1 | `keyboard` | `fn` | Hold | Press and hold your configured key — `fn`, `⌃`, `⇧`, or `⌥`. Recording starts instantly. |
| 2 | `mic` | — | Speak | Talk like you would to a person. Audio never leaves your Mac. |
| 3 | `text.cursor` | — | Release | Let go. Polished text appears at your cursor, in any app. |

### Privacy callout

One panel, centered. Text:

> **Nothing leaves your Mac.**
> WhisperKit transcribes locally. MLX-Qwen refines locally. Audio is never uploaded, never stored.

Right side: ~60×60px SVG of a MacBook silhouette containing a lock icon. Monochrome, `--text-tertiary`.

### Under the hood

Single-column `<dl>`, six rows, mono left / regular right:

```
WhisperKit       Offline speech recognition
MLX-Swift-LM     On-device LLM inference
Swift 6          Native, no cross-platform wrappers
ScreenCaptureKit Screen context via OCR
AVAudioEngine    Low-latency mic capture
Vision           On-device OCR for homophone correction
```

Below, one small-caption line:
> Runs on **macOS 26+** · **Apple Silicon** only · **MIT licensed**

### Install

Centered, three elements max:

1. Button: `Download for macOS` → `https://github.com/IchenDEV/opentype/releases/latest`
2. Mono code box (click-to-copy):
   ```
   xattr -cr /Applications/OpenType.app
   ```
   Caption: `Run once if macOS shows a Gatekeeper prompt.`
3. Secondary-color line:
   > Works with OpenAI, Claude, Gemini, OpenRouter, SiliconFlow, Doubao, Bailian, MiniMax — or any OpenAI-compatible endpoint.

### Footer

Single centered line, 12px `--text-secondary`:

`OpenType · GitHub · Releases · Issues · MIT · Built for Apple Silicon`

## File structure

```
docs/                                  # (renamed from Docs/)
├── CNAME                              # unchanged: opentype.idevlab.cn
├── index.html                         # rewritten, target < 250 lines
├── favicon.svg                        # new: line-art mic icon, ≤ 1KB
├── assets/
│   ├── styles.css                     # new, target < 400 lines
│   ├── demo.js                        # new, target < 250 lines
│   ├── screenshot-menubar.png         # renamed from menubar-popover.png (not used in first viewport; retained for future)
│   ├── email-mock.svg                 # new: fake email thumbnail for voice-cmd sample
│   └── demos/
│       ├── en-sample.mp3
│       ├── en-sample.json
│       ├── zh-sample.mp3
│       ├── zh-sample.json
│       ├── voice-cmd-sample.mp3
│       └── voice-cmd-sample.json
└── superpowers/
    └── specs/
        └── 2026-04-19-landing-redesign-design.md   # this file
```

## Asset generation

All generation is scripted so a future contributor can regenerate:

- **mp3:** `say -v Samantha -o /tmp/en-sample.aiff "..."` then `afconvert -f mp4f -d aac -b 24000 -c 1 /tmp/en-sample.aiff docs/assets/demos/en-sample.mp3`. Samantha for English, Tingting for Chinese. Placeholder quality — replace with human recordings before any "v1.0" announcement if desired.
- **timing JSON:** hand-written. English ~0.3s/word, Chinese ~0.2s/char. Rough alignment is fine; the demo reveals by timestamp, not by strict ASR alignment.
- **email-mock.svg:** pure SVG, ≤ 1KB, two gray rects for header/body, two light-gray rects for text lines. No raster.
- **favicon.svg:** two-path line mic icon, 24×24 viewBox, `currentColor`.

## Deployment fix

Two problems today in `.github/workflows/pages.yml`:
1. Trigger path `paths: [docs/**]` — case-sensitive on the GitHub runner, so pushes touching `Docs/` never trigger.
2. `upload-pages-artifact` `path: docs` — same case issue.

Fix: rename the folder `Docs` → `docs`. The workflow already expects lowercase. Git case-rename requires two steps because macOS is case-insensitive:

```
git mv Docs docs.tmp
git mv docs.tmp docs
```

No workflow changes needed after the rename.

## Scope guardrails (explicit non-changes)

- No JS dependencies.
- No CSS framework.
- No build step.
- No server-side code.
- No `README.md` changes.
- No in-app Swift code changes.
- No Chinese localized page this round.
- No manual dark-mode toggle.
- No changelog page, no docs pages, no blog.

## Verification checklist

Manual verification, no unit tests.

Local:
1. `python3 -m http.server -d docs 8000`
2. Open http://localhost:8000
3. Verify:
   - [ ] All three samples play; waveform responds to audio amplitude
   - [ ] Verbatim/Smart toggle changes final output text
   - [ ] Voice Command sample shows `email-mock.svg` thumbnail; others hide it
   - [ ] `prefers-reduced-motion: reduce` disables animation and autoplay
   - [ ] Light and dark `prefers-color-scheme` both render correctly
   - [ ] Keyboard Tab order reaches every interactive element
   - [ ] iPhone-width (390px) reflows three-beat row to stacked
   - [ ] Lighthouse mobile: Performance ≥ 90, Accessibility ≥ 95, Best Practices ≥ 95

Post-merge:
- [ ] `.github/workflows/pages.yml` run succeeds on `main`
- [ ] `https://opentype.idevlab.cn` serves the new page within 5 minutes of deploy

## Risks

1. **Case rename in Git** may be surfaced inconsistently across clients. Mitigation: split the rename and the content rewrite into two separate commits so either can be reverted.
2. **Browser autoplay blocks** audio until user gesture. Mitigation: no autoplay; audio only starts on ▶ click.
3. **iOS Safari `AnalyserNode` amplitude range differs.** Mitigation: normalize amplitude to 0–1 before applying to bar height.
4. **`opentype.idevlab.cn` DNS in mainland China** out of scope — noted only.
5. **Non-Apple OS font fallback** (Windows/Linux visitors see Helvetica → Arial). Acceptable; the product is macOS-only.

## Open questions / defaults locked in

| # | Question | Default (locked unless user overrides) |
|---|---|---|
| Q1 | Real-human vs `say`-synthesized sample audio? | `say`-synthesized placeholder; replaceable later |
| Q2 | Voice Command screen-context artwork? | Email thumbnail (generic) |
| Q3 | Keep any amber accent? | No. System blue only |
| Q4 | Hero tagline? | **"Speak. Your Mac types."** (2 words each, verb-first) |
| Q5 | Download link target? | `/releases/latest` (GitHub auto-redirects) |
| Q6 | Keep existing menubar screenshot in hero? | No. File retained under `assets/` for future but not rendered on this page |

## Success criteria

- Lighthouse mobile: Performance ≥ 90, Accessibility ≥ 95, Best Practices ≥ 95.
- First-viewport TTI < 1.5s (pure static).
- Total gzip payload < 350KB including three mp3s.
- `https://opentype.idevlab.cn` serves the new page within 5 minutes of merge to `main`.
