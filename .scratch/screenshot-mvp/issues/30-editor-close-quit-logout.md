# 30: Editor close, quit, and logout choices

**What to build:** leaving the editor always has a deliberate, predictable outcome, whether Prateek closes it, quits Frisket, or logs out.

**Blocked by:** 26

**Status:** ready-for-agent

- [ ] Closing with edits asks Finalize (Return, default), Delete capture (destructive, never default), or Cancel (Esc).
- [ ] Closing without edits finalizes to History (decision 44).
- [ ] Sudden termination is disabled while editors are open; Quit shows the same choice for each editor.
- [ ] A logout or restart that interrupts an unanswered prompt discards that capture (decision 30).
- [ ] Seam 1 tests cover each path.

## Comments
