import CoreGraphics
import Foundation
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

private func blank(_ width: Int, _ height: Int) throws -> Picture {
    try picture(Array(repeating: String(repeating: ".", count: width), count: height))
}

private func picture(_ rows: [String]) throws -> Picture {
    let pixels = try rows.flatMap { row in
        try row.map { character in try #require(palette[character]) }
    }
    return try #require(Picture(width: rows[0].count, height: rows.count, pixels: pixels))
}

/// The edit rules, checked at the save path (`CaptureRenderer.flatten`): every picture here is
/// encoded as a PNG, flattened with the edits and decoded again.
@Suite struct EditedOutputTests {
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
        let base = try #require(Picture(width: side, height: side, pixels: pixels))
        let redactions = [(2.1, 1.6, 1.3, 2.2), (5 + fraction, 4 - fraction, 2.5, 1.75), (8.4, 7.9, 3, 3)]
        let crop = (1 + fraction, 1 + fraction / 2, 8.5, 7.25)
        let whole = try render(base, scale: scale, redactions)
        let cropped = try render(base, scale: scale, crop: crop, redactions)
        let minX = Int((crop.0 * scale).rounded(.down)), minY = Int((crop.1 * scale).rounded(.down))
        let maxX = Int(((crop.0 + crop.2) * scale).rounded(.up)), maxY = Int(((crop.1 + crop.3) * scale).rounded(.up))
        let window = (minY..<maxY).flatMap { y in (minX..<maxX).map { x in whole.pixel(x: x, y: y)! } }
        #expect(cropped == Picture(width: maxX - minX, height: maxY - minY, pixels: window),
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
        // Ticket 85: a solid head 12 px long and 6 px each side; row 14 is past the shaft's width.
        var headPixels = 0
        for y in 0..<15 where rendered.pixel(x: 24, y: y) == DocumentAnnotation.stroke { headPixels += 1 }
        #expect(headPixels > 0)
        #expect(rendered.pixel(x: 0, y: 0) == palette["."])
    }

    @Test func labelIsDrawnInThePinnedFontWithNoPlate() throws {
        let base = try blank(40, 28)
        let annotation = try #require(DocumentAnnotation(.text(x: 4, y: 2, characters: "H")))
        let rendered = try render(base, annotations: [annotation])
        // 18 pt HelveticaNeue-Bold: the H's stems are solid ink, with no white plate (decision 100).
        #expect(rendered.contains(DocumentAnnotation.stroke))
        #expect(!rendered.contains(plate))
        let ink = try #require(rendered.bounds(of: DocumentAnnotation.stroke))
        #expect(ink.minX >= 4 && ink.maxX <= 20 && ink.minY >= 2 && ink.maxY <= 22,
                "an 18 pt capital sits inside its em box below the label's top-left: \(ink)")
        #expect(rendered.pixel(x: 39, y: 27) == palette["."])
        // The label scales with the document: at 2× its ink is about twice as tall.
        let doubled = try render(try blank(80, 56), scale: 2, annotations: [annotation])
        let tall = try #require(doubled.bounds(of: DocumentAnnotation.stroke))
        #expect(abs((tall.maxY - tall.minY) - 2 * (ink.maxY - ink.minY)) <= 2)
    }

    /// Annotation golden, with a stated tolerance of 2 per channel. A snapped rectangle's 2 px stroke
    /// falls on whole pixels, so antialiasing adds nothing here; '~' cells (pixels an edge covers in
    /// part) would be free, and this golden has none. '*' ink, '.' capture; no white plate (decision 100).
    @Test func rectangleOutlineMatchesItsGoldenWithinTwoPerChannel() throws {
        let golden = [
            "..........",
            ".********.",
            ".********.",
            ".**....**.",
            ".**....**.",
            ".**....**.",
            ".**....**.",
            ".********.",
            ".********.",
            ".........."
        ]
        let colours: [Character: RGBAPixel?] = ["*": DocumentAnnotation.stroke, "p": plate, ".": palette["."]]
        let annotation = try #require(DocumentAnnotation(.rectangle(x: 1, y: 1, width: 8, height: 8)))
        let rendered = try render(try blank(10, 10), annotations: [annotation])
        for (y, row) in golden.enumerated() {
            for (x, cell) in row.enumerated() where cell != "~" {
                let got = try #require(rendered.pixel(x: x, y: y)), want = try #require(colours[cell] ?? nil)
                let close = [(got.red, want.red), (got.green, want.green), (got.blue, want.blue), (got.alpha, want.alpha)]
                    .allSatisfy { abs(Int($0.0) - Int($0.1)) <= 2 }
                #expect(close, "golden (\(x), \(y)) is '\(cell)', rendered \(got)")
            }
        }
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
        #expect(DocumentAnnotation(.text(x: 0, y: 0, characters: " \t ")) == nil)
        #expect(DocumentAnnotation(.text(x: 0, y: 0, characters: "!@#")) != nil)
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

    @Test func blurAveragesAThreeByThreeWindowWithVImage() throws {
        let base = try picture([
            "aaa",
            "a.a",
            "aaa"
        ])
        let effect = try #require(DocumentEffect(.blur(x: 0, y: 0, width: 3, height: 3)))
        let rendered = try render(base, effects: [effect])
        // vImage's box convolution (edge-extended, rounded to nearest; ticket 67), six passes.
        #expect(rendered.pixel(x: 1, y: 1) == RGBAPixel(red: 0xaf, green: 0x74, blue: 0x42, alpha: 0xff))
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
}

/// Flattens `base` with these edits through the save path and decodes the result.
private func render(_ base: Picture, scale: Double = 1, crop: (Double, Double, Double, Double)? = nil,
                    _ rectangles: [(Double, Double, Double, Double)] = [],
                    annotations: [DocumentAnnotation] = [],
                    effects: [DocumentEffect] = []) throws -> Picture {
    let redactions = try rectangles.map { try #require(SolidRedaction(x: $0.0, y: $0.1, width: $0.2, height: $0.3)) }
    let cropRect = try crop.map { try #require(DocumentCrop(x: $0.0, y: $0.1, width: $0.2, height: $0.3)) }
    let edits = try #require(DocumentEdits(scale: scale, crop: cropRect, redactions: redactions,
                                           annotations: annotations, effects: effects))
    return try delivered(base.png(), edits)
}

/// The white annotation plate that decision 100 removed; no output may show it around a mark.
private let plate = RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255)

/// Pixels in the renderer's working format: 8-bit sRGB RGBA, premultiplied, rows top to bottom.
/// Test-only; the product exposes PNG bytes and `CGImage`s.
struct Picture: Equatable {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        (self.width, self.height, self.bytes) = (width, height, bytes)
    }

    init?(width: Int, height: Int, pixels: [RGBAPixel]) {
        self.init(width: width, height: height, bytes: pixels.flatMap { [$0.red, $0.green, $0.blue, $0.alpha] })
    }

    /// Draws any image into a fixed sRGB RGBA8 premultiplied bitmap.
    init(_ image: CGImage) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        (width, height, self.bytes) = (image.width, image.height, bytes)
    }

    init(png: Data) throws {
        let decoded = try CaptureRendererTests.decode(png)
        (width, height, bytes) = (decoded.width, decoded.height, decoded.bytes)
    }

    func png() throws -> Data { try CaptureRendererTests.encode(bytes, width: width, height: height) }

    func pixel(x: Int, y: Int) -> RGBAPixel? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        let index = (y * width + x) * 4
        return RGBAPixel(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
    }
}

/// What Done delivers for these edits, decoded.
func delivered(_ png: Data, _ edits: DocumentEdits) throws -> Picture {
    try Picture(png: try CaptureRenderer().flatten(png, edits: edits))
}

/// What the editor preview shows for these edits.
func previewed(_ preview: CapturePreview, _ edits: DocumentEdits) throws -> Picture {
    try Picture(try preview.render(edits))
}

extension Picture {
    func contains(_ colour: RGBAPixel) -> Bool {
        (0..<height).contains { y in (0..<width).contains { x in pixel(x: x, y: y) == colour } }
    }

    /// The first row where two same-sized bitmaps differ, or nil when they are identical.
    func firstDifferingRow(from other: Picture) -> Int? {
        guard width == other.width, height == other.height else { return 0 }
        let rowBytes = width * 4
        return (0..<height).first { y in
            bytes[(y * rowBytes)..<((y + 1) * rowBytes)] != other.bytes[(y * rowBytes)..<((y + 1) * rowBytes)]
        }
    }

    /// Half-open pixel bounds of every pixel equal to `colour`.
    func bounds(of colour: RGBAPixel) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? { bounds { $0 == colour } }

    /// Half-open pixel bounds of every pixel that matches.
    func bounds(where matches: (RGBAPixel) -> Bool) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var box: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for y in 0..<height {
            for x in 0..<width where matches(pixel(x: x, y: y)!) {
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
private func generatedDocument(seed: UInt64, height: Int, effects withEffects: Bool = true,
                               annotations withAnnotations: Bool = true) throws -> (base: Picture, edits: DocumentEdits) {
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
    let base = try #require(Picture(width: width, height: height, pixels: pixels))
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
    let edits = try #require(DocumentEdits(scale: 1, redactions: redactions, annotations: withAnnotations ? annotations : [],
                                           effects: withEffects ? effects : []))
    return (base, edits)
}

/// Ticket 68: the editor preview is `CaptureRenderer.preview(capture).render(edits)`, with the
/// same edits Done flattens. At full size it is the delivered image, byte for byte.
@Suite struct EditorPreviewTests {
    /// Every edit kind, anywhere in the image, with `maxEdge` at the capture's longer edge and above.
    @Test(arguments: [8, 13, 257, 600, 2000])
    func previewAtFullSizeEqualsTheDeliveredImageForEveryEditKind(height: Int) throws {
        for seed in UInt64(1)...3 {
            let document = try generatedDocument(seed: seed &* UInt64(height), height: height)
            let png = try document.base.png()
            let saved = try delivered(png, document.edits)
            for maxEdge in [max(document.base.width, height), height + 1, CaptureRenderer.previewMaxEdge] where maxEdge >= max(document.base.width, height) {
                let preview = try CaptureRenderer().preview(png, maxEdge: maxEdge)
                #expect(!preview.isDownscaled)
                let shown = try previewed(preview, document.edits)
                let row = shown.firstDifferingRow(from: saved)
                #expect(row == nil, "height \(height), seed \(seed), maxEdge \(maxEdge): the preview differs from the delivered image from row \(row ?? -1)")
            }
        }
    }

    @Test func previewAtFullSizeEqualsTheDeliveredImageWithACropAtTwoTimes() throws {
        let document = try generatedDocument(seed: 99, height: 300)
        let crop = try #require(DocumentCrop(x: 3.25, y: 17.5, width: 30.3, height: 211.1))
        let edits = try #require(DocumentEdits(scale: 2, crop: crop, redactions: document.edits.redactions,
                                               annotations: document.edits.annotations, effects: document.edits.effects))
        let png = try document.base.png()
        let preview = try CaptureRenderer().preview(png)
        #expect(try previewed(preview, edits) == delivered(png, edits))
    }

    @Test func previewShrinksOnlyWhenAnEdgeExceedsMaxEdge() throws {
        let small = try CaptureRenderer().preview(try blank(40, 30).png())
        #expect((small.width, small.height, small.isDownscaled) == (40, 30, false))
        let tall = try CaptureRenderer().preview(try blank(60, 900).png(), maxEdge: 300)
        #expect((tall.captureWidth, tall.captureHeight) == (60, 900))
        #expect((tall.width, tall.height, tall.isDownscaled) == (20, 300, true))
    }

    @Test func previewRefusesWhatFlattenRefuses() throws {
        #expect(throws: RenderFailure.unreadableCapture) { try CaptureRenderer().preview(Data([1, 2, 3])) }
    }

    /// Decision 61: downscaled, every preview pixel whose block touches a redacted pixel is exactly
    /// the redaction's colour at alpha 255, and no other preview pixel shows anything from under it.
    /// The two captures differ only under the redaction (a canary against a neutral colour), so
    /// their previews must be identical. Sizes make the reduction non-integer, with Blur over the
    /// redaction's edge.
    @Test(arguments: [(1000, 333, 300), (301, 97, 128), (777, 1234, 500), (4000, 45, 2048)])
    func downscaledPreviewFillsEveryBlockTouchingARedactionAndShowsNothingUnderIt(width: Int, height: Int, maxEdge: Int) throws {
        let w = Double(width), h = Double(height)
        let grey = RGBAPixel(red: 0x80, green: 0x80, blue: 0x80, alpha: 0xff)
        for colour in [SolidRedaction.fill, grey] {
            let redaction = try #require(SolidRedaction(x: w * 0.31 + 0.4, y: h * 0.27 + 0.3, width: w * 0.2 + 0.35,
                                                        height: h * 0.3 + 0.45, colour: colour))
            let blur = try #require(DocumentEffect(.blur(x: w * 0.25, y: h * 0.2, width: w * 0.2, height: h * 0.2)))
            let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction], effects: [blur]))
            let redacted = CaptureRendererTests.snapped(redaction.x, redaction.y, redaction.width, redaction.height, scale: 1)
            func capture(under fill: RGBAPixel) throws -> Data {
                var bytes = CaptureRendererTests.pattern(width: width, height: height)
                for y in redacted.minY..<redacted.maxY {
                    for x in redacted.minX..<redacted.maxX {
                        let i = (y * width + x) * 4
                        bytes.replaceSubrange(i..<(i + 4), with: [fill.red, fill.green, fill.blue, fill.alpha])
                    }
                }
                return try CaptureRendererTests.encode(bytes, width: width, height: height)
            }
            let canary = try CaptureRenderer().preview(try capture(under: RGBAPixel(red: 0xff, green: 0, blue: 0xff, alpha: 0xff)), maxEdge: maxEdge)
            let neutral = try CaptureRenderer().preview(try capture(under: RGBAPixel(red: 0, green: 0xff, blue: 0, alpha: 0xff)), maxEdge: maxEdge)
            #expect(canary.isDownscaled)
            let shown = try previewed(canary, edits)
            #expect(shown == (try previewed(neutral, edits)), "\(width)×\(height) at \(maxEdge): the preview shows what the redaction covers")
            let block = cover(redacted, capture: (width, height), preview: (shown.width, shown.height))
            for y in block.minY..<block.maxY {
                for x in block.minX..<block.maxX where shown.pixel(x: x, y: y) != colour {
                    Issue.record("\(width)×\(height) at \(maxEdge): preview pixel (\(x), \(y)) touches the redaction but is \(String(describing: shown.pixel(x: x, y: y)))")
                    return
                }
            }
        }
    }
}

/// The preview pixels a box of capture pixels touches: minimum edges down, maximum edges up.
private func cover(_ box: (minX: Int, minY: Int, maxX: Int, maxY: Int), capture: (width: Int, height: Int),
                   preview: (width: Int, height: Int)) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
    (box.minX * preview.width / capture.width, box.minY * preview.height / capture.height,
     (box.maxX * preview.width + capture.width - 1) / capture.width,
     (box.maxY * preview.height + capture.height - 1) / capture.height)
}

/// Known defects in edited output (ticket 44). Each stays red until its fix removes the wrapper.
@Suite struct EditedOutputDefectTests {
    /// D23: the downscaled editor preview drew marks larger than the saved output (strokes floored
    /// at 2 preview px, arrow heads at 8, labels at 18 pt per preview point). A mark in the preview
    /// may cover the preview pixels its saved pixels touch, and no more. A Solid redaction covers
    /// exactly those, in its own colour.
    @Test(arguments: [1.0, 2.0])
    func d23DownscaledPreviewDrawsMarksNoLargerThanTheSavedOutput(scale: Double) throws {
        let full = (width: 64, height: Int(Double(2 * CaptureRenderer.previewMaxEdge) * scale))
        let base = try blank(full.width, full.height)
        let png = try base.png()
        let preview = try CaptureRenderer().preview(png)
        #expect(preview.isDownscaled, "the capture must be downscaled for the preview")
        let grey = RGBAPixel(red: 0x80, green: 0x80, blue: 0x80, alpha: 0xff)
        let marks: [(name: String, annotations: [DocumentAnnotation], redactions: [SolidRedaction])] = [
            ("label", [try #require(DocumentAnnotation(.text(x: 2, y: 4, characters: "A")))], []),
            ("arrow", [try #require(DocumentAnnotation(.arrow(x0: 2, y0: 40, x1: 28, y1: 40)))], []),
            ("outline", [try #require(DocumentAnnotation(.rectangle(x: 3, y: 80, width: 20, height: 9.5)))], []),
            ("Solid redaction", [], [try #require(SolidRedaction(x: 3.3, y: 60.2, width: 7.1, height: 5.6))]),
            ("grey Solid redaction", [], [try #require(SolidRedaction(x: 13.3, y: 70.2, width: 7.1, height: 5.6, colour: grey))])
        ]
        let background = try #require(base.pixel(x: 0, y: 0))
        for mark in marks {
            let edits = try #require(DocumentEdits(scale: scale, redactions: mark.redactions, annotations: mark.annotations))
            let saved = try #require(delivered(png, edits).bounds { $0 != background })
            let shown = try previewed(preview, edits)
            let drawn = try #require(shown.bounds { $0 != background })
            let allowed = cover(saved, capture: full, preview: (shown.width, shown.height))
            let inside = drawn.minX >= allowed.minX && drawn.minY >= allowed.minY
                && drawn.maxX <= allowed.maxX && drawn.maxY <= allowed.maxY
            #expect(inside, "D23: at \(Int(scale))× the preview draws the \(mark.name) over preview pixels \(drawn), but the saved output covers only \(allowed) at that scale")
            if let redaction = mark.redactions.first {
                #expect(drawn == allowed, "D23: the \(mark.name) must fill every preview pixel its saved pixels touch")
                #expect(shown.bounds { $0 == redaction.colour }.map { $0 == allowed } == true)
            }
        }
    }

    /// D6: the old 5×7 label font kept only A–Z, 0–9 and space, and uppercased everything.
    /// Each typed character must add ink to the label, and lowercase must differ from uppercase.
    @Test func d6LabelKeepsEveryTypedCharacter() throws {
        let typed = "v2.1 $4.99 -10%"
        let base = try blank(220, 24)
        func label(_ characters: String) throws -> Picture? {
            guard let annotation = DocumentAnnotation(.text(x: 2, y: 2, characters: characters)) else { return nil }
            return try render(base, annotations: [annotation])
        }
        var steps: [(character: Character, before: Picture?, after: Picture?)] = []
        for (index, character) in typed.enumerated() where character != " " {
            let prefix = String(typed.prefix(index))
            steps.append((character, try label(prefix), try label(prefix + String(character))))
        }
        let lower = try label("v"), upper = try label("V")
        for step in steps {
            #expect(step.after != nil && step.after != step.before,
                    "D6: typing '\(step.character)' in \"\(typed)\" adds nothing to the label")
        }
        #expect(lower != upper, "D6: lowercase v is drawn as uppercase V")
    }
}
