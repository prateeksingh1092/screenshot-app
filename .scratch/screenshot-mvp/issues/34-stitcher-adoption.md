# 34: Stitcher adoption: port or fresh

**What to build:** Frisket's core gains a stitcher, either the ported Snapzy stitcher or a fresh implementation, per Prateek's decision from ticket 5.

**Blocked by:** 05

**Status:** resolved (tested on `main` at `c2c764e`; recorded real scroll sequences pending Prateek, decision 49)

- [x] The stitcher is a pure function from frame sequence to image, with static header and footer detection and alignment scoring; it writes no temporary files.
- [ ] (Partly met; recordings pending) Either path passes the same tests: synthetic frames with byte-exact expectations; a few recorded real scroll sequences (no personal content, provenance documented) checking height tolerance and no duplicated bands; the 5120×57,600 run under 2 GB.
- [x] If ported: BSD-3 header kept, provenance entry added, Snapzy added to third-party notices, identity scrub passes.
- [x] Vision use is recorded in test results.

## Comments

### 2026-09-22 — coordinator note

Decision 48: port the adapted stitcher from `Trials/StitcherTrial/`, keeping its BSD-3 notices and provenance, and add Snapzy to the third-party notices for the product.

### 2026-09-23 — coordinator: resolved

- **Implementer:** Codex GPT-6 Astra, high. Report: `.scratch/screenshot-mvp/reports/34-implementer.md`.
- **Change:** the stitcher moved into `Sources/FrisketCore/Stitcher/`, and the trial package was removed. Tests, fixtures and checks moved with it. Snapzy was added to the third-party notices.
- **Vision:** the probe passed outside the sandbox (translation ty=-80, `usedVisionEstimate=true`).
- **Review:** fresh Codex, `reviews/34-code-review-codex.md`: no findings, verdict merge.
- **Integration:** `integrate/34` ran the root `swift test`: 51 tests in 7 suites passed. The earlier opt-in memory run peaked at 1,270,796,288 bytes, under the 2 GB limit, for the 5120×57,600 case. x86_64 only; arm64 not executed.
- **Pending:** a few recorded real scroll sequences, with no personal content and documented provenance. The harness and synthetic proof are in place; recordings wait for Prateek under decisions 49 and 50.
