# 40: Final acceptance

**What to build:** Frisket v1 is verified end to end on this Mac against the spec.

**Blocked by:** 10, 14, 15, 16, 17, 22, 25, 27, 28, 29, 30, 31, 33, 36, 38, 39

**Status:** in-progress (branch `ticket/40-final-acceptance`)

- [ ] The complete manual checklist passes, including cases added after ticket 39 (display unplug and lock outcomes, exclusion list, editor flows).
- [ ] Performance is re-measured after scrolling capture and meets the ratified targets.
- [ ] A universal release build is produced and labelled "arm64 built and signed, never executed"; nothing is distributed (decision C3).
- [x] All static checks pass: dependency allowlist, dependency direction, identity scrub, licence headers and provenance, no writes before finalization, no free-text logging, no event taps or idle monitors, no network entitlement.
- [ ] Codex assesses the verification report before v1 is declared done.

## Comments

### 2026-09-23 — coordinator

Claimed on `bc98b39` after ticket 39 closed. Coordinator chat implements
(Codex/Other Models still limited). Branch `ticket/40-final-acceptance`.
Hardware first-run, ratified performance targets, a universal signed Release,
and Codex's assessment remain open.

### 2026-09-23 — implementer

Report: [40-implementer.md](../reports/40-implementer.md). Release configs and
offline tests landed. Unsigned universal binary exists; signing timed out on
the keychain. Status/checkboxes unchanged pending review.

- **Integration:** `integrate/40` fast-forwarded `main` to `aee1767`. Release
  is universal (`x86_64` + `arm64`) with the production identifier. Static
  checks passed. Isolated re-run of
  `tierOneRecoversEveryInterruptedCommitTwice` after two `.rootLocked` flakes
  in the full suite. Unsigned x86_64 Development `xcodebuild` succeeded.
  C3 signed label, hardware first-run, ratified targets, and Codex assessment
  remain open. Ticket stays in-progress. x86_64 only for execution; arm64
  compiled, never executed.

- **Integration:** `integrate/40` fast-forwarded `main` to `aee1767`. Release
  is universal (`x86_64` + `arm64`) with the production identifier. Static
  checks passed. Isolated re-run of
  `tierOneRecoversEveryInterruptedCommitTwice` after two `.rootLocked` flakes
  in the full suite. Unsigned x86_64 Development `xcodebuild` succeeded.
  C3 signed label, hardware first-run, ratified targets, and Codex assessment
  remain open. Ticket stays in-progress. x86_64 only for execution; arm64
  compiled, never executed.
