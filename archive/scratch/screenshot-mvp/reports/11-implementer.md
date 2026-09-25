Implemented ticket 11; stopped before review. [Saved report](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-11/.scratch/screenshot-mvp/reports/11-implementer.md).

`CaptureCommandLayer` now accepts `save`/`retrySave`. `CaptureExport` receives only an authorized frozen revision. Pure `ExportFolderPolicy` rejects History and unwritable destinations and identifies iCloud warnings. The disk adapter resolves symlinks and case aliases, creates missing folders, and exclusively writes independent PNGs with collision suffixes. Exports never enter History ownership.

`SaveOutcome` separates revision, History commit, and delivery results. Save shares Copy’s finalization branch; retries retain the same revision and commit result. History failure permits delivery; export failure preserves committed History and retryable bytes. Diagnostics contain only closed events/codes.

SwiftUI Settings opens through ⌘, and the menu bar menu. Choose… uses a directory panel, with keyboard operation and accessibility labels. The default is `~/Pictures/Frisket`. This target is unsandboxed, so it stores a plain path in bundle-scoped UserDefaults; no security-scoped bookmark is needed.

Verification used the pinned Xcode toolchain and in-worktree caches:

- `sh scripts/test-core.sh`: **86 passed, 3 skipped**, including **8 static checks and 30 fixtures**.
- `sh scripts/test-core.sh --filter 'SaveCommandsTests|ExportFolderPolicyTests'`: **9 tests / 13 cases passed**; red→green exercised success, retry, folder protection, and filename collisions.
- App-source `xcrun swiftc -typecheck` and `git diff --check`: passed.
- The [documented unsigned xcodebuild](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-11/docs/app-build.md) with `CODE_SIGNING_ALLOWED=NO` was blocked by a sandbox-denied GRDB manifest-cache write. Coordinator rerun outside the sandbox remains required; Xcode linking is unverified.

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

Prateek’s pending [manual checks](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-11/docs/manual-checks/11-save-and-settings.md): synthetic Save/retry, Settings persistence, ⌘,/keyboard routing, VoiceOver, iCloud warning, and retention/deletion independence after those tickets integrate.

No staging, commits, ticket-status/checkbox changes, app launches, capture, clipboard, signing, or installs. History recovery internals are unchanged.


## Fix pass

Model: Codex GPT-6 Astra, high.

- Fixed duplicated delivery bookkeeping with one shared Copy/Save delivery step; renamed commit and failure state.
- Added standard application, File and Edit menus, including Quit (⌘Q), Close Window (⌘W), and responder-chain Copy.
- Refused debug and production Application Support History roots and descendants.
- Added volume/file resource-identity comparisons on existing ancestors, including missing-root suffixes. Foundation already normalized the tested firmlinks on this Mac; alias protection is now explicit.
- Fixed rejected Save feedback, conflicting card messages, same-folder temporary writes followed by exclusive rename, and file creation mode `0644` (subject to umask).

Left open: outcome data duplication preserves typed public results; Settings-shell naming awaits additional sections; synchronous Settings assessment needs an asynchronous redesign; intermediate-symlink races require descriptor-relative traversal. Command-comma focus behavior remains a manual check. Keyboard/VoiceOver checks remain pending because launches were prohibited.

Validation: red→green for cross-build roots, relocated History aliases, and permissions. Focused suite: 12 tests passed. Root Swift suite: 89 passed, 3 skipped (92 total), including static checks. App typecheck and diff checks passed. Unsigned Xcode build was sandbox-blocked by GRDB’s manifest-cache write; coordinator rerun required.

No staging, commits, or ticket status/checkbox changes.
