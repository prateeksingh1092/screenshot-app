# 26: Editor tracer: Solid redaction to a flattened result

**What to build:** Prateek opens a capture from its thumbnail, covers part of it with Solid redaction, and presses Done; the flattened result is finalized, the thumbnail switches to it, and no output contains the redacted pixels.

**Blocked by:** 09

**Status:** resolved (tested on `main` at `e1649a9`; VoiceOver/real-content editor manual pending)

- [x] The editor edits a document (base image, Solid redactions); the renderer is a pure function from document to bitmap.
- [x] Solid redaction is its own element type: fixed colour, full opacity, no corner radius or stroke, copy blend, no antialiasing, rectangle snapped outward to whole output pixels.
- [x] Done finalizes the rendered revision; the thumbnail refreshes from it.
- [x] If Frisket copied this capture earlier and the clipboard's change count is unchanged, the copy is replaced with the redacted result.
- [x] AppKit editor with no document architecture, autosave, window restoration, disk image caches, or Live Text on the original.
- [x] Seam 2 renderer tests are pixel-exact.
- [x] Canary tests: unique colours under each redaction; clipboard, History image, and thumbnail outputs decoded in fixed sRGB; every covered pixel equals the fill at full opacity and no canary colour appears.
- [x] Editor controls have VoiceOver labels and keyboard operation (canvas contents excepted).

## Comments

- **Integration:** `integrate/26` merged onto `0e44dba` and fast-forwarded `main` to `e1649a9`. Coordinator resolved ~23 conflict hunks so the thumbnail stack, Save, drag, window capture and launch recovery stayed, and ticket 26's editor, revisioned pending images and clipboard replacement landed. Root `swift test`: 188 tests in 28 suites passed. Unsigned x86_64 `xcodebuild` succeeded (`CODE_SIGNING_ALLOWED=NO`). x86_64 only; arm64 not executed. Codex was already past its included-usage limit, so this pass ran in the coordinator chat.
