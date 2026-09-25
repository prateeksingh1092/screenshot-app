# Ticket 37 operator runbook — measurements pending

No baseline has been collected. Codex built only the metadata probe and ran offline
tests/dry runs. Launches, permissions and capture by Screenshot or Snapzy require
Prateek's approval at the time; decisions 46/50 do not grant that approval. Nothing
here invokes Instruments, event taps, Accessibility automation, synthetic input,
clipboard operations, or a capture API. The operator launches the target and performs
each capture by hand. No captured images may be saved, including temporary images.

## Current blockers and honest limits

1. **Snapzy capture cannot satisfy the no-image-storage constraint.** At reference
   `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`,
   `Snapzy/Services/Capture/ScreenCaptureManager.swift` saves before returning the
   capture URL. `PostCaptureActionHandler.swift` passes that URL to Quick Access;
   `TempCaptureManager.swift` writes to Application Support even with Auto-save off.
   Disabling History or deleting afterwards does not prevent those writes. The
   harness no longer offers a `snapzy` tool (ticket 80). Do not patch the
   reference or pretend a patched persistence path is an unmodified baseline.
   The coordinator must resolve this constraint with Prateek before Snapzy latency
   can be measured. Idle measurement does not capture or need this exception.
2. **Screenshot's no-storage thumbnail route is unverified.** The installed
   `/usr/share/man/man1/screencapture.1` says `-u` presents UI and ignores output
   filenames. Thus `screencapture -u /dev/null` is not a verified discard sink.
   The UI's regular destination and clipboard are also unsuitable. Do not conduct
   a capture to experiment with this while the no-saving rule remains in force.
   `--no-image-storage-verified` is an operator assertion requiring evidence of a
   compliant route, not permission to relax the rule. This remains pending.
3. External latency is **mouse-release-to-thumbnail-window availability**, a
   transparent proxy. It is not a pixel presentation measurement. Window creation
   may precede downsampling/rendering or occur during animation. This systematic
   bias has no established numeric bound; do not ratify the 500 ms target from it.
   Ticket 38 must keep app timing and this proxy labelled separately until an
   approved calibration establishes their relationship. No personal pixels or
   recordings are collected to perform that calibration in this ticket.
4. A nonresident macOS screenshot service has no ten-minute idle PID. Record
   **not resident / not measurable**, never zero. A stable Screenshot toolbar PID
   may be measured with the toolbar left open, but label that state; it is not the
   same as Frisket's menu-bar idle state. The harness deliberately refuses exit,
   counter resets, and PID reuse instead of combining unrelated processes.

## Tooling and setup

From this worktree:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
bash Tools/Performance/build-probe.sh
/usr/bin/python3 -B -m unittest discover -s Tools/Performance -p 'test_*.py'
/usr/bin/python3 -B Tools/Performance/measure.py dry-run --tool macos \
  --output .build/performance/dry-run.md
```

`baseline.py` is the pure parsing/statistics/condition/report interface.
`measure.py` orchestrates it. `probe.swift` reads `proc_pid_rusage(RUSAGE_INFO_V0)`,
ProcessInfo thermal state, mouse-button state, and WindowServer metadata. It has
no image read/write path. `build-probe.sh` builds a host-architecture command-line
executable with workspace module caches and no signing.

Python's standard-library unittest is appropriate for these development scripts:
the repository already invokes Python for offline checks, and this introduces no
application dependency or package resolution. Seven public-seam tests were written
in individual red → green cycles (no refactor phase). The root Swift Testing suite
invokes them through `performanceToolingSatisfiesOfflineChecks`.

The dry run reads real host metadata, conditions, and **its own** process counters,
then feeds 20 fabricated intervals through the same calculations and formatter.
It neither waits ten minutes nor enumerates windows, launches a target, synthesizes
input, or captures. Its report is explicitly labelled synthetic, not a baseline.

## Snapzy baseline — removed

Ticket 80 deleted `build-snapzy.sh` and the `snapzy` tool option in `measure.py`:
the blocker below was never lifted, so no Snapzy baseline is measured. Compare
against macOS Screenshot only.

## Operator sequence

1. Prateek explicitly approves each target's launch and any permitted capture.
   Resolve the storage blockers above first for latency. Keep all current capture
   runs pending. Check Screen Recording permission without granting it unattended.
2. Use the Frisket synthetic test-pattern window from ticket 08. This checkout
   predates that app; use the coordinator's approved build. Position only the
   synthetic pattern in the capture area; exclude title bars, desktop, notifications,
   and every other window. No full-screen captures. Use the same fixed area, scale,
   display, and thumbnail placement for every tool. Record dimensions and display
   refresh rate as numeric operator notes. Never save an image to document setup.
3. Connect AC, disable sleep through normal operator controls if necessary, close
   heavy work, and allow the machine to cool. Do not change GPU policy. Use Activity
   Monitor's Energy view to observe the graphics card in use before and after each
   session, then close Activity Monitor before measurement. Record Intel/AMD/unknown
   and whether a discrete-GPU consumer remains. Record external-display connection.
   `system_profiler` supplies a sanitized adapter inventory, **not active render-GPU
   proof**. Its output here did not even include display attachments. The harness
   conservatively flags low-power GPU unconfirmed; add operator evidence alongside
   the report rather than removing that flag without evidence. Ticket 38 requires
   affirmative confirmation. Do not treat `pmset gpuswitch=2` as proof.
4. For Snapzy, after the separately approved build/signing step, Prateek launches
   that exact app manually. For macOS, Prateek launches Screenshot manually (Finder
   or `open -a Screenshot` in his terminal). **Codex does not run those commands.**
   Disable clipboard, history, upload and updater actions through approved target
   controls. Idle does not require performing a capture. Stop if the target tries
   an unapproved network action; reference Snapzy is not Frisket's local-only app.
5. Identify the PID in Activity Monitor (or `pgrep -x Screenshot` / `pgrep -x Snapzy`
   in the operator's terminal). If macOS delegates the thumbnail to another process,
   use its actual owner PID for latency and record that difference. This harness
   measures the specified process, excluding WindowServer, kernel, and helper CPU.
   Do not claim whole-system energy or aggregate unrelated PIDs.
6. Run idle measurements, substituting the PID and target token:

   ```sh
   /usr/bin/python3 -B Tools/Performance/measure.py idle --tool macos \
     --pid 12345 --operator-approved --output .build/performance/macos-idle.json
   # Screenshot is the only comparison target (ticket 80 removed the Snapzy baseline).
   ```

   Each of **20 runs** has five continuous nominal minutes of cool-down followed
   by at least 600 monotonic seconds. Budget approximately five hours per target
   for idle plus cool-down. Do not interact with the target during idle. Counters
   and conditions are sampled about every five seconds. AC loss, non-nominal
   thermal state, reported CPU speed/scheduler limits below 100, a stale sampler,
   process exit, or PID reuse aborts the session. Partial files cannot produce a
   final report. Start a fresh session after correcting conditions; do not cherry-pick
   failed runs or substitute zeroes. Five-second polling cannot rule out shorter
   power/thermal excursions; report any operator-observed anomaly too.
7. **After the latency storage blockers are resolved**, calibrate which PID and
   bounds correspond exclusively to a thumbnail. Use this numeric-only inventory
   before and during an approved synthetic capture, without saving images:

   ```sh
   .build/performance/probe inventory --operator-approved 12345
   ```

   It prints only window IDs and rectangles for that PID, not names or titles.
   Coordinates are global screen **points**. Compare the rectangles to the visible
   synthetic thumbnail and record x/y/width/height. Clear the previous thumbnail.
   No matching window may exist when the next run starts. If geometry changes,
   re-calibrate and restart the session, rather than relaxing matching after the fact.
8. Conditional macOS latency command, with calibrated numeric values:

   ```sh
   /usr/bin/python3 -B Tools/Performance/measure.py latency --tool macos \
     --pid 12345 --thumbnail-rect 1000 650 250 180 \
     --operator-approved --no-image-storage-verified \
     --output .build/performance/macos-latency.json
   ```

   These bounds are **examples**, not this machine's calibration. The command
   waits for Return, cools down five minutes, then prints ARMED. Only then enter
   area capture using a human shortcut and drag inside the synthetic pattern.
   Release the mouse to finish selection. Do not click unrelated UI while armed.
   Confirm the detected window was the thumbnail. Repeat 20 times, clearing the
   thumbnail by the previously verified no-storage route. A mismatched window,
   timeout, bad conditions or operator rejection invalidates the session.
   Snapzy uses the same observer design, but its CLI is blocked until persistence
   policy is resolved. No capture happens just by running the observer.
9. Generate a report only from two complete sessions for the same target/build/arch:

   ```sh
   /usr/bin/python3 -B Tools/Performance/measure.py report \
     --idle .build/performance/macos-idle.json \
     --latency .build/performance/macos-latency.json \
     --output .build/performance/macos-report.md
   ```

   Keep raw **numeric** observations with the report. Record target version,
   idle state, PID role, test rectangle/scale, GPU observations and calibration
   limitations in operator notes. No captured images, titles or clipboard data.
   Do not submit the dry run as baseline evidence. No performance target is ratified
   by this ticket; Prateek ratifies after ticket 38's comparable measurements.

## Definitions and error bars

- CPU percentage = `100 * Δ(ri_user_time + ri_system_time) / Δmonotonic_ns`.
  Kernel CPU counters are nanoseconds; 100% means one fully occupied logical CPU.
  This is interval CPU time, not an instantaneous `ps %cpu` or a sampled average.
- Wakeups = differences of `ri_pkg_idle_wkups` and `ri_interrupt_wkups`, each
  divided by actual elapsed seconds. They are distinct kernel counters; neither
  is a count of every scheduler wakeup. An unavailable counter read is an error.
- Footprint = `ri_phys_footprint` bytes, reporting interval-end and maximum sampled
  values. This is not RSS; a five-second sample cadence can miss transient peaks.
- Start bracket `[s0,s1]`: before the last observation of the human-held left
  button, through after the first observation of it released. No event tap or
  synthetic keypress is installed. HID delivery/dispatch time is not measured.
- End bracket `[e0,e1]`: before the last absent matching-window query, through
  after the first present matching-window query. The observer uses
  `CGWindowListCopyWindowInfo`, the calibrated owner PID, positive alpha and bounds
  within four points. More than one match is rejected. Polling sleeps 5 ms, but
  actual query and scheduling durations determine the brackets.
- Latency lies in `[max(0,e0-s1), e1-s0]` for these **observed state transitions**.
  Report midpoint ± half-width, in milliseconds, for every run. Two exact 5 ms
  brackets would yield ±5 ms; this is an example, not a promised error bar.
  Median/p95 are also calculated for lower and upper bounds. There is no fixed
  ±5 ms claim for real runs. The window-to-visible-pixels and physical-release-to-HID
  systematic errors remain **uncalibrated**, outside these bounds.
- Statistics: exactly 20 accepted runs, median = mean of sorted values 10 and 11,
  p95 = nearest-rank value 19. These are descriptive statistics, not confidence
  intervals. A report requires all 20 idle and all 20 latency runs.

Local primary references used without network: the installed SDK's `libproc.h`,
`sys/resource.h`, CoreGraphics/Foundation interfaces, the installed screencapture
manpage, and the pinned Snapzy source/Package.resolved. No upstream code was ported.

## Ticket 38 interface

Reuse `idle --tool frisket --pid ...` unchanged. Use app logging for latency:

```sh
/usr/bin/python3 -B Tools/Performance/measure.py app-latency \
  --operator-approved --log .build/performance/frisket-clock.jsonl \
  --output .build/performance/frisket-latency.json
```

The log must initially be absent/empty. The app appends one complete newline-ended
JSON object per capture: `{"run":1,"start_ns":1000000000,"end_ns":1100000000}`,
numbered 1 through 20, containing **only these numeric fields**. Use one monotonic
nanosecond clock within the process (e.g. the same CLOCK_MONOTONIC_RAW helper).
Log start when the final selection is accepted and capture work is enqueued; log
end after thumbnail downsampling and its presentation submission. Document that
submission still differs from physical display presentation. Do not mix wall
clock, ticks, boot sessions, or clocks from different processes. The app writes the
paired row only when both events exist, avoiding a polling-derived latency.

The operator waits for ARMED after each cool-down, then performs one synthetic
capture. The harness monitors conditions while awaiting each row. It imports the
clock interval directly, with zero **polling** error; clock resolution and logging
overhead still need characterization by ticket 38. The report command above works
unchanged with Frisket idle and app-latency files. No app changes are made here.

## Pending for Prateek/coordinator

- Resolve the reference-tool no-storage conflict and validate external endpoint
  semantics/error before collecting latency. Do not bypass the Snapzy refusal.
- Approve package network resolution and any necessary signing; build and verify
  the scratch Snapzy app without altering the reference clone.
- Approve/perform target launches and synthetic-only captures, permissions,
  GPU confirmation, geometry calibration, 20-run measurements, and report review.
- Run the remaining ticket 08 permission/launch checks through its own checklist.
  Real performance numbers, target comparisons and target ratification remain pending.
