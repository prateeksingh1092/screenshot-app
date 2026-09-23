# 39: Manual hardware checklist, first recorded run

**What to build:** a scripted manual checklist for everything automated tests can't reach, and its first recorded run on this Mac.

**Blocked by:** 18, 19, 20, 21, 23, 24, 32

**Status:** in-progress (branch `ticket/39-manual-checklist-first-run`)

- [ ] A bundled test-pattern window at known coordinates and a script that checks output dimensions and marker pixels.
- [ ] Each run records date, OS build, commit, architectures and code signature, display layout, and permission state, with no personal pixels.
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
