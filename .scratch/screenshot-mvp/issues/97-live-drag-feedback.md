# 97: Live drag feedback in the editor

**What to build:** While drawing, moving, resizing or bending a mark, the canvas shows the mark as it will be saved, on every drag event, with its real width, style, curve, head, ink and plate. Today a move, resize or bend jumps into place on mouse-up (`EditorWindow.swift:787-822`, `:273-277`), and the draw guide is a 2 pt straight red line (`:196-206`). Guides follow the chosen colours: the Solid redaction guide shows the chosen fill, and the white edge is one output pixel (audit item 5).

**Blocked by:** none. **Status:** ready-for-agent (medium effort).

- [ ] A provisional edit is rendered through the same preview path (`CapturePreview.render`) on each drag event. Commit and undo still happen once, on mouse-up.
- [ ] Rendering stays under the frame budget at 6,016 × 3,384, as measured in decision 75 (for example by rendering only the dirty rectangle, or by throttling to display refresh).
- [ ] A test in the core: the provisional edits at each drag point equal the edits that mouse-up would commit.
