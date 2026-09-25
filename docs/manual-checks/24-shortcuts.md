# 24: Shortcuts and collisions with macOS

Set up as in [README.md](README.md). Also record the keyboard layout. The
package tests check validation; the harness uses ⌘⇧1 and ⌘⇧2. This file
checks the keys against macOS and other apps. Frisket never changes macOS's
own screenshot shortcuts (DA-2).

1. Quit any other screenshot app that uses ⌘⇧3/4/5, such as CleanShot. In
   System Settings › Keyboard › Keyboard Shortcuts › Screenshots, turn off the
   macOS shortcuts that use them. Start Frisket with fresh shortcut settings.
   Settings shows ⌘⇧1 History, ⌘⇧2 Focus Latest Thumbnail, ⌘⇧3 Capture Full
   Screen, ⌘⇧4 Capture Area and ⌘⇧5 Capture Window. ⌘⇧6 does nothing in
   Frisket (decision 60).
2. Press each once, with another app frontmost and on another Space. Each does
   exactly one Frisket action, and no macOS screenshot UI appears. Cancel the
   Selections with Esc.
3. Turn one macOS screenshot shortcut back on. Settings says which one macOS
   still uses and links to System Settings. The link opens Keyboard Shortcuts.
   Turn it off again: Settings notices when you come back.
4. In Settings, change each shortcut. The new one works, the old one doesn't,
   and the change survives a relaunch. Restore Default brings back the number
   row. A shortcut macOS still uses, or one another Frisket action has, is
   refused with a warning, and the old one stays.
5. Take a shortcut another app has registered. Frisket warns and keeps the old
   one working.
6. Do steps 3 and 4 by keyboard and with VoiceOver: Change, the warnings and
   Restore Default are reachable and read.
