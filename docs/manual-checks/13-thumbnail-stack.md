# Ticket 13: thumbnail stack and Delete capture (Prateek)

**Pending; not executed by the implementer.** Run only with the installed signed
debug build (see [app-build.md](../app-build.md)) and only against Frisket's
synthetic test pattern (decisions 50 and 51). Never capture any other window,
the full screen, or real content, and keep no captures in the repository.
Hide personal menu-bar items, notifications and Dock content before each capture.

1. Record the date, `sw_vers`, `uname -m`, the tested commit, the code signature and
   designated requirement, the display layout (IDs, frames, scales), and the Screen
   Recording state. On this Mac, record **arm64 not executed**. Resolve first-launch
   permission with [ticket 08's checklist](08-first-launch.md).

2. Build the synthetic helper and show the pattern on the display under test:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   .build/FrisketTestPattern --show
   ```

   Every capture below is **⌃⌥⌘4, then Return without moving the selection**. This
   takes the default centered 320×180-point rectangle, which lies entirely inside
   the pattern.

3. **Stack and placement.** Take three captures. The cards must appear at the
   bottom-right of the capture display, with the newest nearest the corner and
   older cards above it. Frisket must not become the active app, and the
   frontmost app's menu bar must stay unchanged. Each arrival is announced by
   VoiceOver when it is on.

4. **Overflow.** With four cards visible (the default maximum), take a fifth
   capture. The oldest card must show "Kept in History" and then disappear, leaving
   four cards. Record the elapsed time.

5. **Timeout.** Take one capture and don't touch it. After the default delay
   (10 seconds from its arrival), it must show "Kept in History" and disappear.
   Cards that arrived later must stay until their own delay has passed.

6. **Swipe.** On a trackpad, swipe two fingers horizontally across a card. It must
   show "Kept in History" and disappear. A vertical swipe must not dismiss it.

7. **Close and Esc.** Choose **Focus Latest Thumbnail**. Press Esc: the card must
   finalize ("Kept in History"). On the next card, press Tab until Close is
   focused, then Space. On the next, press ⌘W. Each must finalize. Also click Close
   with the pointer on another card.

8. **Delete Capture.** Focus a card and press Delete (⌫), and separately Tab to
   Delete Capture and press Space. The card must disappear without "Kept in
   History". Compare the list of files in
   `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex/images`
   before and after: it must be unchanged.

9. **History check.** After steps 4 to 7, the `images/` directory must contain one
   PNG per finalized card and none for deleted cards. Inspect only the file names
   and counts; don't open the images outside a synthetic-only session.

10. **Full-screen Spaces.** Close the helper, then run
    `.build/FrisketTestPattern --full-screen`. It shows the same pattern in its own
    full-screen Space. Wait for the transition, then capture. The card must appear
    over the full-screen pattern and Frisket must not leave the Space. Switch Spaces
    with Control-arrow keys: the card must stay visible on every Space and in
    Mission Control. Close the helper with Esc.

11. **Two displays**, if available: capture on the external 1× display, then on the
    built-in display. Each card must appear on the display where it was captured,
    each with its own stack.

12. **VoiceOver and keyboard.** With VoiceOver on, move through a focused card.
    You must hear the labels "Copy capture", "Delete pending capture" and "Close
    thumbnail and keep capture in History". After a Copy whose clipboard delivery
    failed but whose History commit succeeded, Delete Capture must be absent.
    This state isn't reproducible without a failing pasteboard, so record it as
    not executed unless it occurs.

13. Record PASS, FAIL or not executed for each step, with the timings from steps 4
    and 5. Close the helper with Esc. Runtime, Spaces and VoiceOver claims stay
    pending until this run; the ticket's status and checkboxes belong to the
    coordinator.
