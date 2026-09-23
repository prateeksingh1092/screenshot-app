# Ticket 20 — fresh Codex review (GPT-6 Astra, high), 2026-09-23

Fixed point `11aeb4b`, snapshot `987d378`.

**Standards — 0 findings.**

- Diagnostics still use closed event, operation and error enums with fixed fields; no free text was added.
- The synthetic helper changes support full-display verification. The sRGB window colour space is preserved, and incorrect dimensions and marker pixels are still rejected.

**Spec — 0 findings.**

- The fixture test genuinely crosses seam 1, through `CaptureCommandLayer` and the lifecycle coordinator. Its 1×, 2× and negative-coordinate cases check observable results: Pending image dimensions, thumbnail dimensions and delivered bytes.
- The implementation selects the display under the pointer and requests native-scale pixels. It reuses the fail-closed own-app exclusion filter, with no window-sharing fallback.
- Full-screen capture is menu-only.
- Both capture modes share byte accounting and the app's capture guard. Area-overlay hiding and thumbnail placement on the capture display are unchanged.
- The manual checklist covers each required display, own-app exclusion, Copy/Delete and permission failures, and requires synthetic-only content. Runtime checks remain explicitly pending under decisions 49 and 50.

**Validation** on x86_64 macOS 26.7 (25G229):
- Swift suite: 56 passed, 3 existing skips.
- The unsigned Xcode build and diff checks passed.
- arm64 not executed.

No source edits, app launches, screen captures or clipboard use.

Verdict: merge
