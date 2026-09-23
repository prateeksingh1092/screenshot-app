---
status: accepted
---

# Build Frisket fresh, with Snapzy as a read-only reference

Snapzy (BSD-3-Clause) is the closest open-source match for this app, so a reader will expect us to have forked it or ported its parts. We didn't: its renderer, capture overlay, capture engine, and database layer carry designs our invariants forbid (unredacted originals persisted, styled-rectangle redaction and blur that samples the original, no ownership or finalization state in the schema, pointer-only thumbnail), and its capture path depends on CoreGraphics capture calls obsoleted in macOS 15 and on `sharingType = .none`, which ScreenCaptureKit ignores. Removing those while keeping callers working costs more than writing small, fresh code around our own invariants, and fresh code lets the invariants live in the types. We read Snapzy's code, docs, and fixed bugs to write our test cases and manual checklist instead.

## Considered Options

- **Fork Snapzy:** rejected; the capture-lifecycle invariant cuts across its plumbing, so we would diverge and lose upstream merges anyway.
- **Port selected parts:** the original decision 13; rejected after the red-team review found every candidate except the stitcher tangled with those designs.
- **Clean room (never read Snapzy):** rejected; BSD-3 gives it no legal benefit, and it discards years of recorded multi-display, Spaces, and scrolling fixes.

## Consequences

The scrolling stitcher is the one exception under consideration, because it is pure image processing and its alignment tuning is empirical work Snapzy has already done. It is ported only if a trial shows it compiles alone, passes its tests on the Intel development Mac, fits the 2 GB scrolling budget after moving to strip storage, and costs less than a fresh implementation. Any ported file keeps its BSD-3 header and a provenance entry.
