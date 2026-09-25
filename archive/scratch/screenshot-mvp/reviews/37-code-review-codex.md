# Ticket 37 — fresh Codex review (GPT-6 Astra, high), 2026-09-23

Fixed point `71002db`, snapshot `cf8bb57`.

**Standards**

- **Nit — `Tools/Performance/measure.py:165`:** app-log validation duplicates `baseline.parse_app_log`, and the two have already drifted. The live parser accepts `true` as run 1, so the bad value is only rejected after all 20 runs finish. A shared row parser would prevent this drift. This is a design judgement, not a hard standards violation.

**Spec**

- **Should-fix — `Tools/Performance/measure.py:152`:** `app_latency` accepts a capture row written during cooldown, before ARMED, and can include it in a completed baseline. Reject pre-arming rows, and test this through the orchestration interface.
- **Should-fix — `Tools/Performance/measure.py:64`:** cooldown counts elapsed time without detecting sampling stalls. A long suspension followed by one good reading can satisfy "five uninterrupted nominal minutes". Apply continuity checks like the idle loop's.

These are correct:

- the CPU-time calculation, wakeup counters and physical footprint;
- the median and the nearest-rank p95.

These are disclosed honestly:

- GPU uncertainty;
- latency's uncalibrated systematic errors.

Snapzy's build uses an archived source tree under `.build/`, which protects the reference clone. The added tooling has none of the following: event taps, synthetic input, global monitors, Instruments, launches, capture calls, or pixel storage.

All **16 Swift tests and 7 Python tests passed** on x86_64, macOS 26.7 (25G229); arm64 was not executed. Python tests run through the root suite. Live baselines, storage-route validation and operator approvals remain explicitly pending.

Verdict: fix-then-merge
