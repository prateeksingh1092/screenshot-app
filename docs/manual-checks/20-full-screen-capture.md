# Ticket 20: full-screen capture (Prateek)

**Pending; not executed by the implementer.** Decision 50 explicitly excludes
full-screen capture from its standing approval. Obtain Prateek's explicit
approval for these full-display synthetic captures, plus any signing/keychain,
installation, launches and clipboard actions required for this run. Never use
personal pixels. Follow the stable signed identity and installed path in
[app-build.md](../app-build.md); never launch the unsigned verification build.

1. Record date, OS/build, architecture, tested commit, signature/designated
   requirement, Screen Recording state, and each display's ID, global frame,
   scale and expected native pixel dimensions. On this Mac record **arm64 not
   executed**. Resolve first-launch permission/relaunch requirements using
   [ticket 08's checklist](08-first-launch.md); its two-rebuild grant checks
   remain separate pending work.

2. Compile the synthetic helper from the worktree root:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   ```

   After approval, launch the installed Frisket and run
   `.build/FrisketTestPattern --show-all`. This covers every attached display
   with an opaque synthetic window. Hide personal menu-bar items, notifications
   and Dock content; visually confirm the entire target contains only synthetic
   content before each capture. If any personal content is visible, stop.

3. Run the following cases separately. Record expected and actual dimensions
   rather than assuming the built-in display's current resolution:

   | Case | Arrangement | Expected result |
   | --- | --- | --- |
   | Built-in Retina | 2×, ordinary arrangement | Full display at native 2× dimensions |
   | External non-Retina | 1× | Full external display at native 1× dimensions |
   | Negative coordinates | External left of and/or below the primary display | Correct external display, no shifted crop, padding or clipping |

   Relaunch the synthetic helper after changing display arrangement so its
   windows cover the new frames. An unavailable display is **not executed**.

4. On the target display, choose **Frisket → Capture Full Screen**. The pointer
   must be on that display when the menu action fires (use that display's menu
   bar, or keyboard navigation after placing the pointer there). No selection
   overlay should appear. Confirm one thumbnail arrives on the target display.
   The new command is menu-only; no full-screen hot key is registered. Ticket 24
   owns default shortcuts and remapping; ⌃⌥⌘4 remains area capture.

5. Focus Latest Thumbnail, then Copy. In Preview use New from Clipboard and
   save only the synthetic image under ignored `.build/`. Verify the complete
   display dimensions and centered pattern marker with the helper (replace
   WIDTH, HEIGHT and SCALE with the independently recorded expected values):

   ```sh
   .build/FrisketTestPattern --verify-full "$PWD/.build/full-screen.png" WIDTH HEIGHT SCALE
   ```

   Retain the existing ±3/255 sRGB tolerance. Inspect all four image edges:
   no missing strips, offsets, stretching, cursor, or selection overlay. A
   dimension/colour failure is an open failure, not a passed checklist case.

6. Repeat on each display while a previous synthetic Frisket thumbnail is
   visible over the pattern. Copy the new capture and verify that the previous
   thumbnail is absent and the synthetic background underneath is intact.
   Confirm Copy/Delete continue to work on the full-screen Pending capture.

7. In an authorized permission-state run, denied/revoked Screen Recording or
   a disconnected target must produce a static failure notice and no thumbnail
   or fallback capture. Re-cover remaining displays before retrying; never
   capture while rearranging or uncovering personal content.

8. Record per-case PASS/FAIL/not-executed, actual dimensions, marker-verifier
   output, target display/thumbnail placement and own-app exclusion. Close the
   helper with Escape. Runtime, permission and exclusion claims stay pending
   until this manual run; ticket status/checkboxes belong to the coordinator.
