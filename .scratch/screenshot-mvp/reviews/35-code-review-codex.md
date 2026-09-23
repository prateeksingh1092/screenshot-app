## Standards

- **P1 — [ScrollingCaptureSession.swift:161](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-35/Sources/FrisketCore/Stitcher/ScrollingCaptureSession.swift:161):** Alignment failures become `.unchanged`, allowing Done to silently return an incomplete image; `docs/stitcher.md` requires callers to preserve rejection evidence.
- **P2 — [ScrollingCaptureSession.swift:141](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-35/Sources/FrisketCore/Stitcher/ScrollingCaptureSession.swift:141):** Product capture directly uses mutable matcher methods, bypassing the pure `Stitcher.stitch(_:)` interface required by the spec and documented adoption contract.

## Spec

- **P2 — [CaptureLifecycleCoordinator.swift:172](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-35/Sources/FrisketCore/CaptureLifecycleCoordinator.swift:172):** Budget and identifier checks precede the permission `await`, while reservation follows it; concurrent commands can exceed the global pending budget or start duplicate captures.
- **P2 — [ManualScrollingCapture.swift:57](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-35/Frisket/Adapters/ManualScrollingCapture.swift:57):** Cancel during `captureRegion` is not checked after it returns; a limit-triggering viewport can immediately produce a thumbnail despite cancellation.

Validation: 107 tests across 17 suites passed; four opt-in tests skipped. Working tree remains clean. Real recordings and live memory checks remain explicitly pending.

Standards: 2 findings, worst P1. Spec: 2 findings, worst P2.

Verdict: fix-then-merge