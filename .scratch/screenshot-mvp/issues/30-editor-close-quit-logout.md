# 30: Editor close, quit, and logout choices

**What to build:** leaving the editor always has a deliberate, predictable outcome, whether Prateek closes it, quits Frisket, or logs out.

**Blocked by:** 26

**Status:** in-progress (branch `ticket/30-editor-close-quit-logout`)

- [ ] Closing with edits asks Finalize (Return, default), Delete capture (destructive, never default), or Cancel (Esc).
- [ ] Closing without edits finalizes to History (decision 44).
- [ ] Sudden termination is disabled while editors are open; Quit shows the same choice for each editor.
- [ ] A logout or restart that interrupts an unanswered prompt discards that capture (decision 30).
- [ ] Seam 1 tests cover each path.

## Comments

### 2026-09-23 — coordinator

Claimed on `d0190eb` after ticket 29 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/30-editor-close-quit-logout`.

### 2026-09-23 — implementer

Report: [30-implementer.md](../reports/30-implementer.md). Unchanged close finalizes; edited close offers Finalize / Delete / Cancel; logout during the prompt discards. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `d0190eb`: [30-code-review.md](../reviews/30-code-review.md). No blocking findings.

