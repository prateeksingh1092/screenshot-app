# 99: Annotation ink palette (decision 92)

**What to build:** Six ink swatches (Red, Yellow, Blue, Green, Black, White) in the style bar for Arrow, Line, Shape and Text, and for a selected mark of those kinds. They call `MarkEditor.recolourSelection` (decision 81). Each swatch's AX label is "Ink colour: <Name>".

**Blocked by:** 97 (same editor code). **Status:** ready-for-agent (medium effort).

- [x] `StyleBar.controls` lists the ink swatches for those tools and marks, and not for Solid redaction, Crop, Blur or Magnify.
- [x] Recolouring is one named undo step, and preview equals flatten in each colour.
- [ ] A live row, `editor-ink-colour`, added to the harness.

## Comments

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Core:** `DocumentAnnotation.palette` (six `InkColour`s; Red #FF3B30 is the existing default, so no golden moves), `inkName(_:)`, `StyleControl.inkColour` in `StyleBar.controls` for Arrow/Line/Shape/Text and their selected marks, `MarkEditor.selectionInk`, `LabelSession.recolour` ("Restyle Label" while typing). Outlined labels now use Box's letter rule (`letterColour(on:)`): black letters in Yellow and White ink, so a White Outlined label stays readable.
- **App:** six "Ink colour: <Name>" swatches in the style bar (group "Ink colour"), one editor-wide ink set on every `InkTool` (Arrow, Line, Shape, Text); a choice recolours the typed label or the selected annotation. Not persisted (ticket 100).
- **Decision:** this ticket's decision in `decisions.md`: the white plate stays for every ink (a dark plate for light inks would be a product change for Prateek); letters in a light ink are black.
- **Tests:** new `InkPaletteTests` (palette, one named undo step and preview = flatten per kind per colour, exact ink inside a shape stroke, typed-label recolour, Outlined letters: red → green), `StyleBarTests` updated for `.inkColour` (the old expectations locked in the bar without ink) plus a test that ink is absent for Solid redaction, Crop, Blur, Magnify and Select.
- **Live:** row `editor-ink-colour` added (matrix.tsv, `row_editor_ink_colour`, new `meter colour` mode); not run, uncalibrated.
- **Open:** first live run of `editor-ink-colour`; whether White/Yellow should get a dark plate is a product question.
