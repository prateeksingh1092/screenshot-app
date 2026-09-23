# Window capture (ticket 21)

Status: pending Prateek; no application launch, screen capture, signing, installation,
or clipboard use was performed by the implementer. Automated tests use fixture
window metadata and synthetic PNG bytes only.

## Record each run

Record date, tested commit, macOS version/build, architecture, installed app path,
bundle identifier and code signature, Screen Recording state, and display layout
(frame coordinates and backing scales). Development baseline: x86_64 macOS 26.7
(25G229); arm64 not executed. Follow the existing signing/install procedure in
[app-build.md](../app-build.md) and permission cases in
[23-permission-states.md](23-permission-states.md).

Use only the separate synthetic `Tools/FrisketTestPattern.swift` application.
Never capture real windows or the desktop, and never keep captures in the repo.
For overlap cases use multiple synthetic pattern windows. Frisket's own panels
may contain only previous synthetic captures. Inspect/export/copy only synthetic
images through the existing authorized workflow.

## Synthetic fixture commands (operator only)

Build and launch the existing fixture's movable window mode after recording the
signed Frisket identity. These commands were not launched by the implementer:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  Tools/FrisketTestPattern.swift -o /private/tmp/FrisketTestPattern
/private/tmp/FrisketTestPattern --show-window
```

This opens two overlapping, resizable, minimizable synthetic windows. Move them
between displays and Spaces using ordinary macOS controls. The pattern is centred
in each entire frame, including its transparent titlebar. For pixel verification,
record that frame's current width/height in points and multiply by its backing
scale. Export the selected synthetic window to `/private/tmp/window-pattern.png`
through an authorized workflow, then use the existing verifier (its `--verify-full`
name also applies to this centred, whole-window pattern):

```sh
/private/tmp/FrisketTestPattern --verify-full /private/tmp/window-pattern.png WIDTH HEIGHT SCALE
```

Substitute the independently recorded integer pixel dimensions and scale 1 or 2.
The verifier checks dimensions, all four quadrant samples and the black marker.
For full-screen Space tests use the fixture's green full-screen control; keep all
other content out of the selected synthetic window.

## Cases

- [ ] **Permission gate:** invoke Capture Window in not-asked, denied, revoked,
  and needs-relaunch states. Recovery appears before window selection. Explicit
  permission requests never automatically start a capture. After granting,
  invoke the menu again. Any OS authorization alert must have no overlay above it.
- [ ] **Hover/click:** with the synthetic pattern frontmost, invoke Capture Window.
  Its border highlights; click produces a Pending thumbnail of that window alone.
  Overlap two synthetic windows: the frontmost eligible one under the pointer wins;
  hovering the exposed part of the rear one selects it. Desktop clicks do nothing.
- [ ] **Own-app exclusion:** overlap the pattern with Frisket's synthetic thumbnail
  and other panels. Those panels never highlight. The selected pattern's PNG contains
  none of Frisket's panels or the selection border, even where they overlap it.
- [ ] **Dimensions/pixels:** run on built-in Retina and external 1x displays. Compare
  the PNG's dimensions with the synthetic window's content size times its native
  scale; verify the test pattern's corner colours/labels and complete window bounds.
  Verify no cursor, shadow padding, stretch, or unrelated pixels. Repeat with the
  external display left of and above the main display (negative coordinates), and
  a synthetic window spanning the display boundary.
- [ ] **Space/minimized:** a minimized synthetic window and a synthetic window on
  another Space are not candidates. Restore/switch and invoke again: it becomes
  selectable. Invoke over a full-screen synthetic pattern. Switch Spaces during
  selection: selection cancels, no Pending image; invoke again on the new Space.
- [ ] **Cancellation/focus:** from another active app displaying only the synthetic
  pattern, invoke the menu and press Esc. All overlays disappear, no Pending
  capture is added, and Frisket does not become active. Repeat with the pointer on
  each display, and unplug the external display mid-selection. Selection cancels.
- [ ] **Keyboard/accessibility:** use arrows/Tab to cycle eligible windows, Return
  to capture the highlighted synthetic window, and Esc to cancel. Verify the
  overlay's VoiceOver instructions and highlight announcement without window titles.
- [ ] **Changes during selection:** close or minimize the synthetic target before
  accepting. No stale window is captured. Move/resize it and invoke again; capture
  uses current dimensions. A revoked grant produces recovery without accepting pixels.
- [ ] **Lifecycle:** no History entry until authorized finalization. Dismiss/Escape
  of the thumbnail and Quit keep the synthetic result in History; Copy delivers
  the same result; Delete discards it. Check failed Copy retry uses the same revision.
- [ ] **Menu only:** Capture Window has no registered shortcut in ticket 21. Existing
  area shortcut and full-screen menu still work under their separate checklists.

Record observed results and failures; leave unchecked cases pending. OS focus,
Space membership, native scaling, ScreenCaptureKit exclusion, and alert ordering
require these runtime checks and are not established by fixture tests.

## Implementer verification commands

These use only fixtures, compilation and static checks. Compiler caches copied
from another worktree cannot be reused at a new absolute path. This worktree used
fresh caches below; the repository checker also recreates `.build/module-cache`
and `.build/clang-cache`. SwiftPM's missing checkout was copied from the already
seeded `.build/SourcePackages` checkout, with no dependency download.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ticket-21/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ticket-21/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --disable-automatic-resolution --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security \
  --filter WindowCaptureCommandsTests
# Repeat without --filter WindowCaptureCommandsTests for the full suite.
xcrun swiftc -typecheck -parse-as-library -swift-version 6 \
  -target x86_64-apple-macos26.0 -module-name Frisket \
  -I .build/x86_64-apple-macosx/debug/Modules \
  -Xcc -fmodule-map-file=.build/checkouts/GRDB.swift/Sources/GRDBSQLite/module.modulemap \
  Frisket/*.swift Frisket/Adapters/*.swift
xcrun swiftc -typecheck -parse-as-library Tools/FrisketTestPattern.swift
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO build
```

The unsigned Xcode command was attempted but exited 74: its resolver tried to
write `~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/grdb.swift.dia`,
which the sandbox denied. App-source typechecking passed; this is not evidence of
Xcode linking/packaging. The coordinator must rerun the unsigned build where the
cache write is permitted. No permission escalation was attempted.
