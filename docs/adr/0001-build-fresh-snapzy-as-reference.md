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

The scrolling stitcher that was briefly adapted from that project has been removed. Frisket's stitcher is its own code. Nothing from that project is shipped.

## Stitcher trial outcome (decision 48)

Decision 48 accepted a port after ticket 05 met the synthetic memory gate and
the coordinator verified Vision outside the sandbox. That port was later
removed. The stitcher that ships is Frisket-owned code, and
nothing is ported (the empty `docs/ported-files.json` ledger and its provenance check were deleted by ticket 80). Real recorded sequence acceptance remains
pending authorized captures; see the stitcher documentation (`docs/stitcher.md`, deleted by ticket 87).
The broader fresh-build decision remains in force.

## Superseded note: scrolling capture removed (decision 60, 2026-09-25)

Scrolling capture has been removed from Frisket (ticket 87), so the stitcher and
its documentation no longer exist. The last commit that has them is tagged
`scrolling-capture-last`. The sections above are kept as history. The
fresh-build decision itself is unchanged.
