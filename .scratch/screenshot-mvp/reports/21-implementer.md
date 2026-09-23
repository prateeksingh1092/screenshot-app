Implemented ticket 21 with **Codex GPT-6 Astra, high**, stopping before review.

The core interface is `CaptureCommand.captureWindow(_:maximumBytes:)`, with an injected `windowSource` sharing the existing permission gate, Pending capture budget, Copy/retry, Delete, and History finalization. `WindowSelection` filters fixture metadata and hit-tests front-to-back in global coordinates, including negative coordinates.

Candidates must be on-screen, layer 0, non-minimized, and outside Frisket’s process/bundle. The adapter intersects ScreenCaptureKit’s on-screen list with CoreGraphics’ metadata z-order, excluding minimized/other-Space windows. It revalidates after selection and uses `SCContentFilter(desktopIndependentWindow:)` to capture only the selected foreign window. Nonactivating panels handle hover/click, keyboard selection and Esc; Space/display changes cancel. Capture Window is menu-only.

Verification on **x86_64 macOS 26.7 (25G229); arm64 not executed**:

- Three red→green slices; no refactor step.
- `swift test … --filter WindowCaptureCommandsTests`: 11 tests passed.
- `swift test …`: 108 tests reported, 105 passed, three opt-in tests skipped; includes eight repository checks and 30 checker fixtures.
- `xcrun swiftc -typecheck …`: app sources and synthetic-pattern tool passed.
- `git diff --check`: passed.
- Unsigned `xcodebuild … CODE_SIGNING_ALLOWED=NO build`, including all required package-resolution flags: blocked, exit 74, by the sandbox denying Xcode’s manifest-cache write under `~/Library/Caches`.

Full commands and Prateek’s pending synthetic-only checks are in [the manual checklist](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-21/docs/manual-checks/21-window-capture.md): permission states, focus/Esc, overlapping windows, own-panel exclusion, Spaces/minimization, Retina/1x/negative-coordinate layouts, unplugging, marker pixels, and finalization. The fixture adds movable windows via `--show-window`; none were launched.

No review, staging, commit, signing, capture, clipboard use, or ticket-status/checkbox changes. The coordinator must rerun the unsigned Xcode build outside this cache restriction.
