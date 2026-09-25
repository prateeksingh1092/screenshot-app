# 77: Adapters as a package product

**What to build:** The app links `FrisketAdapters` as a package product instead of compiling the adapter sources itself, so every line the app runs is compiled once and tested. Preference keys live in one enum, without the never-released ⌃⌥⌘ migration. Unneeded `@preconcurrency` imports, `Sendable` on actor-confined types, and force unwraps in History are removed.

**Blocked by:** 74, 75, 76

**Phase:** 4 (O13 step 2)

**Status:** ready-for-agent

- [x] The app target compiles no adapter source file.
- [x] The unsigned build, the suite and `ci.sh` are green.
- [x] The force unwraps in History are replaced by typed failures.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). This ticket's decision records the choices.

- **Build graph:** `Package.swift` exposes `FrisketAdapters` as a static product; `project.pbxproj` links it and lists every `Adapters/*.swift` file in the synchronized `Frisket` folder's membership exceptions (a bare `Adapters` folder entry is ignored by Xcode), so the app compiles no adapter file: the app's `Frisket.SwiftFileList` has no adapter path. The adapter API the app calls is `public`; test seams stay internal. `ScreenCapturePlatform` gains a public app initializer; its synthetic-content initializer is internal. App files that use adapters `import FrisketAdapters` (one import line in `HistoryWindow.swift`, nothing else there).
- **Checks:** `app-sources` in `Checks/check_repository.py` now also fails if any `Frisket/Adapters/*.swift` file is missing from the app's membership exceptions or the app stops linking `FrisketAdapters` (new fixture `app-sources-adapters-rejected`; the accepted fixture gains both). The core import fence and the network check still pass.
- **Preference keys:** `PreferenceKey` (FrisketCore) replaces ten scattered string keys; raw values unchanged.
- **Migration:** `legacyDefaultBinding` and the ⌃⌥⌘ migration are gone.
- **History:** the `!` in `usageBytes` and GRDB's trapping non-optional row subscripts become `HistoryFailure.unavailable`.
- **Concurrency:** the four `@preconcurrency import ScreenCaptureKit` lines are removed. The stitcher/session `Sendable` item had nothing left to do (ticket 87 removed both).
- **Tests:** new `HistoryRowDecodingTests` (red: GRDB `Fatal error` trap on an unreadable `finalized_at`/`width`; green: `.failure(.unavailable)`). Changed tests that locked old behaviour: `unchangedLegacyDefaultsMigrateToCommandShiftNumbers` replaced by `aSavedControlOptionCommandShortcutIsKept`; onboarding key assertions now use `PreferenceKey`; `Tools/Release/test_project.py` expects both products and every adapter file excluded.
- **Housekeeping:** stale module caches seeded from ticket-79 (`.build/module-cache`, `.build/x86_64-apple-macosx/debug/ModuleCache`, `DerivedData/ModuleCache.noindex`, `SwiftExplicitPrecompiledModules`) were deleted in this worktree only.
- **Open:** no live check needed beyond the usual smoke run: capture, Copy, drag and Settings should behave as before.

