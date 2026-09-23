# Scrolling capture sequences (seam 3)

**Real recordings: pending.** Decision 46 gates real screen capture on Prateek.
Ticket 34 captured nothing. `synthetic-sticky/` is generated entirely from
mathematical coloured cells by `generate-synthetic.py`. It is not real-scroll
coverage. It has a 31-row header, a 27-row footer, three 240×458 viewports, and
an independently generated 240×560 content reference.

The normal core suite loads that folder through the same test-only disk adapter
used for recordings, stitches the frames, checks every output byte, checks
height, and verifies all 35 unique reference bands occur exactly once in order.
It also supplies a deliberately duplicated band at unchanged height and a
cropped result to prove the property oracle rejects both defects.

## Add an authorized recording later

1. Obtain Prateek's screen-capture authorization. Use only a purpose-built,
   nonpersonal test page with unique row markers, sticky header and fixed footer.
   Do not put application chrome, personal content or secrets in fixtures.
2. Create a named folder under `Tests/Fixtures/ScrollingCapture/recordings/`.
   This path and all images remain gitignored by default. No capture script
   is included. Save overlapping, same-size lossless PNG viewports in scroll
   order, without rescaling, and a separately established content-only reference
   image (for example, the test page's known raster). Never derive the reference
   by running this stitcher. A changing page is unsuitable for byte-band checks.
3. Add `sequence.json` using the version 1 format below. Document the test page,
   author/date, authorization reference, OS build, and display scale in provenance
   strings. Leave `expectedVerticalStep` absent for manual scrolling unless a
   step is independently known. Set `isSettled` only for a verified settled view.
4. Choose full-width bands with unique, invariant pixels from the reference,
   especially around every overlap/seam. Bands must be sorted by reference row
   and occur exactly once in the reference itself. Use enough bands to cover
   the seam locations; this oracle cannot rule out duplication in unmarked areas.
   Height tolerance is in output pixels and must be justified in provenance.
5. Run `FRISKET_RECORDED_SCROLLS=1 sh scripts/test-core.sh --filter recordedScrollSequences`
   from the repository root, outside the sandbox if successful Vision registration
   is also being assessed. The opt-in test fails on missing/empty recordings;
   it cannot pass with no real cases. Preserve case names, Vision-use counts,
   OS/architecture, results and provenance in the verification report. Individually
   review any proposed fixture inclusion and add exact ignore exceptions later.

## Version 1 manifest

```json
{
  "version": 1,
  "provenance": {
    "kind": "recorded",
    "source": "Nonpersonal test page, author/date, display scale, reference origin and tolerance rationale",
    "authorization": "Prateek approval reference",
    "osBuild": "Actual build captured on"
  },
  "frames": [
    {"file": "frame-0.png"},
    {"file": "frame-1.png", "isSettled": true}
  ],
  "reference": "reference.png",
  "expectedWidth": 240,
  "expectedHeight": 560,
  "heightTolerance": 2,
  "uniqueBands": [
    {"referenceRow": 0, "height": 16},
    {"referenceRow": 320, "height": 16}
  ]
}
```

Files are sibling PNG basenames (no absolute paths or traversal). `kind` must
be `synthetic` or `recorded`; the real gate requires `recorded`. Provenance
strings, frames, and bands cannot be empty. The reference dimensions must equal
the expected dimensions. Test images are normalized to opaque/premultiplied
RGBA in the same device RGB space as the matcher. These test-only disk reads
are outside the pure core stitcher; it receives in-memory frames only.

Regenerate just the synthetic files offline with:

```sh
python3 Tests/Fixtures/ScrollingCapture/generate-synthetic.py
```
