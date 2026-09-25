# 43: Local CI, pre-push hook and known-defect tests

**What to build:** One command says whether the tree can merge: `scripts/ci.sh` runs the repository checks, the package tests and the unsigned app build, and a pre-push hook runs it (decision 57, DA-7). The event-tap and global-monitor check moves from every Xcode build into `ci.sh`. A new rule rejects network APIs anywhere in the product (story 74). Tests that reproduce a known defect are marked so the suite stays green while they are red, and they fail the moment the defect is fixed, so the fix must remove the mark.

**Blocked by:** 42

**Phase:** 0

**Status:** resolved (see Comments for the `main` commit)

- [x] `scripts/ci.sh` runs the repository checks, `swift test` and the unsigned Xcode build, and exits non-zero on any failure.
- [x] A tracked pre-push hook runs `ci.sh`, and the build doc says how to enable it.
- [x] The "Reject Event Taps and Global Monitors" build phase is gone from the project. The same check runs in `ci.sh` and in the Swift suite, with its fixtures unchanged.
- [x] A no-network rule fails on networking APIs in product code, with passing and failing fixtures.
- [x] `@_silgen_name` in product code fails the checks, except for the listed D22 uses, which are reported as known defects until tickets 63 and 67 remove them.
- [x] A known-defect wrapper passes only while its body records a failed expectation. It fails when the body passes, and a thrown error is never hidden as the known defect. `FRISKET_SHOW_DEFECTS=1` runs the bodies unwrapped, so the reds can be seen.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, resolved

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, medium effort), on branch `ticket/43-local-ci-and-known-defects`.
- **`scripts/ci.sh`:**
  - It runs the 10 repository checks, then `scripts/test-core.sh` (now executable), then an unsigned `xcodebuild -quiet` for the host architecture, and prints `ci: green`.
  - `--defects` runs `FRISKET_SHOW_DEFECTS=1` over the tests matching `[./]d[0-9]+[A-Z]` and lists the defects still red, plus any wrapper whose defect is already fixed.
- **Hook:** `.githooks/pre-push` runs `ci.sh`. `core.hooksPath` is set on this clone.
- **Checks:**
  - `network`: networking modules and APIs are rejected. A `func connect(...)` declaration is not a call.
  - `silgen`: `@_silgen_name` is rejected except for the six listed D22 uses; `--strict` reports those too.
  - Each has 2–3 fixtures, and both are wired into `RepositoryChecksTests`.
  - The "Reject Event Taps and Global Monitors" build phase is removed. `BuildGraphTests` asserts that no build phase runs `check_repository.py` and that `ci.sh` runs `input-monitoring`.
- **Known defects:**
  - `knownDefect(_:_:)` exists in both test targets.
  - It matches only `.expectationFailed` issues whose comment names the ID (`"D1: …"`).
  - Five self-tests in `KnownDefectTests` cover: passes while red; fails once fixed; never hides a thrown error; never hides an expectation that doesn't name the defect; show mode runs unwrapped.
  - The first known defect is `d22ProductCodeBindsNoCFunctionThroughSilgenName`.
- **Evidence:** `scripts/ci.sh` is green in 36 s: 292 tests in 45 suites passed with 8 known issues, and the unsigned build succeeded. `ci.sh --defects` lists d22 as red. x86_64 only.
