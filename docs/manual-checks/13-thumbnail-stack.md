# 13: Thumbnail stack

Set up as in [README.md](README.md). The harness checks that two Thumbnails
don't overlap (`stack`). Each capture below is ⌘⇧4, then Return, over
`.build/FrisketTestPattern --show`.

1. **Placement.** Take three captures. The Thumbnails appear at the
   bottom-right of the capture's display, newest nearest the corner. Frisket
   does not become the active app; the front app's menu bar stays.
2. **Overflow and timeout.** With four Thumbnails, take a fifth: the oldest is
   kept in History and leaves. Take one capture and leave it: after 10 seconds
   it is kept in History and leaves. Later Thumbnails wait for their own time.
3. **Swipe.** Swipe two fingers sideways across a Thumbnail on a trackpad: it
   is kept in History and leaves. A vertical swipe does nothing.
4. **Exits.** Focus a Thumbnail (⌘⇧2) and press Esc; on the next, Tab to Close
   and press Space; on the next, press ⌘W. Each is kept in History.
5. **Delete.** Focus a Thumbnail and press ⌫. It leaves without a History row.
   The file count in `History.noindex/images/` doesn't change.
6. **Kept Thumbnail.** Copy a Thumbnail (C). It stays, now named "Capture kept
   in History", with no Edit or Delete, until its timeout.
7. **Full-screen Space.** Run `.build/FrisketTestPattern --show-full-screen`
   and capture. The Thumbnail shows over the full-screen pattern, and Frisket
   doesn't leave the Space. Switch Spaces with Control-arrow: the Thumbnail
   stays visible, also in Mission Control.
8. **Two displays.** Capture on each display. Each Thumbnail appears on the
   display it came from.
