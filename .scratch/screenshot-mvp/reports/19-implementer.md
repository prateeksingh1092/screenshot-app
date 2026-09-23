Implemented ticket 19; stopped before review. Nothing staged or committed; ticket status and checkboxes unchanged.

`SelectionGeometry(displayFrame:scale:)` is pure Foundation, with read-only `rect`, `begin(at:)`, `update(to:modifiers:)`, and `nudge(dx:dy:)`. It handles Shift axis locking, Option centred growth, Space translation, and device-pixel nudges; clamps to the origin display; and rounds at 1×/2×, including negative coordinates. Eight red → green slices exercised this interface, without a refactor step.

The overlay forwards its own panel events into the core. Its nonactivating key panel makes the selection view first responder; Escape/key code 53 and `cancelOperation` cancel without an app-activation call, event tap, or global monitor. Actual activation behavior remains a manual check.

The magnifier enlarges a 15×15-device-pixel crop without interpolation, marks the pointer pixel, and uses a bounded, memory-only frozen snapshot taken before the panel appears. The panel and magnifier are hidden before final capture.

Verification on **x86_64 macOS 26.7 (25G229); arm64 not executed**:

- `sh scripts/test-core.sh --filter SelectionGeometryTests`: 8 tests passed, covering 12 parameterized/nonparameterized cases.
- `sh scripts/test-core.sh`: 66 tests reported across 9 suites; 63 passed, 3 opt-in stitcher probes skipped. All 8 repository checks and 28 checker fixtures passed.
- Unsigned app build succeeded using:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath "$PWD/.build/DerivedData" CODE_SIGNING_ALLOWED=NO build
```

Prateek's pending checks are in `docs/manual-checks/19-selection-precision.md`: synthetic-pattern magnifier fidelity, every modifier and combinations, Esc without activation, overlay-free output, 1×/2× and negative-coordinate displays, unplugging, and Spaces. No app launch, screen capture, clipboard, signing, installation, or network operation was performed.
