# 39: Manual hardware checklist, first recorded run

**What to build:** a scripted manual checklist for everything automated tests can't reach, and its first recorded run on this Mac.

**Blocked by:** 18, 19, 20, 21, 23, 24, 32

**Status:** resolved (harness tested on `main` at `9810f19`; hardware first-run pending)

- [x] A bundled test-pattern window at known coordinates and a script that checks output dimensions and marker pixels.
- [x] Each run records date, OS build, commit, architectures and code signature, display layout, and permission state, with no personal pixels.
- [ ] Cases: every Screen Recording state; the built-in Retina plus the external 1x display, including negative coordinates and unplug mid-selection; overlays over full-screen apps and across Space switches; Esc without activation; Full Keyboard Access and VoiceOver on all thumbnail actions; each default shortcut triggering one tool; a permission grant surviving two rebuilds.
- [ ] Prateek performs or approves the hardware steps; results are recorded.

## Comments

### 2026-09-23 — coordinator

Claimed on `e00eed1` after ticket 36 closed. Coordinator chat implements
(Codex/Other Models still limited). Branch `ticket/39-manual-checklist-first-run`.
Hardware cases stay pending for Prateek.

### 2026-09-23 — implementer

Report: [39-implementer.md](../reports/39-implementer.md). Pixel-free record
harness, bundled 320×180 pattern, and the first-run index. Hardware not run.
Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `9575f6f`: [39-code-review.md](../reviews/39-code-review.md).
Justified fixes: capture `codesign` stderr, `lipo` the Mach-O, and read
`_spdisplays_resolution`.

- **Integration:** `integrate/39` fast-forwarded `main` to `9810f19`.
  `Tools/FirstRun/record.py` writes a pixel-free header; live run against
  `~/Applications/Frisket.app` recorded macOS 26.7 (25G229), x86_64, team
  `9M43Q952NK`, one built-in Retina 3584×2240 / 1792×1120, 21 cases pending.
  `FrisketTestPattern` remains the 320×180 centred verifier. Root `swift test`:
  292 tests in 43 suites passed. Unsigned x86_64 `xcodebuild` succeeded
  (`CODE_SIGNING_ALLOWED=NO`). x86_64 only; arm64 not executed. Coordinator
  chat after Codex/Other Models limits. Hardware cases in
  [39-first-run.md](../../../docs/manual-checks/39-first-run.md) remain for
  Prateek (external 1× display, TCC states, VoiceOver, two rebuilds).

- **Coordinator continue (2026-09-23 20:42 CDT):** new pixel-free header
  against the `16e8e3e` install. External 1× 1920×1080 is attached. Isolated
  TCC-account cases marked `blocked`. Grant, both-display captures, shortcuts,
  and VoiceOver remain pending.

- **Coordinator continue (2026-09-23 21:17 CDT):** live synthetic run on the
  21:13 signed debug install recorded 10 first-run passes (grant, two
  rebuilds, both displays, Esc, three default shortcuts, pattern verify).
  Isolated TCC cases stay blocked. Negative coordinates, unplug, overlay
  Space/fullscreen, Full Keyboard Access, and VoiceOver remain pending.
