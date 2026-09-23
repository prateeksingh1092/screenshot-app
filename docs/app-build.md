# Ticket 08 development app

`Frisket.xcodeproj` is authored directly, with one shared `Frisket` scheme and
one `Development` configuration. No project generator or added dependency is
needed. The app target uses a synchronized `Frisket/` folder: adding or removing
app Swift source files needs no project-file edit. `Info.plist` and
`Frisket.entitlements` are excluded from target membership and remain inputs
through their existing build-setting paths, so they are not copied as resources.
The AppKit/SwiftUI adapters compile in the app target. Its static
`FrisketCore` dependency compiles the **same** `Sources/FrisketCore/` directory
as the Swift package, using an Xcode synchronized source group (future source
files are included automatically). Lifecycle policy remains in that directory.
The root Swift package also compiles `Frisket/Adapters/` in a test-only module,
so Swift Testing can exercise the app adapters without an application host.

Before ticket 09, an initial local-Swift-package project reference was blocked: Xcode's resolver
attempted to write `~/Library/Caches/org.swift.swiftpm/manifests` even with an
explicit package cache path. The native static target avoided that resolver and duplicate source copies.
Ticket 09 adds the exact GRDB package reference to this target, so its dependency
now requires package resolution. Reconcile build settings when
adding future package resources, dependencies or conditional compilation.

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

The app targets macOS 26.0 with the macOS 26.5 SDK and x86_64 only. The build
phase `Reject Event Taps and Global Monitors` runs on **every build**, fails on
forbidden APIs under `Frisket/` and `Sources/`, and needs no network. Fixtures
cover direct, C, and aliased event-tap calls and global event monitors. Like
the test suite, this phase also rejects multiple Carbon hot-key registration
call sites across product files; fixtures cover duplicate and single registrations.
Like other lexical checks, this is not a proof against deliberately obfuscated or
dynamically resolved APIs. Swift Testing runs all repository static checks.

## One signing and install path (coordinator only, after approval)

Use the existing Apple Development identity in Personal Team `9M43Q952NK`.
Do not create identities, enable provisioning updates, sign ad hoc, or re-sign
with a separate packaging step. This exact command signs the app through
Xcode; it has **not** been run by the implementer:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$PWD/.build/DerivedData" \
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

The only global hot key is **Control–Option–Command–4 (⌃⌥⌘4)**, registered with
Carbon. It avoids all specified system screenshot shortcuts. A registration
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
  Frisket/*.swift Frisket/Adapters/*.swift
```

This typecheck does not establish Xcode linking, packaging, signing, or runtime
behavior. Manual ticket 09 checks: authorized synthetic capture, Dismiss and
focused Escape, “Kept in History” visual/VoiceOver announcement, Quit persistence,
Delete leaving no pending image on disk, and actual backup exclusion. Continue
ticket 08's permission and signed-rebuild checklist with Prateek. Recovery,
retention/quota, and database-failure recovery UI are not implemented here.
