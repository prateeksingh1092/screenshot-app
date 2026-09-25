# 67: Blur and Magnify drawn natively; the hand-rolled encoder is deleted

**What to build:** Blur (vImage, edge-extend, clamped to its box) and Magnify (CoreGraphics over the full box) run in the native renderer. The strip PNG encoder, the 5×7 font, the `@_silgen_name` zlib bindings and the zlib and libcompression link flags are deleted (D21, D22). Gate B checks peak memory at 5,120 × 32,768.

**Blocked by:** 66

**Phase:** 2 (◆ Gate B)

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [x] Blur and Magnify never read outside their box or under a redaction, and their output hash is stable on x86_64.
- [x] The D21 test passes without the known-defect mark.
- [x] No `@_silgen_name` remains in product code, and that check becomes strict.
- [x] Gate B: peak memory at 5,120 × 32,768 with every edit kind is measured. If it is over budget, the per-strip CGContext fallback is adopted before the old encoder is deleted. The result is recorded in `decisions.md`.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62 supersedes this ticket's xhigh line).

- **Blur and Magnify, native:** `DocumentRenderer` now blurs with vImage (3 × 3 box, edge-extend, six passes) and magnifies with CoreGraphics (top-left quarter drawn 2× over the whole box, no interpolation), each on a copy of its own box of the redacted composite. The preview and `CaptureRenderer.flatten` share this code, so delivered == preview stays byte-exact.
- **D1 effects half (red → green):** `forEachStrip` widens a window to the whole rows of every effect box it meets. The test now runs each document with and without annotations: exact without, within decision 68's tolerance with. The wrapper is gone.
- **D22 (red → green):** `StripPNGEncoder`, its tests, the `@_silgen_name` bindings and the `z`/`compression` link flags are deleted. The `silgen` check is strict with no allowance; the strict fixture is gone.
- **D21:** already green since ticket 65; still passes.
- **Tests added:** a Solid redaction under Blur and Magnify keeps its exact colour for black, white and grey; a pixel-hash golden for effect output. Changed golden: `blurAveragesAThreeByThreeWindowWithVImage` (vImage rounds to nearest; +1 on two channels).
- **Gate B (decision 71):** one display, 6,016 × 3,384, every edit kind: peak 171.5 MB, well under 2 GB. No fallback needed. The 5,120 × 32,768 cap measured 2.35 GB (1.35 GB of it the fixture), for reference only.
- **Docs:** `docs/app-build.md`, `docs/core-package.md`, `docs/manual-checks/29-blur-and-magnify.md` (the two drift items in files touched here are fixed).
- **Open:** arm64 hash unverified; D23 untouched (ticket 68). Live: Blur and Magnify look and the redaction colour under them in the editor and every output.
