# 87: Remove scrolling capture

**What to build:** Scrolling capture is gone from the product, the code, the tests, the checks, the harness and the docs (decision 60). The inventory, the timing and the steps are in `Plans/2026-09-25-remove-scrolling-capture.md`.

**Blocked by:** none (it runs before 65 and 73)

**Phase:** 1b

**Status:** ready-for-agent (high effort)

- [x] Tag `scrolling-capture-last` on the last commit that has scrolling.
- [x] No menu item, no ⌘⇧6 hotkey, no `ManualScrollingCapture`.
- [x] No `.captureScrolling` command, no scrolling outcomes or budgets, no `Sources/FrisketCore/Stitcher/`.
- [x] Scrolling tests, fixtures, check rules and harness rows are removed. `ci.sh` is green.
- [x] The stories are marked retired, and `CLAUDE.md`, the ADR, the docs and the plan are updated. Tickets 75 and 80 are unblocked.
- [ ] Live check, at most 15 minutes on one display: the area, window and full rows pass; ⌘⇧6 does nothing.

### 2026-09-25: implementer, report

Model and effort: Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Tag:** `scrolling-capture-last` already pointed at d438dc5 (the branch base); left untouched.
- **App and adapter:** the "Capture Scrolling Page" menu item, the ⌘⇧6 dispatch and DA-9 branch, the scrolling notices and `scrolling.hide()` are gone; `ManualScrollingCapture.swift` and the `ScrollingRegionCapturing` conformance are deleted. The Shortcuts settings text and onboarding copy no longer mention ⌘⇧6.
- **Core:** `.captureScrolling`, `.scrollingLimited`, `.scrollingRefused`, `CaptureSourceFailure.rejectedAlignment`, the coordinator's scrolling path and init parameters, the three scrolling budgets, the scrolling-only diagnostic codes (`pixelCap`, `memoryBudget`, `rejectedAlignment`) and `ShortcutAction.captureScrolling` are removed. `Sources/FrisketCore/Stitcher/` is deleted. `StripPNGEncoder`, Vision, GRDB and the zlib/compression link flags stay.
- **Shortcut preferences:** removing `captureScrolling` would have made the saved `globalShortcuts.v1` preference fail to decode and silently reset every customised shortcut. `ShortcutAction.savedBindings(from:)` now skips unknown actions; `CarbonHotKey` uses it. Two new tests cover it (a legacy blob naming `captureScrolling`, and a round trip).
- **Tests:** Stitcher tests (8 files), `ScrollingCaptureCommandsTests`, `ScrollingSessionMemoryTests`, `ScrollingCaptureAdapterTests`, the scrolling case in `CaptureModeExclusionTests`, `Tests/Fixtures/ScrollingCapture/` and its `.gitignore` exceptions are deleted. `ShortcutCommandsTests` no longer expects a ⌘⇧6 binding.
- **Checks:** the `Stitcher/` import allowance, the three `stitcher-*` inventories and their test cases are removed; generic fixtures that used a `Stitcher` path now use `Ported`/`Port`/`Disk`.
- **Scripts and harness:** `scripts/stitcher-memory-run.sh`, `stitcher-vision-probe.sh`, `scrolling-memory-run.sh`; matrix rows `scroll-steady`, `scroll-flick`, `scroll-keys`; `scroll_start`/`scroll_finish`; `meter blocks`; `pattern --show-scroll`/`--render-scroll`; `drive wheel` and `drive scrollpos` (no other row used them).
- **Docs:** `docs/stitcher.md` and `docs/manual-checks/35-scrolling-capture.md` deleted; ADR 0001 gets a superseded note; `docs/core-package.md`, `CONTEXT.md`, `README.md`, `CLAUDE.md` (seam example is now `CaptureCommandLayer.execute`, since `CaptureFlattening.flatten` does not exist yet), `docs/app-build.md`, `docs/history-storage.md`, manual checks 22, 24, 36 (marked retired), 38, 39, the harness README, spec stories, plan Gate A and Phase 3, tickets 75 and 80 updated.
- **Result:** `scripts/ci.sh` prints `ci: green`: repository checks, 304 package tests in 45 suites (39 known issues), unsigned app build, harness compile.
- **Open:** the tolerant shortcut decoding is a technical choice not yet recorded in `decisions.md`. The only remaining grep hit in live code is the `captureScrolling` string inside that migration test, on purpose.
- **Live (coordinator):** area, window and full rows on one display; ⌘⇧6 does nothing; the menu has no scrolling item.
