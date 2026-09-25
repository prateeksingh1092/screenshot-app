# 97: Live drag feedback in the editor

**What to build:** While drawing, moving, resizing or bending a mark, the canvas shows the mark as it will be saved, on every drag event, with its real width, style, curve, head, ink and plate. Today a move, resize or bend jumps into place on mouse-up (`EditorWindow.swift:787-822`, `:273-277`), and the draw guide is a 2 pt straight red line (`:196-206`). Guides follow the chosen colours: the Solid redaction guide shows the chosen fill, and the white edge is one output pixel (audit item 5).

**Blocked by:** none. **Status:** ready-for-agent (medium effort).

- [x] A provisional edit is rendered through the same preview path (`CapturePreview.render`) on each drag event. Commit and undo still happen once, on mouse-up.
- [x] Rendering stays under the frame budget at 6,016 × 3,384, as measured in decision 75 (for example by rendering only the dirty rectangle, or by throttling to display refresh).
- [x] A test in the core: the provisional edits at each drag point equal the edits that mouse-up would commit.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **What changed:** `MarkEditor.provisional(_:fromX:fromY:toX:toY:slop:)` returns the edits `release` would commit, sharing one change computation with `release`, and `selectionOutline(in:)` gives the outline for those edits. The canvas reports every drag event (`onDrag`); `EditorWindow.drag` builds the provisional edits (a held mark through `MarkEditor`, a drawing tool through the same `applyDrag` as mouse-up; crop keeps its dimming guide) and renders them through the existing one-at-a-time `CapturePreview.render` loop. Mouse-up clears them and commits once, one undo step (decision 77). Guides: the red 2 pt line and box are gone; shapes, arrows and lines show only the rendered mark; the Solid redaction shows its rendered chosen fill with a white edge one output pixel wide outside it; Blur and Magnify keep a thin outline. Recorded as this ticket's decision in `decisions.md`.
- **Tests:** `LiveDragTests` (3 tests): the provisional edits equal the committed edits at each drag point for every mark kind and handle, with no commit and no undo registered; a whole live drag is one undo step; the provisional preview equals the flattened delivery byte for byte, with a moving Grey redaction exactly Grey. Red first against a stub `provisional` that returned the unchanged edits. `EditorMemoryRunTests.liveDragRendersEachPointWithinTheFrameBudget` (gated like the other memory runs) measured, in release at 6,016 × 3,384: redaction draw median 5.0 ms, slowest 11.3 ms; Curved arrow tip median 5.5 ms, slowest 15.1 ms; moving over every edit kind with a whole-capture blur median 14.0 ms, slowest 16.9 ms.
- **Open, for the live matrix:** how the drag feels on the real canvas, and the white edge's width at 1× and 2×; the worst-case drag (whole-capture blur underneath) can drop a frame now and then.
