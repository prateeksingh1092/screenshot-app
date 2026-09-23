Implemented the tooling; live baselines remain pending. Stopped before review, staging, or commit. Ticket status and checkboxes are unchanged.

`Tools/Performance/` contains the Swift metadata probe, Python measurement/report interface, tests, and isolated Snapzy build script. Ticket 38 reuses `idle --tool frisket`, `app-latency` (numeric `run/start_ns/end_ns` logs), and `report`.

External latency brackets human mouse release and matching thumbnail-window arrival, without event taps or synthetic input. Reports calculate actual polling error bounds per run; ±5 ms is only an example for two 5 ms brackets. Window-to-visible-pixels bias remains uncalibrated, so this proxy cannot yet ratify the visible-thumbnail target.

Verification on **x86_64, macOS 26.7, build 25G229; arm64 not executed**:

- Seven Python tests passed after individual red → green cycles, without refactoring:
  `/usr/bin/python3 -B -m unittest discover -s Tools/Performance -p 'test_*.py'`.
- Full Swift suite: **16 tests passed**, including six repository checks and 21 fixtures. With pinned Xcode and cache environment from `docs/core-package.md`:
  `swift test --disable-sandbox --disable-keychain --disable-xctest --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security`.
- `bash Tools/Performance/build-probe.sh`, shell syntax checks, and `measure.py dry-run --tool macos --output .build/performance/dry-run.md` passed. Dry run observed AC/nominal thermal state; active GPU remains unconfirmed.

Snapzy build command, **not executed; coordinator required for dependency-resolution network access**:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/Performance/build-snapzy.sh --coordinator-build
```

It builds unsigned under `.build/`, preserving the reference clone. Signing remains separate.

Pending for Prateek: follow `docs/manual-checks/37-performance-baselines.md`; approve launches/captures, confirm GPU, resolve no-image-storage routes, calibrate latency, and collect 20-run baselines. Snapzy persists captures even with Auto-save off, so its latency command refuses execution. Screenshot's no-storage thumbnail route also remains unverified.
