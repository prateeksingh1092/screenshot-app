# Ticket 16 synthetic manual checks

Not executed by the implementer. Use only generated PNG fixtures or Frisket's
synthetic test-pattern window in an isolated test History root. Never use real
screen content or a personal export folder. Record date, OS build, tested commit,
architecture, signature, and fixture locations when the operator runs this list.

1. Open Settings with Command-comma. Verify defaults of 30 days and 1,000 MB,
   keyboard editing of both limits, Apply History Limits, and VoiceOver labels.
   Apply limits, reopen Settings and relaunch; confirm they persist.
2. Seed synthetic captures at known dates. Lower the age limit and verify oldest
   captures disappear first, while exported PNG copies retain identical bytes.
3. Fill synthetic History past a small quota. Confirm the newest finalized
   capture survives, equal dates use creation-key order, and usage includes
   image and thumbnail files and the SQLite files. Verify the quota notice is
   presented once and the dated Settings line persists after dismissal/relaunch.
4. Deliver an oversized synthetic fixture. Verify History refuses it with an
   explicit notice, Copy and Save still deliver, and failed Dismiss keeps the
   thumbnail available. Exercise drag only after ticket 12 is integrated.
5. Use the stand-in clock harness, never the Mac's system clock, for backward and
   large-forward jumps. Verify age cleanup is deferred and quota still applies.
6. Simulate a missing/unreadable owned file only in the isolated fixture root.
   Confirm usage is unavailable and new History commits fail while delivery works.
   Restore the fixture and apply limits again to retry maintenance.
7. Run the automated throw/SIGKILL cases for all six eviction points. Confirm two
   recovery sweeps agree, deleting entries stay hidden, usage matches disk, and
   the exported fixture remains byte-identical.

No signing, installation, launch, capture, clipboard, or arm64 runtime verification
was performed for this checklist.
