# 52: Saved edits match the editor (interim)

**What to build:** Until the native renderer lands, the Done, Copy, Save and drag output of an edited capture is rendered in one pass by the same function the editor preview uses. Arrows, labels, Blur and Magnify are then never lost or repeated at strip boundaries (D1, story 82). Only outputs taller than 32,768 px keep the strip path, and DA-6 removes that path in ticket 65. Decision 58 records why this interim stays.

**Blocked by:** 44

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D1 test for the save path passes without the known-defect mark, for outputs up to 32,768 px tall.
- [ ] The strip-versus-render test stays a known defect for the strip path; ticket 65 retires it.
- [ ] The Solid redaction canary tests are unchanged and green.
- [ ] Peak memory for an edited 5,120 × 32,768 save is measured and recorded.
- [ ] Live editor row: on a 400×500 image, the arrow at row 450 appears and the label appears once.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
