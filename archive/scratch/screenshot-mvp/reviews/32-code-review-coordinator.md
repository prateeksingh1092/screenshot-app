Reviewed `a504468...7786230` after Codex and Other Models limits. Coordinator review, one pass. Recursion guard: no further review agents.

## Standards

No blockers. Key mapping and focus stay in `ThumbnailStack` / the command layer; the panel only consumes local `sendEvent` and VoiceOver custom actions. No event tap or global monitor.

## Spec

- **P2 — [ThumbnailPanel.swift:132](Frisket/ThumbnailPanel.swift):** VoiceOver can land on a card without `becomeKey`. Timeout pause currently keys off keyboard `becomeKey` / Focus Latest Thumbnail, so a VoiceOver-only user can still lose the card. Treat accessibility focus the same as key focus.

Verification: 237 tests / 36 suites passed; unsigned x86_64 `xcodebuild` succeeded. arm64 not executed. Manual Full Keyboard Access and VoiceOver pending.

Standards: 0 findings. Spec: 1 finding, worst P2.

Verdict: fix-then-merge
