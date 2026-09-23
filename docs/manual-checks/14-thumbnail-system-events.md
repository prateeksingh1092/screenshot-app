# Ticket 14: quit, display unplug, lock, and auto-dismiss (Prateek)

**Pending; not executed by the implementer.** Run only with the installed signed
debug build (see [app-build.md](../app-build.md)) and only against Frisket's
synthetic test pattern (decisions 50 and 51). Never capture any other window,
the full screen, or real content, and keep no captures in the repository.

1. Record the date, `sw_vers`, `uname -m`, the tested commit, the code signature,
   display layout (IDs, frames, scales), and Screen Recording state. On this Mac,
   record **arm64 not executed**. Use [ticket 08](08-first-launch.md) for
   permission and the synthetic helper.

2. **Quit finalizes.** Take two synthetic captures. Quit Frisket from the menu.
   Relaunch. Both captures must be in History (`images/` has two PNGs). No
   thumbnail remains.

3. **Screen lock.** Take one capture. Lock the Mac immediately. After more than
   10 seconds, unlock. The card must still be pending. After the remaining
   delay from its original arrival (or immediately if that delay already
   passed), it finalizes. Overflow while locked must still send the oldest
   card to History.

4. **Display unplug**, if the external display is connected: capture on the
   external display, then unplug it. The card must move to the remaining
   display and stay pending. It must not finalize or disappear.

5. **Auto-dismiss Settings.** Open Settings. Confirm Thumbnails offers a delay
   in seconds and **Never auto-dismiss**. Set 0 seconds, Apply, take a capture:
   it must finalize immediately. Set Never, Apply, take a capture and wait well
   past 10 seconds: it stays. A fifth card must still overflow the oldest into
   History. Relaunch and confirm Never persisted. Restore 10 seconds.

6. Record PASS, FAIL or not executed for each step. Runtime lock and unplug
   claims stay pending until this run.
