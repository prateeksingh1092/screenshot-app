# 88: Choose the Solid redaction colour

**What to build:** The Solid redaction tool offers a fill colour, with black as the default (decision 61, spec story 42). Every redacted pixel is exactly that colour at alpha 255 in every output: clipboard, file, drag, History, Thumbnail and OCR input. This holds at any display scale, after cropping, and under Blur and Magnify.

**Blocked by:** 65 (the native renderer draws the fill), 84 (editable marks carry a colour)

**Phase:** 2b (with 84–86)

**Status:** ready-for-agent (decision 61: no filled shapes, a small palette)

- [x] The canary leak tests at the flatten seam pass for black and for at least two other colours.
- [ ] `pattern --verify-redacted` takes the expected colour, and the live `editor-redaction` row checks a colour other than black. (Code done: the verifier takes the colour and the row picks Grey; the live-matrix run is the coordinator's.)
- [x] Shapes are outlines only; no editor tool other than Solid redaction draws an opaque fill. (Amended by decision 88: a Box-style label fills its box; it is a label, not a redaction.)
- [x] Decision 59's filled-rectangle rule, the plan's "guaranteed black" wording and the CleanShot study are updated.

## Comments

### 2026-09-25: implementer, report

Model and effort: Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

**What changed and why**
- `SolidRedaction.palette` (FrisketCore): five opaque neutrals, Black first as the default, then Dark Grey, Grey, Light Grey, White; each a `RedactionColour` with a display name. `MarkEditor.selectionFill` reports a selected redaction's colour.
- Editor: a row of five swatch buttons in the toolbar (one new toolbar item, `redaction-colour`, before the label field), enabled with the Solid Redaction tool or a selected redaction. A choice sets the tool's fill and recolours a selected redaction (`recolourSelection`, one "Restyle Solid Redaction" undo step). Hint and VoiceOver text name the colour. `SolidRedactionTool` carries the colour.
- `pattern --verify-redacted PATH 1|2 [colour]` takes the expected colour (palette name or `RRGGBB`, black by default). The live `editor-redaction` row presses "Redaction colour: Grey" and verifies `grey` (not run here).
- Docs: CONTEXT.md, decision 59's filled-rectangle rule, the plan's "guaranteed black" rows, the CleanShot study, manual check 26 and the harness README. `Checks/retired-terms.tsv` no longer marks "opaque black" pending for 88. This ticket's decision is recorded.

**Tests**
- New: `theRedactionPaletteIsSmallNeutralOpaqueAndStartsWithBlack`, `thePaletteRecoloursASelectedRedactionExactly` (flatten is exact for each palette colour).
- `EditorRedactionCommandsTests`: every canary case now runs in Black, Grey and White at 1× and 2× (History, Thumbnail, clipboard, Save, drag, crop, Blur and Magnify); the OCR stand-in now records its input and checks it is exactly the chosen colour.
- New `CaptureRendererTests.aShapeIsAnOutlineOnly` (2, 4 and 8 pt): the pixels inside a shape's outline stay the source.

**Open:** the live `editor-redaction` row with Grey (coordinator); no colour memory between editors (not asked for).

