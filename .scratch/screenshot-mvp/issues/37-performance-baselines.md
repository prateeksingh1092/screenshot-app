# 37: Performance baselines: macOS tool and Snapzy

**What to build:** scripted, repeatable measurements of the built-in macOS screenshot tool and Snapzy on this Mac, so Frisket's targets rest on real numbers.

**Blocked by:** 03

**Status:** resolved (tooling tested on `main` at `c49b958`; the Snapzy build and live baselines are pending Prateek, decision 49)

- [x] A script measures idle CPU from process CPU time over 10 minutes, idle wakeups, memory footprint, and capture-to-thumbnail latency, without Xcode instruments.
- [ ] (Tooling done; runs and GPU confirmation pending) Conditions: AC power, thermally unthrottled, after cool-down, 20 runs, median and p95; the GPU in use is recorded.
- [ ] (Script done and reviewed; build deferred) Snapzy is built from the read-only clone into a scratch location; the clone is not modified.
- [x] Each report records date, OS build, and architecture, with no personal pixels.
- [x] Builds, launches, and screen capture need Prateek's approval at the time.

## Comments

### 2026-09-23 — coordinator: resolved (baselines pending)

- **Implementer:** Codex GPT-6 Astra, high. Report: `reports/37-implementer.md`, which includes the Fix pass.
  - Tooling lives in `Tools/Performance/`: the probe, `measure.py`, `baseline.py`, tests and `build-snapzy.sh`.
  - Ticket 38 reuses `idle --tool frisket`, `app-latency` and `report`.
- **Review:** fresh Codex, `reviews/37-code-review-codex.md`, verdict fix-then-merge. One fix pass addressed all three findings:
  - capture rows written before arming are rejected;
  - cooldown aborts on sampling stalls;
  - `measure.py` and `baseline.py` share one row parser.
- **Integration:** `integrate/37` passed the root `swift test` (59 tests in 8 suites, which include the Python tooling tests) and the unsigned `xcodebuild`. One trivial conflict in `docs/core-package.md` was resolved by keeping both sides. x86_64 only; arm64 not executed.
- **Snapzy build:** `bash Tools/Performance/build-snapzy.sh --coordinator-build` stopped at an approval prompt at 01:12 and was interrupted. Under the 01:20 directive, only allowlisted commands run outside the sandbox, so the build is deferred to Prateek.
  - Run it from a fresh checkout of `main`, or delete `.build/snapzy-baseline/` first. The script refuses to run if that folder exists.
- **Pending for Prateek:**
  - approval to launch Snapzy and the macOS screenshot tool and let them capture;
  - GPU confirmation;
  - latency calibration and the 20-run baselines, following `docs/manual-checks/37-performance-baselines.md`.
