# 50: Selections keep clicks and keys in Frisket

**What to build:** While the user chooses an area or a window, a click inside the Selection or the window highlight goes to Frisket, never to the app underneath. Keyboard focus stays with the overlay, and Esc always cancels. A Selection that starts on any pixel of a display, including its top row, has an Origin display (stories 85 and 86).

**Blocked by:** 45, 48

**Phase:** 1

**Status:** resolved (tested on `main`; live rows wait for an approved install)

- [x] Both overlays receive mouse events inside the Selection hole and the window cut.
- [x] The D14 test passes without the known-defect mark.
- [ ] Live rows on both displays: a click inside the hole doesn't reach the pattern window, Esc cancels after that click, and a top-row pointer starts a Selection.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **D4:** both overlay panels (area and window) set `ignoresMouseEvents = false`. By default, AppKit passes clicks through a window's fully transparent pixels, which is how presses in the Selection hole reached the app underneath.
- **D14:**
  - `DisplaySelectionSession.display(at:)` uses AppKit's `NSMouseInRect` rule: x in [minX, maxX), y in (minY, maxY]. The pointer's y runs from minY + 1 to maxY, so the top row now has an Origin display.
  - The app's two pointer lookups (`ScreenCapturePlatform.displayUnderPointer` and the window overlay's key-panel choice) use `NSMouseInRect` too.
  - `pointsBelongToOneDisplay…` now uses real pointer positions (minY + 1) and asserts that minY is nobody's.
- **Tests:** `d14PointerOnATopPixelRowHasAnOriginDisplay` is unwrapped and green. `ci.sh` is green: 326 tests, 59 known issues.
- **Live:** the `area-click-inside` and `top-row` rows now expect pass. They run after the next approved install. Candidate D28 (a second drag doesn't replace the Selection) may be the same D4 cause; check it then.
