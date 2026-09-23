# Ticket 19 — fresh Codex review (GPT-6 Astra, high), 2026-09-23

Fixed point `11aeb4b`, snapshot `adfce51`.

## Standards

- **Nit — `Frisket/Adapters/SelectionMagnifier.swift:22`:** own-process exclusion and capture configuration duplicate `ScreenCapturePlatform.capture`. Sharing this policy would stop the two capture paths drifting apart. An advisory duplication smell, not a standards violation.

## Spec

- **Should-fix — `Frisket/Adapters/SelectionOverlay.swift:177`:** all arrow keys now move the selection, which removes the previous Shift+arrow resizing without a replacement. Keyboard users can't choose capture dimensions, contrary to the spec's requirement for full keyboard operation.
- **Should-fix — `Sources/FrisketCore/SelectionGeometry.swift:52`:** Space's early return skips clearing the Shift state. To reproduce:
  1. Lock the horizontal axis with Shift.
  2. Hold Space.
  3. Release Shift and press it again.
  4. Release Space.
  5. Move vertically.

  The old horizontal lock persists, instead of allowing a fresh axis. Add a behavioural regression test for this combination.

These pass:

- The magnifier uses own-app exclusion, stays bounded and memory-only, and is released with the selection.
- The existing 128 MiB reservation covers the magnifier's cap.
- The final capture takes fresh pixels after the overlays are hidden.
- Esc uses the non-activating key panel, with no activation call or event monitor.

Still pending manual checks: runtime activation behaviour and pixel fidelity. The checklist specifies synthetic content.

Verification:
- Root Swift tests passed: 66 reported, three skipped.
- The unsigned build succeeded on x86_64 macOS 26.7 (25G229).
- arm64 not executed.

Verdict: fix-then-merge
