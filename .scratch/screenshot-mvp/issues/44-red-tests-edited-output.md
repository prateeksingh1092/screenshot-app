# 44: Red tests: edited output and preview

**What to build:** Tests reproduce every known way an edited capture's delivered image differs from what the user saw: arrows, labels, Blur and Magnify lost or repeated at strip boundaries (D1); preview redactions and strokes drawn at the wrong size (D23); a fractional crop leaving a sliver of original pixels beside a Solid redaction (D18); label characters dropped (D6); and dark fringes from premultiplied pixels written as straight alpha (D21). Each is red for its stated reason and marked as a known defect.

**Blocked by:** 43

**Phase:** 0

**Status:** ready-for-agent

- [ ] D1: for generated documents with every annotation and effect kind, at several strip heights and image heights from 8 to 2,000 px, the strip output equals the whole-image render.
- [ ] D1: the decoded saved output of an edited capture equals the whole-image render, through the save path the app uses.
- [ ] D23: at a downscaled preview, each Solid redaction and stroke covers the same area as in the saved output at that scale, not more.
- [ ] D18: the test that locks the sliver is corrected. After a fractional crop, no original pixel under a Solid redaction is visible, and the redaction stays aligned with its content.
- [ ] D6: a label typed as `v2.1 $4.99 -10%` renders every character, and lowercase differs from uppercase.
- [ ] D21: a partly transparent pixel survives save and decode without darkening.
- [ ] Each test fails for the reason it names, never because of a fixture error, and is marked as a known defect.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
