# 53: Editor action bar: Done, Copy, Save and Drag always visible

**What to build:** The editor always shows Done, Copy, Save and a drag handle in a bar inside the window, at any window width. ⌘C, ⌘S and Return work whether or not the toolbar overflows. The finish action is called "Done" everywhere (story 87, glossary). The interim `visibilityPriority` step is skipped, as decision 58 records.

**Blocked by:** 48

**Phase:** 1 (D5 → O8)

**Status:** resolved in code (tested on `main` at `b6233e9`); live checks wait for an approved install

- [x] At the default and minimum editor widths, Done, Copy, Save and the drag handle are visible and clickable.
- [x] ⌘C, ⌘S, Return (Done) and Esc or ⌘W work through menu or responder actions, not button key equivalents.
- [x] No "Keep in History" text remains in the UI or in notices, and the VoiceOver labels say "Done".
- [x] The tools stay in the toolbar and stay reachable by keyboard. Typing in the label field is unchanged: Return there doesn't trigger Done.
- [ ] The editor row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5 (1M context), Claude Code, high effort.

- **Action bar.** `EditorActionBar` (in `Frisket/EditorWindow.swift`) runs along the bottom of the content area: the drag handle at the leading edge, then Copy, Save and Done right-aligned, Done last and accent-tinted. Its frames come from the new `EditorWindowLayout.actionBar(width:)` in FrisketCore, with `minimumContentWidth` 560 and `defaultContentWidth` 760. The toolbar keeps the seven tools, the label field, Undo and Close. The hint stays above the canvas.
- **Keys.** No editor button has a key equivalent now. ⌘C (Edit › Copy) and ⌘S (new File › Save) reach `EditorKeyWindow` through the responder chain. So does ⌘Z (Edit › Undo), which the window must override because NSWindow answers `undo:` itself. Esc arrives as `cancelOperation:` and closes only an unchanged editor, as before. ⌘W is unchanged. Return and keypad Enter mean Done through the new core `EditorKey.action`, but only when no text is being edited. In the label field, Return ends typing (a second Return is Done), and Esc behaves as it does elsewhere.
- **Wording.** The Done button, its tooltip and its VoiceOver label now say "Done". The editor notice says "Done could not prepare…". The Thumbnail, notice and menu text says "add to History" instead of "keep in History". Manual check 26 is updated.
- **Harness.** `editor-finish-visible` now looks for "Drag the edited capture", "Copy edited capture", "Save edited capture" and "Done", and its row is flipped to pass. The `editor_done` and `editor_copy` comments are updated; they keep the ⌘W path, which works even when the label field has focus.
- **Tests.** D5 had no `knownDefect` test because there is no package seam. The new `EditorActionBarTests` cover the bar fitting without overlaps at 560 and 760 points and Done being trailing. The new `EditorKeyTests` cover Return meaning Done, Return in the label field not meaning Done, and command keys being left to the menu. Both were red (no API) and are now green.
- **Open (live):** criterion 5, and the key paths themselves: ⌘C, ⌘S, Return, Esc and ⌘W with focus on the canvas, a tool button and the label field. Also the bar's look at 560 points, and the accent tint on Done.


### 2026-09-25: coordinator, integrated

Merged with 53 and 51. At `b6233e9`, `ci.sh` is green: 354 tests, 52 known issues. The live checks listed in the implementer report wait for an approved install.
