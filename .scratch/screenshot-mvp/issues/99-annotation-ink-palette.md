# 99: Annotation ink palette (decision 92)

**What to build:** Six ink swatches (Red, Yellow, Blue, Green, Black, White) in the style bar for Arrow, Line, Shape and Text, and for a selected mark of those kinds. They call `MarkEditor.recolourSelection` (decision 81). Each swatch's AX label is "Ink colour: <Name>".

**Blocked by:** 97 (same editor code). **Status:** ready-for-agent (medium effort).

- [ ] `StyleBar.controls` lists the ink swatches for those tools and marks, and not for Solid redaction, Crop, Blur or Magnify.
- [ ] Recolouring is one named undo step, and preview equals flatten in each colour.
- [ ] A live row, `editor-ink-colour`, added to the harness.
