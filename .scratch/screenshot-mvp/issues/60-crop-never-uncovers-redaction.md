# 60: Crop never uncovers redacted pixels

**What to build:** A crop at fractional coordinates keeps every Solid redaction aligned with the content it covers, and no original pixel under a redaction shows at the crop edge (D18, story 96).

**Blocked by:** 44

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D18 test passes without the known-defect mark.
- [ ] Canary tests at 1× and 2× with a fractional crop and scale pass for the clipboard, the saved file, History, the dragged file and the Thumbnail.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
