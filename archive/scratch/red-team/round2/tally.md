<!-- Output of tally.py over round2/*.md (8 ballots; ARCH via Codex gpt-6-astra high, others Cursor Claude Opus 5.5 High), 00:11 UTC Sep 23. -->
```
Ballots: ARCH, DATA, PERF, PLAT, QA, REL, SEC, UX (8)

ADOPTED (45): ARCH-1, ARCH-3, ARCH-4, ARCH-5, ARCH-6, ARCH-7, DATA-1, DATA-6, DATA-7, DATA-8, PERF-6, PLAT-1, PLAT-2, PLAT-3, PLAT-4, PLAT-5, PLAT-6, PLAT-7, PLAT-8, QA-1, QA-2, QA-3, QA-4, QA-5, QA-6, QA-7, QA-8, REL-1, REL-2, REL-3, REL-4, REL-6, REL-8, SEC-1, SEC-2, SEC-3, SEC-5, SEC-7, SEC-8, UX-1, UX-2, UX-3, UX-4, UX-5, UX-6

SUPERSEDED (2): ARCH-2 [ARCH/DATA/PERF/PLAT/QA/REL/SEC/UX], REL-5 [ARCH/DATA/PERF/PLAT/QA/REL/SEC/UX]

NOT ENOUGH AGREEMENT (1): UX-8 [-]

OBJECTED (14):
  DATA-2 by ARCH: Decodable orphan files lack commit provenance and metadata; lift if adoption requires a validated finalization manifest, otherwise discard them.
  DATA-3 by ARCH: “Before finalization” could forbid its own staging writes; lift if it explicitly means before an authorized finalization request, excluding original pixels.
  DATA-4 by ARCH: Moving recovery archives outside the root cannot exempt app-owned bytes; lift if archives remain counted until explicitly exported or deleted.
  DATA-5 by ARCH: UTC storage does not prevent destructive forward-clock jumps; lift if anomalous jumps defer age eviction and future-date normalization happens once.
  PERF-1 by ARCH: The 150 MP cap could truncate the required 295 MP trial; lift if trial acceptance requires complete output without truncation or downscaling.
  PERF-2 by ARCH: Quit must not commit unapproved edits; lift if termination waits only for authorized commits and applies the agreed editor-close choices.
  PERF-3 by ARCH: Hard 500 ms thresholds precede approved baselines; lift if these remain placeholders until measured and ratified.
  PERF-4 by ARCH: This conflicts with DATA-3 and debug/release isolation; lift if aligned to C1(b) and separate bundle-specific storage roots.
  PERF-4 by DATA: the pre-inserted `committing` row conflicts with C1(b); lift if commit order follows C1's outcome, keeping flock, synchronous=FULL, fullfsync and the evicting state
  PERF-4 by QA: its commit order conflicts with DATA-2, and C1 settles that; lift if its launch-sweep lock, kill-at-each-step, and run-recovery-twice tests are adopted without its commit order
  PERF-5 by ARCH: Main database plus WAL omits SHM and other owned files; lift if totals use the agreed comprehensive accounting definition.
  PERF-7 by PLAT: listen-only event taps need Input Monitoring, a second permission v1 avoids; lift if v1 has no event taps, and overlay key panels handle keys
  REL-7 by ARCH: Requiring an unused packaging script conflicts with deferred distribution; lift if packaging is documented now and implemented when a concrete delivery need exists.
  SEC-4 by ARCH: Session-end deletion can break asynchronous file-promise fulfillment; lift if staging survives outstanding handoffs and cleanup follows their documented completion contract.
  SEC-6 by DATA: excluding history from backup trades history loss on disk failure for privacy; lift if backup exclusion becomes Prateek's call
  UX-7 by ARCH: Origin-display confinement introduces an unapproved capture restriction; lift if Prateek decides that separately from the remaining acceptance checklist.

CONFLICTS:
  C1: b=ARCH/DATA/PERF/PLAT/QA/REL/SEC/UX
  C2: b=ARCH/DATA/PERF/PLAT/QA/REL/SEC/UX
  C3: b=ARCH/DATA/PERF/PLAT/QA/REL/SEC/UX

NEW BLOCKERS:
  DATA: No item says what happens when the history database fails to open or migrate: whether captures still deliver without history, and how the user is told. Snapzy silently skips the history insert (`CaptureHistoryStore.swift:92-104`).
  QA: The stitcher trial requires "passes its tests on this Intel Mac", but those tests are XCTest, which the installed Command Line Tools lack, so the trial must say whether it runs under Xcode or first converts the tests to Swift Testing.
```
