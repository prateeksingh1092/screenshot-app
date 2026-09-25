# Ticket 31 code review

Fixed point: `5d0d6a5` (merge-base with main). Review snapshot: ticket branch HEAD.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- `EditorLeave.deliver` reuses Done, then `EditorDelivery` for the existing
  copy/save/drag commands. No second finalization policy.
- The editor drag well reuses `HistoryDragView` (judgement).
- File-promise session starts before `finishEditing` so `.drag` has an active
  handoff.

## Spec

- Ticket 31: Copy, Save, and drag finalize the rendered revision, then deliver
  what the canvas shows. Canaries cover clipboard, saved file, and drag.
- Failed copy leaves History committed and is retried with `retryCopy`.
- Tools have VoiceOver labels. Manual canvas/drag remain.

## Summary

Standards: 0 hard findings. Spec: 0 blocking gaps. Worst per axis: drag
depends on beginning the file-promise session before the leave command.
