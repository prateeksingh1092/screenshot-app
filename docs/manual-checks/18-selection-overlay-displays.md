# Ticket 18: selection across displays (Prateek)

**Pending manual execution.** Automated tests use fixture display layouts and
pixel stand-ins; the implementer has not launched an app, captured a screen,
used the clipboard, signed, or installed anything. Follow the authorized signed
build/install route in [app-build.md](../app-build.md) and the pixel-verification
steps in [08-first-launch.md](08-first-launch.md). Capture only the synthetic
helper. Keep private content off every display: frozen previews are prepared
for all connected displays before any overlay is shown.

Record date, commit, `sw_vers`, `uname -m`, Xcode version, signature, Screen
Recording state, display IDs/names, global frames, backing scales, arrangement,
and “Displays have separate Spaces” state. Record **arm64 not executed** on
this Intel Mac. Leave each item pending until its observed result is recorded.

1. Compile the helper without launching it:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   ```

2. With the authorized signed Frisket installed and permission granted, run
   `.build/FrisketTestPattern --show-all` to cover the built-in Retina (2×)
   and external non-Retina (1×) displays. Put the pointer on the built-in
   display and press **⌃⌥⌘4**. Both displays must have an overlay; moving the
   pointer between them must show a crosshair. Before dragging, Return must
   accept the invocation display's centered 320×180-point rectangle. Use
   ticket 08's Copy/Preview workflow and `--verify <pasted-PNG> 2`: expect
   640×360 pixels, correct quadrants/marker, and no dimmer, crosshair, border,
   magnifier, or other Frisket panel. Repeat from the external display using
   `--verify <pasted-PNG> 1`: expect 320×180 pixels. Delete extra captures.

3. Invoke on the built-in display, then move to the external display and
   start dragging there. Its magnifier and rectangle must use 1× pixels.
   Cross back onto the built-in display while holding the mouse: the rectangle
   must stop at the external display edge. Return/release accepts only that
   display's selected area. Repeat starting on the built-in display after
   invoking on the external display. Exercise Shift, Option, Space, arrows,
   and Shift-arrows as in [19-selection-precision.md](19-selection-precision.md).
   A zero-area click must not capture; Esc must still cancel.

4. Place the external display left of and then below the built-in display in
   System Settings. Record the resulting negative x/y coordinates. Reopen
   `--show-all` after each layout change so the synthetic helper covers the
   new frames. Repeat steps 2–3, including dragging through the shared edge
   and through a gap between display frames. Confirm correct origin display,
   pixel dimensions, and no translated/flipped crop.

5. Start dragging on the external display and unplug it before releasing.
   All overlays must disappear, input must return to the previous app, and
   no new thumbnail, Pending capture, or History item may appear. Reconnect,
   restart the helper, and repeat with a drag originating on the built-in
   display while unplugging the external display. Also try unplugging before
   dragging and while previews prepare. A fresh selection must succeed after
   reconnection; no hung capture or exhausted Pending budget. Repositioning,
   changing resolution/scale, or adding a display during selection should
   likewise cancel; switching Spaces alone should not.

6. Keep `--show-all` running to cover the other display. In another terminal,
   run `.build/FrisketTestPattern --show-full-screen`.
   This mode uses a native full-screen window/Space, rather than merely a
   borderless display-sized window. With the helper focused on the desired
   display, wait for the full-screen transition to finish, then invoke capture.
   Confirm the overlay is above the full-screen app and on the other display.
   Repeat on each display (leave full screen, move the helper window, and use
   its green full-screen control to enter full screen there). Capture only
   the synthetic pattern and verify its default crop with `--verify` at the
   appropriate scale. Record any notch/menu-bar-related coordinate mismatch.

7. Invoke selection over the full-screen helper, then switch to another Space
   and back with the configured system Space-switch gesture/shortcut. Confirm
   panels remain above content, the same rectangle/origin display is retained,
   crosshair input works, and Esc cancels. Repeat after beginning a drag and
   while holding modifiers. The previous Space's frozen preview is discarded;
   “Magnifier unavailable” is expected until a new capture invocation. A drag
   interrupted by a Space switch stops resizing; Return may accept its retained
   rectangle, or a fresh drag may start on the same origin display. Do not
   accept a capture on a Space that is not covered by the synthetic helper.

8. Keep the helper active and press Esc before dragging, during dragging on
   either display, and after switching Spaces. Only the overlays must close:
   Frisket must not activate and the helper must remain open. Re-enter selection
   to verify keyboard routing and cursor restoration. Confirm existing macOS
   screenshot shortcuts still belong to macOS without capturing private content.

Record pass/fail per item and display, including activation, cursor restoration,
full-screen/Space behavior, cancellation, and PNG verification. Denied permission
or unavailable previews do not count as a passed pixel/magnifier check. These
runtime checks remain open regardless of automated test or unsigned-build results.
