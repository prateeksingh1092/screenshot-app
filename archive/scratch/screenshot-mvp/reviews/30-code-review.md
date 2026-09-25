# Ticket 30 code review

Fixed point: `d0190eb` (merge-base with main). Review snapshot: ticket branch HEAD.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- `EditorLeave` is the command mapping; AppKit only presents the sheet.
- Failed unchanged finalize no longer drops the editor from the map (judgement:
  the first draft removed it before the command succeeded).
- Quit presents the same sheet and cancels termination until the user quits
  again (judgement). The ticket requires the choice, not a nested
  `terminateLater` loop.

## Spec

- Decision 44: close without edits dismisses into History.
- Decision 17 / 30: edited close is Finalize / Delete capture / Cancel;
  logout or restart during an unanswered prompt discards.
- Sudden termination is disabled while any editor is open.
- Seam 1 covers unchanged finalize, delete, and logout-discard.

## Summary

Standards: 0 hard findings. Spec: 0 blocking gaps. Worst per axis: quit is
sheet-then-quit-again rather than one `terminateLater` pass.
