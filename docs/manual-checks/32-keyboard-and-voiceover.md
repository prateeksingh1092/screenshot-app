# Ticket 32: keyboard and VoiceOver thumbnails (Prateek)

**Pending; not executed by the implementer.** Run only with the installed signed
debug build (see [app-build.md](../app-build.md)) and only against Frisket's
synthetic test pattern (decisions 50 and 51). Never capture any other window,
the full screen, or real content. On this Mac, record **arm64 not executed**.

1. Record the date, `sw_vers`, `uname -m`, the tested commit, the code signature,
   display layout, and Screen Recording state. Resolve permission with
   [ticket 08](08-first-launch.md) if needed. Show the pattern with
   `.build/FrisketTestPattern --show`.

2. Take two area captures (⌃⌥⌘4, Return). Press **Focus Latest Thumbnail**
   (⌃⌥⌘T). The newest card must become key with a visible Copy outline.
   Auto-dismiss must not fire while the stack is key. Arrow-up moves to the
   older card; arrow-down returns to the newest.

3. With Full Keyboard Access on, complete every action from the keyboard only:
   C copies, S saves, E opens the editor (Escape leaves it), Delete deletes,
   Escape dismisses to History. Tab still reaches the on-card buttons.

4. With VoiceOver on, each new card is announced. The card itself exposes
   Copy, Save, Edit, Delete, and Close as custom actions that work without
   hovering. Act on both cards from the VoiceOver rotor or actions menu.

5. After the last card leaves, auto-dismiss must resume for the next capture.
