Reviewed `1bc6091...cefe81f` after Codex usage ended (2026-09-23). Coordinator review, one pass. Recursion guard: no further review agents.

## Standards

No blockers. Eviction is a deep module behind `HistoryStore`; diagnostics stay closed-set.

## Spec

No blockers. Age/quota/oldest-first, just-committed protection, oversized delivery, clock deferral, Settings limits, and eviction crash points have seam 1 tests. `status(consumeNotice:)` returns the pending flag then clears it — matches a one-time notice. Exports are excluded via the existing Save path (not counted in History usage).

Implementer notes about ticket 10 recovery and ticket 12 drag are stale: both are on `main`. Integration when this branch merges must keep WAL lock and drag staging out of usage.

Verification: implementer reported 128 tests; not re-run here (Codex limit). Manual Settings/VoiceOver pending.

Verdict: merge
