# 30: Editor close, quit, and logout choices

**What to build:** leaving the editor always has a deliberate, predictable outcome, whether Prateek closes it, quits Frisket, or logs out.

**Blocked by:** 26

**Status:** resolved (tested on `main` at `ad41a5e`; close/quit sheet VoiceOver manual pending)

- [x] Closing with edits asks Finalize (Return, default), Delete capture (destructive, never default), or Cancel (Esc).
- [x] Closing without edits finalizes to History (decision 44).
- [x] Sudden termination is disabled while editors are open; Quit shows the same choice for each editor.
- [x] A logout or restart that interrupts an unanswered prompt discards that capture (decision 30).
- [x] Seam 1 tests cover each path.

## Comments

### 2026-09-23 — coordinator

Claimed on `d0190eb` after ticket 29 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/30-editor-close-quit-logout`.

### 2026-09-23 — implementer

Report: [30-implementer.md](../reports/30-implementer.md). Unchanged close finalizes; edited close offers Finalize / Delete / Cancel; logout during the prompt discards. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `d0190eb`: [30-code-review.md](../reviews/30-code-review.md). No blocking findings.

- **Integration:** `integrate/30` fast-forwarded `main` to `ad41a5e`. Unchanged close finalizes to History; edited close is Finalize / Delete / Cancel; logout during the prompt discards. Root `swift test`: 275 tests in 38 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual close/quit sheet remain for Prateek.

