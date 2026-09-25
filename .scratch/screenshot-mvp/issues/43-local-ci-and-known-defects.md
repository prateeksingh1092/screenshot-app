# 43: Local CI, pre-push hook and known-defect tests

**What to build:** One command says whether the tree can merge: `scripts/ci.sh` runs the repository checks, the package tests and the unsigned app build, and a pre-push hook runs it (decision 57, DA-7). The event-tap and global-monitor check moves from every Xcode build into `ci.sh`. A new rule rejects network APIs anywhere in the product (story 74). Tests that reproduce a known defect are marked so the suite stays green while they are red, and they fail the moment the defect is fixed, so the fix must remove the mark.

**Blocked by:** 42

**Phase:** 0

**Status:** ready-for-agent

- [ ] `scripts/ci.sh` runs the repository checks, `swift test` and the unsigned Xcode build, and exits non-zero on any failure.
- [ ] A tracked pre-push hook runs `ci.sh`, and the build doc says how to enable it.
- [ ] The "Reject Event Taps and Global Monitors" build phase is gone from the project. The same check runs in `ci.sh` and in the Swift suite, with its fixtures unchanged.
- [ ] A no-network rule fails on networking APIs in product code, with passing and failing fixtures.
- [ ] `@_silgen_name` in product code fails the checks, except for the listed D22 uses, which are reported as known defects until tickets 63 and 67 remove them.
- [ ] A known-defect wrapper passes only while its body records a failed expectation. It fails when the body passes, and a thrown error is never hidden as the known defect. `FRISKET_SHOW_DEFECTS=1` runs the bodies unwrapped, so the reds can be seen.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
