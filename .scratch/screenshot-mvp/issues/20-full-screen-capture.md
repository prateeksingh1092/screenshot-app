# 20: Full-screen capture

**What to build:** a shortcut or menu item captures the whole display under the pointer into a thumbnail.

**Blocked by:** 08

**Status:** resolved (tested on `main` at `58f0b2f`; manual checklist pending Prateek, decision 49)

- [x] Captures the display at its native pixel scale, excluding Frisket's own windows.
- [x] Issued through the command layer; seam 1 test with a fixture display.
- [ ] (Checklist written; runs pending) Manual checklist case on each test display.

## Comments

### 2026-09-23 — coordinator: resolved (manual runs pending)

- **Implementer:** Codex GPT-6 Astra, high. Report: `reports/20-implementer.md`.
  - Adds a `captureFullScreen` command and a **Capture Full Screen** menu item. The trigger is the menu item only: no second Carbon hot key, since shortcuts belong to ticket 24.
  - The seam 1 test covers 1×, 2× and negative-coordinate fixture displays.
- **Review:** fresh Codex, `reviews/20-code-review-codex.md`: no findings, verdict merge.
- **Integration:** `integrate/20` passed the root `swift test` (60 tests in 9 suites) and the unsigned `xcodebuild`. x86_64 only; arm64 not executed.
- **Pending for Prateek:** `docs/manual-checks/20-full-screen-capture.md` on the built-in Retina display, the external 1× display and a negative-coordinate arrangement. It needs a signed build of the current `main` (deferred: `codesign` and `ditto` are outside the allowlist).
