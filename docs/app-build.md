# Ticket 08 development app

`Frisket.xcodeproj` is authored directly, with one shared `Frisket` scheme and
one `Development` configuration. No project generator or added dependency is
needed. The AppKit/SwiftUI adapters compile in the app target. Its static
`FrisketCore` dependency compiles the **same** `Sources/FrisketCore/` directory
as the Swift package, using an Xcode synchronized source group (future source
files are included automatically). Lifecycle policy remains in that directory.
The root Swift package also compiles `Frisket/Adapters/` in a test-only module,
so Swift Testing can exercise the app adapters without an application host.

An initial local-Swift-package project reference was blocked: Xcode's resolver
attempted to write `~/Library/Caches/org.swift.swiftpm/manifests` even with an
explicit package cache path. The native static target avoids that resolver,
network access, and duplicate source copies. Reconcile build settings when
adding future package resources, dependencies or conditional compilation.

## Unsigned verification (approved for the implementer)

Run all commands from the worktree root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$PWD/.build/DerivedData" CODE_SIGNING_ALLOWED=NO build
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

The app targets macOS 26.0 with the macOS 26.5 SDK and x86_64 only. The build
phase `Reject Event Taps and Global Monitors` runs on **every build**, fails on
forbidden APIs under `Frisket/` and `Sources/`, and needs no network. Fixtures
cover direct, C, and aliased event-tap calls and global event monitors. Like
other lexical checks, this is not a proof against deliberately obfuscated or
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
empty entitlements alone do not enforce a network sandbox. No network code
or dependency is added.

Launch only the installed app, never the unsigned bundle or an Xcode Run
product. Permission identity follows the signed bundle identifier and stable
designated requirement. Do not reset TCC between rebuilds. Grant persistence
is an empirical manual check, not established by an unsigned build.

The root reserved for later History storage is
`~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`.
`AppIdentity` derives it from `Bundle.main.bundleIdentifier`; ticket 08 does
not create it or persist captures. Production's identifier would produce a
separate root and TCC identity.

## Scope and operator checks

The only global hot key is **Control–Option–Command–4 (⌃⌥⌘4)**, registered with
Carbon. It avoids all specified system screenshot shortcuts. A registration
failure displays a notice; the menu still works. Remapping and the richer
selection/thumbnail stack are later tickets. This slice provides drag plus
arrows/Shift-arrows/Return/Escape selection, a non-activating thumbnail on the
capture display, a menu action to focus it, accessible Copy/Delete controls,
and Copy retry without losing the pending image.

History is explicitly unavailable. There is no timeout, close button or
implicit discard on the thumbnail. Copy delivers the in-memory PNG; Delete
issues the core discard command. Quit with pending captures asks for explicit
Delete Captures and Quit or Cancel. Finalizing unedited exits to History
requires the subsequent History/lifecycle work.

See [first launch checks](manual-checks/08-first-launch.md). Those checks cover
launch, Screen Recording, synthetic pixels, Copy, and two signed rebuilds.
No runtime claim, permission persistence claim, or Apple-silicon execution
claim is made by this ticket's automated checks.
