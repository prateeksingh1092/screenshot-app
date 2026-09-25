# 51: The Loupe while choosing a Selection

**What to build:** The Loupe comes back (D26, stories 6 and 100). While the user chooses an area Selection, a magnified view of the device pixels under the pointer follows the pointer so edges can be placed exactly. The Loupe never appears in the capture.

**Blocked by:** 48

**Phase:** 1

**Status:** ready-for-agent

- [x] The Loupe shows device pixels around the pointer, with the centre pixel marked, on Retina and 1× displays.
- [x] It stays on the Origin display and moves aside near display edges so it never covers the pointer.
- [x] Its pixels come from the same capture source as the Selection, so it never shows Frisket's own overlay.
- [x] It is hidden before pixels are taken, so no capture contains it.
- [ ] Live row: the Loupe is visible on both displays, and the captured image has no Loupe in it.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5 (1M context), Claude Code, high effort.

The Loupe is back (D26). There was no `knownDefect` test for D26, so the new tests went red first: they didn't compile before the Loupe existed, and breaking the fail-closed guard or the coalescing turns 3 adapter tests red.

- **Why the old magnifier was slow.** Before the overlay appeared, the deleted `SelectionMagnifier` captured every display in full, one after another, with a fresh `SCShareableContent` load for each (up to 128 MB per display). It then repainted the whole overlay on every pointer move. Its frozen preview also went blank after a Space change.
- **Core, `Sources/FrisketCore/Loupe.swift`:**
  - `Loupe.sample` picks the 15 × 15 device-pixel square around the pointer's pixel. Near a display edge the square stays whole and on the display, and the marked pixel moves off centre.
  - `Loupe.frame` puts the Loupe above and to the right of the pointer. It flips per axis at the display edges and stays 20 pt clear of the pointer.
  - `DisplaySelectionSession.loupeTarget` follows the display under the pointer until a drag starts. After that it stays on the Origin display, clamped to its edge.
- **Adapters:**
  - `ScreenCapturePlatform.sampleLoupe` captures only that square, through the Selection's own route: the same `ScreenCaptureContent`, filter policy and exclusions.
  - It loads its snapshot after the overlay is on screen. It fails closed unless the snapshot lists Frisket's own process, so the overlay can never be sampled.
  - An app launch or a Space change drops that snapshot.
  - `LoupeFeed` keeps at most one capture in flight; faster moves collapse into the latest.
  - `LoupeView` is drawn with layers, with nearest-neighbour cells, a grid and a red marker, so moving it repaints nothing beneath.
  - `SelectionOverlay.finish` stops the feed and hides the Loupe before it orders the panels out.
- **Decision:** recorded under decision 58, Phase 1 choices.
- **Tests:**
  - `LoupeTests` (core): 6 tests.
  - `LoupeSamplingTests` (adapter): 6 tests.
- **Open, live only:**
  - Whether the Loupe appears promptly on both displays.
  - Whether its marker sits on the pixel under the crosshair at 1× and 2×.
  - Whether it tracks smoothly with low CPU use.
  - Whether the first sample is ever refused because the snapshot doesn't yet list Frisket.
  - Whether captures contain no Loupe.

