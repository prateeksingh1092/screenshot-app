# 75: One Region request for every capture mode

**What to build:** Area and full-screen capture use one Region request computed in the core, which carries the display ID. `WindowSelection(rows:)` owns the join and filter of window listings. Together they replace the seven-step ordering and the display-ID side channels (scrolling capture was removed by decision 60, ticket 87).

**Blocked by:** 49, 50 (72 withdrawn by decision 60)

**Phase:** 4 (candidates #6, #7)

**Status:** ready-for-agent

- [x] Coordinates are flipped in one place, and displays are looked up in one place.
- [x] The exclusion regression tests from ticket 45 stay green for every mode.
- [ ] The capture rows of the live matrix stay green on both displays.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Recorded as decision 64.

**Scope note:** the ticket's scrolling and ticket-72 parts are void under decision 60; the Region request covers area and full-screen capture only.

**What changed:**
- `Sources/FrisketCore/RegionRequest.swift` (new): `RegionRequest.area`/`.fullScreen` compute the display ID, the display-local top-left source rectangle snapped to pixels, and the output size, with the decoded-byte refusal. `CaptureDisplays` is the one display lookup (pointer with the D14 rule, ID, largest window overlap) and the one AppKit ↔ top-left flip. `DisplaySelectionSession.display(at:)` delegates to it; `WindowSelectionOverlay` and `ScreenCapturePlatform.displayUnderPointer` use it.
- `CaptureImage.displayID`; the coordinator assigns the Thumbnail display from it. The `captureDisplayID` side channels (both platforms, `CaptureSurfaces`, `FrisketApp`) and `FullScreenDisplay` are removed.
- `WindowSelection(rows:excluding:ownProcessID:ownBundleIdentifier:)` joins `WindowListRow` (window-server order) with `ShareableWindowRow` (ScreenCaptureKit) and filters, including the Capture exclusion list. The platform now only fetches rows; `WindowCaptureSource` takes the exclusion list.

**Tests (red → green):** `thumbnailAppearsOnTheDisplayTheCaptureCameFrom` (red with the coordinator line removed); `excludedAppsWindowIsNeverOffered` and `windowThumbnailGoesToTheDisplayHoldingMostOfTheWindow` (red by mutation of `WindowCaptureSource`). New green: `RegionRequestTests` (7), `WindowSelectionRowsTests` (4, incl. the D2 cursor as live rows), Thumbnail display assertions in the area and full-screen command tests. The ticket-45 exclusion tests are unchanged apart from the `FullScreenDisplay` → `SelectionDisplay` rename. D2 had no `knownDefect` wrapper left (fixed earlier); nothing to remove.

**Evidence:** `scripts/ci.sh`: `ci: green`, 318 tests in 47 suites, drift 0 failures (4 pending, decision 61, not this ticket), unsigned app build.

**Open:** the area platform's step protocol (prefetch → prepare → select → hide → capture → finish) is kept; collapsing it to `select`/`capture` would move the ordering tests behind AppKit (decision 64). Live-matrix criterion unticked: Thumbnail placement and window highlight on both displays need a live check.
