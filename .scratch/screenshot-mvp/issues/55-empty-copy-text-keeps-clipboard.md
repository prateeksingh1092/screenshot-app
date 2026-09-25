# 55: Copy Text with no text leaves the clipboard alone

**What to build:** Copy Text on a capture with no recognizable text leaves the clipboard exactly as it was and shows "No text found" on the Thumbnail status line, with no modal. When text is found, it is copied and the confirmation is non-modal too (D8, DA-5, story 89).

**Blocked by:** 47

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D8 test passes without the known-defect mark.
- [ ] Neither outcome shows a modal alert, and VoiceOver announces the result.
- [ ] The Copy Text rows of the live matrix (text and none) pass.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
