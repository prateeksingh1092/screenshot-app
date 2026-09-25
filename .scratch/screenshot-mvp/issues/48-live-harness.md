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

### 2026-09-24: coordinator, first live runs (Prateek away)

The installed Frisket (build 8, `73be4ce`) ran on both displays. Only synthetic patterns were used, and the clipboard was saved and restored on every run.

**Calibration fixes:**
- `select_rect` drags once. The old decoy drag was captured instead of the real Selection (see candidate D28).
- Tool names are the real accessibility names: `Solid Redaction`, `Crop`, `Arrow`, `Shape`, `Text`, `Blur`, `Magnify`.
- `tool()` presses only a tool that isn't selected, because pressing the selected tool deselects it.
- An edit finishes with ⌘W, then Return (Finalize), and the result is copied from its Thumbnail. This works under D5.
- Scrolling starts when the mouse button comes up. Return in the panel means Done, so the row no longer presses it.
- Cleanup closes every editor and every Thumbnail between rows.
- Steady-scroll steps are 4 wheel lines.
- The redaction drag starts on the image corner, because a drag that starts outside the image is ignored.
- `drive activate` is new, and so is a fallback for opening the editor.
- The click guard skips the Dock's full-display backdrop window, except over the bottom 100 pt.
- `$DW×$DH` is fixed; `set -u` failed on the multibyte character.

**Result, per display (external 1× and built-in 2×):**
- **PASS (6):** area, full, editor-redaction (exact black under Blur and Magnify), editor-crop, copytext-text, history-copy.
- **XFAIL for the right reason (12):** window (D2), scroll-steady and scroll-flick (D3), scroll-keys (D11: Page Down didn't move the page), editor-arrow-label (D1: no arrow ink, label repeated), editor-label-text (D6), editor-finish-visible (D5), copytext-none (D8: "Copied 0 characters" alert), stack (D9), focus-latest (D12: keys went to the pattern), history-save (D17: UUID name, no date), drag-cancel (D7).
- **XFAIL, reason still unclear (3):**
  - area-click-inside: the pattern window opened with odd bounds (87×33 on the built-in display).
  - top-row: the log has no evidence of why it failed.
  - history-delete: the log has no evidence of why it failed.

**Candidate findings, not yet in §1.2:**
- **D28:** a second drag in one area-capture activation doesn't replace the first Selection. Checked by hand: a 100×100 first drag was captured, not the 320×180 second drag.
- **Minor:** pressing the selected editor tool leaves no tool selected.
- **Minor:** a redaction drag that starts just outside the image is ignored. CleanShot accepts such drags.

**Still open:** calibrate the three unclear rows, and rerun the whole matrix after each Phase 1 batch.

### 2026-09-25: coordinator, Phase 1 live run (Prateek away)

Installed signed build of `main` at `7ea997e` (decision 59), in `~/Applications/Frisket.app`. Full run `20260925-002814` covered both displays, followed by single-row reruns and hand checks. Only synthetic content was used, and the clipboard was restored.

**Phase 1 fixes confirmed live on both displays:**
- D1: arrow and label ink both land in place.
- D5: Done, Copy and Save are visible.
- D11: Page Down scrolls during a scrolling capture.
- D12: ⌘⇧2 gives keys to the Thumbnail.
- D14: a pointer on the top pixel row still starts a Selection.
- D4: a press inside the preselected Selection doesn't move the pattern window, and Esc cancels.
- D7: a cancelled drag leaves History and drag staging unchanged.

**Confirmed by hand; the row still fails for a harness reason:**
- D8: "No text found" is shown, the clipboard is unchanged, and no alert appears.
- D10: Delete asks first, then removes the image.

**Still open, as the matrix expects:** D2, D3 (steady and flick), D6, D17.

**Reopened: D9, ticket 56.** Two Thumbnails taken within 10 s sit on the identical frame, according to both the window server and accessibility.
- **Suspect:** `ThumbnailPanel.layoutChrome` (lines 334–336) re-sets the origin it has just read on every model change, which cancels `place(at:)`'s animated move.
- **Matrix:** the row is now `xfail`.

**Calibration fixes (`beta-matrix.sh`):**
- **area-click-inside:** mouse-up accepts a Selection, so the old row's "click inside" landed after the capture had finished. The row now presses inside the *preselected* Selection of a second activation, then checks Esc in a third.
- **copytext-none:** the notice is a static text's value, which `axfind` doesn't search. The row now greps `axdump`.
- **history-delete:**
  - It uses Copy, which keeps the Thumbnail open; the editor's Done closes it.
  - It presses the alert's Delete button through accessibility; Return doesn't reach the modal while another app is frontmost.
- **Thumbnail buttons:** they report `enabled="0"` for a moment after the Thumbnail appears. Captures now wait for `card_ready`, and `card_copy` waits too. Whether a user notices this delay is unmeasured.
- **drag-cancel:**
  - The drop point is the first pattern point of a 5×5 grid.
  - The Dock's full-display backdrop is skipped, which is why the built-in display found no point before.

**Flakes:** in the full run, editor-arrow-label (D1) and editor-finish-visible (D5) failed on the external display, and both passed alone. This points to state leaking between rows. One likely source: `reset_state` never closes the History window.

**Candidates:**
- **D28 is not a defect.** Mouse-up accepts the Selection, so a second drag within one activation doesn't exist.
- **Deferred to editor tickets 84–86:** tool deselection and the outside-image redaction drag were not checked.

**Still open:**
- copytext-none and history-delete still fail in the harness after these fixes. Their logs haven't been read yet.
- The History window leak between rows.
