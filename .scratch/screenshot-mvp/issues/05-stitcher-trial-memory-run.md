# 05: Stitcher trial, part 2: strip storage and memory run

**What to build:** the trial stitcher works on fixed-size strips and completes a synthetic 5120×57,600 capture within the memory limit, and Prateek gets a port-or-fresh recommendation with evidence.

**Blocked by:** 04

**Status:** in-progress (branch `ticket/05-stitcher-trial-memory`)

- [ ] Frames are compared only with the previous frame; new rows go into fixed-size strips; frames are released promptly; no temporary files are written.
- [ ] The synthetic 5120×57,600 capture completes without truncation or downscaling, with peak physical footprint under 2 GB, measured and recorded.
- [ ] Static header and footer detection still pass their tests.
- [ ] Vision-assisted alignment succeeds at least once on this Mac outside Codex's sandbox, or the failure is explained with evidence (ticket 04 saw -6662 inside the sandbox).
- [ ] A written recommendation compares the cost of porting against a fresh implementation against the same tests.
- [ ] Prateek decides port or fresh; the decision is recorded in the decisions file.

## Comments
