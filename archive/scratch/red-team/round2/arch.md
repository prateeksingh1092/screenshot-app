## ARCH: round 2 votes
ARCH-1: agree
ARCH-2: superseded
ARCH-3: agree
ARCH-4: agree
ARCH-5: agree
ARCH-6: agree
ARCH-7: agree
UX-1: agree
UX-2: agree
UX-3: agree
UX-4: agree
UX-5: agree
UX-6: agree
UX-7: object: Origin-display confinement introduces an unapproved capture restriction; lift if Prateek decides that separately from the remaining acceptance checklist.
UX-8: abstain
QA-1: agree
QA-2: agree
QA-3: agree
QA-4: agree
QA-5: agree
QA-6: agree
QA-7: agree
QA-8: superseded
DATA-1: agree
DATA-2: object: Decodable orphan files lack commit provenance and metadata; lift if adoption requires a validated finalization manifest, otherwise discard them.
DATA-3: object: “Before finalization” could forbid its own staging writes; lift if it explicitly means before an authorized finalization request, excluding original pixels.
DATA-4: object: Moving recovery archives outside the root cannot exempt app-owned bytes; lift if archives remain counted until explicitly exported or deleted.
DATA-5: object: UTC storage does not prevent destructive forward-clock jumps; lift if anomalous jumps defer age eviction and future-date normalization happens once.
DATA-6: agree
DATA-7: agree
DATA-8: agree
REL-1: agree
REL-2: abstain
REL-3: agree
REL-4: abstain
REL-5: superseded
REL-6: agree
REL-7: object: Requiring an unused packaging script conflicts with deferred distribution; lift if packaging is documented now and implemented when a concrete delivery need exists.
REL-8: abstain
PERF-1: object: The 150 MP cap could truncate the required 295 MP trial; lift if trial acceptance requires complete output without truncation or downscaling.
PERF-2: object: Quit must not commit unapproved edits; lift if termination waits only for authorized commits and applies the agreed editor-close choices.
PERF-3: object: Hard 500 ms thresholds precede approved baselines; lift if these remain placeholders until measured and ratified.
PERF-4: object: This conflicts with DATA-3 and debug/release isolation; lift if aligned to C1(b) and separate bundle-specific storage roots.
PERF-5: object: Main database plus WAL omits SHM and other owned files; lift if totals use the agreed comprehensive accounting definition.
PERF-6: abstain
PERF-7: abstain
SEC-1: agree
SEC-2: agree
SEC-3: agree
SEC-4: object: Session-end deletion can break asynchronous file-promise fulfillment; lift if staging survives outstanding handoffs and cleanup follows their documented completion contract.
SEC-5: agree
SEC-6: abstain
SEC-7: agree
SEC-8: agree
PLAT-1: abstain
PLAT-2: agree
PLAT-3: agree
PLAT-4: abstain
PLAT-5: agree
PLAT-6: agree
PLAT-7: abstain
PLAT-8: agree
C1: b: Fewer persisted states; orphan adoption still needs validated finalization provenance.
C2: b: Preserve the newest capture, visibly report overage, and explicitly amend decision 5’s ceiling.
C3: b: Keep development efficient; verify universal builds separately and require Apple-silicon execution before distribution.