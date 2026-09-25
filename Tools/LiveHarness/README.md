# Live harness

Tools that drive the installed Frisket against synthetic patterns and measure what it delivers.
They reproduced D1–D26 in the 2026-09-24 live beta (`.scratch/visual-pass/beta/`). Ticket 48
moved them here from `/tmp/frisket-beta`.

**Only synthetic content, only when Prateek is away.** The matrix types, clicks and
uses the clipboard on the real screen. Run it only after Prateek has said he's away. Never point
it at personal windows.

## Build

```sh
Tools/LiveHarness/build.sh      # → .build/live-harness/{pattern,drive,meter,sckwins,sheet}
```

`scripts/ci.sh` runs `build.sh` so the tools keep compiling. It never runs them.

| Tool | Source | What it does |
|---|---|---|
| `pattern` | `Tools/FrisketTestPattern.swift` | Synthetic windows: `--show`, `--show-all`, `--show-window`, `--show-full-screen`, each with `[--display ID\|main\|builtin\|external]` (or `FRISKET_PATTERN_DISPLAY`). Verifiers: `--verify`, `--verify-full`, `--verify-redacted` |
| `drive` | `drive.swift` | Keys, typing, pointer, AX reads and presses, window lists, clipboard save/restore, raw pixel reads. Run `drive` with no arguments for usage, or read the `switch` in `main` |
| `meter` | `meter.swift` | Pixel meters: `px`, `scan` (red/blue runs and markers), `redink` and `band` (annotation ink) |
| `sckwins` | `sckwins.swift` | ScreenCaptureKit's list of small windows, with bundle IDs (D2: the cursor window has an empty bundle ID) |
| `sheet` | `sheet.swift` | A labelled contact sheet of evidence PNGs |

## Run the matrix

```sh
Tools/LiveHarness/beta-matrix.sh --dry-run                  # prints the plan; touches nothing
Tools/LiveHarness/beta-matrix.sh --live                     # every row, both displays
Tools/LiveHarness/beta-matrix.sh --live --display external --row area
```

Before `--live`, launch the installed Frisket (`~/Applications/Frisket.app`); the script refuses
to start without it.

The rows are in `matrix.tsv`. Each row names its defect and is `xfail` while that defect is
open. A fix flips its row to `pass` in the same change. An unexpected pass is `XPASS`, and it
fails the run just as a `FAIL` does.

Output goes to `.build/live-harness/runs/<time>/`, which git ignores:
- `report.tsv`;
- one log per row and display;
- evidence PNGs, cropped to the pattern window, or to its central 800×600 when it fills the display.

The script saves the clipboard to an owner-only temporary file before the first row and
restores it on every exit path, including Ctrl-C. It deletes the saved copy only after a
successful restore. The only files it deletes are exports that its own `history-save` row
just created. Test captures stay in Frisket's History, as they did in the beta.

**Calibration.** Several steps depend on UI geometry that tickets 50–64 change: where a label
lands with the Text tool, and the confirmation-button labels. The first `--live` run records each step in the row logs. Adjust the row functions from those logs, not
from guesses.

## Safety rails (in `drive`, not the caller)

- **Keys:** `key`, `type`, `kdown` and `kup` refuse unless Frisket or `pattern` is frontmost. Global ⌘⇧ hot keys follow the same rule.
- **Pointer:** every pointer point must lie on an active display. The arrangement is re-read on each command, because a lid closing once shifted every coordinate by 1792.
- **Clicks:** a click, a double click, or the start of a drag must land on a window owned by Frisket or `pattern`. That stops a misread coordinate from clicking another app (one beta click landed in the terminal). `FRISKET_DRIVE_ALLOW_OWNERS=Finder` widens this for a single command.
- **Frisket lookup:** Frisket is found by bundle ID (`FRISKET_BUNDLE_ID` overrides it). `drive frisket` prints its PID, and AX commands accept `frisket` or `pattern` in place of a PID.

## Key codes

| Key | Code | Key | Code |
|---|---|---|---|
| 1 | 18 | Return | 36 |
| 2 | 19 | Keypad Enter | 76 |
| 3 | 20 | Esc | 53 |
| 4 | 21 | Tab | 48 |
| 5 | **23** | Page Down | 121 |
| 6 | **22** | C | 8 |

Modifiers are passed as `cmd,shift,opt,ctrl`: `drive key 21 cmd,shift` is ⌘⇧4. Carbon hot keys
fire only for events posted at the HID tap, which is what `drive` does.

## Gotchas

- **Retina halving.** On the built-in display a screenshot pixel is half a point, so divide screenshot coordinates by 2 before pointing. `drive displays` prints each display's scale.
- **Stopping the pattern.** Use `pkill -x pattern`. `pkill -f …/pattern` misses relative launches.
- **Preselection.** Frisket preselects the last Selection, and a press inside it goes through to the app underneath (D4). Start each drag outside the previous Selection. Don't drag twice in one activation: a second drag doesn't replace the first Selection (candidate D28), so `select_rect` drags once.
- **AX press vs real click.** An AX press on a Thumbnail's Edit doesn't activate Frisket, and the editor can open behind other windows. Use `drive axclick frisket "Edit capture"`, which sends a real click at the element's centre.
- **Privacy.** Crop evidence to the test windows (`seq "shot X Y W H FILE"`), because the desktop shows personal file names. Save the clipboard before a run and restore it after (`drive clip-save` / `clip-restore`); the matrix does both.
- **Swipe to dismiss** needs precise, phased trackpad deltas, which synthetic events don't produce. The matrix doesn't test it.
- **CleanShot comparison.** It was a one-off (plan §1.3). Its CleanShot-only typing helper wasn't kept; if a parity question comes up, drive CleanShot through its menu with AX, and decline its URL-scheme consent prompt.
