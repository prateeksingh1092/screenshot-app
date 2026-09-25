# 96: Marks are invisible to VoiceOver (D31)

**What to build:** Each mark on the editor canvas is an accessibility element with a role (image), its label from `MarkEditor.accessibilityLabel(for:)` (for example "Curved arrow …"), a frame and its selected state, as ticket 84 requires. VoiceOver and the live harness can read it.

**Evidence (2026-09-25, live, `99ed2d6`, external display):** after two arrows were drawn, the "Capture canvas" AXImage has two children, and both have no readable attributes: no role, no description, no frame. `axfind "Curved arrow"` finds nothing, so the `editor-curved-arrow` row fails its mark count while its pixel checks pass. The likely cause is `EditorWindow.swift:188-193`: `accessibilityChildren()` builds new `NSAccessibilityElement`s on every call and keeps no reference to them, so each is deallocated before a client reads its attributes.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [x] The mark elements live as long as their marks: rebuilt when the edits change, and kept otherwise.
- [x] Each element reports its role, label, frame (screen coordinates) and selected state.
- [ ] Live: `editor-curved-arrow` passes on both displays.

## Comments

### 2026-09-25: coordinator, created

Found while calibrating ticket 94's rows. Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Cause:** `EditorCanvasView.accessibilityChildren()` built fresh `NSAccessibilityElement`s per call and kept none, so AppKit's clients found them deallocated.
- **Change:** new adapter `Frisket/Adapters/MarkAccessibilityElements.swift` owns the elements. It updates them only when a mark's label, frame or selection changes (in place for the same count, rebuilt otherwise). Each is `.image`, labelled by `MarkEditor.accessibilityLabel(for:)` (through `MarkEditor.accessibleMarks`), parented to the canvas, selected state set, with its frame set in parent space so AppKit reports screen coordinates. The canvas now also answers `accessibilitySelectedChildren()`. The adapter file is listed in the app target's membership exceptions (ticket 77).
- **Core:** the pure mapping (marks to labels and boxes in canvas points) already lives in `MarkEditor.accessibleMarks`, tested by `everyMarkHasAVoiceOverLabelRelativeToTheCrop`; nothing new was needed there.
- **Tests:** `MarkAccessibilityElementsTests` (adapter package): `d31EachMarkIsAnImageWithItsLabelScreenFrameParentAndSelectedState` went red on the frame (AppKit reads parent-space frames from the bottom-left even in a flipped view: got y 220, expected 350), then green after the adapter flips the frame. `d31ElementsAreKeptUntilTheMarksChange` checks the elements outlive the call and persist until marks change. No `knownDefect("D31")` wrapper existed.
- **Harness:** `editor-curved-arrow` flipped from `D31 xfail` to `D31 pass`.
- **Open:** the live row on both displays, for the coordinator. Decision: this ticket's decision in `decisions.md`.
