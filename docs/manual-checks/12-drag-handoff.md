# Ticket 12: drag a capture into Finder and onto the Trash

**Not executed by the implementer.** Use the synthetic test pattern only.
Do not capture any other window, the full screen, or real content, and do not
keep captures in the repo. Record date, `sw_vers`, `uname -m`, `git rev-parse HEAD`,
and **arm64 not executed**.

1. Follow the signed-build and install steps in [app-build.md](../app-build.md).
   Launch only `/Users/16intelmac/Applications/Frisket.app`. Build and show the
   pattern the same way as [first launch](08-first-launch.md):

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   .build/FrisketTestPattern --show
   ```

2. Press **⌃⌥⌘4**, leave the selection on the centered pattern, and press Return.
   Drag the thumbnail image into a Finder folder. The drop must be a copy.
   Save nothing from the screen itself. Verify the dropped file:

   ```sh
   .build/FrisketTestPattern --verify "/path/to/Capture.png" 2
   ```

   Use `1` on a 1× display. Expected: PASS, with the same dimensions and marker
   as a Copy of the pattern.

3. In Finder, confirm the History image is still present at
   `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex/images/`
   and is a different file from the Finder copy. Dragging must not move or
   delete that file.

4. Capture the pattern again. Drag the thumbnail onto the Trash. A refused drop
   leaves the capture pending: its Thumbnail stays open and History gains no row.
   A separate copy in the Trash is also acceptable; it finalizes the capture once
   and never removes its History image. Drags stage nothing: `staging/drag/` must
   not exist (ticket 54, DA-3); the launch sweep removes one an earlier build left.

5. Press Esc during a drag, or drop it on a window that accepts no files. The
   Thumbnail stays open and pending, History is unchanged, and nothing is written
   under `History.noindex`. Do not capture real content to retry.
