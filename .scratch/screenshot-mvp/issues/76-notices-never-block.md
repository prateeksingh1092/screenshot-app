# 76: Notices that never block

**What to build:** Every notice goes through one non-modal notice service: the Thumbnail status line plus a VoiceOver announcement. Modals appear only for destructive or irreversible choices. Termination handling lives in one place (story 99).

**Blocked by:** 73

**Phase:** 4 (O9, DA-5)

**Status:** ready-for-agent

- [ ] No alert is shown for a success or an informational notice; only destructive choices (delete, close with edits, quit with unanswered editors) are modal.
- [ ] Every notice is announced to VoiceOver.
- [ ] A test maps every outcome to a non-modal notice, except for the destructive set.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
