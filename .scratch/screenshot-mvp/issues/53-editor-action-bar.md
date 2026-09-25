# 53: Editor action bar: Done, Copy, Save and Drag always visible

**What to build:** The editor always shows Done, Copy, Save and a drag handle in a bar inside the window, at any window width. ⌘C, ⌘S and Return work whether or not the toolbar overflows. The finish action is called "Done" everywhere (story 87, glossary). The interim `visibilityPriority` step is skipped, as decision 58 records.

**Blocked by:** 48

**Phase:** 1 (D5 → O8)

**Status:** ready-for-agent

- [ ] At the default and minimum editor widths, Done, Copy, Save and the drag handle are visible and clickable.
- [ ] ⌘C, ⌘S, Return (Done) and Esc or ⌘W work through menu or responder actions, not button key equivalents.
- [ ] No "Keep in History" text remains in the UI or in notices, and the VoiceOver labels say "Done".
- [ ] The tools stay in the toolbar and stay reachable by keyboard. Typing in the label field is unchanged: Return there doesn't trigger Done.
- [ ] The editor row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
