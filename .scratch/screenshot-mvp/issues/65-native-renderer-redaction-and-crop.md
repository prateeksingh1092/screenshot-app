# 65: Native Capture renderer: crop and Solid redaction

**What to build:** Done, Copy, Save, drag, History and OCR input of an edited capture all come from one renderer behind `CaptureFlattening.flatten`. It draws crop and Solid redaction into an sRGB CGContext and encodes PNG in memory. In this slice, annotations and effects are still painted by the existing pixel code over the whole image; tickets 66 and 67 replace them. Output taller than 32,768 px is refused before anything is allocated (DA-6). The core may import CoreGraphics, CoreText, ImageIO and Accelerate (DA-1). The interface is the design-it-twice hybrid in the plan's Phase 2.

**Blocked by:** 52, 60

**Phase:** 2

**Status:** ready-for-agent

- [ ] The privacy-checklist tests are written first:
  1. integer crop with no resampling;
  2. byte-exact redaction goldens;
  3. effects never read outside their box or under a redaction;
  4. a fixed sRGB working space;
  5. OCR reads only the rendered result;
  6. the original is released on Delete or Close;
  7. the PNG carries no metadata.
- [ ] The coordinator takes a `flattener:`, with the production renderer in the app and a `ScriptedFlattener` in tests that replaces the reject-once and loop codecs.
- [ ] `outputTooTall` is thrown before any allocation. The scrolling pixel cap and the edited-output cap are both 32,768 px, and the editor memory test is updated to match.
- [ ] The repository fence allows CoreGraphics, CoreText, ImageIO and Accelerate in the core, and still bans URL-based image destinations and every other disk I/O.
- [ ] If `flatten` is async, the in-progress guard is set before the await.
- [ ] The existing Solid redaction canary tests pass unchanged.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
