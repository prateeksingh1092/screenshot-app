# 104: Remove the white halo from annotations (decision 100)

**What to build:** Arrows, lines, shapes and labels draw with no 1-pixel white plate, in the preview and in every output. Outlined and Box labels keep their own outline and box. Solid redaction is unchanged.

**Status:** ready-for-agent (medium effort)

- [ ] Preview equals flatten for every mark kind and ink with no plate. Update the golden images and tests that expected the plate (EditPainter, InkPaletteTests, `aShapeIsAnOutlineOnly`), and say which ones changed.
- [ ] Live: the `editor-ink-colour` and `editor-arrow-label` rows still pass.
