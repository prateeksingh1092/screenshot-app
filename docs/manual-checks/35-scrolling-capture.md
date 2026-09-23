# Ticket 35: scrolling capture (Prateek)

**Pending; not executed by the implementer.** Nothing here captures the real
screen. Use only the synthetic scroll page below. Record date, OS build,
architecture, tested commit, and Screen Recording state. On this Mac record
**arm64 not executed**. Permission and signed-rebuild checks stay with
[ticket 08](08-first-launch.md).

1. Compile the helper from the worktree root:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   ```

   Launch the installed Frisket, then run `.build/FrisketTestPattern --show-scroll`.
   A titled window shows six copies of the synthetic quadrants on a dark page.
   Scroll that page yourself. Escape closes it. If any personal content is
   visible in the region you will select, stop.

2. Choose **Frisket → Capture Scrolling Page**. Draw the selection inside the
   synthetic window only, then press Return. Frisket must not ask for
   Accessibility permission. No event tap or global monitor is part of this
   check. Scroll the page by hand. The live preview should grow. **Done** keeps
   one tall thumbnail. **Cancel** shows no thumbnail.

3. Focus the thumbnail and Copy. In Preview, use New from Clipboard and save
   only that synthetic image under ignored `.build/`. Confirm the image is
   taller than the selected region, the quadrant colours repeat down the page,
   and Frisket's own preview panel is absent. Do not keep the image in the repo.

4. Dismiss another synthetic scrolling capture and confirm it can be opened
   from History, then delete it there so the development History does not keep
   the trial image.

5. Scroll until Frisket stops on its own, or note that the page ended first.
   The stop must say that the image includes only the section that fit. The
   pixel cap is 294,912,000 (the 5,120 × 57,600 trial capture). The memory
   budget is 2,000,000,000 bytes. A capture also stops when the pending
   original would exceed the 128 MB reservation inside the 256 MB pending-byte
   budget.

6. **Live peak memory, still pending:** during one synthetic scroll, record
   Frisket's peak in Activity Monitor. The automated stand-in measurement is
   in the ticket 35 implementer report; it is not this live figure.

7. Record PASS/FAIL/not-executed for selection, manual scroll, live preview,
   Done, Cancel, Copy, History, the stop message, and the live peak. Runtime
   claims stay pending until this run.
