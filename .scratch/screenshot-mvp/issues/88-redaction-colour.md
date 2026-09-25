# 88: Choose the Solid redaction colour

**What to build:** The Solid redaction tool offers a fill colour, with black as the default (decision 61, spec story 42). Every redacted pixel is exactly that colour at alpha 255 in every output: clipboard, file, drag, History, Thumbnail and OCR input. This holds at any display scale, after cropping, and under Blur and Magnify.

**Blocked by:** 65 (the native renderer draws the fill), 84 (editable marks carry a colour)

**Phase:** 2b (with 84–86)

**Status:** ready-for-agent (decision 61: no filled shapes, a small palette)

- [ ] The canary leak tests at the flatten seam pass for black and for at least two other colours.
- [ ] `pattern --verify-redacted` takes the expected colour, and the live `editor-redaction` row checks a colour other than black.
- [ ] Shapes are outlines only; no editor tool other than Solid redaction draws an opaque fill.
- [ ] Decision 59's filled-rectangle rule, the plan's "guaranteed black" wording and the CleanShot study are updated.
