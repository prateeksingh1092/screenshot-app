# 16: History limits in Settings

Set up as in [README.md](README.md). The package tests check eviction order,
clock jumps and crashes during eviction. This file checks the Settings side.

1. Open Settings › History. The defaults are 30 days and 1,000 MB. Change both
   by keyboard and press Apply History Limits. Reopen Settings and relaunch:
   the limits stay. VoiceOver reads each field and the button.
2. Set a very small size limit and apply it. The oldest captures leave History.
   A notice says so once; the dated line in Settings stays after a relaunch.
   An export saved earlier is untouched.
3. Put the size limit below one capture's size, then Save a new capture. Save
   still writes the file, and a notice says History didn't keep it.
4. Restore the defaults.
