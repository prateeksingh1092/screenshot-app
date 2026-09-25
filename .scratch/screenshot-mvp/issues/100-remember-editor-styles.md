# 100: Remember the editor's last-used styles (decision 93)

**What to build:** The redaction colour, ink colour, arrow style, line width, label size and label style persist through `PreferenceKey` and UserDefaults, across editors and relaunches.

**Blocked by:** 99. **Status:** ready-for-agent (medium effort).

- [x] A core test: a style model loads its defaults when nothing is stored, round-trips every value, and ignores a stored value that is invalid (for example a redaction colour outside the palette).
- [x] A new editor opens with the last choices. <!-- wired in EditorWindow; the live look is the coordinator's -->

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Recorded as this ticket's decision in `decisions.md`.

- **Styles:** new `EditorStyles` (`Sources/FrisketCore/EditorStyles.swift`) with eight new `PreferenceKey` cases. `EditorWindow` loads it from `UserDefaults.standard` when it opens and applies it to the tools, and stores it whenever a style control changes the tools (redaction colour, ink, arrow style, line width, label size and style). Line widths are kept per tool (Arrow, Line, Shape), as the editor already had them. Tests: `EditorStylesTests` (defaults with nothing stored, every value round-trips, each invalid value falls back alone, a remembered redaction colour is always an opaque palette colour); red first because the API didn't exist, then green.
- **Leftover 1, ticket 101's fifth criterion:** a label's bottom-right handle scales its size (whole points, 6–144) and its wrap width, as one "Resize Label" step, with the live preview through `MarkEditor.provisional`. Test `LabelTests.theCornerHandleScalesTheLabelAsOneUndoStep`; `LiveDragTests.provisionalEditsAtEachDragPointEqualWhatMouseUpCommits` now also drags the label corner. Changed existing test: `theWidthHandleWrapsTheText` expected a label to have only `[.trailing]`; it now expects `[.trailing, .bottomRight]`. The size menu shows a handle-set size as its own item.
- **Leftover 2, onboarding Later:** `OnboardingContent.current(for:)`; reopened after completion, the button is "Close" with VoiceOver label "Close onboarding. Reopen it with What Frisket Stores… in the Frisket menu bar menu". Test `OnboardingAndAboutTests.aReopenedOnboardingDoesNotPromiseToShowAgainOnLaunch`.
- **Open (live):** a new editor opening with the last styles, including after a relaunch; the label corner handle's drag feel and the size menu item; the reopened onboarding's Close button and its VoiceOver label.
