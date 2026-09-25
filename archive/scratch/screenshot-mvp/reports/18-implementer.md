Implemented ticket 18. Report saved as `.scratch/screenshot-mvp/reports/18-implementer.md`.

`DisplaySelectionSession` provides pure display ownership, origin locking, geometry updates, layout validation, and accepted rectangles. It reuses `SelectionGeometry`, handles negative coordinates, and cancels irreversibly when displays, frames, or scales change.

Every display gets a nonactivating crosshair panel using screen-saver level and full-screen/Space collection behaviors. Space notifications restore panel ordering and keyboard focus, retain the rectangle, and discard stale previews. All panels hide before final capture. Esc uses panel-local input. The unplug stand-in verifies no pixels, clipboard writes, or Pending capture, plus budget recovery.

Verification: TDD red→green; **22 focused tests passed**. Full suite: **76 tests—73 passed, 3 opt-in checks skipped**; all eight repository static-check cases passed. **Unsigned Xcode build passed**. Synthetic full-screen helper compiled without launching.

**x86_64 macOS 26.7 (25G229); arm64 not executed**

Commands, from the worktree root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security
xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath "$PWD/.build/DerivedData" CODE_SIGNING_ALLOWED=NO build
```

Prateek’s pending [manual checklist](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-18/docs/manual-checks/18-selection-overlay-displays.md) covers Retina/external 1× displays, negative coordinates, unplugging either display, native full-screen apps, Space switches, Esc without activation, and synthetic pixel verification.

Stopped before review. Nothing staged or committed; ticket status and checkboxes unchanged.

## Fix pass

Fixed the single should-fix: Space changes were unobserved during preview preparation and final capture. Observation now spans prefetch through capture completion. Generation checks discard invalidated previews and reject pixels if the Space changes after acceptance, returning cancellation with no Pending capture and recovering the budget. Space changes during selection preserve the rectangle.

Model: **Codex GPT-6 Astra, high**.

Controlled asynchronous stand-in tests reproduced both failures before the fixes and passed afterward. The focused suite passed **3 tests**, including both stable-Space and switched-Space preview cases. Root `swift test` reported **78 tests: 75 passed, 3 opt-in skips**; all eight repository static-check cases passed. The unsigned x86_64 Xcode build **succeeded** with `CODE_SIGNING_ALLOWED=NO`, the pinned `DEVELOPER_DIR`, and documented in-worktree paths. `git diff --check` passed.

No review finding remains open. Actual Space/window behavior remains subject to the existing manual checklist; arm64 was not executed. Nothing staged or committed; ticket Status and checkboxes unchanged.
