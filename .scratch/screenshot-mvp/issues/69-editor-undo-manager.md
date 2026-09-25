# 69: Editor undo through NSUndoManager

**What to build:** Undo and Redo in the editor use the window's `NSUndoManager`, so ⌘Z, ⌘⇧Z and the Edit menu work the same way for every edit kind, crop included.

**Blocked by:** 53, 68

**Phase:** 2 (O11)

**Status:** ready-for-agent

- [ ] The custom undo stack is deleted.
- [ ] Every edit kind undoes and redoes, and the Undo menu item names the edit.
- [ ] The close-with-edits choice is unchanged.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
