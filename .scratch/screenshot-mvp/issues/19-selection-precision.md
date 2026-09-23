# 19: Selection precision

**What to build:** selection feels like the built-in tool: a device-pixel magnifier, modifier keys, arrow nudging, and Esc that works even though Frisket isn't the active app.

**Blocked by:** 08

**Status:** resolved (tested on `main` at `3f86bf6`; manual checks pending Prateek, decision 49)

- [ ] (Built; pixel fidelity pending a manual check) A magnifier shows device pixels at the pointer.
- [x] Shift locks an axis, Option grows from the centre, Space moves the selection, arrow keys nudge it.
- [ ] (Built; non-activation pending a manual check) Esc cancels through the overlay's key panel without activating Frisket.
- [x] Selection geometry is unit-tested in the core; Esc without activation is in the manual checklist.

## Comments

### 2026-09-23 — coordinator: resolved (manual checks pending)

- **Implementer:** Codex GPT-6 Astra, high. Report: `reports/19-implementer.md`, which includes the Fix pass.
  - `SelectionGeometry` is a pure core module: Shift, Option, Space, arrow nudge, clamping to the origin display, and device-pixel rounding at 1× and 2× with negative coordinates.
  - Esc is handled by the non-activating key panel, with no monitors or taps.
  - The magnifier reads from a bounded, memory-only snapshot taken with the own-app exclusion filter.
- **Review:** fresh Codex, `reviews/19-code-review-codex.md`, verdict fix-then-merge. One fix pass:
  - Shift+arrow resizes by one device pixel;
  - the axis lock is reset correctly after Space;
  - a shared `ScreenCapturePolicy` now serves both the magnifier and the final capture.
- **Integration:** `integrate/19` passed the root `swift test` (72 tests in 10 suites) and the unsigned `xcodebuild`. `ScreenCapturePlatform.swift` auto-merged with ticket 20, and all capture paths use `ScreenCapturePolicy`. x86_64 only; arm64 not executed.
- **Pending for Prateek:** `docs/manual-checks/19-selection-precision.md`: magnifier fidelity, each modifier, and Esc without activation. It needs a signed build of the current `main` (deferred).
