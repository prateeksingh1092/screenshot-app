# 21: Window capture

**What to build:** Prateek hovers to highlight a window on the current Space and clicks to capture that window alone.

**Blocked by:** 08

**Status:** resolved (tested on `main` at `1e40a4d`; synthetic window capture pending)

- [x] Only windows visible on the current Space are candidates; minimized windows and other Spaces are out of scope.
- [x] The highlight ignores Frisket's own panels, and Frisket's windows never appear in the capture.
- [x] Esc cancels without activating Frisket.
- [x] Seam 1 test with a fixture window list; manual checklist case with the test-pattern window.

## Comments

### 2026-09-23 — coordinator: resolved

Batch-integrated with ticket 10. Floating-window fix included. Manual: test-pattern window.
