# Ticket 05 — port or fresh recommendation

**Recommendation only; Prateek decides. No decision has been recorded.**

Recommend carrying the adapted stitcher forward as the sole port candidate,
subject to separate review and the outside-sandbox Vision probe. The measured
storage changes preserve the deterministic tests and satisfy this synthetic
memory gate. Recreating the alignment search, ambiguity rejection, known-step
checks, settled-final-step handling, and sticky-band behavior would add work
without removing the shared Vision and memory risks.

## Evidence and effort so far

- Ticket 04 measured **10m 50s** of Codex implementation/verification (excluding
  initial instruction reading and review). It extracted the isolated package,
  converted 22 tests to Swift Testing, preserved attribution, extended repository
  checks, and added an exact settled-overlap fallback after an inherited failure.
- Ticket 05's measured implementation interval and final checks are in
  [05-implementer.md](05-implementer.md). Work replaces frame-retaining slices
  with compressed 256-row strips, releases caller frames, removes the retained
  initial raster, adds streaming output and a strip-backed CGImage provider,
  fixes exact sticky-band boundaries, and adds opt-in probes. No refactor stage.
- **27 normal tests passed; 2 opt-in tests skipped** in the normal suite. This
  includes all 22 inherited scenarios and five new strip/lifetime/sticky tests.
  The separate full-size test passed: 79 frames → 5120×57,600, all 225 strips
  and all 1,179,648,000 output bytes verified against synthetic source pixels.
- Peak physical footprint **1,289,433,088 bytes**, elapsed **35.617 seconds**;
  kernel `TASK_VM_INFO.ledger_phys_footprint_peak`, including full-image-byte
  materialization and validation. Previous full-bitmap output failed at
  **3,664,924,672 bytes**. The accepted test limit is the stricter decimal 2 GB.
- x86_64, macOS 26.7 build 25G229; Xcode 26.5 (17F42), Swift 6.3.2.
  **arm64 not executed.**

## Cost comparison against the same acceptance tests

A second fresh implementation was **not built or tested** in this ticket. Its
cost below is a low-confidence planning estimate, not a measured race or an
established proof that a port costs less. The estimate assumes the same Codex
workflow and scope; it excludes shared app integration and real-screen QA.

| Work | Adapt this port | Fresh implementation |
| --- | --- | --- |
| Completed evidence | Extraction plus strip conversion, all 22 inherited tests and new deterministic tests green, measured memory run | None; no fresh code or test result claimed |
| Remaining implementation estimate | 2–4 hours for review fixes, explicit failure handling/API integration as selected, and addressing probe findings | 8–16 hours to implement and tune the same behavior, then meet the identical gates; could increase with real-sequence failures |
| Storage/rendering | Trial strip store and lazy output now exist; integrate strip-by-strip rendering/encoding rather than full bitmap copies | Build equivalent lossless bounded storage and output ownership; replacing alignment does not avoid this |
| Alignment | Keep empirical scoring/search, document local changes and reconcile selectively with upstream | Design overlap scoring, ambiguity rejection, known-step validation, duplicate/boundary behavior, final short steps and static-band detection |
| Common acceptance gate | Existing 22 scenarios **unchanged**, the five new tests, the exact same full-size fixture/budget, and the real Vision probe | Run that same suite with only module/type wiring changed; do not weaken assertions or omit difficult cases |

A fresh exact-overlap-only prototype could be short, but would not establish
comparable performance on noisy real scroll sequences or replace the empirical
matcher. Conversely, inherited tests alone are not enough: several permit
alignment failure or merely check non-nil updates. Both alternatives still
need the specification's nonpersonal recorded real sequences, sticky-band
properties and Apple-silicon execution when authorized/available.

## Modifications still needed and risks

- **Vision:** the repeatable probe fails inside Codex's sandbox with
  `NSOSStatusErrorDomain -6662`, allocating a 320×400 `420f` CVPixelBuffer.
  The failure is observed at buffer allocation, not explained as a proven
  sandbox/GPU root cause. The coordinator must run the documented command
  outside the sandbox and attach its result. Passing synthetic tests via the
  pixel matcher is not Vision success. A fresh implementation using Vision
  shares this dependency; removing Vision requires new reliability evidence.
- **Memory:** this result is for a coloured-cell synthetic document. It does
  not bound arbitrary image entropy, many simultaneously pending captures,
  Vision's successful-allocation path outside the sandbox, or downstream PNG
  encoding. Compression can fall back to raw strips if the compressor fails.
  Production needs the agreed global memory admission/budget handling, tiled
  or downsampled editor proxy, incremental encoding, and a ratified pixel cap.
  The snapshot provider can serve ranges, but a consumer requesting all bytes
  still allocates the 1.18 GB bitmap; retaining many such snapshots is costly.
- **Maintenance:** the matcher is a large inherited heuristic implementation.
  Local storage, ownership, boundary and fallback changes require selective
  upstream comparisons; it is not an unchanged drop-in. Several failure paths
  are intentionally conservative. The trial retains its existing content-only
  output (detected static headers/footers excluded), and the extracted matcher
  initially searches downward movement. App-level behavior must be assessed
  against the eventual scrolling-capture ticket rather than inferred here.
- **Fresh option:** a smaller interface and simpler algorithms could improve
  ownership clarity, but avoiding the existing tuning shifts risk to new
  alignment regressions. If review or real-sequence evidence reveals broader
  correctness problems, the cost advantage could reverse. Reassess then with
  a bounded fresh prototype and the same frozen tests.

## Licence obligations

The locally supplied [BSD-3-Clause licence](../../../docs/licenses/Snapzy-LICENSE)
permits modification and redistribution. Keep the copyright notice,
conditions and disclaimer in source redistributions; reproduce them in binary
redistribution materials; do not imply endorsement by the holder/contributors.
Keep the existing full headers, original banners, pinned revision and hashes in
[ported-files.json](../../../docs/ported-files.json), and describe local changes.
The read-only reference clone remains untouched; the trial stays outside
Frisket's dependency graph until a decision and integration ticket.

A fresh production implementation does not remove attribution duties for any
copied tests, fixture helpers, or other retained upstream material. Reusing the
same ported tests therefore keeps their BSD notices/provenance even if the
production matcher is later replaced. No new project licence is selected.

**Decision handoff:** Prateek chooses port or fresh after the evidence and
recommendation. The ticket's decision criterion remains pending; neither this
report nor passing tests records acceptance of the recommendation.

## Coordinator evidence: Vision outside the sandbox (2026-09-22 23:28)

The Cursor coordinator ran `sh Trials/StitcherTrial/scripts/vision-probe.sh` outside Codex's sandbox, with Xcode 26.5 on x86_64, macOS 26.7 (25G229). `visionAssistedAlignmentProbe()` passed in 0.586 s. The probe requires `usedVisionEstimate == true`, so a pixel fallback can't pass it. The -6662 buffer-allocation failures seen in tickets 04 and 05 occurred inside Codex's sandbox and did not recur outside it; the cause hasn't been isolated. Vision-assisted alignment works on this Mac outside the sandbox. arm64 was not executed.
