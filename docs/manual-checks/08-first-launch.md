# Ticket 08: first launch (Prateek)

**Not executed by the implementer.** Obtain Prateek's approval at the time for
signed build/keychain access, installation, app launches, Screen Recording,
screen capture and clipboard use. Use synthetic content only. Do not reset
permissions or change the signing identity between runs.

1. Record date, `sw_vers`, `uname -m`, `git rev-parse HEAD`, Xcode version,
   display names/scales/arrangement, and Screen Recording state. Record
   **arm64 not executed** on this Intel Mac. Follow the exact signed-build,
   install and signature-inspection steps in [app-build.md](../app-build.md).
   Preserve the designated requirement and entitlement output for comparison.

2. Build the synthetic helper (compilation alone does not launch it):

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   ```

3. After launch approval, run:

   ```sh
   open /Users/16intelmac/Applications/Frisket.app
   .build/FrisketTestPattern --show
   ```

   The helper covers its screen with synthetic content. It puts a 320×180-point
   pattern at the exact center of that display: red/green above blue/white,
   plus a black marker. It never captures or accesses the pasteboard. Leave
   private content off the other display; move the pointer over the pattern.

4. Press **⌃⌥⌘4**. On a first run, approve Frisket's Screen Recording request
   in System Settings → Privacy & Security → Screen & System Audio Recording.
   If macOS asks for relaunch, cancel the selection, quit Frisket, and reopen
   **the fixed installed path**. Retry ⌃⌥⌘4. Denial must show a static notice,
   never an image; do not interpret the first blank attempt as success.

5. With permission granted, press ⌃⌥⌘4 and **Return without moving the
   selection**. Its default centered 320×180-point rectangle matches the
   helper exactly. Confirm no dimmer/border/cursor appears in the thumbnail.
   Separately drag an area, drag across the display edge (it must stay on the
   original display), and cancel with Esc without activating Frisket. Delete
   those extra captures explicitly. Check that macOS ⇧⌘3/4/5/6 still belong to
   macOS; do not take real-content screenshots to test them.

6. Use Frisket's **Focus Latest Thumbnail** menu item. **Copy** must immediately
   have keyboard focus and a visible outline, without first pressing Tab.
   Tab to Delete Capture and Shift-Tab back to Copy; confirm Space copies.
   On fresh captures, test C, and test choosing the menu item again after
   tabbing to Delete: focus and the outline must return to Copy. With multiple
   pending captures, the menu must target the latest thumbnail. With no pending
   captures, it must do nothing. With VoiceOver, confirm “Copy capture” is announced.
   Focus routing is in the SwiftUI window layer, outside the adapter test seam;
   these keyboard, visible-focus and VoiceOver checks require a manual run.
   The thumbnail must disappear only on successful Copy. In Preview choose
   File → New from Clipboard, then save as PNG at
   `$PWD/.build/pasted-pattern.png`. This is the operator's paste action, not
   a Frisket read of the general pasteboard. Run:

   ```sh
   .build/FrisketTestPattern --verify "$PWD/.build/pasted-pattern.png" 2
   ```

   Use `1` on a 1× display. Expected: 640×360 pixels at 2×, 320×180 at 1×,
   correct four quadrants and black marker, and a PASS message. Record FAIL
   verbatim without saving any personal pixels. The verifier normalizes to
   sRGB, samples away from edges and permits 3/255 color-management rounding.
   **Fix-pass colour rerun:** rebuild and relaunch the helper with its explicit
   sRGB window colour space, then repeat this pasted-PNG verification on the
   built-in wide-gamut 2× display. The earlier colour failure remains open
   until this manual rerun passes; retain the ±3 tolerance. If it still fails,
   investigate the capture's colour conversion, comparing the direct captured
   PNG with the pasted PNG before Preview export in an authorized diagnostic run.
   Repeat the capture on the external 1× display if available. A denied grant,
   pixel mismatch or inaccessible Copy is an open failure, not a passed check.

7. Quit Frisket. Rebuild with the **same signed command**, replace the bundle
   at the **same install path**, and verify signature/entitlements/requirement.
   Launch that path and repeat steps 5–6. There must be no new grant required.
   Repeat this complete rebuild/install/launch/capture cycle **a second time**.
   Do not use `tccutil reset`, ad-hoc signing or another app copy. Record both
   designated requirements and both grant outcomes; investigate any changed
   requirement or new prompt rather than calling persistence verified.

8. Bring the synthetic helper forward and press Esc to close it. Record
   pass/fail for launch, permission, display/scale, pixels, VO/keyboard Copy,
   own-app exclusion, cancellation, and rebuilds 1 and 2. Keep only synthetic
   exported images in ignored `.build/`; ticket status stays with the coordinator.
