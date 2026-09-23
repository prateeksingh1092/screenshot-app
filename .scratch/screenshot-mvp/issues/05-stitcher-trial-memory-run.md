# 05: Stitcher trial, part 2: strip storage and memory run

**What to build:** the trial stitcher works on fixed-size strips and completes a synthetic 5120×57,600 capture within the memory limit, and Prateek gets a port-or-fresh recommendation with evidence.

**Blocked by:** 04

**Status:** resolved (tested on `main` at `c02086a`; decision 48)

- [x] Frames are compared only with the previous frame; new rows go into fixed-size strips; frames are released promptly; no temporary files are written.
- [x] The synthetic 5120×57,600 capture completes without truncation or downscaling, with peak physical footprint under 2 GB, measured and recorded.
- [x] Static header and footer detection still pass their tests.
- [x] Vision-assisted alignment succeeds at least once on this Mac outside Codex's sandbox, or the failure is explained with evidence (ticket 04 saw -6662 inside the sandbox).
- [x] A written recommendation compares the cost of porting against a fresh implementation against the same tests.
- [x] Prateek decides port or fresh; the decision is recorded in the decisions file.

## Comments

### 2026-09-22 — coordinator integration and close

- Implemented by Codex (GPT-6 Astra, high); reports in `../reports/05-implementer.md` and `../reports/05-port-or-fresh.md`.
- Vision probe run by the coordinator outside Codex's sandbox: passed. The probe requires a real Vision estimate. The -6662 failure occurs only inside the sandbox; its cause hasn't been isolated.
- Fresh Codex review against `2915182`: Standards 0, Spec 1 nit (Vision causality wording, fixed). Verdict merge. The review independently confirmed a peak of 1,282,326,528 bytes for the 5120×57,600 run, with all 1,179,648,000 output bytes checked (`../reviews/05-code-review-codex.md`).
- Integration branch `integrate/05` on Xcode 26.5, x86_64, macOS 26.7 (25G229): 15 root tests, 29 trial tests (2 opt-in skipped), and the Vision probe all passed. arm64 was not executed.
- Prateek decided to port the adapted stitcher (decision 48). `main` is at `c02086a`.
