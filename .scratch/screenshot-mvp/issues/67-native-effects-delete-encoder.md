# 67: Blur and Magnify drawn natively; the hand-rolled encoder is deleted

**What to build:** Blur (vImage, edge-extend, clamped to its box) and Magnify (CoreGraphics over the full box) run in the native renderer. The strip PNG encoder, the 5×7 font, the `@_silgen_name` zlib bindings and the zlib and libcompression link flags are deleted (D21, D22). Gate B checks peak memory at 5,120 × 32,768.

**Blocked by:** 66

**Phase:** 2 (◆ Gate B)

**Status:** ready-for-agent

- [ ] Blur and Magnify never read outside their box or under a redaction, and their output hash is stable on x86_64.
- [ ] The D21 test passes without the known-defect mark.
- [ ] No `@_silgen_name` remains in product code, and that check becomes strict.
- [ ] Gate B: peak memory at 5,120 × 32,768 with every edit kind is measured. If it is over budget, the per-strip CGContext fallback is adopted before the old encoder is deleted. The result is recorded in `decisions.md`.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
