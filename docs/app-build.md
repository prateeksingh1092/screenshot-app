# Development app build

`Frisket.xcodeproj` is authored directly, with one shared `Frisket` scheme,
a native `Development` configuration (`ARCHS = $(NATIVE_ARCH_64_BIT)`, so x86_64 on this Intel Mac and arm64 on Apple silicon), and a universal
`Release` configuration (`x86_64` + `arm64`, production bundle
`io.github.prateeksingh1092.frisket`). No project generator is needed. The app
target uses a synchronized `Frisket/` folder: adding or removing app Swift
source files needs no project-file edit. `Info.plist` and
`Frisket.entitlements` are excluded from target membership and remain inputs
through their existing build-setting paths, so they are not copied as resources.

**One build graph (ticket 42, decision 58).** The app links the root Swift
package's `FrisketCore` product through a local package reference, so the app
and `swift test` compile the core from the same package. GRDB is pinned once,
in `Package.swift`. The project's `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
is a symlink to the root `Package.resolved`. The package links no extra
libraries (ticket 67 removed the zlib and libcompression flags). `SDKROOT` is `macosx`, so the build uses the
installed Xcode's SDK. The app also links the package's `FrisketAdapters`
product (ticket 77): the synchronized `Frisket` folder's membership exceptions
list every `Adapters/*.swift` file (Xcode ignores a bare folder name there), so the adapters compile once, in the package, and the code the
app runs is the code `FrisketAdapterTests` exercises without an application
host. The `app-sources` repository check fails if an adapter file is missing from
the exceptions (add a new adapter file there) or the app stops linking the product.

**Signing.** The app target's base configuration is `Config/Frisket.xcconfig`.
It signs ad hoc unless `Config/Signing.xcconfig` exists. That file is ignored by
git, and `Config/Signing.example.xcconfig` shows its two settings (identity and
team). An ad-hoc or unsigned build has no stable designated requirement, so
macOS forgets the Screen Recording grant on every rebuild (decision 49). Beta
testers should create `Signing.xcconfig` with their own Personal Team.

## Unsigned verification (approved for the implementer)

Run all commands from the worktree root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO build
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

The app targets macOS 26.0 with the installed Xcode's macOS SDK (26.5 today), native architecture in Development.

## Local CI (ticket 43, decision 57 DA-7)

`scripts/ci.sh` decides whether the tree can merge. It runs every repository
check (`Checks/check_repository.py`), then `scripts/test-core.sh`, then the
unsigned Development build above, and exits non-zero on the first failure. A
tracked pre-push hook runs it; enable it once per clone with
`git config core.hooksPath .githooks`. Hosted CI waits until the repository is
public (decision 9).

The input-monitoring check (no event taps, no global event monitors, one
Carbon hot-key registration) used to run as a build phase on every Xcode build.
It now runs in `ci.sh` and in the Swift suite, with its fixtures unchanged.
Two checks are new. The first, `network`, rejects networking modules and
APIs in product code (story 74). The second, `silgen`, rejects
every `@_silgen_name` in product code (D22); tickets 63 and 67 removed the
last uses, so it has no allowance list. Like the other lexical
checks, none of these proves the absence of deliberately obfuscated or
dynamically resolved APIs.

Tests that reproduce an open defect use `knownDefect("Dn")` (decision 58): the
suite stays green while the defect exists and turns red when it is fixed.
`scripts/ci.sh --defects` runs those tests unwrapped and lists which defects
are still red.

## One signing and install path (coordinator only, after approval)

Use the existing Apple Development identity in Personal Team `9M43Q952NK`, set
in this Mac's untracked `Config/Signing.xcconfig`. Do not create identities,
enable provisioning updates, sign ad hoc, or re-sign with a separate packaging
step. This command signs the app through Xcode; the explicit settings match
`Signing.xcconfig`, so it also works in a fresh checkout:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$PWD/.build/DerivedData" \
  -clonedSourcePackagesDirPath "$PWD/.build/SourcePackages" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=9M43Q952NK CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
```

The sole installed location is:

`/Users/16intelmac/Applications/Frisket.app`

Packaging is a manual copy of the signed app bundle; there is no packaging
script, archive, installer, updater or distribution step. Quit the installed
app before replacing it. After Prateek approves installation:

```sh
mkdir -p /Users/16intelmac/Applications
# On rebuilds only, move the previous bundle aside before copying, to avoid stale files.
# Keep the backup outside any application-search folder; never launch it.
# mv /Users/16intelmac/Applications/Frisket.app "$PWD/.build/Frisket-previous-$(date +%Y%m%d-%H%M%S).app"
ditto "$PWD/.build/DerivedData/Build/Products/Development/Frisket.app" \
  /Users/16intelmac/Applications/Frisket.app
codesign --verify --strict --verbose=2 /Users/16intelmac/Applications/Frisket.app
codesign -dvv /Users/16intelmac/Applications/Frisket.app
codesign -d --entitlements :- /Users/16intelmac/Applications/Frisket.app
codesign -d -r- /Users/16intelmac/Applications/Frisket.app
```

Before launching, record the requirement and confirm the identifier
`io.github.prateeksingh1092.frisket.debug`, TeamIdentifier `9M43Q952NK`, Apple
Development authority, `runtime` flag, and absence of `get-task-allow` and
network entitlements. The fresh entitlement file is an empty dictionary: no
special entitlement is needed for these non-sandboxed macOS capture and
pasteboard APIs. Hardened runtime is enabled; base-entitlement injection and
Xcode's debug dylib are disabled. This build does not request App Sandbox;
empty entitlements alone do not enforce a network sandbox. No network code is added. GRDB is the sole dependency.

Launch only the installed app, never the unsigned bundle or an Xcode Run
product. Permission identity follows the signed bundle identifier and stable
designated requirement. Do not reset TCC between rebuilds. Grant persistence
is an empirical manual check, not established by an unsigned build.

The History storage root is
`~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`.
`AppIdentity` derives it from `Bundle.main.bundleIdentifier`; ticket 09 creates
it only on authorized finalization and excludes it from backup. Production's identifier would produce a
separate root and TCC identity.

## Scope and operator checks

Global shortcuts are **Command–Shift and a number** (decision 55): ⌘⇧4 area,
⌘⇧3 full screen, ⌘⇧5 window, ⌘⇧2 latest thumbnail, ⌘⇧1 History. ⌘⇧6 is
left free (decision 60).
They are registered with Carbon. If macOS still has the screenshot number row
enabled, Frisket turns those symbolic hotkeys off. A registration
failure displays a notice; the menu still works. Remapping and the richer
selection/thumbnail stack are later tickets. This slice provides drag plus
arrows/Shift-arrows/Return/Escape selection, a non-activating thumbnail on the
capture display, a menu action to focus it, accessible Copy/Delete controls,
and Copy retry without losing the pending image.

Ticket 09 adds Dismiss (including Escape while the thumbnail is focused),
finalization on Copy, and finalization of unedited thumbnails on Quit. Dismiss
shows and announces “Kept in History” only after commit. A failed dismissal stays
pending.

Ticket 13 stacks the cards. Each has its own nonactivating panel on the capture
display, newest nearest the bottom-right corner, overlapping when the display is
short. The panels use `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary` and
`ignoresCycle`. The card's single controls row holds Copy (C), Delete Capture (⌫,
hidden after a committed Copy whose delivery failed) and Close (⌘W). Esc and a
horizontal two-finger swipe are recognized inside the card's own window, with no
global monitor. Every thumbnail exit, including timeout and overflow, goes
through `exitThumbnail`; the app schedules timeouts from the core's `expiresAt`.
See [the ticket 13 checklist](manual-checks/13-thumbnail-stack.md); the
helper's new `--full-screen` mode hosts the synthetic pattern in a full-screen Space.

See [first launch checks](manual-checks/08-first-launch.md). Those checks cover
launch, Screen Recording, synthetic pixels, Copy, and two signed rebuilds.
No runtime claim, permission persistence claim, or Apple-silicon execution
claim is made by this ticket's automated checks.

## Ticket 09 resolver handoff

Since ticket 42 the project has no remote package reference of its own: GRDB reaches Xcode through the local package, and both resolvers read the one root `Package.resolved`.

The initial sandboxed resolution was blocked by Xcode's manifest-cache write
outside the worktree. The coordinator subsequently verified resolution and the
unsigned build outside that sandbox (2026-09-23). The earlier `-packageCachePath`
form resolved no packages and caused `Missing package product 'GRDB'`; do not
share SwiftPM's `.build/cache` with Xcode's resolver.

The coordinator's verified resolution command is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
xcodebuild -resolvePackageDependencies -project Frisket.xcodeproj -scheme Frisket \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages
```

Then run the unsigned build above, using the resolved checkout and disabling
automatic package resolution. Resolution may require network access when the
approved dependency is not cached; do not run it under a no-network brief.

Root SwiftPM builds/tests are the automated build gate available in the sandbox.
An additional app-source typecheck uses those modules without resolving Xcode
packages or launching an app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
xcrun swiftc -typecheck -parse-as-library -swift-version 6 \
  -target x86_64-apple-macos26.0 -module-name Frisket \
  -I .build/x86_64-apple-macosx/debug/Modules \
  -Xcc -fmodule-map-file=.build/checkouts/GRDB.swift/Sources/GRDBSQLite/module.modulemap \
  Frisket/*.swift
```

This typecheck does not establish Xcode linking, packaging, signing, or runtime
behavior. Manual ticket 09 checks: authorized synthetic capture, Dismiss and
focused Escape, “Kept in History” visual/VoiceOver announcement, Quit persistence,
Delete leaving no pending image on disk, and actual backup exclusion. Continue
ticket 08's permission and signed-rebuild checklist with Prateek. Launch recovery is now wired by ticket 10 through `HistoryStore.launch(root:)`.
Retention/quota and database-failure recovery UI remain later work. The test-only
`HistoryCrashHelper` target exists only in SwiftPM, outside the synchronized core
and app folders; it is not linked or copied into the app.

Ticket 10 manual checks for Prateek: with an authorized synthetic capture, force
quit and relaunch the signed app, check History consistency, attempt a second
instance and confirm the active instance remains intact, and verify a relocated
or restored History root. No app launches, screen capture, or clipboard use were
performed by the ticket 10 implementer.

## Ticket 11 Settings and Save

The thumbnail offers Save/Retry Save (S while focused). It shares History
finalization with Copy and Dismiss. Export failures leave the thumbnail available
for retry or dismissal; successful exports with failed History show an
acknowledgment-required notice.

The app's standard Settings menu command (Command-comma) and status menu open
one SwiftUI Settings window hosted in AppKit. Export folder is its first section;
Choose… uses a directory-only `NSOpenPanel` (also Command-O in Settings). Controls
have accessible labels and native keyboard operation; verify actual VoiceOver
and Full Keyboard Access behavior with the ticket's manual checklist.

The current target explicitly does **not** enable App Sandbox (the entitlement
file remains empty). Therefore `ExportSettings` stores `exportFolderPath` as a
plain path in the app's bundle-scoped `UserDefaults`, defaulting to
`~/Pictures/Frisket`. No security-scoped bookmark is needed or created. If a
future ticket enables sandboxing, it must replace this path preference with a
security-scoped bookmark and balance access around validation/export. Debug and
production preferences remain separated by bundle identity.

No app launch, screen capture, clipboard access, signing, or installation is
part of ticket 11's automated verification. Operator runbook:
[11-save-and-settings.md](manual-checks/11-save-and-settings.md).
