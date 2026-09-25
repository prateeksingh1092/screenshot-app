# Ticket 18 — fresh Codex review (GPT-6 Astra, high), 2026-09-23

Fixed point `ffbbf48`, snapshot `c4e4834`. The review was launched before the 02:22 directive that pairs Codex implementations with Opus reviewers.

## Standards

No findings.
- `DisplaySelectionSession` keeps the display policy behind a small interface and reuses `SelectionGeometry`.
- The unplug stand-in verifies, through the command seam, that the selection cancels, that no Pending capture or clipboard write occurs, and that the budget is recovered.
- The synthetic helper's native full-screen mode is justified by the checklist, and it still draws only synthetic content.
- The permission gating and History paths are untouched.

## Spec

- **Should-fix — `Frisket/Adapters/ScreenCapturePlatform.swift:38`:** Space changes are observed only while the panels are visible. Two consequences:
  - A switch during asynchronous preview preparation can show a magnifier from the old Space.
  - A switch during the final capture can admit pixels from a different Space, because the check after the `await` compares only display IDs, frames and scales.

  Track Space changes from preview preparation through capture completion. Discard invalidated previews, keep the rectangle during selection, and reject the final pixels if the Space changes after acceptance. Add controlled asynchronous stand-in coverage for both cases.

Already in place:
- panel teardown;
- local Esc handling;
- the nonactivating and full-screen flags;
- the flush before capture.

The screen-saver level is inherited from the fixed point. The actual ordering and focus behaviour remain manual checks.

The checklist covers mixed scales, negative coordinates, unplugging the origin display or another display, full-screen apps and Space switches.

Verification on x86_64 macOS 26.7 (25G229): the Swift suite passed (76 tests reported, 3 opt-in skips), and the unsigned Xcode build passed. arm64 was not executed.

Verdict: fix-then-merge
