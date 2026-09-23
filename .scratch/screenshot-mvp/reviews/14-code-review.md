# Ticket 14 code review

Fixed point: `b04a53c` (merge-base with main). Review snapshot: `a84fc3f`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- **Quit busy leftover (hard, correctness):** `applicationShouldTerminate` now marks every panel busy, then `handleSystemEvent(.quit)` stops on the first failed commit. Only the failed card is un-busied. Later cards stay `busy == true`, so Copy/Save/Close/Delete are stuck until relaunch. Old loop only busied the card it was dismissing.
- **Crash seam (judgement):** the crash test proves an unedited pending capture writes no `history.sqlite` and no `images/`. It does not construct a second command layer. Decision 31 is the disk rule; empty memory on a new process is structural. Acceptable if documented.
- Baseline smells: `ThumbnailAutoDismissPreference` plus `ThumbnailAutoDismiss` is a small data clump that Settings needs (never vs zero). Not speculative. Display remapping lives in `ThumbnailStack` (locality) rather than AppKit-only layout. No documented-standard breach besides the busy leftover.

## Spec

- Ticket 14 / decision 44 / story 32 and 36: never vs delay, zero ≠ never, quit finalizes oldest-first and stops on failed commit, lock leaves pending and pauses timeout, overflow still due under never/lock, unplug rehomes and leaves pending, crash writes nothing. Present at seam 1.
- Settings persist never and seconds separately and apply live. Manual checklist covers lock and unplug.
- Not asked and not a problem: `setThumbnailPolicy` on existing cards (Settings Apply).
- Missing vs ticket wording: crash is proven as “nothing on disk,” not “new layer empty.” Unplug/lock AppKit observers are adapters over the same seam.

## Summary

Standards: 1 hard finding (quit busy leftover). Spec: 0 blocking gaps. Worst per axis: leftover busy on remaining cards after a failed quit; crash test is disk-only.
