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

    @Test func fractionalCropAndRedactionSnapOutwardAfterCropAndScale() throws {
        let base = try picture([
            "......",
            "......",
            "......",
            "......"
        ])
        // Crop 1.25,0.25 3×2.25 → output 1..<5 × 0..<3. Redaction 2.1,0.6 1×1 is
        // 0.85,0.35 in cropped points → columns 0..<2, rows 0..<2 of the crop.
        #expect(try render(base, crop: (1.25, 0.25, 3, 2.25), [(2.1, 0.6, 1, 1)]) == picture([
            "##..",
            "##..",
            "...."
        ]))
    }

    @Test func twoTimesCropSnapsOutwardThenRedactsInTheCroppedOutput() throws {
        let base = try picture([
            "........",
            "........",
            "........",
            "........"
        ])
        // Crop 0.75,0.25 2×1 at 2× → output 1.5..<5.5 × 0.5..<2.5 → 1..<6 × 0..<3.
        // Redaction 1.25,0.5 0.75×0.5 → cropped 0.5,0.25 → output 1.0..<2.5 × 0.5..<1.5.
        #expect(try render(base, scale: 2, crop: (0.75, 0.25, 2, 1), [(1.25, 0.5, 0.75, 0.5)]) == picture([
            ".##..",
            ".##..",
            "....."
        ]))
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
        let base = try picture([
            ".....",
            ".....",
            ".....",
            ".....",
            "....."
        ])
        let annotation = try #require(DocumentAnnotation(.rectangle(x: 1, y: 1, width: 3, height: 3)))
        #expect(try render(base, annotations: [annotation]) == picture([
            ".....",
            ".***.",
            ".*.*.",
            ".***.",
            "....."
        ]))
    }

    @Test func horizontalArrowHasAOnePixelHead() throws {
        let base = try picture([
            ".....",
            ".....",
            ".....",
            ".....",
            "....."
        ])
        let annotation = try #require(DocumentAnnotation(.arrow(x0: 0, y0: 2, x1: 4, y1: 2)))
        #expect(try render(base, annotations: [annotation]) == picture([
            ".....",
            "...*.",
            "*****",
            "...*.",
            "....."
        ]))
    }

    @Test func textUsesTheClosedBitmapFont() throws {
        let base = try picture([
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            "......."
        ])
        let annotation = try #require(DocumentAnnotation(.text(x: 0, y: 0, characters: "A")))
        #expect(try render(base, annotations: [annotation]) == picture([
            ".***...",
            "*...*..",
            "*...*..",
            "*****..",
            "*...*..",
            "*...*..",
            "*...*..",
            "......."
        ]))
    }

    @Test func annotationsDrawAboveRedactionsWithoutClearingNeighbourFill() throws {
        let base = try picture([
            ".....",
            ".....",
            ".....",
            ".....",
            "....."
        ])
        let annotation = try #require(DocumentAnnotation(.rectangle(x: 1, y: 1, width: 3, height: 3)))
        #expect(try render(base, [(0, 0, 5, 5)], annotations: [annotation]) == picture([
            "#####",
            "#***#",
            "#*#*#",
            "#***#",
            "#####"
        ]))
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
