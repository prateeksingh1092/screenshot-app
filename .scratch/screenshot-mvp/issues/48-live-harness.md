# 48: Live harness in the repository

**What to build:** The live checks that found D1–D26 can be rerun from the repository. The harness has:

- a pattern window with a display choice and a scroll page that opens at its top;
- a focus-guarded driver that types only into Frisket or the pattern and checks every point against all displays;
- pixel meters for blocks and ink bands;
- a beta-matrix script that runs the plan's §1.2 live rows, saves and restores the clipboard, and writes a pass/fail report without personal pixels.

**Blocked by:** 43

**Phase:** 0

**Status:** in-progress (merged; the first unattended live run waits until Prateek is away)

- [x] The harness tools build from the repository with one command, and `ci.sh` compiles them without running them.
- [x] The driver refuses to send keys unless Frisket or the pattern window is frontmost, and refuses points outside every display.
- [x] The scroll page opens at its top.
- [x] The beta matrix covers area, window, full-screen and scrolling capture (steady and flick); editor marks (arrow, label, Solid redaction, Blur, Magnify, crop); Copy Text with and without text; the Thumbnail stack; History Copy, Save and Delete; ⌘⇧2 focus; and a top-row pointer on both displays. Each row names its defect ID, and rows for open defects are expected failures.
- [x] The clipboard is saved and restored around every run. Evidence is cropped to the test windows and kept out of git.
- [x] A README beside the tools records the key codes and gotchas from the handoff.
- [ ] One unattended run of the matrix is recorded. It drives the real screen, so it runs only when Prateek says he is away.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5, Claude Code, medium effort. Branch `ticket/48-live-harness`. No live run: nothing was launched, typed, clicked or copied; only compiles and `--dry-run`.

- **Promoted from `/tmp/frisket-beta`:** the Swift sources only; none of its `.txt`, `.plist`, `.log` or `.png` state came across.
  - `drive.swift`:
    - Frisket is found by bundle ID instead of a hard-coded PID.
    - Every pointer point must lie on an active display; the old external-display ID is gone.
    - New: a click or drag may start only on a Frisket or pattern window.
    - Folded in the beta's `wheel`, `cardact`, `whatat`, `hit`, `wins` and `cgbounds` as `drive wheel`, `drive cardact`, `drive whatat`, `drive cgwin` and `drive displays`.
    - Added `axfind`, `axframe`, `axclick` (a real click), `scrollpos`, `clip-count`, `frontmost` and `size`.
  - `meter.swift`: the beta's `scan`, `redink` and `px`, plus `band` and `blocks`, which checks an exact scroll stitch.
  - `sckwins.swift` (was `sck`) and `sheet.swift`.
  - Dropped: `cstype` (CleanShot-only), `measure.py` (a two-line stub), and `hit`/`whatat` (hard-coded points).
- **Pattern tool:** it stays in `Tools/FrisketTestPattern.swift`.
  - `--display ID|main|builtin|external` (or `FRISKET_PATTERN_DISPLAY`).
  - The `--show-scroll` page is flipped and opens at its top, with block 1 first.
  - New `--render-scroll OUT 1|2` renders the page offscreen as a reference.
- **Meter check:** `meter blocks` passes the rendered page at 1× and 2×. It fails a copy with 15 rows cut at a seam (height, blue 75, missing marker, 385 spacing) and one with 34 rows cut.
- **Build and CI:** `Tools/LiveHarness/build.sh` compiles `pattern`, `drive`, `meter`, `sckwins` and `sheet` into `.build/live-harness/` in Swift 5 mode (33 s cold, no warnings). `scripts/ci.sh` now runs it, compile only.
- **Matrix:** `beta-matrix.sh` runs `matrix.tsv`: 21 rows, each on the built-in and external displays.
  - Modes: `--dry-run` or `--live`, plus `--display` and `--row`.
  - Verdicts: PASS, XFAIL, XPASS, FAIL or ERROR. XPASS, FAIL and ERROR make the exit status 1.
  - The clipboard is saved to an owner-only temporary file and restored by an EXIT trap.
  - Evidence is cropped to the pattern window. Evidence and the report go to `.build/live-harness/runs/<time>/`, which git ignores, as it does `*.png`.
- **Open:** the unattended run needs Prateek away. The first live run will calibrate the steps that depend on UI geometry (README "Calibration").
- **CI:** `scripts/ci.sh` is green in the worktree: 292 tests in 45 suites and 8 known issues; the unsigned build and the harness compile succeeded.

### 2026-09-24: coordinator, merged

Merged into `main`; at `ce152d4`, `ci.sh` compiles the harness. Still open: the first unattended run and calibrating the rows from its logs.
