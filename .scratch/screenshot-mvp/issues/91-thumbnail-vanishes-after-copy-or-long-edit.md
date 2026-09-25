# 91: The Thumbnail vanishes after Copy or after a long edit

**What to build:** A Thumbnail stays on screen after Copy and after editing, so the user can still Save, drag or Copy Text from it. This is regressed by ticket 73.

**Evidence (2026-09-25, live, `03a14d9`, built-in display):**

| Action | Thumbnails afterwards |
|---|---|
| Capture, then Copy | 0 within 0.5 s. Before 73 the card stayed and showed "Kept in History". |
| Capture, open the editor, press Done after 1 s | 1 |
| Capture, open the editor, press Done after 12 s | 0 |

The live `editor-redaction` and `history-delete` rows fail because of this. The 10-second Thumbnail timeout keeps running while the editor is open, and a finalized card seems to exit at once.

**The rule (coordinator's decision, recorded at merge):**
- Opening the editor pauses the Thumbnail's timeout. Done or Close in the editor restarts it in full.
- A finalized Thumbnail (after Copy, Save, drag or Done) stays until its timeout, a Close, or the stack overflows, as decision 67 describes ("Capture kept in History", no Edit or Delete).

**Blocked by:** none (it touches the coordinator's Thumbnail status from ticket 73)

**Status:** ready-for-agent (medium effort)

- [x] Red tests through `thumbnails()` or the coordinator for all three cases in the table, then green.
- [ ] Coordinator live check: the `editor-redaction` and `history-delete` rows pass on both displays.

### 2026-09-25: implementer, report

Model and effort: Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). The rule is recorded as this ticket's decision in `decisions.md`.

**Cause.** Ticket 73's `release(id)` removed the card from the stack together with the pixels, so every committed Copy, Save, drag or editor Close closed the Thumbnail at once, and `CaptureSurfaces` also called `remove(id)` after each. The timeout ran from arrival while the editor was open, so Done after 10 s found no card.

**Changes.**
- `CaptureLifecycleCoordinator`: `setEditorOpen(_:for:)` pauses that card's timeout (no timeout `dueExit`, no `nextDueAt`, `.exitThumbnail(_, .timeout)` refused) and restarts it in full when the editor leaves. `release` keeps a finalized card in the stack; `.exitThumbnail` (finalize exits) and quit close it through `finalizeAndClose`; History Delete also closes it. A kept card reports `status: .finalized`, `editable: false`, and delivers from History.
- `ThumbnailStack`: `contains` and `restartTimeout`.
- `CaptureSurfaces`: calls `setEditorOpen(true)` when the editor shows and `setEditorOpen(false)` when it leaves; after a committed Copy, Save, drag or editor Close it keeps the panel when the core still lists it (`closeUnlessKept`).
- `ThumbnailPanel`: a finalized card's status line reads "Kept in History".

**Tests.** New, red then green (`ThumbnailStackCommandsTests`, "Ticket 91"): Copy keeps a finalized card until timeout or Close (both arguments); an open editor pauses the timeout and Done restarts it in full (the 12 s case); an unchanged editor's Close keeps the card and restarts the timeout; a quick edit returns a finalized card that survives Copy (the 1 s case); quit and History Delete close a kept card. Changed because they locked in the old behaviour: `failedCopyDeliveryWaitsForExplicitRetry…` (a committed retry now keeps the card), `leavingCardsFreeTheirPlaceInTheStack` (closes the copied card explicitly), and two `DragHandoffTests` expectations (an accepted drop leaves a finalized card, not an empty stack).

**Open.** The live `editor-redaction` and `history-delete` rows on both displays are for the coordinator. The core still admits an overflow exit for a card whose editor is open, as before; the app skips it while the card is busy with its editor.

