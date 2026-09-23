Implemented `HistoryStore.launch(root:)` with one app launch-call change. `CaptureCommandLayer.recoverHistory()` exposes the sweep and its typed size/error report. The store holds an exclusive root lock, reconciles files and rows, validates decoded pixels before adoption, and uses closed diagnostics. Root relocation, interrupted deletions, missing files, size totals, and competing instances are covered. `close()` provides deterministic shutdown.

Tier 1 injects faults at all nine commit points, closes/rebuilds the store, and recovers twice. Tier 2 runs the test-only `HistoryCrashHelper` through `Process`, requiring SIGKILL at every point, then performs the same checks. The helper is outside the app targets. Both tiers compare public History, recorded sizes, disk totals, and unchanged file bytes after the second sweep.

The coverage check compares each tier’s explicit cases against `HistoryCommitPoint.allCases`. Deliberately removing a case made it fail; the case was restored.

Verification used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and in-worktree caches:

- `sh scripts/test-core.sh --filter HistoryRecoveryTests`: **16 tests / 43 cases passed**.
- `sh scripts/test-core.sh`: **93 passed, 3 opt-in skipped**, including 8 repository checks and 30 checker fixtures.
- `swift build` and app-source `xcrun swiftc -typecheck`, using the documented full commands: passed. `git diff --check`: passed.
- Documented `xcodebuild … CODE_SIGNING_ALLOWED=NO build`: blocked by GRDB manifest-cache writes outside the sandbox. Coordinator must rerun outside it; Xcode linking remains unverified.

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

Prateek’s manual items: signed-app force-quit/relaunch and second-instance checks with synthetic captures; actual restore on another Mac; existing permission/rebuild and backup-exclusion checks.

Stopped before review. Nothing staged or committed; ticket status and checkboxes unchanged.
