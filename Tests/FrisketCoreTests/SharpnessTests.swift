import CoreGraphics
import Foundation
import FrisketCore
import ImageIO
import Testing

/// Ticket 102 (D32): captures and labels as crisp as CleanShot's, and ticket 104: no white halo.
/// Fixtures are synthetic; the helpers are `CaptureRendererTests`'.
@Suite struct SharpnessTests {
    typealias Helpers = CaptureRendererTests
    static let white: [UInt8] = [0xff, 0xff, 0xff, 0xff]

    static func image(_ bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    static func dpi(_ png: Data) throws -> (x: Double, y: Double)? {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        guard let x = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
              let y = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue else { return nil }
        return (x, y)
    }

    // MARK: PNG density

    /// A Retina capture is marked 72 dpi × the display's scale, as `screencapture` and CleanShot mark
    /// theirs, so viewers that honour the density show it at its point size, pixel for pixel.
    @Test(arguments: [1.0, 2.0, 3.0])
    func aCapturePNGCarriesItsDisplayDensity(scale: Double) throws {
        let width = 12, height = 8
        let pixels = Helpers.pattern(width: width, height: height)
        let png = try #require(CaptureRenderer.capturePNG(try Self.image(pixels, width: width, height: height), scale: scale))
        let density = try #require(try Self.dpi(png))
        #expect(abs(density.x - 72 * scale) < 0.5 && abs(density.y - 72 * scale) < 0.5, "\(density)")
        #expect(Helpers.chunkTypes(png).contains("pHYs"))
        #expect(!Helpers.chunkTypes(png).contains("eXIf"), "no metadata beyond the density")
        #expect(try Helpers.decode(png).bytes == pixels, "the capture's pixels are kept 1:1, not resampled")
    }

    /// Every delivered edit (clipboard, file, drag, History) keeps the capture's density.
    @Test(arguments: [1.0, 2.0])
    func anEditedCaptureKeepsItsDensity(scale: Double) throws {
        let width = 24, height = 16
        let pixels = Helpers.pattern(width: width, height: height)
        let png = try #require(CaptureRenderer.capturePNG(try Self.image(pixels, width: width, height: height), scale: scale))
        let mark = try #require(SolidRedaction(x: 1, y: 1, width: 2, height: 2))
        let crop = try #require(DocumentCrop(x: 0.5, y: 0.5, width: 8, height: 5))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 1, y0: 4, x1: 7, y1: 4)))
        let edits = try #require(DocumentEdits(scale: scale, crop: crop, redactions: [mark], annotations: [arrow]))
        let flattened = try CaptureRenderer().flatten(png, edits: edits)
        let density = try #require(try Self.dpi(flattened))
        #expect(abs(density.x - 72 * scale) < 0.5 && abs(density.y - 72 * scale) < 0.5, "\(density)")
    }

    /// A capture with no density of its own takes the document's scale.
    @Test func aCaptureWithoutADensityTakesTheDocumentScale() throws {
        let png = try Helpers.encode(Helpers.pattern(width: 8, height: 8), width: 8, height: 8)
        #expect(try Self.dpi(png) == nil)
        let edits = try #require(DocumentEdits(scale: 2))
        let density = try #require(try Self.dpi(try CaptureRenderer().flatten(png, edits: edits)))
        #expect(abs(density.x - 144) < 0.5)
    }

    // MARK: Editor preview

    /// A capture of one whole display is previewed at full resolution, so the editor shows its real
    /// pixels (the canvas never has more device pixels than a display).
    @Test func aDisplaySizedCaptureIsPreviewedAtFullResolution() throws {
        #expect(CaptureRenderer.previewMaxEdge >= 6016, "the largest Apple display, decision 60")
        let width = 3584, height = 1972   // the 1,792 × 986 pt window of ticket 102, at 2×
        let png = try Helpers.encode([UInt8](repeating: 0xff, count: width * height * 4), width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        #expect(!preview.isDownscaled && preview.width == width && preview.height == height)
    }

    /// A live drag renders through a smaller preview, so it keeps the 60 Hz frame; the settled edits
    /// render through the full-resolution one. The smaller one keeps D23's leak-free blocks.
    @Test func aLiveDragRendersThroughAReducedPreview() throws {
        let width = 3000, height = 90
        let png = try Helpers.encode(Helpers.pattern(width: width, height: height), width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        #expect(!preview.isDownscaled)
        let live = preview.reduced()
        #expect(live.isDownscaled && live.width == CaptureRenderer.livePreviewMaxEdge)
        #expect((live.captureWidth, live.captureHeight) == (width, height))
        let tall = try CaptureRenderer().preview(png, maxEdge: 1000)
        #expect(tall.reduced().width == tall.width, "an already reduced preview is kept")
        let redaction = try #require(SolidRedaction(x: 101.3, y: 10.2, width: 17.1, height: 9.6))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        let shown = try Helpers.decode(try Self.png(live.render(edits)))
        let columns = (101 * live.width / width)..<((119 * live.width + width - 1) / width)
        let rows = (10 * live.height / height)..<((20 * live.height + height - 1) / height)
        for y in rows { for x in columns {
            let i = (y * live.width + x) * 4
            #expect(shown.bytes[i..<(i + 4)].elementsEqual([0, 0, 0, 0xff]), "live preview pixel (\(x), \(y)) touches the redaction")
        } }
    }

    /// A downscaled preview averages every capture pixel into its block: no column or row of the
    /// capture is dropped, so thin text stems never vanish or double (they did with one sample per block).
    @Test(arguments: [(7, 4), (9, 5), (16, 9), (20, 6)])
    func aDownscaledPreviewDropsNoColumnOrRow(size: Int, maxEdge: Int) throws {
        for line in 0..<size {
            var bytes = [UInt8]()
            for y in 0..<size {
                for x in 0..<size { bytes += (x == line || y == line) ? [0, 0, 0, 0xff] : Self.white }
            }
            let preview = try CaptureRenderer().preview(try Helpers.encode(bytes, width: size, height: size), maxEdge: maxEdge)
            #expect(preview.isDownscaled)
            let edits = try #require(DocumentEdits(scale: 1))
            let shown = try Helpers.decode(try Self.png(preview.render(edits)))
            let columnBlock = line * preview.width / size, rowBlock = line * preview.height / size
            // The block holding the line, on a row (column) away from the crossing line.
            let farRow = rowBlock < preview.height / 2 ? preview.height - 1 : 0
            let farColumn = columnBlock < preview.width / 2 ? preview.width - 1 : 0
            let a = (farRow * preview.width + columnBlock) * 4, b = (rowBlock * preview.width + farColumn) * 4
            #expect(shown.bytes[a] < 0xff, "column \(line) of \(size) vanished at \(preview.width) px")
            #expect(shown.bytes[b] < 0xff, "row \(line) of \(size) vanished at \(preview.height) px")
        }
    }

    static func png(_ image: CGImage) throws -> Data {
        try #require(CaptureRenderer.capturePNG(image, scale: 1))
    }

    // MARK: Labels

    /// A label's baseline sits on a whole output pixel, so the foot of every stem is one sharp edge:
    /// the lowest ink row is solid ink and the row below is the untouched capture.
    @Test(arguments: [1.0, 2.0], [LabelFormat.sizes.min()!, LabelFormat.defaultSize])
    func aLabelsBaselineIsASharpEdge(scale: Double, size: Double) throws {
        let width = Int(80 * scale), height = Int(50 * scale)
        let png = try Helpers.encode([UInt8](repeating: 0xff, count: width * height * 4), width: width, height: height)
        let format = try #require(LabelFormat(size: size))
        let label = try #require(DocumentAnnotation(.text(x: 5.3, y: 10.37, characters: "HIH"), label: format))
        let edits = try #require(DocumentEdits(scale: scale, annotations: [label]))
        let output = try Helpers.decode(try CaptureRenderer().flatten(png, edits: edits))
        let ink = DocumentAnnotation.stroke
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return output.bytes[i..<(i + 4)].elementsEqual([ink.red, ink.green, ink.blue, 0xff])
        }
        let counts = (0..<width).map { x in (0..<height).filter { isInk(x, $0) }.count }
        let stem = try #require(counts.indices.max { counts[$0] < counts[$1] })
        let foot = try #require((0..<height).last { isInk(stem, $0) })
        let below = ((foot + 1) * width + stem) * 4
        #expect(output.bytes[below..<(below + 4)].elementsEqual(Self.white),
                "the row under the stem's foot is partly inked: \(Array(output.bytes[below..<(below + 4)]))")
    }

    // MARK: Ticket 104: no white halo

    /// On a black capture, arrows, lines, shapes and Standard labels leave nothing lighter than their
    /// own ink: no white plate. A Box label's white letters stay inside its box.
    @Test(arguments: [1.0, 2.0])
    func annotationsDrawWithNoWhitePlate(scale: Double) throws {
        let width = Int(120 * scale), height = Int(60 * scale)
        let black = [UInt8](repeating: 0, count: width * height * 4).enumerated().map { $0.offset % 4 == 3 ? 0xff : $0.element }
        let png = try Helpers.encode(black, width: width, height: height)
        let marks = [
            try #require(DocumentAnnotation(.arrow(x0: 5, y0: 5, x1: 50, y1: 25))),
            try #require(DocumentAnnotation(.arrow(x0: 5, y0: 50, x1: 50, y1: 40), style: .line)),
            try #require(DocumentAnnotation(.rectangle(x: 60, y: 5, width: 25, height: 20))),
            try #require(DocumentAnnotation(.text(x: 60, y: 30, characters: "Hi")))
        ]
        let ink = DocumentAnnotation.stroke
        for mark in marks {
            let edits = try #require(DocumentEdits(scale: scale, annotations: [mark]))
            let output = try Helpers.decode(try CaptureRenderer().flatten(png, edits: edits))
            var inked = 0
            for i in stride(from: 0, to: output.bytes.count, by: 4) {
                #expect(output.bytes[i + 1] <= ink.green && output.bytes[i + 2] <= ink.blue,
                        "\(mark.kind) at \(scale)×: pixel \(i / 4 % width), \(i / 4 / width) is lighter than the ink")
                if output.bytes[i] > 0 { inked += 1 }
                if output.bytes[i + 1] > ink.green { break }
            }
            #expect(inked > 0)
        }
        let boxFormat = try #require(LabelFormat(style: .box, size: LabelFormat.defaultSize))
        let boxed = try #require(DocumentAnnotation(.text(x: 20, y: 20, characters: "Hi"), label: boxFormat))
        let output = try Helpers.decode(try CaptureRenderer().flatten(png, edits: try #require(DocumentEdits(scale: scale, annotations: [boxed]))))
        let box = LabelLayout(characters: "Hi", format: boxFormat).bounds
        let minX = Int(((20 + box.x) * scale).rounded(.down)), minY = Int(((20 + box.y) * scale).rounded(.down))
        let maxX = Int(((20 + box.x + box.width) * scale).rounded(.up)), maxY = Int(((20 + box.y + box.height) * scale).rounded(.up))
        for y in 0..<height {
            for x in 0..<width where x < minX || x >= maxX || y < minY || y >= maxY {
                let i = (y * width + x) * 4
                #expect(output.bytes[i..<(i + 4)].elementsEqual([0, 0, 0, 0xff]), "Box at \(scale)×: (\(x), \(y)) outside the box")
                if output.bytes[i] != 0 { return }
            }
        }
    }
}
