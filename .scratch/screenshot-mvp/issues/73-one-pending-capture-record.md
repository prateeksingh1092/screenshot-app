# 73: One Pending capture record, one Thumbnail status

**What to build:** The coordinator keeps one record per capture instead of about 13 parallel collections. `thumbnails()` reports each Thumbnail's public status and the next due time, and the UI applies that status. A finalized Thumbnail is therefore announced as finalized, with the right actions. Drag goes through `deliver()` like every other delivery.

**Blocked by:** 54, 55, 57, 58, 59

**Phase:** 4 (candidate #2)

**Status:** ready-for-agent

- [x] Thumbnail status assertions at the command test surface replace the planned presenter tests.
- [ ] The accessibility name says pending or finalized, stale Edit and Delete actions disappear after finalization, and the close action works (part of D16).
- [x] There are no `editing` or `delivering` states.
- [x] The surfaces drop their shadow copies of arrival order and screens.
- [x] Every existing lifecycle test stays green.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5, Claude Code, medium effort (decision 62). Recorded as decision 67.

- **Core:** `CaptureLifecycleCoordinator` keeps one `PendingCapture` record per open capture and a settled map, replacing the parallel sets and maps. Only two transient locks remain (command in progress, Copy Text); no editing or delivering state. `.drag` now runs through `deliver()`: it commits only after an accepted drop (DA-3) and has no retry gate. Decisions 60, 64 (synchronous `flatten` and its guard order) and 65 (`displayID` from `CaptureImage`) are unchanged.
- **Status:** `thumbnails()` returns `Thumbnails` (cards with `status` pending/finalized and `editable`, plus `nextDueAt`).
- **App:** `CaptureSurfaces` applies the core's status, lays cards out on the core's displays, and wakes once at `nextDueAt`. `arrivalOrder`, `screens` and per-card timers are gone. `ThumbnailPanel` renames a finalized card "Capture kept in History" and rebuilds its custom actions without Edit and Delete.
- **Tests:** three new tests in `ThumbnailStackCommandsTests` (status, close on a finalized card, `nextDueAt`) and one in `DragHandoffTests` (a refused drag stays pending; dragging again finalizes). One existing assertion now compares `.cards`. `scripts/ci.sh`: green, 334 tests.
- **Open (live):** the VoiceOver name and actions after a failed Copy or Save that History committed, and whether Close works from VoiceOver (the core path is tested; the no-op in D16 did not reproduce at the package seam).

