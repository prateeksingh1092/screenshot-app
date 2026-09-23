# Ticket 38 — Frisket measurement handoff

All live measurements and target ratification remain pending. This implementation
ran only offline tests, compilation and static checks. The 500 ms thumbnail
placeholder remains unchanged. No measured baseline or low-power GPU confirmation
is claimed. Decision 53 is absent from this checkout; decisions 46 and 49–52 were
read. The ticket-specific brief prohibits live measurement in this session.

## Instrumentation contract

`FRISKET_CAPTURE_LATENCY=1` enables logging for a fresh app process. Other values
and normal launches produce no latency output. The app uses
`clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` for both endpoints, serialized on the
main actor. No timer, polling, wall-clock conversion or cross-process subtraction
is used. The recorder emits exactly one newline-ended JSON row per successfully
submitted thumbnail, containing only integer `run`, `start_ns`, and `end_ns`.
Run numbering starts at 1 per process. Failed/cancelled captures and preview
failures produce no row; a duplicate submission produces no second row. Failed
output disables logging for that process; restart the entire measurement session.

Area start is immediately after the selection result returns, before hiding the
overlay and validating/enqueuing pixels. It excludes prefetch, magnifier setup,
human selection duration, and event delivery before that return. Full-screen start
is after display selection; keep modes in separate sessions. End is after PNG
thumbnail downsampling and `ThumbnailPanel` construction, which calls
`orderFrontRegardless` and posts its accessibility announcement. Thus layout,
window construction and announcement submission are included. The endpoint is
presentation **submission**, not proof of SwiftUI rendering, compositor delivery
or physical display presentation. Ticket 37's external-window proxy has different
endpoints: do not treat a difference as a product regression without calibration.

The app writes numeric rows to inherited stdout; it does not open a measurement
file, save pixels, or add a general-purpose diagnostic sink. The operator redirects
stdout only, leaving stderr separate. Encoding/writing the paired row occurs after
the end sample; clock-read and start-instrumentation overhead remains included.
Nanosecond units do not establish nanosecond accuracy. Effective resolution,
instrumentation overhead, and submission-to-display bias are unmeasured; ticket
40 must record calibration evidence before using timings to ratify visibility.

## Operator runbook — execute later with Prateek

Reuse the existing [ticket 37 runbook](37-performance-baselines.md),
`Tools/Performance/build-probe.sh`, `measure.py`, and `baseline.py` unchanged as
entry points. No merge-time copy or replacement script is needed on this branch.
Resolve its reference-tool storage and endpoint-calibration blockers first.

1. Use a verified signed build at the established installed location. Prepare a
   fresh output directory, quiet machine, AC power, nominal thermal conditions,
   fixed synthetic area/scale/display, and no sleep during runs. Record app build,
   OS build, architecture, capture mode, numeric geometry and display refresh rate.
   Do not change GPU policy. Confirm the active low-power GPU with Prateek using
   ticket 37's procedure; the hardware inventory alone is insufficient.
2. Start a fresh Frisket process with the environment flag and stdout redirected.
   Example for the **operator only**, from the repo root, after creating a new
   empty `.build/performance/38-session` directory and quitting any old instance:

   ```sh
   FRISKET_CAPTURE_LATENCY=1 "$HOME/Applications/Frisket.app/Contents/MacOS/Frisket" \
     > .build/performance/38-session/frisket-clock.jsonl
   ```

   Leave that terminal running. No app launch was executed by this implementer.
   Never reuse/truncate a previous session's evidence. Do not capture before ARMED.
3. In another terminal, reuse the baseline harness:

   ```sh
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   bash Tools/Performance/build-probe.sh
   /usr/bin/python3 -B Tools/Performance/measure.py app-latency \
     --operator-approved --log .build/performance/38-session/frisket-clock.jsonl \
     --output .build/performance/38-session/frisket-latency.json
   ```

   Each of 20 runs requires five continuous cool-down minutes and ARMED before
   Prateek captures only the synthetic area. Delete each pending thumbnail using
   its Delete control; Dismiss/Escape/Quit commits to History and is unsuitable
   for no-storage measurement. No full-screen capture or clipboard operation is
   part of this protocol. Any failure, extra capture, mixed mode, malformed row,
   interrupted condition or timeout invalidates the session; restart with a new
   process and new empty log. Do not cherry-pick successful captures after failure.
4. With no pending thumbnail, identify Frisket's PID and collect idle data using
   the same menu-bar idle state and instrumentation setting. Substitute its PID:

   ```sh
   /usr/bin/python3 -B Tools/Performance/measure.py idle --tool frisket \
     --pid 12345 --operator-approved \
     --output .build/performance/38-session/frisket-idle.json
   /usr/bin/python3 -B Tools/Performance/measure.py report \
     --idle .build/performance/38-session/frisket-idle.json \
     --latency .build/performance/38-session/frisket-latency.json \
     --output .build/performance/38-session/frisket-report.md
   ```

   Idle is 20 runs of at least 600 seconds, each after 300 seconds of cool-down;
   budget roughly five hours. CPU uses process CPU-time deltas, wakeups use both
   kernel counters, and footprint uses end and sampled maximum bytes. Retain raw
   numeric evidence. Reconfirm GPU and thermal conditions at the end. Existing
   harness flags remain until independently supported operator evidence exists.

## Comparison shape for ticket 40 / Prateek

Every numeric cell should contain median / nearest-rank p95 and an evidence link
for exactly 20 valid runs. Pending is not zero. Separate capture modes, builds and
architectures; record nonresident macOS idle as not measurable when appropriate.

| Metric / endpoint | macOS baseline | Snapzy baseline | Frisket | Proposed target + rationale | Prateek ratification / date |
| --- | --- | --- | --- | --- | --- |
| External mouse-release → window proxy (ms) | Pending | Blocked by storage policy | Not the app-clock endpoint | Pending calibration | Pending |
| App selection-accepted → submission (ms) | Unavailable | Unavailable | Pending | 500 ms visibility placeholder retained; endpoint mapping pending | Pending |
| Idle CPU (% of one core) | Pending / nonresident | Pending | Pending | Pending; existing <1% placeholder retained | Pending |
| Package idle wakeups / second | Pending | Pending | Pending | Pending | Pending |
| Interrupt wakeups / second | Pending | Pending | Pending | Pending | Pending |
| Footprint end / sampled peak (bytes; separate summaries) | Pending | Pending | Pending | Pending | Pending |
| Active low-power GPU evidence | Pending | Pending | Pending | Confirmation required | Pending |
| Clock resolution / overhead / display calibration | Pending | Pending | Pending | No numeric error claim yet | Pending |

Scrolling peak memory is outside this capture-to-thumbnail measurement; its
existing <2 GB placeholder is unchanged. Ticket 40 and Prateek must fill the
comparison, resolve non-comparable endpoints, choose targets and only then record
accepted ratification in decisions.md. This ticket does not ratify any target.
