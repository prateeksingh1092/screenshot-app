# 17: History database failure mode

**What to build:** if the History database can't be opened or migrated, History turns off with a visible notice and a recovery option, while capturing, copying, saving, and dragging keep working (decision 40).

**Blocked by:** 09, 11, 12

**Status:** ready-for-agent

- [ ] Open and migration failures (corrupt file, unknown migration, permission denied) put History in a disabled state without writing to the database.
- [ ] A visible notice and a recovery option are shown; the recovery never erases the database silently.
- [ ] Seam 1 tests prove capture, copy, save, and drag still succeed in the disabled state, and that dismiss behaves safely without History.

## Comments
