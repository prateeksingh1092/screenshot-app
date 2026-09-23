# 37: Performance baselines: macOS tool and Snapzy

**What to build:** scripted, repeatable measurements of the built-in macOS screenshot tool and Snapzy on this Mac, so Frisket's targets rest on real numbers.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] A script measures idle CPU from process CPU time over 10 minutes, idle wakeups, memory footprint, and capture-to-thumbnail latency, without Xcode instruments.
- [ ] Conditions: AC power, thermally unthrottled, after cool-down, 20 runs, median and p95; the GPU in use is recorded.
- [ ] Snapzy is built from the read-only clone into a scratch location; the clone is not modified.
- [ ] Each report records date, OS build, and architecture, with no personal pixels.
- [ ] Builds, launches, and screen capture need Prateek's approval at the time.

## Comments
