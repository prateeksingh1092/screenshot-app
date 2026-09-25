# 49: Window capture picks the window under the pointer

**What to build:** ⌘⇧5 highlights and captures the real window under the pointer, never the cursor, the Dock or a tiny helper window. Foreign floating windows can still be captured. When window capture fails, the message says why (story 84).

**Blocked by:** 45

**Phase:** 1

**Status:** resolved (tested on `main` at `22213c5`; live rows wait for an approved install)

- [x] The D2 tests pass without the known-defect mark.
- [x] Rejected windows: an empty owning-app bundle ID, a level at or above the Dock, pop-up menu and cursor levels, a side shorter than 32 pt, the Dock, and Frisket itself.
- [x] Foreign floating windows are still captured ahead of overlapping normal windows.
- [ ] The window row of the live matrix passes on both displays.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5 (1M context), Claude Code, high effort. Branch `ticket/49-window-capture-picks-the-window`.

**What changed and why:**
- `WindowSelection` (core) now also rejects a window whose owning-app bundle ID is empty, whose level is at or above `kCGDockWindowLevel` (20; this covers pop-up menus at 101 and the cursor at 2147483630), whose owner is `com.apple.dock`, or whose frame is shorter than 32 pt on either side. Frisket (by process ID and bundle ID), nil bundle IDs, off-screen and minimized windows stay rejected. Foreign floating windows below the Dock level (for example layer 3 or 19) are still picked ahead of normal windows.
- Failure message (story 84, the unchecked D2 criterion of ticket 45): `CaptureSourceFailure` gains `.window(WindowCaptureFailure)` with four causes, each with a title ("Window not captured") and a message in the core:
  - `noWindow`: no capturable window once Frisket, system chrome, minimized windows and the Capture exclusion list are left out. `WindowCaptureSource` returns it when no candidate remains (previously `.unavailable`).
  - `windowChanged`: the chosen window closed, moved to another Space or changed before capture. The platform throws it when the re-listed window no longer matches, or its size is not finite.
  - `tooLarge`: the window's pixels exceed the decoded ceiling or the encoded allowance.
  - `systemRefused`: ScreenCaptureKit or the PNG encoder returned nothing. `WindowCaptureSource` maps any other `.unavailable` from the platform to it, so window mode never shows the area-capture "smaller area" advice.
- `CaptureSurfaces.start` shows `failure.title` and `failure.message` for `.captureFailed(.window)`. Diagnostics gains closed codes `noCapturableWindow`, `windowChanged`, `windowTooLarge` and `windowRefused`.

**Tests:**
- `d2WindowUnderThePointerIsPickedNotSystemChrome` (5 cases) and `d2WindowCaptureTakesTheWindowUnderTheCursorNotTheCursor`: wrappers removed. Red before the fix (`picked?.id → 4`, `offered → [4, 7]`, `captured → [4]`), green after.
- New: `everyWindowFailureMessageNamesItsCause`, `windowsJustInsideTheRulesArePicked` (layer 19, 32×32 pt), `onlySystemChromeOnScreenFailsAsNoWindowWithoutOpeningSelection`, `platformFailureIsReportedAsAWindowFailure` (prepare and pixels), `platformWindowCauseReachesTheCaller` (`windowChanged`, `tooLarge`).
- Changed: `noEligibleWindowsDoesNotOpenSelectionOrConsumeTheBudget` locked `.captureFailed(.unavailable)`; it now expects `.captureFailed(.window(.noWindow))`.
- `foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow` and `foreignFloatingWindowInFrontIsStillPicked` stay green.

**Left open (live):**
- The window row of the live matrix on both displays: ⌘⇧5 highlights and captures the pattern window, not the cursor, the Dock or a menu.
- The notice text itself is shown by the app target (`CaptureSurfaces`), which no package test reaches. A live check should confirm that a failed window capture shows "Window not captured" with the cause, not "smaller area".
- `WindowScreenCapturePlatform` throws `windowChanged`, `tooLarge` and `systemRefused` only against live ScreenCaptureKit; the package tests cover the source's mapping, not those throw sites.
- The 32 pt and Dock-level thresholds come from this ticket; no new decision was recorded in `decisions.md`.
- Under heavy machine load (load average about 11), `RetentionCommandsTests.processKillAtEveryEvictionPointResumesIdempotently` failed with `.recoveryRequired` in the first `ci.sh` run and in 1 of 3 solo runs. This ticket does not touch History. It then passed 8 of 8 solo runs, and 6 of 6 on the clean base commit, so it looks like a load-dependent flake worth its own ticket.

**Evidence (x86_64 only):** `scripts/ci.sh` prints `ci: green` on the second run, including the unsigned app build. `scripts/ci.sh --defects` no longer lists either D2 test as red.


### 2026-09-24: coordinator, integrated

Merged with tickets 60 and 63 (batch 1). `ci.sh` on `main` `22213c5` is green: 326 tests, 67 known issues. The live-matrix rows wait until Prateek approves installing a new build (docs/app-build.md).
