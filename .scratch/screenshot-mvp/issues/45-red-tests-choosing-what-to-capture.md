# 45: Red tests: choosing what to capture

**What to build:** Tests pin down how Frisket chooses what to capture. The cursor window (empty owning-app bundle ID, very high window level) is never chosen over the window under it (D2). A Selection that starts on a display's top pixel row or leftmost column has an Origin display (D14). The Capture exclusion list and Frisket's own windows stay out of area, full-screen, window and scrolling captures.

**Blocked by:** 43

**Phase:** 0

**Status:** resolved (tested on `main` at `ce152d4`)

- [x] D2, through `WindowSelection`: with a cursor-like window above a normal window, the normal window is picked.
- [ ] D2: when no window can be picked, the failure names that cause, not "smaller area".
- [x] `foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow` stays green.
- [x] D14: a pointer on a display's top pixel row or minimum x gets that display as its Origin display.
- [ ] For each of the four capture modes, the content filter excludes Frisket and every app on the Capture exclusion list. These are regression guards and are green today.
- [x] The D2 and D14 tests are marked as known defects.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5, Claude Code, medium effort. Branch `ticket/45-red-tests-choosing-what-to-capture`. No product code changed.

**Known-defect tests.** Each is red with `FRISKET_SHOW_DEFECTS=1` at its `"Dn:"` expectation, and each passes as a known issue in the normal suite.

- `WindowSelectionTests.d2WindowUnderThePointerIsPickedNotSystemChrome(_:)` (core, `WindowSelection` seam) has 5 cases. Each puts one intruder in front of a normal pattern window under the pointer:
  - `cursor`: empty bundle ID, layer 2147483630, 20×26 pt;
  - `empty bundle ID`: layer 0, large;
  - `pop-up menu level`: layer 101;
  - `Dock`: `com.apple.dock`, layer 20;
  - `tiny helper`: 16×16 pt.

  Red today in every case: `picked?.id → 4` instead of 10. Each case isolates one rejection rule from ticket 49, so every rule has its own red.
- `WindowCaptureCommandsTests.d2WindowCaptureTakesTheWindowUnderTheCursorNotTheCursor()` (command seam, `CaptureCommandLayer` → `WindowCaptureSource`) reproduces the live scenario. Red: `offered → [4, 7]` and `captured → [4]`, where both should be `[7]`.
- `DisplaySelectionSessionTests.d14PointerOnATopPixelRowHasAnOriginDisplay()` uses this Mac's layout (Retina 1440×900 @2× plus an external 1920×1080 @1× at negative coordinates). A pointer at y == maxY (the top pixel row, including the top-left corners) gets `originDisplay → nil`, and `begin(at:)` returns false: 8 issues.

**Green guards added:**
- `WindowSelectionTests.foreignFloatingWindowInFrontIsStillPicked` (layer 3).
- `DisplaySelectionSessionTests.pointerOnALeftmostPixelColumnHasAnOriginDisplay`, because minimum x already works.
- `CaptureModeExclusionTests.contentFilterExcludesFrisketAndTheExclusionList(mode:)` for area, full screen and scrolling. It runs the production `AreaCaptureSource`, `FullScreenCaptureSource` and `ManualScrollingCapture` over the production `ScreenCapturePlatform`, with only the overlay and pointer stubbed. A recording `ScreenCaptureContent` captures the identifier set handed to `ScreenCapturePolicy.filter`, and the test asserts it equals Frisket plus the list.
  - Mutation check: dropping the platform's `exclusions()` in `captureRegion` makes the scrolling case fail, so it guards the only path that brings the list into scrolling capture.
  - `foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow` stays green.

**Helper change (both copies, identical).** `knownDefect` now takes `isolation: isolated (any Actor)? = #isolation` and forwards it to `withKnownIssue`. Without it, a `@MainActor` suite can't pass its body ("sending value of non-Sendable type… risks data races"). The five `KnownDefectTests` still pass.

**Left open:**
- *D2 failure message (criterion unchecked).* The "Capture unavailable … smaller area" text lives in the app target (`CaptureSurfaces.start`). It maps every `.captureFailed` except `.cancelled` to the same notice, and `CaptureSourceFailure` has no window-specific cause (`.unavailable`, `.emptyImage`, `.cancelled`, `.rejectedAlignment`, `.permissionRequired`). No package seam can observe the message, so it is a live-harness row for tickets 48 and 49. Ticket 49 will probably need a distinct failure case.
- *Window-mode exclusion list (criterion unchecked for window mode only).* Window capture filters a single foreign window (`SCContentFilter(desktopIndependentWindow:)`). Frisket's own windows are excluded by `WindowSelection`, covered by `onlyVisibleForeignWindowsParticipateInZOrder` and the floating test. The Capture exclusion list is applied only inside `WindowScreenCapturePlatform.loadWindows`, in the SCK/CG join, which needs live ScreenCaptureKit. That is the seam candidate #6 / ticket 75 creates (`WindowSelection(rows:)` owns the join and filter); add the window-mode exclusion test there.
- *App-layer D14 twin.* `ScreenCapturePlatform.displayUnderPointer()`, used by full-screen capture, uses `NSScreen.frame.contains(pointer)`, which is half-open like the core. It needs `NSScreen`, so there is no package test. Ticket 50 should fix both.
- *Fix semantics for ticket 50.* AppKit mouse locations follow `NSMouseInRect` (unflipped: `minX ≤ x < maxX`, `minY < y ≤ maxY`). The existing `pointsBelongToOneDisplayIncludingNegativeCoordinatesAndSharedEdges` asserts bottom-edge points `(0, 0)` and `(-1920, -180)`, so ticket 50 must reconcile it.

**Evidence (x86_64 only; arm64 not executed):**
- `scripts/ci.sh` in the worktree: `ci: green`, 298 tests in 47 suites, with the unsigned app build.
- `scripts/ci.sh --defects` lists d14, d22, `d2WindowCaptureTakesTheWindowUnderTheCursorNotTheCursor` and `d2WindowUnderThePointerIsPickedNotSystemChrome` as red.
- The first `ci.sh` run hit an intermittent, unrelated failure: `HistoryRecoveryTests.tierOneRecoversEveryInterruptedCommitTwice(.imageRenamed)` threw `.rootLocked`. It passed alone and on the next full run. It looks like the interrupted store's `flock` is not yet released when recovery reopens the root; it may show up under load.

### 2026-09-24: coordinator, resolved

Merged into `main`. At `ce152d4`, `scripts/ci.sh` is green (320 tests in 52 suites, 101 known issues), and `ci.sh --defects` lists this ticket's tests as red. x86_64 only.
