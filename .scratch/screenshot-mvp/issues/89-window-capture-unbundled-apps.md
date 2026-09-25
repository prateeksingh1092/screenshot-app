# 89: Window capture works for apps without a bundle ID

**What to build:** Window capture offers every normal window under the pointer, including windows of apps without a bundle ID, such as unbundled executables and some Java or Python apps. The mouse cursor is still never offered (D2).

- **Today:** `WindowSelection` refuses any window whose owner has an empty bundle ID (`Sources/FrisketCore/WindowSelection.swift:105`). That rule was added to skip the cursor, which ScreenCaptureKit lists with an empty bundle ID.
- **The fix:** skip the cursor for what it is, not by its bundle ID: its owner, its window layer, or its size.

**Evidence (2026-09-25, live):** the `window` row fails on both displays. After ⌘⇧5 the screen dims but no window is highlighted, so Return does nothing. `sckwins 5000` lists the pattern window as `owner=pattern bundle=""`. The package D2 test passes because its fixture windows all have bundle IDs.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [x] A `WindowSelection` test with an unbundled owner's window, taken from a real `sckwins` row, goes red, then green.
- [x] The D2 cursor test still passes, and the cursor is excluded without using the bundle ID.
- [ ] The live `window` row passes on both displays; the coordinator checks this and flips the row from `xfail` to `pass`.

## Comments

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Recorded as decision 69.

**What changed:** `Sources/FrisketCore/WindowSelection.swift` drops the empty-bundle-ID rejection. The cursor stays excluded by its level (2147483630, above the Dock-level ceiling of 20) and its size (under 32 pt). The Capture exclusion list is unchanged; it matches bundle IDs, so an unbundled window cannot be excluded by it.

**Tests (red → green):** `unbundledAppsWindowIsPicked` and `unbundledAppsWindowIsOfferedAndTheCursorIsNot` (the live `sckwins` rows: pattern window `bundle=""` at layer 0 behind the cursor) were red, now green. The D2 intruder case `empty bundle ID` locked in the old behaviour; it is replaced by `cursor-level window` (a large, bundled window at the cursor level), which shows the cursor is excluded without the bundle ID. The D2 cursor tests (core and adapter) pass unchanged.

**Evidence:** `scripts/ci.sh`: `ci: green`, 336 tests in 49 suites, unsigned app build, live harness compiled.

**Open:** the live `window` row on both displays (coordinator).
