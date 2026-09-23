**Model:** Claude Opus 5.5 High, via the Cursor CLI. TDD red→green in four slices, with no refactor step.

**Core interface** (`ThumbnailStack.swift`, a pure stack inside the coordinator that holds exactly its Pending captures):
- `CaptureCommandLayer(…, thumbnailPolicy: ThumbnailStackPolicy(maximumCount: 4, autoDismissDelay: .seconds(10)), clock: () -> ContinuousClock.Instant)`. Both defaults are my choice and are **not ratified by Prateek**.
- `thumbnails() -> [ThumbnailCard]`: newest first, each with `revision`, `expiresAt`, and `dueExit` (`.overflow`, `.timeout` or nil).
- `execute(.exitThumbnail(revision, ThumbnailExit))`. `ThumbnailExit.outcome` gives the outcome; an exit that isn't due returns `rejected(thumbnailExitNotDue)`.

**Outcome table**

| Exit | Outcome | Admitted |
| --- | --- | --- |
| timeout | finalize to History | once `expiresAt` passes |
| swipe, close, Esc | finalize to History | always |
| overflow | finalize to History | only for a card beyond the maximum |
| delete | discard; nothing written | refused (`alreadyFinalized`) after a committed Copy whose delivery failed |

Overflow is an explicit command, so capture still never authorizes persistence. In the app, each card has its own nonactivating panel on the capture display (`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `ignoresCycle`). The card has one controls row: Copy (C), Delete Capture (⌫) and Close (⌘W). Esc and swipe are handled inside the card's own window.

**Tests** (with `DEVELOPER_DIR` set and in-worktree caches):
- `sh scripts/test-core.sh --filter ThumbnailStackCommandsTests`: 6 tests, 8 cases passed.
- `sh scripts/test-core.sh` (the documented root `swift test`): 103 tests in 15 suites passed, 3 opt-in tests skipped, static checks included.
- App `swiftc -typecheck` passed.
- `xcodebuild -resolvePackageDependencies` resolved GRDB 7.11.1. The unsigned `CODE_SIGNING_ALLOWED=NO` build succeeded. Xcode's resolver may also use its own user-level caches.

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

**Manual items for Prateek** (`docs/manual-checks/13-thumbnail-stack.md`, synthetic pattern only):
- stack order and placement, with no app activation;
- overflow at the fifth card;
- the 10-second timeout;
- trackpad swipe;
- Close, Esc and ⌘W;
- Delete writes nothing;
- over full-screen Spaces and Mission Control, using the helper's new `--full-screen` mode (typechecked, never launched);
- two displays;
- VoiceOver labels.

He should also ratify or change the two defaults.

Stopped before review. No git commands were run; the ticket's status and checkboxes are unchanged.
