# Removing scrolling capture (decision 60)

Prateek removed scrolling capture as a feature on 2026-09-25. This file covers what the removal involves and when to do it. The work is ticket 87.

## What it involves, layer by layer

| Layer | What goes | Size |
|---|---|---|
| App | Menu item "Capture Scrolling Page", the ⌘⇧6 hotkey and its DA-9 "press again for Done" branch (`FrisketApp.swift`), the scrolling notices and `scrolling.hide()` (`CaptureSurfaces.swift`) | about 20 lines |
| Adapter | `Frisket/Adapters/ManualScrollingCapture.swift`: the frame source, preview panel and Done/Cancel panel | 1 file |
| Core, lifecycle | `.captureScrolling` in `CaptureCommands`; `.scrollingLimited` and `.scrollingRefused` outcomes; the scrolling paths in `CaptureLifecycleCoordinator` (8 references) and `CaptureDelivery` (1); `scrollingEncodedBytes`, `scrollingMemoryBytes` and `scrollingPixelCap` in `CaptureBudgets` | about 60 lines |
| Core, stitcher | `Sources/FrisketCore/Stitcher/`: `Stitcher`, `ScrollingCaptureStitcher` and `ScrollingCaptureSession` | about 990 lines, with the adapter |
| Tests | `Tests/FrisketCoreTests/Stitcher/` (8 files), `ScrollingCaptureCommandsTests`, `ScrollingSessionMemoryTests`, `ScrollingCaptureAdapterTests`, the scrolling case in `CaptureModeExclusionTests`, `Tests/Fixtures/ScrollingCapture/` | 12 files and one fixture folder |
| Repository checks | the `Sources/FrisketCore/Stitcher/` rule in `check_repository.py`, the `stitcher-*` inventories and the stitcher entries in the provenance, identity, memory and latency fixtures, with their `RepositoryChecksTests` cases | 1 rule, about 15 fixtures |
| Live harness | the `scroll-steady`, `scroll-flick` and `scroll-keys` rows; `scroll_start` and `scroll_finish`; `meter blocks`; the `pattern --show-scroll` and `--render-scroll` modes; `drive wheel` and `scrollpos` if nothing else uses them | 3 rows, about 80 lines |
| Docs | `docs/stitcher.md`; the stitcher parts of ADR 0001 and `docs/core-package.md`; `CLAUDE.md` (its scrolling test-seam example); `CONTEXT.md` scrolling terms | 1 doc deleted, 4 edited |
| Spec and plan | Stories 4, 16, 17, 18, 81, 92 and 93 plus the ⌘⇧6 part of story 19, marked retired; plan Phase 1 Gate A and Phase 3 marked removed | text only |

**Dependencies that stay.** No package or system framework belongs to scrolling alone.
- Vision serves Copy Text (OCR).
- GRDB serves History.
- `StripPNGEncoder` and the zlib/libcompression link flags are used by the editor's `PNGBitmapCodec`, so they stay until ticket 67 deletes them.
- `THIRD-PARTY-NOTICES.md` and `docs/ported-files.json` list nothing from the stitcher, so no licence text changes.

**Knock-on simplifications:**
- **DA-6:** the conflict between `scrollingPixelCap` (57,600 px) and the 32,768 px cap disappears. Without scrolling, the largest capture is one display: 5,120 × 2,880 on a 5K screen.
- **Tickets 65 and 67:** the `.tooTall` guard and the tile-pipeline fallback at Gate B lose their main reason, so both tickets shrink.
- **Ticket 75:** the Region request covers area and full-screen capture only. It is no longer blocked by 72.
- **Ticket 80:** it is no longer blocked by 70.
- **Tickets 64, 70, 71 and 72:** withdrawn. Two of them needed xhigh.
- **Live matrix:** three rows gone, about 4 minutes less per display.

## When: now, before the renderer and lifecycle work

1. **Tickets 65 and 73 rewrite the code scrolling lives in:** the coordinator, the budgets and the render path. If scrolling is removed first, those tickets never carry its paths into the new design. If it is removed afterwards, the same code is written, reviewed and deleted.
2. **Nothing in flight touches scrolling.** The open work is 56 (Thumbnail) and 48 (harness), and neither depends on it.
3. **It is low risk.** It deletes a closed feature and adds no behaviour. The compiler finds every missed `switch` case, and `ci.sh` covers the checks and fixtures.
4. **It must not wait for a later clean-up ticket (80).** Until the removal lands, every agent reads the stitcher, its tests and its docs as live requirements.

**Before starting:** tag the last commit that has scrolling (`scrolling-capture-last`), so it can be recovered without searching the history.

## How: ticket 87, one agent, high effort

One commit per step. Run `ci.sh` at the end.

1. **App and adapter:** delete the menu item, the hotkey, the notices and `ManualScrollingCapture`.
2. **Core lifecycle:** delete the command, the outcomes, the coordinator paths and the scrolling budgets. Let the compiler find the leftovers.
3. **Stitcher and its tests:** delete the folder and its tests.
4. **Checks and fixtures:** remove the stitcher rule and fixtures, and update `RepositoryChecksTests`.
5. **Harness:** remove the scrolling rows and helpers. Keep any `drive` command another row uses.
6. **Docs, spec and tickets:**
   - Mark the stories retired, not deleted, so their numbers stay stable.
   - Update `CLAUDE.md`, the ADR and the plan.
   - Unblock 75 and 80.

**Live check** (at most 15 minutes, one display):
- the area, window and full rows still pass;
- ⌘⇧6 does nothing in Frisket;
- the menu has no scrolling item.

This needs a new install. Decision 59 covers only Phase 1 checks and Gate A, so it needs Prateek's approval.
