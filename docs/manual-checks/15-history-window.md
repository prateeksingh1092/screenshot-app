# Ticket 15: History window (Prateek)

**Pending; not executed by the implementer.** Run only with the installed signed
debug build and only against Frisket's synthetic test pattern (decisions 50 and
51). Never capture any other window, the full screen, or real content.

1. Record date, `sw_vers`, `uname -m`, commit, signature, display layout, and
   Screen Recording state. On this Mac, record **arm64 not executed**.

2. Take two synthetic captures and dismiss both (Esc or timeout). Open
   **History** from the Frisket menu and with Control-Command-Y. Newest first.
   Each row shows a preview, pixel size, and time. No file names or paths.

3. **Copy, Save, drag, Delete.** Copy the newest row (button or C). Save (S)
   writes a PNG to the export folder; History still lists the item. Drag the
   preview to Desktop; History still lists it. Delete (Delete) removes the row
   immediately; it must not appear in Trash. Confirm the owned History file is
   gone.

4. **No re-edit.** There is no Edit action. Selecting a row must not open the
   editor.

5. **Exclusion.** With the History window open, capture the synthetic pattern
   (⌃⌥⌘4, Return). The History window must not appear in the capture.

6. **Keyboard and VoiceOver.** Tab and arrows move. C/S/Delete act on the
   selected row. VoiceOver must speak the capture size and time, not a path.

7. Record PASS, FAIL, or not executed. Runtime claims stay pending until this run.
