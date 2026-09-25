# 83: Remediation acceptance

**What to build:** The remediated Frisket is accepted on this Mac:

- `ci.sh` is green;
- the live matrix is green on both displays;
- the §1.3 CleanShot rows are marked met or intentionally different;
- Prateek runs the checks the harness can't automate: missing and revoked permission, logout and lock, display unplug, first launch;
- performance is re-measured;
- ticket 40 is closed on a tree rebased onto the remediated `main`;
- every DA item is recorded in `decisions.md`.

**Blocked by:** 42–82, 84–86

**Phase:** 6

**Status:** ready-for-human

- [ ] `ci.sh` is green, and the live matrix is green on both displays.
- [ ] The §1.3 rows are marked met or intentionally different.
- [ ] The manual checks needing a person are recorded, with date, OS build, commit and display layout.
- [ ] `Tools/Performance`, capture-to-Thumbnail latency and the editor memory run at 5,120 × 32,768 are re-measured.
- [ ] The stale `.worktrees/ticket-40` is rebased or recreated from `main`, and ticket 40 is closed.
- [ ] Every DA item appears in `decisions.md`.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
