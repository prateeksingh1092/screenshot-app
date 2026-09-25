# 81: Clear windows, voice and names

**What to build:** History and Settings open on the active display with focus on the first useful control. A Thumbnail's picture has an accessibility element. Save confirms without a modal, and exported file names carry the date. About renders as formatted text. Copy Latest and Delete Latest are disabled when there is nothing to act on. Shortcuts are written ⌘⇧ everywhere (story 101).

**Blocked by:** 76

**Phase:** 5 (D15, D16, D17)

**Status:** ready-for-agent

- [x] Each item above has a live matrix row or a unit test.
- [ ] Settings' first focus is not the auto-dismiss field.
- [x] Export names follow `Frisket <date> at <time>.png` or the format recorded in `decisions.md`.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). No `knownDefect("D15"|"D16"|"D17")` wrapper existed (they were live-only defects), so each package-reachable item got a new test; the rest became live-matrix rows. Recorded as this ticket's decision in `decisions.md`.

- **Export names (D17):** `ExportFilenamePolicy.filename(at:in:collisionIndex:)` gives `Frisket 2026-09-25 at 14.03.07.png` (local time of the save, ` (2)` on collision). `PNGFileExporter` takes `now`/`timeZone`. Dragged-out files use the same name instead of `Capture.png`. Tests: `SaveCommandsTests.exportNameCarriesTheDateAndTimeOfTheSave`, `draggedFileNameCarriesTheDate`; `exportFilenameNeverOverwritesExistingFiles` changed from the UUID names to the dated ones (it locked in the old format).
- **Save confirms (D17):** `Notice.after` returns `Notice.saved(filename)` for a successful Save or Retry Save, on the notice line; History row Save shows it through a new `onNotice` hook. `NoticeTests.successOutcomesShowNoNotice` no longer lists Save (it locked in the silent Save); new `saveConfirmsWithTheExportName`.
- **⌘⇧ order (story 101):** `ShortcutBinding.modifierSymbols` in the core; Settings rows use it; README updated. Test `shortcutsAreWrittenCommandShift`. Menu key-equivalent glyphs are drawn by macOS as ⇧⌘ and stay native.
- **Copy/Delete Latest (D17):** `Thumbnails.latestToCopy`/`latestToDelete`, used by the menu actions and by `validateMenuItem`. Test `copyAndDeleteLatestActOnlyWhenThereIsSomethingToActOn`.
- **About (D17):** `AboutContent.noticeBlocks` (headings, formatted paragraphs, monospaced licence text); the notices intro no longer cites a decision number. Test extended in `aboutShowsTheBundleVersionAndThirdPartyNotices`.
- **Windows (D15), Thumbnail picture (D16):** History and Settings centre on the pointer's display; Settings clears first responder so the auto-dismiss field isn't focused; the Thumbnail image well is an image accessibility element. App-only: live rows.
- **Live matrix:** `history-save` flipped to `pass`; new rows `history-display`, `settings-focus`, `thumbnail-picture`, `save-confirms`, `menu-latest` with row functions in `beta-matrix.sh`. Not run and uncalibrated; the coordinator should run them and adjust from the logs.
- **Open:** the Settings focus fix (`makeFirstResponder(nil)`, also on the next run loop turn) and the About layout are unverified live. The Matt Pocock section of the notices still names repository paths; it is a licence notice, so it was left.

