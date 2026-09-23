# Ticket 19: selection precision (Prateek)

Pending manual execution. The implementer runs only automated tests and an
unsigned build. Use the signed installation and synthetic helper from
[08-first-launch.md](08-first-launch.md); keep the origin display covered by
the helper and other displays free of private content. The magnifier samples
an in-memory snapshot of the origin display before the overlay appears.
It is a frozen preview; the final capture is taken after the overlay closes.

Record date, commit, `sw_vers`, architecture, Xcode version, code signature,
Screen Recording state, display layout/scales, and each result below. On this
Intel machine record **arm64 not executed**. Repeat on the built-in 2× display
and external 1× display, including an external display left/below the main
display (negative coordinates).

1. Bring the synthetic helper forward, put the pointer over its pattern, and
   press **⌃⌥⌘4**. Move over the quadrant boundaries and black marker. The
   magnifier must show sharp individual device-pixel cells without smoothing,
   with the pointer's pixel outlined. Verify top/bottom and left/right colours
   against the pattern, especially near the black marker. Check near all four
   display edges: the magnifier stays visible and samples do not wrap. Its
   cells represent device pixels at both scales, not points enlarged at 2×.
2. Drag a nonzero rectangle. Hold **Shift**, then move mainly horizontally:
   the height must stay fixed. Release Shift and check free resizing resumes.
   Repeat moving mainly vertically: width stays fixed. While still holding
   Shift, change direction; the chosen axis stays locked until release.
3. Start inside the pattern and hold **Option** while dragging: the starting
   point is the centre and opposite edges grow symmetrically. Approach each
   display edge: growth stops symmetrically within that display. Release
   Option and verify normal corner-anchored selection resumes. Try Option
   together with Shift.
4. During a drag hold **Space**, then move: the whole rectangle translates
   without changing dimensions. Approach each display edge; it stops there.
   Release Space without releasing the mouse; resizing resumes without a
   jump. Repeat with Option held and with Shift held. Press/release Space
   repeatedly and confirm key repeat does not reset the movement anchor.
5. Before dragging, use each **arrow** to nudge the default rectangle by one
   device pixel (1 point at 1×, 0.5 point at 2×). Confirm arrows also translate
   while Shift is held. During a drag nudge, then continue dragging: the
   nudge must persist. At each display edge, repeated nudges stop without
   shrinking the rectangle. Return accepts; mouse release accepts a nonzero
   dragged area. A zero-area click must not capture.
6. Keep the helper active and press **⌃⌥⌘4**, then **Esc** before dragging.
   Only the overlay closes: the helper remains open and its app stays active.
   Repeat during dragging and while each modifier is held. Frisket must
   never become the active app. There is no thumbnail from cancellation.
   Re-enter selection after each cancellation to check input is restored.
7. Capture the default pattern with Return, and separately accept a dragged
   synthetic area with the magnifier visible. Inspect the delivered images:
   no magnifier, crosshair, dimmer, selection border, or Frisket panels. Use
   ticket 08's pasted-pattern verifier for the unchanged default selection;
   it must remain 320×180 device pixels at 1× or 640×360 at 2×. Delete extras.
8. Drag across the origin display's boundary: geometry and preview remain
   confined to that display. Unplug a display mid-selection and confirm a
   clean cancellation with no new thumbnail. Repeat over the synthetic
   helper in a full-screen Space and across a Space switch. Never use a
   private-content window for these checks.

Record failures verbatim. Denied/revoked permission or an unavailable preview
must not be recorded as a successful magnifier check. No live runtime,
permission, colour fidelity, activation, or Apple-silicon result is implied
by the automated geometry tests.
