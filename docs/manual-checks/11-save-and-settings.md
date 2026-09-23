# Save and Settings — pending operator checks

Run with Prateek after the coordinator reviews and builds the signed app. The
implementer has not launched, captured, copied, installed, or signed anything.
Use only `Tools/FrisketTestPattern.swift` and the synthetic-pattern setup in
[08-first-launch.md](08-first-launch.md). Never capture a full screen or personal
content. Do not store captures in the repository.

Record date, tested commit, macOS version/build, architecture, signature and
bundle identifier, display layout/scales, Screen Recording state, Full Keyboard
Access and VoiceOver state. Record arm64 as not executed on this Intel Mac.

1. Open Settings from the Frisket menu and with Command-comma while a thumbnail
   has focus. Confirm a single SwiftUI Settings window opens and reopens after
   closing with Command-W. Verify the first section is Export folder. Select the
   path and use Edit > Copy / Command-C, then paste into a disposable text field.
   Confirm Command-Q follows the existing pending-capture finalization flow.
   Command-comma while another app is active remains a manual focus limitation.
2. Verify the default is `~/Pictures/Frisket`. On a synthetic area capture, focus
   its thumbnail and press S. Check a PNG is created even if the folder did not
   exist. Decode it using the marker/dimension procedure from the first-launch
   checklist. Compare dimensions and marker pixels with the synthetic pattern.
   Verify one matching History item exists and its image remains in History.
3. Use Tab/Shift-Tab, Space/Return and Command-O to operate Choose…; cancel with
   Escape. Select a dedicated temporary export directory. Reopen Settings and
   relaunch the signed app to confirm the selection persists. Save again and
   confirm the destination changed.
4. Attempt to select the debug and production History roots, a descendant, and
   a symlink or `/System/Volumes/Data/…` alias to either. Each must be refused
   without changing the preference.
   Select a directory without write permission; verify refusal. If a selected
   directory later becomes unwritable, Save must fail visibly and retain Retry
   Save and Dismiss, with Delete hidden when History committed.
   Confirm the card shows one status message after failure, without the generic
   “Dismiss to keep in History” prompt when History has already committed.
   Restore access or choose another folder, then Retry Save: one History entry,
   one successful export, same rendered pixels.
5. Select a test directory in iCloud Drive only with Prateek's agreement to
   potential sync. Confirm the warning appears before accepting and remains in
   Settings. Cancel first and verify the prior setting remains. No real or
   sensitive content may be used.
6. Force a filename collision using a disposable synthetic export; verify the
   existing file is unchanged and another PNG receives a numeric suffix.
   Once History deletion/retention tickets are integrated, delete/expire the
   matching History item and confirm the saved PNG survives unchanged.
7. With a test History failure, confirm Save still delivers and an acknowledgment
   notice explains that History failed. With an export failure, confirm History
   remains intact and retry/dismiss are usable. Do not alter production History.
8. With VoiceOver, navigate and activate every Settings and thumbnail control.
   Verify folder, warning/error, Save/Retry Save, and Dismiss are announced;
   confirm the Settings close control and directory panel are keyboard-operable.
   Repeat the workflow with Full Keyboard Access and no pointer.

Pending: real keyboard routing, panel focus/layout, VoiceOver announcements,
actual iCloud resource detection, signed preference persistence, and runtime
History retention/deletion integration. Automated fixtures do not establish
these platform behaviors.
