# 11: Export folder and Settings

Set up as in [README.md](README.md). The harness checks Save's notice, the
dated name and where Settings opens (`save-confirms`, `history-save`,
`settings-focus`). The package tests check the name collisions and the folder
rules. This file checks the folder picker and real folders.

1. Open Settings (⌘,). The first section is Export folder, set to
   `~/Pictures/Frisket`. Choose… opens a folder picker; ⌘O does too. Cancel
   once: nothing changes. Choose a test folder. Quit and relaunch: the choice
   stays. Save a capture (S on its Thumbnail): the file lands there.
2. Try to choose Frisket's History folder, a folder inside it, and a symlink to
   it. Each is refused and the setting doesn't change. Try a folder you can't
   write to: refused.
3. Make the chosen folder unwritable, then Save. Save fails on the Thumbnail's
   status line with Retry Save. Make it writable again and Retry Save: one
   file, one History row.
4. Only with Prateek's agreement: choose a folder in iCloud Drive. A
   confirmation warns that copies leave the Mac, before the folder is used.
   Cancel keeps the old folder.
5. With VoiceOver, then with Full Keyboard Access and no pointer, reach and use
   every Settings control. The folder, a warning and each button are announced.
