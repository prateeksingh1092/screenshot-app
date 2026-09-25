import FrisketCore
import Testing

/// Literal pictures: each character is one output pixel, rows top to bottom.
private let palette: [Character: RGBAPixel] = [
    ".": RGBAPixel(red: 0x20, green: 0x40, blue: 0x60, alpha: 0xff),
    "a": RGBAPixel(red: 0xc1, green: 0x7a, blue: 0x3e, alpha: 0xff),
    "t": RGBAPixel(red: 0x40, green: 0x10, blue: 0x08, alpha: 0x80), // premultiplied, half transparent
    "#": RGBAPixel(red: 0, green: 0, blue: 0, alpha: 0xff),
    "*": DocumentAnnotation.stroke
]

private func blank(_ width: Int, _ height: Int) throws -> Bitmap {
    try picture(Array(repeating: String(repeating: ".", count: width), count: height))
}

private func picture(_ rows: [String]) throws -> Bitmap {
    let pixels = try rows.flatMap { row in
        try row.map { character in try #require(palette[character]) }
    }
    return try #require(Bitmap(width: rows[0].count, height: rows.count, pixels: pixels))
}

@Suite struct DocumentRendererTests {
    @Test func wholePixelRedactionReplacesExactlyTheCoveredPixelsWithOpaqueBlack() throws {
        let base = try picture([
            ".....",
            ".at..",
            "....."
        ])
        #expect(try render(base, [(1, 1, 2, 1)]) == picture([
            ".....",
            ".##..",
            "....."
        ]))
    }

    @Test func fractionalRectangleSnapsOutwardToEveryPartlyCoveredPixel() throws {
        let base = try picture([
            ".....",
            ".....",
            ".....",
            "....."
        ])
        // x 1.5 to 2.75 touches columns 1-2; y 0.25 to 2.0 touches rows 0-1.
        #expect(try render(base, [(1.5, 0.25, 1.25, 1.75)]) == picture([
            ".##..",
            ".##..",
            ".....",
            "....."
        ]))
    }

    @Test func atTwoTimesPointRectangleSnapsOutwardToWholeOutputPixels() throws {
        let base = try picture([
            "......",
            "......",
            "......",
            "......"
        ])
        // Points x 0.75 to 1.75, y 0.25 to 0.75 are output pixels x 1.5 to 3.5, y 0.5 to 1.5.
        #expect(try render(base, scale: 2, [(0.75, 0.25, 1, 0.5)]) == picture([
            ".###..",
            ".###..",
            "......",
            "......"
        ]))
    }

    @Test func rectanglesBeyondTheImageAreClippedAndOverlapsStayOpaque() throws {
        let base = try picture([
            "....",
            "..a.",
            "...."
        ])
        #expect(try render(base, [
            (-1.5, -0.5, 2.25, 1),       // clipped to the top-left pixel
            (3.5, 2.5, 1e300, 1e300),    // clipped to the bottom-right pixel
            (10, 10, 1, 1),              // entirely outside
            (2, 1, 1, 1), (1.5, 0.5, 1, 1) // overlapping; the second touches columns 1-2, rows 0-1
        ]) == picture([
            "###.",
            ".##.",
            "...#"
        ]))
    }

    @Test func invalidGeometryCannotBecomeARedactionOrADocument() {
        let invalid: [(Double, Double, Double, Double)] = [(.nan, 0, 1, 1), (0, .infinity, 1, 1), (0, 0, 0, 1), (0, 0, 1, -1)]
        for (x, y, width, height) in invalid {
            #expect(SolidRedaction(x: x, y: y, width: width, height: height) == nil)
            #expect(DocumentCrop(x: x, y: y, width: width, height: height) == nil)
        }
        for scale: Double in [0, -2, .nan, .infinity] { #expect(DocumentEdits(scale: scale) == nil) }
        #expect(Bitmap(width: 2, height: 1, bytes: [0, 0, 0, 255]) == nil)
    }

    @Test func cropExtractsTheSnappedOutputPixelsAndKeepsUnredactedColours() throws {
        let base = try picture([
            "aaa.",
            ".a..",
            "...."
        ])
        #expect(try render(base, crop: (1, 0, 2, 2), []) == picture([
            "aa",
            "a."
        ]))
    }

    /// D18: this test used to lock the sliver. The crop keeps base columns 1..<5 and rows 0..<3
    /// (its edges snap outward to whole pixels). Redaction 2.1,0.6 1×1 covers base columns 2..<4 and
    /// rows 0..<2, the canary `a` pixels, so in the cropped output it must cover columns 1..<3.
    /// The renderer shifts it by the crop's fractional 0.25 instead, covering columns 0..<2 and
    /// leaving base column 3 visible beside it.
    @Test func d18FractionalCropKeepsTheRedactionOnTheContentItCovers() throws {
        let base = try picture([
            "..aa..",
            "..aa..",
            "......",
            "......"
        ])
        let rendered = try render(base, crop: (1.25, 0.25, 3, 2.25), [(2.1, 0.6, 1, 1)])
        let expected = try picture([
            ".##.",
            ".##.",
            "...."
        ])
        #expect(!rendered.contains(palette["a"]!),
                "D18: an original pixel under the Solid redaction shows at the crop edge")
        #expect(rendered == expected, "D18: the redaction moved off the content it covers after a fractional crop")
    }

    /// D18 at 2×: this test used to lock a redaction shifted by the crop's fractional edge.
    /// Crop 0.75,0.25 2×1 at 2× keeps base pixels 1..<6 × 0..<3. Redaction 1.25,0.5 0.75×0.5
    /// covers base pixels 2.5..<4 × 1..<2, so columns 2..<4 of row 1 (the canary `a` pixels),
    /// which are cropped columns 1..<3 of cropped row 1. The renderer subtracts the unsnapped
    /// crop origin and also blacks out cropped row 0, content the user never selected.
    @Test func d18TwoTimesCropKeepsTheRedactionOnItsContent() throws {
        let base = try picture([
            "........",
            "..aa....",
            "........",
            "........"
        ])
        let rendered = try render(base, scale: 2, crop: (0.75, 0.25, 2, 1), [(1.25, 0.5, 0.75, 0.5)])
        let expected = try picture([
            ".....",
            ".##..",
            "....."
        ])
        #expect(!rendered.contains(palette["a"]!), "the canary stays concealed either way")
        #expect(rendered == expected, "D18: the redaction moved off the content it covers after a fractional 2× crop")
    }

    /// D18: a crop only removes pixels. At any fractional crop origin and scale, rendering with the
    /// crop equals rendering without it and then keeping the crop's snapped whole-pixel window.
    @Test(arguments: [1.0, 2.0], [0.25, 0.5, 0.75])
    func fractionalCropEqualsCroppingTheUncroppedRender(scale: Double, fraction: Double) throws {
        let side = Int(12 * scale)
        let pixels = (0..<(side * side)).map { index in
            RGBAPixel(red: UInt8(index % 251), green: UInt8(index / side), blue: 0x60, alpha: 0xff)
        }
        let base = try #require(Bitmap(width: side, height: side, pixels: pixels))
        let redactions = [(2.1, 1.6, 1.3, 2.2), (5 + fraction, 4 - fraction, 2.5, 1.75), (8.4, 7.9, 3, 3)]
        let crop = (1 + fraction, 1 + fraction / 2, 8.5, 7.25)
        let whole = try render(base, scale: scale, redactions)
        let cropped = try render(base, scale: scale, crop: crop, redactions)
        let minX = Int((crop.0 * scale).rounded(.down)), minY = Int((crop.1 * scale).rounded(.down))
        let maxX = Int(((crop.0 + crop.2) * scale).rounded(.up)), maxY = Int(((crop.1 + crop.3) * scale).rounded(.up))
        let window = (minY..<maxY).flatMap { y in (minX..<maxX).map { x in whole.pixel(x: x, y: y)! } }
        #expect(cropped == Bitmap(width: maxX - minX, height: maxY - minY, pixels: window),
                "D18: a fractional crop moved a redaction relative to the content it covers")
    }

    @Test func renderEqualsAnIndependentCropThenRedactSnapshot() throws {
        let base = try picture([
            ".a.t",
            "aa..",
            "...."
        ])
        let crop = (1.0, 0.0, 2.0, 2.0)
        let redactions = [(1.5, 0.25, 1.0, 1.0)]
        let rendered = try render(base, crop: crop, redactions)
        let croppedBase = try picture([
            "a.",
            "a."
        ])
        let translated = redactions.map { ($0.0 - crop.0, $0.1 - crop.1, $0.2, $0.3) }
        let equivalent = try render(croppedBase, translated)
        let frozen = try picture([
            "##",
            "##"
        ])
        #expect(rendered == equivalent)
        #expect(rendered == frozen)
    }

    @Test func rectangleOutlineIsNotAFilledRedaction() throws {
        let base = try blank(20, 20)
        let annotation = try #require(DocumentAnnotation(.rectangle(x: 4, y: 4, width: 12, height: 12)))
        let rendered = try render(base, annotations: [annotation])
        #expect(rendered.pixel(x: 4, y: 4) == DocumentAnnotation.stroke)
        #expect(rendered.pixel(x: 10, y: 10) == palette["."])
        #expect(rendered.pixel(x: 0, y: 0) == palette["."])
    }

    @Test func horizontalArrowHasAVisibleHead() throws {
        let base = try blank(40, 32)
        let annotation = try #require(DocumentAnnotation(.arrow(x0: 2, y0: 16, x1: 30, y1: 16)))
        let rendered = try render(base, annotations: [annotation])
        #expect(rendered.pixel(x: 16, y: 16) == DocumentAnnotation.stroke)
        var headPixels = 0
        for y in 0..<12 where rendered.pixel(x: 24, y: y) == DocumentAnnotation.stroke { headPixels += 1 }
        #expect(headPixels > 0)
        #expect(rendered.pixel(x: 0, y: 0) == palette["."])
    }

    @Test func textUsesTheClosedBitmapFont() throws {
        let base = try blank(24, 20)
        let annotation = try #require(DocumentAnnotation(.text(x: 0, y: 0, characters: "A")))
        let rendered = try render(base, annotations: [annotation])
        // The top bar of A stays ink. The counter is the 1 px white plate, not the capture.
        #expect(rendered.pixel(x: 2, y: 0) == DocumentAnnotation.stroke)
        #expect(rendered.pixel(x: 4, y: 4) == DocumentRenderer.plate)
        #expect(DocumentRenderer.outputCount(points: 18, scale: 2) == 36)
        #expect(DocumentRenderer.outputCount(points: 18, scale: 2.0 * 182.0 / 5120.0) == 1)
        #expect(DocumentRenderer.outputCount(points: 1, scale: 2.0 * 182.0 / 5120.0) == 0)
    }

    @Test func annotationsDrawAboveRedactionsWithoutClearingNeighbourFill() throws {
        let base = try blank(16, 16)
        let annotation = try #require(DocumentAnnotation(.rectangle(x: 3, y: 3, width: 10, height: 10)))
        let rendered = try render(base, [(0, 0, 16, 16)], annotations: [annotation])
        #expect(rendered.pixel(x: 3, y: 3) == DocumentAnnotation.stroke)
        #expect(rendered.pixel(x: 8, y: 8) == SolidRedaction.fill)
        #expect(rendered.pixel(x: 0, y: 0) == SolidRedaction.fill)
    }

    @Test func annotationGeometryIsRejectedWhenItCannotBeAStroke() {
        #expect(DocumentAnnotation(.rectangle(x: 0, y: 0, width: 0, height: 1)) == nil)
        #expect(DocumentAnnotation(.arrow(x0: 1, y0: 1, x1: 1, y1: 1)) == nil)
        #expect(DocumentAnnotation(.text(x: 0, y: 0, characters: "!@#")) == nil)
    }

    @Test func magnifyDoublesPixelsFromTheSnappedOrigin() throws {
        let base = try picture([
            "a...",
            "....",
            "....",
            "...."
        ])
        let effect = try #require(DocumentEffect(.magnify(x: 0, y: 0, width: 4, height: 4)))
        #expect(try render(base, effects: [effect]) == picture([
            "aa..",
            "aa..",
            "....",
            "...."
        ]))
    }

    @Test func blurAveragesAThreeByThreeWindow() throws {
        let base = try picture([
            "aaa",
            "a.a",
            "aaa"
        ])
        let effect = try #require(DocumentEffect(.blur(x: 0, y: 0, width: 3, height: 3)))
        let rendered = try render(base, effects: [effect])
        // This 3×3 is already one average. Further passes stay put under integer division.
        #expect(rendered.pixel(x: 1, y: 1) == RGBAPixel(red: 0xaf, green: 0x73, blue: 0x41, alpha: 0xff))
    }

    @Test func blurAndMagnifyOverARedactionKeepFillAndHideTheCanary() throws {
        let base = try picture([
            "aaaaa",
            "aaaaa",
            "aaaaa",
            "aaaaa",
            "aaaaa"
        ])
        let blur = try #require(DocumentEffect(.blur(x: 0, y: 0, width: 5, height: 5)))
        let magnify = try #require(DocumentEffect(.magnify(x: 0, y: 0, width: 5, height: 5)))
        #expect(try render(base, [(0, 0, 5, 5)], effects: [blur, magnify]) == picture([
            "#####",
            "#####",
            "#####",
            "#####",
            "#####"
        ]))
    }

    @Test func effectGeometryIsRejectedWhenItCannotSampleARegion() {
        #expect(DocumentEffect(.blur(x: 0, y: 0, width: 0, height: 1)) == nil)
        #expect(DocumentEffect(.magnify(x: 1, y: 1, width: -1, height: 1)) == nil)
    }

    @Test func stripRenderMatchesFullRenderOnATallCanary() throws {
        let base = try picture([
            "a.....",
            "..a...",
            "....a.",
            "a.....",
            "..a...",
            "....a.",
            "a.....",
            "..a..."
        ])
        let redaction = try #require(SolidRedaction(x: 2, y: 1, width: 3, height: 4))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        let document = EditorDocument(base: base, edits: edits)
        let full = DocumentRenderer.render(document)
        var rows: [Bitmap] = []
        DocumentRenderer.forEachStrip(document, stripHeight: 3) { rows.append($0) }
        #expect(rows.map(\.height) == [3, 3, 2])
        #expect(DocumentRenderer.concatenate(rows) == full)
        #expect(full.pixel(x: 2, y: 1) == SolidRedaction.fill)
        #expect(full.pixel(x: 0, y: 0) == palette["a"])
    }

    @Test func editorProxyShrinksOnlyWhenAnEdgeExceedsTheCap() {
        #expect(EditorProxy.displaySize(width: 40, height: 30) == (40, 30))
        let tall = EditorProxy.displaySize(width: 5120, height: 57_600, maxEdge: 2048)
        #expect(tall.width == 182)
        #expect(tall.height == 2048)
        #expect(EditorProxy.displayScale(fullWidth: 5120, proxyWidth: 182, scale: 2) == 2 * 182.0 / 5120)
    }
}

private func render(_ base: Bitmap, scale: Double = 1, crop: (Double, Double, Double, Double)? = nil,
                    _ rectangles: [(Double, Double, Double, Double)] = [],
                    annotations: [DocumentAnnotation] = [],
                    effects: [DocumentEffect] = []) throws -> Bitmap {
    let redactions = try rectangles.map { try #require(SolidRedaction(x: $0.0, y: $0.1, width: $0.2, height: $0.3)) }
    let cropRect = try crop.map { try #require(DocumentCrop(x: $0.0, y: $0.1, width: $0.2, height: $0.3)) }
    let edits = try #require(DocumentEdits(scale: scale, crop: cropRect, redactions: redactions,
                                           annotations: annotations, effects: effects))
    return DocumentRenderer.render(EditorDocument(base: base, edits: edits))
}

private extension Bitmap {
    func contains(_ colour: RGBAPixel) -> Bool {
        (0..<height).contains { y in (0..<width).contains { x in pixel(x: x, y: y) == colour } }
    }

    /// The first row where two same-sized bitmaps differ, or nil when they are identical.
    func firstDifferingRow(from other: Bitmap) -> Int? {
        guard width == other.width, height == other.height else { return 0 }
        let rowBytes = width * 4
        return (0..<height).first { y in
            bytes[(y * rowBytes)..<((y + 1) * rowBytes)] != other.bytes[(y * rowBytes)..<((y + 1) * rowBytes)]
        }
    }

    /// Half-open pixel bounds of every pixel equal to `colour`.
    func bounds(of colour: RGBAPixel) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var box: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for y in 0..<height {
            for x in 0..<width where pixel(x: x, y: y) == colour {
                box = (min(box?.minX ?? x, x), min(box?.minY ?? y, y), max(box?.maxX ?? x + 1, x + 1), max(box?.maxY ?? y + 1, y + 1))
            }
        }
        return box
    }
}

/// SplitMix64: the same seed always generates the same documents.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

/// A 48-px-wide patterned capture with at least one of every edit kind: Solid redaction,
/// rectangle, arrow, label, Blur and Magnify. Positions are anywhere in the image.
private func generatedDocument(seed: UInt64, height: Int) throws -> EditorDocument {
    var random = SeededGenerator(seed: seed)
    let width = 48
    var pixels: [RGBAPixel] = []
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels.append(RGBAPixel(red: UInt8((x * 37 + y * 11) % 256), green: UInt8((x * 5 + y * 3) % 256),
                                    blue: UInt8((y * 7) % 256), alpha: 255))
        }
    }
    let base = try #require(Bitmap(width: width, height: height, pixels: pixels))
    let w = Double(width), h = Double(height)
    func box() -> (x: Double, y: Double, width: Double, height: Double) {
        let x = Double.random(in: 0..<(w - 4), using: &random)
        let y = Double.random(in: 0..<max(1, h - 2), using: &random)
        return (x, y, Double.random(in: 2...(w - x), using: &random), Double.random(in: 1...max(1, min(h - y, 400)), using: &random))
    }
    func point() -> (x: Double, y: Double) { (Double.random(in: 0..<w, using: &random), Double.random(in: 0..<h, using: &random)) }
    let redactions = try (0..<Int.random(in: 1...2, using: &random)).map { _ in
        let b = box()
        return try #require(SolidRedaction(x: b.x, y: b.y, width: b.width, height: b.height))
    }
    var annotations: [DocumentAnnotation] = []
    let outline = box()
    annotations.append(try #require(DocumentAnnotation(.rectangle(x: outline.x, y: outline.y, width: outline.width, height: outline.height))))
    for _ in 0..<Int.random(in: 1...2, using: &random) {
        let tail = point(), head = point()
        annotations.append(try #require(DocumentAnnotation(.arrow(x0: tail.x, y0: tail.y, x1: head.x + 0.5, y1: head.y))))
        let label = String((0..<Int.random(in: 1...4, using: &random)).map { _ in Array("AB12 XYZ").randomElement(using: &random)! })
        let at = point()
        if let text = DocumentAnnotation(.text(x: at.x, y: at.y, characters: label)) { annotations.append(text) }
    }
    let blurred = box(), magnified = box()
    let effects = [
        try #require(DocumentEffect(.blur(x: blurred.x, y: blurred.y, width: blurred.width, height: blurred.height))),
        try #require(DocumentEffect(.magnify(x: magnified.x, y: magnified.y, width: magnified.width, height: magnified.height)))
    ]
    let edits = try #require(DocumentEdits(scale: 1, redactions: redactions, annotations: annotations, effects: effects))
    return EditorDocument(base: base, edits: edits)
}

/// Known defects in edited output (ticket 44). Each stays red until its fix removes the wrapper.
@Suite struct EditedOutputDefectTests {
    /// D1: the save path renders strip by strip (`forEachStrip`, 256 rows in production), while the
    /// editor preview renders the whole image. Arrows and labels ignore the strip's row offset, and
    /// Blur and Magnify read only a 1-row halo, so marks vanish or repeat at strip boundaries.
    @Test(arguments: [7, 64, DocumentRenderer.stripHeight])
    func d1StripOutputEqualsTheWholeImageRenderForEveryEditKind(stripHeight: Int) async throws {
        let heights = [8, 13, 255, 256, 257, 600, 1024, 1500, 2000]
        var cases: [(seed: UInt64, height: Int, whole: Bitmap, strips: Bitmap)] = []
        for (index, height) in heights.enumerated() {
            let seed = UInt64(index + 1)
            let document = try generatedDocument(seed: seed, height: height)
            var strips: [Bitmap] = []
            DocumentRenderer.forEachStrip(document, stripHeight: stripHeight) { strips.append($0) }
            let joined = try #require(DocumentRenderer.concatenate(strips))
            cases.append((seed, height, DocumentRenderer.render(document), joined))
        }
        try await knownDefect("D1") {
            for item in cases {
                let row = item.strips.firstDifferingRow(from: item.whole)
                #expect(row == nil, "D1: strip height \(stripHeight), image height \(item.height), seed \(item.seed): strips differ from the whole render from row \(row ?? -1)")
            }
        }
    }

    /// D23 mirrors the editor preview. `CaptureSurfaces.edit` decodes a proxy at most
    /// `EditorProxy.maxEdge` px on a side (`ThumbnailImage`), and `EditorWindow.refresh()` renders
    /// `DocumentRenderer.render` over it with the edits rescaled by `EditorProxy.displayScale`. The
    /// base here is uniform, so any downsampling filter gives the same proxy. The saved output is the
    /// whole-image render at full size (what the save path gives once D1 is fixed). A mark in the
    /// preview may cover the whole preview pixels its saved pixels touch, and no more; strokes and
    /// glyph cells floored at 2 px (and arrow heads at 8 px) are larger than that.
    @Test(arguments: [1.0, 2.0])
    func d23DownscaledPreviewDrawsMarksNoLargerThanTheSavedOutput(scale: Double) async throws {
        let full = (width: 64, height: Int(4096 * scale))
        let proxy = EditorProxy.displaySize(width: full.width, height: full.height)
        let displayScale = EditorProxy.displayScale(fullWidth: full.width, proxyWidth: proxy.width, scale: scale)
        let kx = Double(proxy.width) / Double(full.width), ky = Double(proxy.height) / Double(full.height)
        #expect(kx < 1 && ky < 1, "the capture must be downscaled for the preview")
        let fullBase = try blank(full.width, full.height)
        let proxyBase = try blank(proxy.width, proxy.height)
        func cover(_ box: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            (Int((Double(box.minX) * kx).rounded(.down)), Int((Double(box.minY) * ky).rounded(.down)),
             Int((Double(box.maxX) * kx).rounded(.up)), Int((Double(box.maxY) * ky).rounded(.up)))
        }
        let marks: [(name: String, annotations: [DocumentAnnotation], redactions: [SolidRedaction], colour: RGBAPixel)] = [
            ("label", [try #require(DocumentAnnotation(.text(x: 2, y: 4, characters: "A")))], [], DocumentAnnotation.stroke),
            ("arrow", [try #require(DocumentAnnotation(.arrow(x0: 2, y0: 40, x1: 28, y1: 40)))], [], DocumentAnnotation.stroke),
            ("Solid redaction", [], [try #require(SolidRedaction(x: 3.3, y: 60.2, width: 7.1, height: 5.6))], SolidRedaction.fill)
        ]
        var measured: [(name: String, saved: (minX: Int, minY: Int, maxX: Int, maxY: Int), preview: (minX: Int, minY: Int, maxX: Int, maxY: Int))] = []
        for mark in marks {
            let saved = DocumentRenderer.render(EditorDocument(base: fullBase, edits: try #require(
                DocumentEdits(scale: scale, redactions: mark.redactions, annotations: mark.annotations))))
            let preview = DocumentRenderer.render(EditorDocument(base: proxyBase, edits: try #require(
                DocumentEdits(scale: displayScale, redactions: mark.redactions, annotations: mark.annotations))))
            measured.append((mark.name, try #require(saved.bounds(of: mark.colour)), try #require(preview.bounds(of: mark.colour))))
        }
        try await knownDefect("D23") {
            for item in measured {
                let allowed = cover(item.saved)
                let inside = item.preview.minX >= allowed.minX && item.preview.minY >= allowed.minY
                    && item.preview.maxX <= allowed.maxX && item.preview.maxY <= allowed.maxY
                #expect(inside, "D23: at \(Int(scale))× the preview draws the \(item.name) over preview pixels \(item.preview), but the saved output covers only \(allowed) at that scale")
            }
        }
    }

    /// D6: the 5×7 label font keeps only A–Z, 0–9 and space, and uppercases everything.
    /// Each typed character must add ink to the label, and lowercase must differ from uppercase.
    @Test func d6LabelKeepsEveryTypedCharacter() async throws {
        let typed = "v2.1 $4.99 -10%"
        let base = try blank(220, 24)
        func label(_ characters: String) throws -> Bitmap? {
            guard let annotation = DocumentAnnotation(.text(x: 2, y: 2, characters: characters)) else { return nil }
            return DocumentRenderer.render(EditorDocument(base: base, edits: try #require(
                DocumentEdits(scale: 1, annotations: [annotation]))))
        }
        var steps: [(character: Character, before: Bitmap?, after: Bitmap?)] = []
        for (index, character) in typed.enumerated() where character != " " {
            let prefix = String(typed.prefix(index))
            steps.append((character, try label(prefix), try label(prefix + String(character))))
        }
        let lower = try label("v"), upper = try label("V")
        try await knownDefect("D6") {
            for step in steps {
                #expect(step.after != nil && step.after != step.before,
                        "D6: typing '\(step.character)' in \"\(typed)\" adds nothing to the label")
            }
            #expect(lower != upper, "D6: lowercase v is drawn as uppercase V")
        }
    }
}
