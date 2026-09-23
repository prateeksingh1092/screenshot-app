import FrisketCore
import Testing

/// Literal pictures: each character is one output pixel, rows top to bottom.
private let palette: [Character: RGBAPixel] = [
    ".": RGBAPixel(red: 0x20, green: 0x40, blue: 0x60, alpha: 0xff),
    "a": RGBAPixel(red: 0xc1, green: 0x7a, blue: 0x3e, alpha: 0xff),
    "t": RGBAPixel(red: 0x40, green: 0x10, blue: 0x08, alpha: 0x80), // premultiplied, half transparent
    "#": RGBAPixel(red: 0, green: 0, blue: 0, alpha: 0xff)
]

private func picture(_ rows: [String]) throws -> Bitmap {
    let pixels = try rows.flatMap { row in
        try row.map { character in try #require(palette[character]) }
    }
    return try #require(Bitmap(width: rows[0].count, height: rows.count, pixels: pixels))
}

private func render(_ base: Bitmap, scale: Double = 1, _ rectangles: [(Double, Double, Double, Double)]) throws -> Bitmap {
    let redactions = try rectangles.map { try #require(SolidRedaction(x: $0.0, y: $0.1, width: $0.2, height: $0.3)) }
    let edits = try #require(DocumentEdits(scale: scale, redactions: redactions))
    return DocumentRenderer.render(EditorDocument(base: base, edits: edits))
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
        }
        for scale: Double in [0, -2, .nan, .infinity] { #expect(DocumentEdits(scale: scale) == nil) }
        #expect(Bitmap(width: 2, height: 1, bytes: [0, 0, 0, 255]) == nil)
    }
}
