# 23: Screen Recording states

Set up as in [README.md](README.md). How the states work is in
[permission-recovery.md](../permission-recovery.md). None of this is in the
harness: it needs real grants, denials and a fresh account.

**Keep Prateek's grant.** Run steps 1 and 2 on his account. Run steps 3–6 in a
separate macOS test account that has never run Frisket, with his approval, the
same signed build and the same install path in that account. Without such an
account, record 3–6 as blocked. Never reset TCC to make a step pass.

1. **Granted.** Launch the installed app. The menu-bar icon shows no warning.
   ⌘⇧4 and Return over the pattern gives a Thumbnail.
2. **After a rebuild.** This is step 4 of [08](08-first-launch.md): the grant
   survives two signed rebuilds.
3. **Not asked** (test account). The icon shows a warning. ⌘⇧4, ⌘⇧3 and ⌘⇧5
   each show the recovery panel, never a Selection or pixels. The panel offers
   Request Screen Recording, Open System Settings and Quit & Reopen.
4. **Denied** (test account). Request, then deny. No overlay shows above or
   below the macOS alert. Each capture shortcut shows denied recovery, also
   after a relaunch, with no Request button (decision 100); the message says to
   turn Frisket on in System Settings. Open System Settings reaches Screen &
   System Audio Recording.
5. **Needs relaunch** (test account). Turn Frisket on in that pane while it
   runs; choose Later if offered. Capture shows needs-relaunch recovery. Quit &
   Reopen quits the old process and opens the installed app once. Capture then
   works. If macOS applies the grant at once, record "not reproducible".
6. **Revoked while running** (test account). Turn Frisket off in the pane while
   it runs. Within two seconds, or when the menu opens, the icon warns, and
   capture shows revoked recovery. Revoke during a Selection too: no image is
   accepted. If macOS quits Frisket instead, record that.
7. **The panel.** Tab, Shift-Tab, Return, Space and Esc work on the recovery
   panel, and VoiceOver reads it. While it is open, capture shortcuts start no
   Selection. Quit & Reopen first keeps every pending capture in History; an
   ordinary Quit after a cancelled reopen does not reopen.
