# 34: Stitcher adoption: port or fresh

**What to build:** Frisket's core gains a stitcher, either the ported Snapzy stitcher or a fresh implementation, per Prateek's decision from ticket 5.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] The stitcher is a pure function from frame sequence to image, with static header and footer detection and alignment scoring; it writes no temporary files.
- [ ] Either path passes the same tests: synthetic frames with byte-exact expectations; a few recorded real scroll sequences (no personal content, provenance documented) checking height tolerance and no duplicated bands; the 5120×57,600 run under 2 GB.
- [ ] If ported: BSD-3 header kept, provenance entry added, Snapzy added to third-party notices, identity scrub passes.
- [ ] Vision use is recorded in test results.

## Comments

### 2026-09-22 — coordinator note

Decision 48: port the adapted stitcher from `Trials/StitcherTrial/`, keeping its BSD-3 notices and provenance, and add Snapzy to the third-party notices for the product.
