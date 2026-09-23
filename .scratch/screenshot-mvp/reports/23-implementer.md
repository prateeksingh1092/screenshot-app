Implemented ticket 23; stopped before review. No staging, commits, ticket-status or checkbox changes.

The AppKit-free core defines five states through required `CapturePermissionSource.capturePermission()`. Both capture commands gate before their sources and return typed `permissionRequired` recovery.

- **Not asked:** negative preflight, no bundle-scoped request marker.
- **Denied:** negative preflight with request history.
- **Granted:** positive preflight without a relaunch requirement.
- **Revoked while running:** access disappears after this process observed a grant.
- **Needs relaunch:** an accepted request remains unusable, or ScreenCaptureKit rejects authorization despite positive preflight.

Boolean APIs cannot prove every Settings-only transition; recovery offers relaunch for every missing state. Shareable-content authorization finishes before selection appears. Added the warning icon, Privacy & Security action, and quit-confirmation-aware relaunch from `~/Applications/Frisket.app`.

TDD red→green completed. Full suite: **68 passed, 3 existing opt-in tests skipped; 71 total across 11 suites**, including 11 new permission tests and repository checks. Unsigned build and `git diff --check` passed.

Commands used from the worktree:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security
xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath "$PWD/.build/DerivedData" CODE_SIGNING_ALLOWED=NO build
```

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

Prateek: run [the manual checklist](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-23/docs/manual-checks/23-permission-states.md) for all states, alert ordering, accessibility, Settings routing, relaunch and two signed rebuilds. Permission-changing scenarios use an isolated account, preserving ticket 08’s grant without a default TCC reset. Runtime checks remain unexecuted.

## Fix pass

Both review findings were validated and fixed; none remain open.

- **Permission policy:** Moved grant history, relaunch latching and state transitions into the pure `CapturePermissionPolicy` core module. The app adapter supplies platform observations and persists the request marker. Four new tests, developed red → green, cover all five states, request results, authorization refusals and process recreation.
- **Quit & Reopen:** Removed the shell. After termination begins, `applicationWillTerminate` starts `/usr/bin/open` directly with `-n` and the fixed installed path. This separate process can outlive Frisket; `-n` prevents reuse of the terminating instance. The fixed-install-path check and quit confirmation remain. Documentation now reflects possible overlap during final termination.
- **Verification:** Root Swift suite: **72 passed, 3 existing opt-in tests skipped; 75 total across 12 suites**. Unsigned x86_64 Xcode build with `CODE_SIGNING_ALLOWED=NO` passed using the pinned developer directory and documented in-worktree paths. `git diff --check` passed.

Runtime relaunch, native-alert ordering and arm64 remain unexecuted. Nothing staged or committed; ticket status and checkboxes unchanged.
