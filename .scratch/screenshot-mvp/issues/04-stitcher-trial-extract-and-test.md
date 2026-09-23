# 04: Stitcher trial, part 1: extract and test

**What to build:** Snapzy's scrolling stitcher, copied from the read-only reference clone, compiles on its own in a scratch package and its deterministic tests pass on this Intel Mac as Swift Testing tests.

**Blocked by:** 02, 03 (ticket 02 found the Command Line Tools lack the Swift Testing module; running tests needs Xcode's toolchain)

**Status:** resolved (tested on `main` at `8594af5`)

- [x] The stitcher and its image factory are copied into a scratch package, not into Frisket's core; the Snapzy clone is not modified.
- [x] Its BSD-3 header is kept and the source commit is recorded.
- [x] Its tests are converted to Swift Testing first (decision 41) and pass under `swift test`.
- [x] Any dependency it needs beyond Foundation, Core Graphics, and Vision is listed.
- [x] The time spent and the changes needed are recorded for the cost comparison in ticket 5.
- [x] Builds need Prateek's approval at the time.

## Comments

### 2026-09-22 — coordinator integration and close

- Implemented by Codex (GPT-6 Astra, high); report in `../reports/04-implementer.md`. Fresh Codex review against `4378b35`: Standards 0, Spec 0, verdict merge (`../reviews/04-code-review-codex.md`).
- Integration branch `integrate/04` on Xcode 26.5, x86_64, macOS 26.7 (25G229): root suite passed (3 tests, all fixtures and repository checks); trial suite passed (22 tests), also when run outside Codex's sandbox. arm64 was not executed.
- Carried to ticket 05: Vision returned -6662 (buffer allocation) in the implementer's probe inside Codex's sandbox. No test yet requires a successful Vision estimate.
- `main` fast-forwarded to `8594af5`.
