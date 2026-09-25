# Ticket 17 code review

Fixed point: `9abd3c2` (merge-base with main). Review snapshot: ticket branch HEAD.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- **Repeat recover on every Settings refresh (hard, performance):** first `availability()` always called `recover()`. Settings refresh and thumbnail finalize would re-sweep History. Fixed: recover once unless `recoverHistory()` is explicit.
- Baseline: notice strings live in the app target (judgement). `Show History Folder` uses `NSWorkspace.shared.open`, an accepted recovery form.

## Spec

- Ticket 17 / story 71 / decision 40: corrupt, unknown-migration, and permission failures disable History without writes; capture/copy/save/drag continue; dismiss stays pending; recovery retries without silent erase.
- Visible notice plus Try Again and Show History Folder. Launch alert when already disabled.
- Missing vs ticket wording: no separate "Reset History" (would erase). Correct.

## Summary

Standards: 1 hard finding, fixed in the snapshot. Spec: 0 blocking gaps. Worst per axis: avoid re-running recovery on every History usage refresh.
