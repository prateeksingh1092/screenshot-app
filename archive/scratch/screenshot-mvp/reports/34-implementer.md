Added `Stitcher.stitch(Sequence<ScrollingCaptureFrame>) throws -> StitchedCapture`: an immutable strip-backed image plus alignment dispositions, scores and Vision-use evidence. Static header/footer detection stays internal; core writes no temporary files and imports no AppKit/SwiftUI.

Removed the trial package because its evaluation is complete; maintaining two matchers would duplicate code and tests. Regression tests, probes, BSD-3 headers, licence and provenance moved to core/documentation. Adapted hashes and change notes are checked; Snapzy is now a product component in third-party notices.

Verification on **x86_64, macOS 26.7 (25G229), Xcode 26.5 (17F42), Swift 6.3.2; arm64 not executed**:

- `sh scripts/test-core.sh`: **48 test functions passed, 3 opt-in tests skipped** (51 discovered); includes six repository checks and 22 checker fixtures. Identity scrub passes.
- `sh scripts/stitcher-memory-run.sh`: **1 passed**; 79 frames → exact **5120×57,600**, all **1,179,648,000 bytes** verified. Peak physical footprint: **1,270,796,288 bytes**, measured with `TASK_VM_INFO.ledger_phys_footprint_peak`, below 2 GB. Elapsed: 40.639 seconds.
- Reported sandbox Vision estimates: **0**; pixel fallback exercised. Vision probe remains opt-in and was not executed here. Coordinator command outside the sandbox:

```sh
sh /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-34/scripts/stitcher-vision-probe.sh
```

**Real recordings remain pending Prateek authorization.** The documented PNG/JSON harness passes a synthetic sticky-header/footer sequence and detects injected duplicated bands and incorrect height. No screen capture occurred.

Red → green evidence and limitations: `docs/stitcher.md`; recording instructions: `Tests/Fixtures/ScrollingCapture/README.md`. No refactor step, review, staging, commit, ticket status change or checkbox change was performed.

## Coordinator evidence (2026-09-23 00:47, outside Codex's sandbox)

`sh scripts/stitcher-vision-probe.sh` with Xcode 26.5 passed: 1 test; `VISION_PROBE translation tx=-0.0 ty=-80.0`; `usedVisionEstimate=true height=480`. The test runner reported `Target Platform: x86_64-apple-macos14.0`. x86_64 only; arm64 not executed. Recorded real scroll sequences remain pending (decisions 49 and 50).
