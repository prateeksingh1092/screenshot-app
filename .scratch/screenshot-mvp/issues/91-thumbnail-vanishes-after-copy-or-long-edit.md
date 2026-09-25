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

- [ ] Red tests through `thumbnails()` or the coordinator for all three cases in the table, then green.
- [ ] Coordinator live check: the `editor-redaction` and `history-delete` rows pass on both displays.
