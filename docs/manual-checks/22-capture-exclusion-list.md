# Ticket 22: Capture exclusion list

Pending operator checklist. Not executed by the implementer. Use a dedicated
synthetic-only desktop and a test-pattern application with a stable bundle ID.
No personal content, password managers, clipboard use, or captures in the repo.
Obtain the required authorization before launches or capture.

Record date, tested commit, OS/build, architecture, signature/bundle ID, display
layout/scales, permission state, Full Keyboard Access and VoiceOver state.
Record arm64 as not executed until an Apple-silicon run exists.

1. With fresh test preferences, open Settings and verify the Capture exclusion
   list is empty. Add the synthetic test-pattern application through Add App.
   Cancel the picker once; verify no change. Add the same app twice; verify one
   entry. Verify name and bundle identifier are readable, with accessible Add
   and Remove controls using the keyboard and VoiceOver.
2. Put that app's synthetic window on screen over a contrasting synthetic
   background. Capture an area intersecting it, then the synthetic-only full
   display. Verify the app's marker pixels are absent from the magnifier preview
   and final images, and Frisket's own windows are absent as well. Leave another
   synthetic app unlisted and verify its marker remains visible.
3. Relaunch the signed build and repeat to verify persistence. Close/reopen the
   listed synthetic app and test again (filtering must not depend on an old PID).
4. Remove the app in Settings, capture again, and verify its marker returns
   while Frisket stays excluded. Remove all entries and confirm empty state.
5. Inspect local diagnostics: no application names or bundle identifiers.
6. When window and scrolling capture are integrated, repeat using the same
   listed synthetic app. An excluded window must never produce its pixels;
   every scrolling frame and preview must obey the shared content filter.

Window and scrolling capture commands do not exist in this ticket's base.
Those runtime cases remain pending integration, as do all checks above.
