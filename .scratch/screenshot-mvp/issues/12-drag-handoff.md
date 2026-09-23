# 12: Drag handoff with file promises

**What to build:** dragging a thumbnail into another app hands over a copy of the rendered image; dropping it on the Trash or moving it can't touch History.

**Blocked by:** 09

**Status:** in-progress (branch `ticket/12-drag-handoff`)

- [ ] Drag uses a file promise of the rendered revision with a copy-only operation, through the shared finalization policy.
- [ ] Each staging file stays until the promise's write completion has returned and the drag session has ended, then is deleted; leftovers are removed by the launch sweep.
- [ ] New interruption points are added to the commit-point list with tier 1 and tier 2 cases.
- [ ] Seam 1 tests use a recording drag stand-in; one manual check drags into Finder and onto the Trash.

## Comments
