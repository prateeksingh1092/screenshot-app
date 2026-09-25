# Building the app

`Frisket.xcodeproj` is written by hand; no project generator is needed. It has
one shared `Frisket` scheme and two configurations:

- **Development:** the machine's own architecture (`ARCHS =
  $(NATIVE_ARCH_64_BIT)`): x86_64 on this Intel Mac, arm64 on Apple silicon.
  Bundle ID `io.github.prateeksingh1092.frisket.debug`.
- **Release:** universal (x86_64 and arm64). Bundle ID
  `io.github.prateeksingh1092.frisket`. `scripts/release-universal.sh` builds
  and signs it, and never installs or launches it.

The app targets macOS 26.0 with the installed Xcode's SDK.

## Build graph

One build graph (tickets 42 and 77, decision 80):

- The app links the root package's two products, `FrisketCore` and
  `FrisketAdapters`, through a local package reference.
- The app target compiles only the app files in `Frisket/`. It uses a
  synchronized folder, so a new app file needs no project edit.
- The synchronized folder lists every `Frisket/Adapters/*.swift` file as a
  membership exception, so no adapter compiles in the app. **A new adapter file
  must be added to that list.** Xcode ignores a bare `Adapters` folder name
  there.
- `Info.plist` and `Frisket.entitlements` are also exceptions. They reach the
  build through their build settings.
- GRDB is pinned once, in `Package.swift`. The project's
  `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is a symlink to
  the root `Package.resolved`.
- The package links no extra system libraries.

The `app-sources` repository check fails if an adapter file compiles in the app
or the app stops linking `FrisketAdapters`. The package and its checks are in
[core-package.md](core-package.md).

## Local CI

`scripts/ci.sh` decides whether the tree can merge. It stops at the first
failure:

1. The repository checks (`Checks/check_repository.py`, with `--self-test`).
2. The drift check (`Checks/check_drift.py`, retired terms).
3. The package tests (`scripts/test-core.sh`).
4. The unsigned Development build.
5. A compile of the live harness (`Tools/LiveHarness/build.sh`).

It ends with `ci: green`. `scripts/ci.sh --defects` runs the `knownDefect`
tests unwrapped and lists the defects still red.

A tracked pre-push hook runs `ci.sh`. Turn it on once per clone with
`git config core.hooksPath .githooks`. Hosted CI waits until the repository is
public (decision 9).

## Unsigned build

This is the build `ci.sh` runs. Anyone may run it; it signs nothing:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO build
```

Never launch the unsigned app. It has no stable signature, so macOS would treat
it as a new app for Screen Recording.

If Xcode reports `Missing package product 'GRDB'`, resolve once. This may need
the network when GRDB is not cached:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -resolvePackageDependencies -project Frisket.xcodeproj -scheme Frisket \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages
```

Don't share SwiftPM's `.build/cache` with Xcode's resolver
(`-packageCachePath`); that form resolves nothing.

## Signing

The app target's base configuration is `Config/Frisket.xcconfig`. It signs ad
hoc unless `Config/Signing.xcconfig` exists. Git ignores that file.
`Config/Signing.example.xcconfig` shows its two settings: identity and team.

An ad-hoc build has no stable designated requirement, so macOS forgets the
Screen Recording grant on every rebuild (decision 49). Beta testers create
`Signing.xcconfig` with their own Personal Team.

## Signed build and install (coordinator, after Prateek approves)

Use the existing Apple Development identity in Personal Team `9M43Q952NK`. Don't
create identities, sign ad hoc, or re-sign in a separate step.

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

The one install path is `/Users/16intelmac/Applications/Frisket.app`. Quit the
running app first. Move the old bundle aside (outside any Applications folder,
for example into `.build/`), then copy and verify:

```sh
ditto "$PWD/.build/DerivedData/Build/Products/Development/Frisket.app" \
  /Users/16intelmac/Applications/Frisket.app
codesign --verify --strict --verbose=2 /Users/16intelmac/Applications/Frisket.app
codesign -dvv /Users/16intelmac/Applications/Frisket.app
codesign -d --entitlements :- /Users/16intelmac/Applications/Frisket.app
codesign -d -r- /Users/16intelmac/Applications/Frisket.app
```

Check before launching:

- identifier `io.github.prateeksingh1092.frisket.debug`;
- TeamIdentifier `9M43Q952NK`, Apple Development authority;
- the `runtime` flag (hardened runtime);
- an empty entitlements dictionary: no `get-task-allow`, no network, no App
  Sandbox.

Launch only the installed app. Don't reset TCC between rebuilds.

## What the app stores

- **History:** `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`.
  `AppIdentity` derives it from the bundle ID, so Release has its own folder
  and its own Screen Recording grant. It is created on the first
  finalization and excluded from backup. See [history-storage.md](history-storage.md).
- **Preferences:** the app's `UserDefaults`. `PreferenceKey` in the core lists
  every key. The export folder is a plain path, `~/Pictures/Frisket` by
  default. The app is not sandboxed; if it ever is, the export folder must
  become a security-scoped bookmark.
- **Logs:** none of its own. Diagnostics go to the unified log (decision 85).

## Shortcuts

The defaults are Command–Shift and a number (decision 55):

| Shortcut | Action |
|---|---|
| ⌘⇧1 | History |
| ⌘⇧2 | Focus the latest Thumbnail |
| ⌘⇧3 | Capture full screen |
| ⌘⇧4 | Capture area |
| ⌘⇧5 | Capture window |

⌘⇧6 is free (decision 60). The shortcuts are registered with Carbon. Frisket
never writes macOS's screenshot shortcuts (DA-2). If macOS still uses one,
Settings says which and links to System Settings › Keyboard › Keyboard
Shortcuts › Screenshots. "Restore macOS screenshot shortcuts" turns back on
only what an earlier build turned off. Frisket writes shortcuts in ⌘⇧ order;
menus show macOS's own ⇧⌘ order (decision 79).

## Checking the running app

The live harness (`Tools/LiveHarness/beta-matrix.sh`, rows in `matrix.tsv`)
drives the installed app with synthetic patterns. What it can't check is in
[manual-checks/](manual-checks/README.md).
