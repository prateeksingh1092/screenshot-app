**Standards**

- **P2 — [CaptureLifecycleCoordinator.swift:168](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-12/Sources/FrisketCore/CaptureLifecycleCoordinator.swift:168)** — Possible Duplicated Code: Drag repeats Copy’s finalization/cache logic; extracting the shared operation would reduce divergence between exit paths. This is a heuristic, not a hard violation.
- **P2 — [DragStagingLifetime.swift:36](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-12/Sources/FrisketCore/StorageAdapter/DragStagingLifetime.swift:36)** — Setting `writeReturned` before the fault callback means a subsequent session-end deletes staging after an injected fault, contradicting the documented requirement to leave that file for recovery.

**Spec**

- **P1 — [FilePromiseDragAdapter.swift:129](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-12/Frisket/Adapters/FilePromiseDragAdapter.swift:129)** — Session-end before the destination callback immediately fails delivery and clears `active`, so a delayed valid promise cannot complete; Apple documents that the [write callback occurs after the drag completes](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate/filepromiseprovider%28_%3Awritepromiseto%3Acompletionhandler%3A%29).
- **P1 — [FilePromiseDragAdapter.swift:106](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-12/Frisket/Adapters/FilePromiseDragAdapter.swift:106)** — `writeHandled` becomes true before the awaited write finishes, allowing a concurrent session-end handler to report `.copied` prematurely and remove the thumbnail even if writing subsequently fails.

`swift test` passed: 104 tests reported, three skipped. Existing adapter tests check the operation mask but do not exercise these callback races. Finder/Trash verification remains unexecuted. Working tree unchanged.

Standards: two findings, worst P2. Spec: two findings, worst P1.

Verdict: fix-then-merge