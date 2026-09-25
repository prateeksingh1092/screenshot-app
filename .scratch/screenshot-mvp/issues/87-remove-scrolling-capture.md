# 87: Remove scrolling capture

**What to build:** Scrolling capture is gone from the product, the code, the tests, the checks, the harness and the docs (decision 60). The inventory, the timing and the steps are in `Plans/2026-09-25-remove-scrolling-capture.md`.

**Blocked by:** none (it runs before 65 and 73)

**Phase:** 1b

**Status:** ready-for-agent (high effort)

- [ ] Tag `scrolling-capture-last` on the last commit that has scrolling.
- [ ] No menu item, no ⌘⇧6 hotkey, no `ManualScrollingCapture`.
- [ ] No `.captureScrolling` command, no scrolling outcomes or budgets, no `Sources/FrisketCore/Stitcher/`.
- [ ] Scrolling tests, fixtures, check rules and harness rows are removed. `ci.sh` is green.
- [ ] The stories are marked retired, and `CLAUDE.md`, the ADR, the docs and the plan are updated. Tickets 75 and 80 are unblocked.
- [ ] Live check, at most 15 minutes on one display: the area, window and full rows pass; ⌘⇧6 does nothing.
