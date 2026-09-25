# 84: Editable marks

**What to build:** After drawing, a mark stays an object. The user selects it with a click (or a select tool) and sees handles. They can move, resize or delete it, and change its colour or width; each change is one undo step (story 102). Solid redactions keep their own rules and stay exact black.

**Blocked by:** 66, 69

**Phase:** 2b (decision 59)

**Status:** ready-for-agent

- [ ] Clicking a mark selects it and shows handles. Esc or a click elsewhere deselects it.
- [ ] Move, resize, delete and restyle each produce one `NSUndoManager` step.
- [ ] The saved output equals the preview after every edit (the parity test from ticket 68).
- [ ] Every mark has a VoiceOver label, and a keyboard path exists: Tab through marks, arrows to move, Delete to delete.

## Comments

### 2026-09-25: coordinator, created

From decision 59 (Prateek agreed with the CleanShot editor study). Claude Opus 5.5, Claude Code, high effort.
