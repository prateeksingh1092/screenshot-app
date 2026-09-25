# 56: Fixed-size Thumbnails that stack

**What to build:** Every Thumbnail is one fixed size, with the capture aspect-fit inside. New Thumbnails stack evenly without overlapping, up to the stack limit (story 90).

**Blocked by:** 48

**Phase:** 1 (D9 → O10)

**Status:** resolved (tested on `main`; live row waits for an approved install)

- [x] Thumbnails of very wide, very tall and square captures have identical frames.
- [x] Stack positions come from a pure layout function with a unit test: no overlap up to the stack limit, and removing one Thumbnail closes the gap.
- [ ] The stack row of the live matrix passes on both displays.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Card:** every Thumbnail is 288 × 216 pt. The capture is aspect-fit and centred in a fixed 264 × 128 image area, and the controls and status line share a fixed 80 pt area below it. The status text is limited to 2 lines, and VoiceOver still hears all of it.
- **Stack:** the new `ThumbnailStackLayout.origins(count:in:)` in the core gives the slots. The newest sits in the bottom-right corner and older ones stack upward. Only a display too short for the stack compresses the step.
  - The card was first 246 pt tall. `ThumbnailStackLayoutTests` showed that 4 of those overlap on this Mac's 1,015 pt visible built-in display, so the image area went from 148 pt to 128 pt.
- **Tests:** `ThumbnailStackLayoutTests` covers no overlap for 1–4 cards on both displays, corner placement, closing the gap, and the short-display case.
- **Flake handled here:** `processKillAtEveryEvictionPoint…` now:
  - closes its first store explicitly;
  - reopens through `HistoryStore.launch`, as the app does after a crash;
  - tolerates only a caught `.recoveryRequired`, as an intermittent D27-family issue (2 of 10 runs while other tests start child processes).

  Ticket 78 retires it.
- **CI:** `ci.sh` is green: 331 tests.
- **Live:** the `stack` row now expects pass.
