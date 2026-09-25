# 47: Red tests: Pending capture lifecycle and History

**What to build:** Tests at the command seam reproduce five defects. A cancelled drag commits to History and leaves a staged file (D7). Copy Text on a capture with no text overwrites the clipboard (D8). History Delete fails while the capture's Thumbnail is open (D10). History actions fail after "Try Again" recovery (D19). Delete from History and Copy Text overlap other commands, and quit stops at the first capture it can't finalize (D25).

**Blocked by:** 43

**Phase:** 0

**Status:** ready-for-agent

- [ ] D7: a drag session that ends without a promise write leaves no file on disk and no History row. It uses the real drag lifetime, not the fake that always fires both events.
- [ ] D8: Copy Text with an empty recognition result leaves the clipboard's change count and contents unchanged.
- [ ] D10: deleting a History item whose Thumbnail is open succeeds and closes that Thumbnail.
- [ ] D19: after History recovery succeeds, `delete` and the finalized image return results rather than `.unavailable`.
- [ ] D25: Delete from History and Copy Text take the in-progress guard like every other command. Quit finalizes every capture it can and reports the rest.
- [ ] Each is marked as a known defect.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
