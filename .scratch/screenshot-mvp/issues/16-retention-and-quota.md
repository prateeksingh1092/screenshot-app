# 16: Retention and quota

**What to build:** History keeps captures for 30 days or up to 1 GB, whichever comes first, both configurable, removing the oldest first and telling Prateek when size eviction happened.

**Blocked by:** 09, 11

**Status:** in-progress (branch `ticket/16-retention-and-quota`)

- [ ] Usage is the recorded logical sizes of all app-owned files plus the database, WAL, and shared-memory files, re-measured at launch; a failed size read blocks the commit.
- [ ] Enforcement runs after each commit from indexed stored sizes, oldest first, with deterministic tie-breaking for equal timestamps.
- [ ] A single capture larger than the size limit is refused from History with a notice while copy, save, and drag still work (decision 27).
- [ ] Age eviction is deferred when the clock looks anomalous (earlier than the newest capture, or jumped past the last sweep by more than the retention window); future-dated captures are normalized once.
- [ ] Quota eviction emits an event shown as a one-time notice and a Settings line.
- [ ] Settings exposes retention days and size limit.
- [ ] Eviction's interruption points get crash cases; seam 1 tests cover each rule with a stand-in clock.

## Comments
