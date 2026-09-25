# 68: Editor preview from the Capture renderer

**What to build:** The editor preview is drawn by `CaptureRenderer.preview(...).render(edits)` from the same edits that Done uses. At full size it equals the delivered image, and when downscaled, every block that touches a Solid redaction is exact black (D23, story 82). Rendering runs off the main actor, which only swaps images. The old renderer and its proxy are deleted.

**Blocked by:** 67

**Phase:** 2

**Status:** ready-for-agent

- [ ] The D23 test passes without the known-defect mark, and a parity test covers `maxEdge` at or above the output size.
- [ ] Editing a 5,120 × 32,768 capture never renders on the main thread; responsiveness is measured.
- [ ] The old renderer's public API, the editor proxy, the PNG bitmap codec and the bitmap and document types are deleted.
- [ ] Thumbnail decoding runs off the main actor.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
