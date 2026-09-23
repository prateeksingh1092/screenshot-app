Draft implementer report — ticket 06

Implemented the command layer, internal actor-isolated Capture lifecycle coordinator, image delivery interfaces, and closed diagnostics in FrisketCore.

Public interface: `CaptureCommandLayer.execute(_:)` accepts capture, Copy, retry Copy, and discard commands with `CaptureID` / `CaptureRevision`. `CopyOutcome` separates commit and delivery outcomes. Added `CapturePixelSource`, write-only `ImageClipboard`, privacy-marked `ClipboardImage`, `ClipboardReceipt`, `DiagnosticSink`, and `LocalDiagnosticLog`.

Verification: build succeeded; the single final full suite passed **15 tests**. Coverage comprises 12 command tests (14 parameterized executions), six repository-check cases, 18 checker-fixture cases, and one toolchain probe. Planted-secret, seven-day retention, retry, stale/duplicate, concurrent-command, and global-budget checks pass. No build/test warnings. `git diff --check` passed.

Commands executed: `swift build` with the mandated in-worktree cache/config/security flags; `sh .build/test-ticket.sh --filter CaptureCommandsTests`; filtered repository checks; and final `sh .build/test-ticket.sh`, which runs `swift test --disable-xctest` with those flags. Reproducible commands are in `docs/core-package.md`; execution logs are under `.build/`. Every Swift command uses Xcode's `DEVELOPER_DIR` and local module caches.

Environment: Xcode 26.5 (17F42), Swift 6.3.2, x86_64, macOS 26.7 build 25G229; **arm64 not executed**.

Design: reservations cover asynchronous captures; failed delivery retains the same revision and charged bytes. Successful delivery/discard releases bytes. Diagnostics accept no payload strings and expire locally after seven days. Static guards cover logging, clipboard shape, and filesystem capabilities.

Open issues: review pending. Platform adapters remain ticket 08; History commits remain ticket 09. Commit outcomes explicitly report History unavailable. Diagnostics are memory-only; static guards are lexical. No review, staging, commits, ticket-status changes, or checkbox changes performed.
