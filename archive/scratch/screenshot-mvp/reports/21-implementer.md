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

## Fix pass

Codex validated the review's P2 finding against `WindowSelection`: the layer-zero
requirement discarded a visible foreign floating window and selected the normal
window behind it. Removed that blanket requirement. Targeted exclusions remain:
Frisket's process and bundle identity, absent app identity, off-screen/minimized
windows, and invalid bounds. Desktop elements remain excluded by the platform's
existing ScreenCaptureKit and CoreGraphics queries. Input z-order is preserved.
This supersedes the layer-zero candidate restriction described above.

Added the Seam 1 fixture
`foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow`, containing a
foreign layer-3 window above a normal window plus two excluded Frisket floating
panels (process and bundle matches). Updated the existing visibility fixture to
exclude its floating panel by Frisket identity rather than its layer.

Verification on x86_64 macOS 26.7 (25G229):

- Red: the new fixture failed because only window 7 was offered/captured instead
  of floating window 80; the other 11 window-capture tests passed.
- Green: all 12 window-capture tests passed.
- Full suite: 109 tests reported across 15 suites, 106 passed and three opt-in
  tests skipped; repository static checks passed. Both test commands exited 0.

Commands used Xcode and in-worktree caches:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ticket-21/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ticket-21/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --disable-automatic-resolution --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security \
  --filter WindowCaptureCommandsTests
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --disable-automatic-resolution --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

The optional PNG-encoder duplication remains open as explicitly requested by the
fix brief. No git commands or Status/checkbox edits. No broad review was relaunched.
Arm64, live window capture, and the pending unsigned Xcode build were not run in
this fix pass; the existing manual verification limitations still apply.
