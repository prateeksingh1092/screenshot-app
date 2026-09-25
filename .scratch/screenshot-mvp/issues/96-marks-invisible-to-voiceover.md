# 96: Marks are invisible to VoiceOver (D31)

**What to build:** Each mark on the editor canvas is an accessibility element with a role (image), its label from `MarkEditor.accessibilityLabel(for:)` (for example "Curved arrow …"), a frame and its selected state, as ticket 84 requires. VoiceOver and the live harness can read it.

**Evidence (2026-09-25, live, `99ed2d6`, external display):** after two arrows were drawn, the "Capture canvas" AXImage has two children, and both have no readable attributes: no role, no description, no frame. `axfind "Curved arrow"` finds nothing, so the `editor-curved-arrow` row fails its mark count while its pixel checks pass. The likely cause is `EditorWindow.swift:188-193`: `accessibilityChildren()` builds new `NSAccessibilityElement`s on every call and keeps no reference to them, so each is deallocated before a client reads its attributes.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [ ] The mark elements live as long as their marks: rebuilt when the edits change, and kept otherwise.
- [ ] Each element reports its role, label, frame (screen coordinates) and selected state.
- [ ] Live: `editor-curved-arrow` passes on both displays.

## Comments

### 2026-09-25: coordinator, created

Found while calibrating ticket 94's rows. Claude Opus 5.5, Claude Code, medium effort.
