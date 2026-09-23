# Ticket 15 code review

Fixed point: `331dd49` (merge-base with main). Review snapshot: `90e0f44`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- **Delete error wiped (hard, correctness):** `HistoryWindowModel.reload()` always sets `message = nil` on a successful list load. `delete()` sets "Delete failed" then calls `reload()`, so the error never stays visible.
- **Stale History window (hard, correctness):** thumbnail dismiss/copy/save/quit refresh History Settings usage but not the open History window, so a visible window omits captures just finalized.
- Baseline: `deliver` grew a pending-vs-history fork (divergent change / judgement). Acceptable for one command path. `historyImage` loads the full PNG per row (judgement); v1 History is bounded.

## Spec

- Ticket 15 / stories 60–62, 66: newest-first items without paths; copy/save/drag reuse adapters and leave the owned file; delete unlinks (not Trash); Done is alreadyFinalized; interrupted delete resumes at launch. Window has labels, C/S/Delete, arrows, and drag. Own-app exclusion covers the window.
- Crash interruption for user delete is one point (`markedDeleting`) plus existing eviction-recovery coverage of the same `evict` path. Enough.
- Missing vs ticket wording: no per-row VoiceOver custom actions (buttons are labelled and keyboard-reachable). Not blocking.

## Summary

Standards: 2 hard findings (wiped delete error; stale open window). Spec: 0 blocking gaps. Worst per axis: delete error never shown; History window does not refresh when a thumbnail finalizes.
