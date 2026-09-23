# 04: Stitcher trial, part 1: extract and test

**What to build:** Snapzy's scrolling stitcher, copied from the read-only reference clone, compiles on its own in a scratch package and its deterministic tests pass on this Intel Mac as Swift Testing tests.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] The stitcher and its image factory are copied into a scratch package, not into Frisket's core; the Snapzy clone is not modified.
- [ ] Its BSD-3 header is kept and the source commit is recorded.
- [ ] Its tests are converted to Swift Testing first (decision 41) and pass under `swift test`.
- [ ] Any dependency it needs beyond Foundation, Core Graphics, and Vision is listed.
- [ ] The time spent and the changes needed are recorded for the cost comparison in ticket 5.
- [ ] Builds need Prateek's approval at the time.

## Comments
