Implemented ticket 08’s buildable slice; stopped before review.

The handwritten Xcode project has an AppKit/SwiftUI app and a static `FrisketCore` target compiling the package’s existing source directory. This avoids Xcode’s sandbox-blocked package resolver. Lifecycle ownership stays in the core. Bundle/storage identity is `io.github.prateeksingh1092.frisket.debug`.

Added `Frisket.xcodeproj/`, nine Swift files and two plists under `Frisket/`, two input-monitoring fixtures, `Tests/FrisketAdapterTests/AreaCaptureCommandsTests.swift`, `Tools/FrisketTestPattern.swift`, `docs/app-build.md`, `docs/manual-checks/08-first-launch.md`, and [this draft report](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-08/.scratch/screenshot-mvp/reports/08-implementer.md).

Verification on x86_64 macOS 26.7 (25G229), Xcode 26.5 (17F42), Swift 6.3.2; **arm64 not executed**:

- Red→green checks covered image queries, capture ordering/cancellation, pasteboard choices, thumbnail downsampling, and forbidden input APIs.
- Full suite: **22 tests passed**, including six adapter tests, seven repository-check cases and 23 fixture cases.
- Unsigned `xcodebuild` succeeded using the command below with `CODE_SIGNING_ALLOWED=NO`; binary deployment minimum 26.0, SDK 26.5.
- A planted global monitor failed the Xcode build (exit 65), then was removed. The PNG verifier passed two positive and two negative synthetic checks without GUI launch.

From the worktree root, set:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
```

Test command:

```sh
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

Signed build command **for the coordinator, not executed**:

```sh
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$PWD/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=9M43Q952NK CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
```

Fixed install path: `/Users/16intelmac/Applications/Frisket.app`.

Default shortcut: **⌃⌥⌘4**. Entitlements: fresh empty dictionary; hardened runtime enabled; no network/debug entitlements or base-entitlement injection.

Open: signed-install verification, runtime/VoiceOver checks, actual pasted pixels, and Screen Recording grant persistence across two rebuilds. History remains unavailable. Follow [the manual checklist](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-08/docs/manual-checks/08-first-launch.md). No signing, installation, GUI launch, screen capture, real clipboard access, review, staging, or commit occurred. Ticket status/checkboxes and stitcher code are unchanged.

## Coordinator manual-check evidence (2026-09-23 00:15–00:35, Prateek operating)

The build was the pre-review snapshot's signed build, made with the documented command but `-derivedDataPath /private/tmp/frisket-grant/DerivedData`. `codesign --verify --strict` passed: identifier `io.github.prateeksingh1092.frisket.debug`, TeamIdentifier `9M43Q952NK`, hardened runtime flag, x86_64 thin. It was installed with `ditto` to `~/Applications/Frisket.app`, and the DerivedData copy was unregistered from LaunchServices. Setup: x86_64 Intel MacBook Pro, macOS 26.7 (25G229). Built-in Retina LCD, 3072×1920, 2×, is the main display; the other is 1920×1080 at 1×. arm64 not executed.

- **Launch and permission: pass.** Frisket launched from the installed path. The first ⌃⌥⌘4 led to the Screen Recording request, and Prateek granted it in System Settings. The selection overlay then appeared.
- **Capture dimensions and content: pass.** With `FrisketTestPattern --show`, ⌃⌥⌘4 then Return gave a thumbnail. After Copy and Preview's New from Clipboard, the image was exactly 640×360 at 2×. Quadrant order and the black marker were correct, with no dimmer, border or cursor visible.
- **Colour: FAIL.** `FrisketTestPattern --verify … 2` failed on both the JPEG and a PNG export. Sampled sRGB values were red 255,0,0; green 1,255,1; **blue 22,0,255** (expected 0,0,255, tolerance 3); white 255,255,255; marker 0,0,0. The pasted PNG carries an sRGB IEC61966-2.1 profile. `ScreenCapturePlatform.swift:59` sets `config.colorSpaceName = CGColorSpace.sRGB`. Needs diagnosis: capture colour conversion, the helper's drawing, or the verifier's tolerance.
- **Copy by pointer: pass.** Clicking Copy removed the thumbnail, and the image pasted.
- **Focus Latest Thumbnail: needs retest.** While a thumbnail was visible, Prateek chose the menu item and saw no visible effect. After Copy, with no thumbnail, nothing happening is expected. Keyboard Tab/Space Copy and VoiceOver were not exercised.
- **Not run:** drag area, display-edge clamp, Esc cancellation without activation, ⇧⌘3/4/5/6 ownership, external-display capture, and grant persistence across two signed rebuilds.
- Pressing Esc while the pattern is key closes the helper, as designed; that is not a defect.

## Fix pass

- **Focus Latest Thumbnail — fixed in code.** The menu now explicitly requests Copy focus through SwiftUI FocusState, with a visible outline. Native button keyboard handling and C remain; the VoiceOver label is “Copy capture”. No behavioural adapter seam exists for this window-layer routing, so the manual checklist covers immediate focus, Tab/Shift-Tab, Space, C, repeated focus, latest-thumbnail targeting and VoiceOver.
- **Colour fixture — fixed; colour result still open.** The helper window explicitly uses sRGB. The verifier retains ±3 tolerance. The checklist requires a fresh pasted-PNG verification on the built-in wide-gamut display; continued failure calls for investigating capture colour conversion and comparing direct/pasted PNGs before Preview export. No colour pass is claimed.
- **Single Carbon hot key — fixed.** The static check rejects multiple registration call sites across product files. Added rejected duplicate and accepted single-registration fixtures; observed red → green.
- **Verification:** `sh scripts/test-core.sh` passed: 55 tests passed, 3 opt-in tests skipped (58 reported), including six adapter tests, seven repository-check cases and 26 fixture cases. Unsigned x86_64 `xcodebuild` with `CODE_SIGNING_ALLOWED=NO` succeeded; the helper compiled. Used the required `DEVELOPER_DIR` and in-worktree caches. arm64 was not executed.
- **Manual pending:** keyboard/focus/VoiceOver, pasted-PNG colour rerun, drag selection, edge clamp, Esc cancellation, system screenshot shortcuts, external-display capture and Screen Recording grant persistence across two signed rebuilds.

No staging, commits, ticket status/checkbox changes, signing, launches, capture or clipboard access.
