# 76: Notices that never block

**What to build:** Every notice goes through one non-modal notice service: the Thumbnail status line plus a VoiceOver announcement. Modals appear only for destructive or irreversible choices. Termination handling lives in one place (story 99).

**Blocked by:** 73

**Phase:** 4 (O9, DA-5)

**Status:** ready-for-agent

- [x] No alert is shown for a success or an informational notice; only destructive choices (delete, close with edits, quit with unanswered editors) are modal.
- [ ] Every notice is announced to VoiceOver.
- [x] A test maps every outcome to a non-modal notice, except for the destructive set.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). This ticket's decision is recorded in `decisions.md`.

- **What changed:** FrisketCore gains `Notices.swift`: `Notice` (title, message, announcement), `Notice.after(command, outcome)`, `Confirmation` (the modal set: History Delete, closing an edited capture, a syncing export folder) and `QuitPlan`/`QuitState`/`QuitStep`. The app gains `NoticeCenter` (a non-activating notice line, announced to VoiceOver). `CaptureSurfaces` and `AppController` show every notice through it; `AppController.notice` (a modal `NSAlert`) is deleted, and so is the "Save failed" alert, which repeated the Thumbnail's status line. `applicationShouldTerminate` follows `QuitPlan`: only an open editor holds Quit; a capture in flight (the live stale flag) has its selection closed and a bounded wait, then Quit finalizes and goes on. New repository check `modals` (in `ci.sh`) allows `NSAlert` only in the three Confirmation files.
- **Tests:** `NoticeTests` (6 tests, red as a compile failure before `Notices.swift`, then green); fixtures `modals-rejected`/`modals-accepted`; `repositorySatisfiesStaticChecks(modals)` was red on `FrisketApp.swift` before the alert went. `scripts/ci.sh`: green, 356 tests.
- **Open:** VoiceOver announcement of the notice line (criterion 2) needs a live check. A stuck capture flag still blocks the next capture until its command returns; only Quit is freed.
