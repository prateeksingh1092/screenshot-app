# 26: Editor tracer: Solid redaction to a flattened result

**What to build:** Prateek opens a capture from its thumbnail, covers part of it with Solid redaction, and presses Done; the flattened result is finalized, the thumbnail switches to it, and no output contains the redacted pixels.

**Blocked by:** 09

**Status:** in-progress (branch `ticket/26-editor-solid-redaction-tracer`)

- [ ] The editor edits a document (base image, Solid redactions); the renderer is a pure function from document to bitmap.
- [ ] Solid redaction is its own element type: fixed colour, full opacity, no corner radius or stroke, copy blend, no antialiasing, rectangle snapped outward to whole output pixels.
- [ ] Done finalizes the rendered revision; the thumbnail refreshes from it.
- [ ] If Frisket copied this capture earlier and the clipboard's change count is unchanged, the copy is replaced with the redacted result.
- [ ] AppKit editor with no document architecture, autosave, window restoration, disk image caches, or Live Text on the original.
- [ ] Seam 2 renderer tests are pixel-exact.
- [ ] Canary tests: unique colours under each redaction; clipboard, History image, and thumbnail outputs decoded in fixed sRGB; every covered pixel equals the fill at full opacity and no canary colour appears.
- [ ] Editor controls have VoiceOver labels and keyboard operation (canvas contents excepted).

## Comments
