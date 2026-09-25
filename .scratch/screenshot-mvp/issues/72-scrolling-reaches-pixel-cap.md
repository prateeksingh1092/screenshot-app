# 72: Scrolling capture reaches the pixel cap on any display

**What to build:** A scrolling capture on a 5K Retina display keeps going until 32,768 px instead of stopping after about two screens (D20, DA-6). The preview appends only the new rows, downsampled. Shareable content is reused between environment changes. Encoded size only decides History admission (decision 27): an oversized result is still delivered to the clipboard and to Save.

**Blocked by:** 65, 70

**Phase:** 3 (O14, D20)

**Status:** ready-for-agent

- [ ] The D20 test passes without the known-defect mark.
- [ ] A preview update costs time in proportion to the new rows. Peak memory for a 5,120-px-wide capture up to the cap is measured and recorded.
- [ ] Shareable content is fetched once per environment generation, not on every sample.
- [ ] Reaching the cap stops the capture with a clear message and keeps the result.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
