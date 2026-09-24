# 40: Final acceptance

**What to build:** Frisket v1 is verified end to end on this Mac against the spec.

**Blocked by:** 10, 14, 15, 16, 17, 22, 25, 27, 28, 29, 30, 31, 33, 36, 38, 39

**Status:** in-progress (branch `ticket/40-final-acceptance`)

- [ ] The complete manual checklist passes, including cases added after ticket 39 (display unplug and lock outcomes, exclusion list, editor flows).
- [ ] Performance is re-measured after scrolling capture and meets the ratified targets.
- [x] A universal release build is produced and labelled "arm64 built and signed, never executed"; nothing is distributed (decision C3).
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
  Ticket stays in-progress. x86_64 only for execution; arm64 compiled, never
  executed.

- **C3 label (2026-09-23, after keychain unlock):** signed the existing
  Release bundle with Personal Team `9M43Q952NK`. `codesign --verify --strict`
  passed. Label
  `arm64 built and signed, never executed`: architectures `arm64`+`x86_64`,
  identifier `io.github.prateeksingh1092.frisket`, CDHash
  `c273fe80a1c0fe7cc1fbf6e0f818cd8cce93772d`, `distributed: false`,
  `arm64_executed: false`. Not launched, not copied to `~/Applications`,
  not distributed. Hardware first-run, ratified targets, and Codex
  assessment remain open.

- **Coordinator continue (2026-09-23 20:42 CDT):** dirty 02:28 debug install
  replaced with signed Development `16e8e3e` at `~/Applications/Frisket.app`.
  RepositoryChecks, FirstRun, and Performance offline tests passed. Pixel-free
  first-run header written; four isolated-account cases blocked; 17 cases
  pending. `tmutil isexcluded` is Excluded on the debug History root. Live
  performance not started (thermal state 1). Draft:
  [40-verification-draft.md](../reports/40-verification-draft.md). Not v1.

- **Coordinator continue (2026-09-23 21:17 CDT):** keychain approved; signed
  Development rebuilt and installed (CDHash
  `8414521e88861a8126204d42bea70f0c79b11cd4`). Own-process listing no longer
  fails closed when the overlay-hidden LSUIElement app is absent from
  `SCShareableContent`. Live synthetic area (built-in 2× and external 1×),
  full-screen, Esc, Copy, and Focus+Copy all verified. First-run record:
  10 pass / 4 blocked / 7 pending. Not v1.
