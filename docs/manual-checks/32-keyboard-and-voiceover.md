# 32: Thumbnails by keyboard and VoiceOver

Set up as in [README.md](README.md). The harness checks that ⌘⇧2 sends keys to
the Thumbnail and that its picture is named (`focus-latest`,
`thumbnail-picture`). This file checks the rest by keyboard and ear.

1. Take two captures (⌘⇧4, Return). Press ⌘⇧2. The newest Thumbnail takes
   focus with a visible outline on Copy. It doesn't time out while focused.
   Up arrow moves to the older one; down arrow comes back.
2. With Full Keyboard Access on and no pointer: C copies, S saves, E opens the
   editor, t copies the text, ⌫ deletes, Esc keeps it in History. Tab reaches
   every button on the Thumbnail.
3. With VoiceOver on, each new Thumbnail is announced. Its actions (Copy
   capture, Save capture, Edit capture, Copy recognized text, Delete, Close)
   work from the actions menu without hovering. A kept Thumbnail is read as
   "Capture kept in History" and has no Edit or Delete.
4. Copy Text on the pattern: the text isn't shown in Notification Center.
5. After the last Thumbnail leaves, the next capture times out as usual.
