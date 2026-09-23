# 16: Retention and quota

**What to build:** History keeps captures for 30 days or up to 1 GB, whichever comes first, both configurable, removing the oldest first and telling Prateek when size eviction happened.

**Blocked by:** 09, 11

**Status:** resolved (tested on `main` at `cd0dd99`; Settings/VoiceOver retention manual pending)

- [x] Usage is the recorded logical sizes of all app-owned files plus the database, WAL, and shared-memory files, re-measured at launch; a failed size read blocks the commit.
- [x] Enforcement runs after each commit from indexed stored sizes, oldest first, with deterministic tie-breaking for equal timestamps.
- [x] A single capture larger than the size limit is refused from History with a notice while copy, save, and drag still work (decision 27).
- [x] Age eviction is deferred when the clock looks anomalous (earlier than the newest capture, or jumped past the last sweep by more than the retention window); future-dated captures are normalized once.
- [x] Quota eviction emits an event shown as a one-time notice and a Settings line.
- [x] Settings exposes retention days and size limit.
- [x] Eviction's interruption points get crash cases; seam 1 tests cover each rule with a stand-in clock.

## Comments

- **Integration:** `integrate/16-22-24` fast-forwarded `main` to `cd0dd99`. Coordinator kept launch recovery, editor/clipboard replacement, and drag, and added retention/quota plus Settings. Failed `imageWriteAttempted` writes surface as `.recoveryRequired`. The launch-gate recovery test uses a 40_000-day window so 1970 crash-helper rows are not also an age-eviction case. Root `swift test`: 210 tests in 31 suites passed. Unsigned x86_64 `xcodebuild` succeeded (`CODE_SIGNING_ALLOWED=NO`). x86_64 only; arm64 not executed. Codex and Cursor Other Models were already past included-usage limits, so this pass ran in the coordinator chat.
