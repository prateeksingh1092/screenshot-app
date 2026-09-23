# 38: Frisket performance measurement and target ratification

**What to build:** Frisket is measured with the same script as the baselines, and Prateek ratifies its performance targets.

**Blocked by:** 08, 37

**Status:** resolved (instrumentation tested on `main` at `f9dbbb2`; live GPU, quiet-Mac baselines, and target ratification pending)

- [x] Latency comes from app-logged monotonic timestamps; idle CPU, wakeups, and footprint as in ticket 37.
- [ ] The low-power GPU is confirmed.
- [ ] A comparison against the baselines proposes targets, replacing the 500 ms placeholder.
- [ ] Prateek ratifies the targets; they are recorded in the decisions file.

## Comments

### 2026-09-23 — coordinator note

Decision 54 / `reports/54-snapzy-baseline.md`: v1 comparison is macOS Screenshot only. Do not wait for a Snapzy Release build. Propose targets from Frisket vs macOS numbers; keep 500 ms as placeholder until those numbers exist. Snapzy remains a later optional comparator.

- **Integration:** `integrate/35-38` fast-forwarded `main` to `f9dbbb2`. `FRISKET_CAPTURE_LATENCY=1` logs numeric-only monotonic rows. Live GPU confirmation, quiet-Mac baselines, and target ratification remain Prateek's. `swift test`: 234 tests in 36 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits.
