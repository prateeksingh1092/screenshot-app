import CoreGraphics
import Foundation
import FrisketCore
import ImageIO
import Synchronization
import Testing

/// Ticket 65: the privacy checklist for the native Capture renderer, at the `flatten` seam.
/// Fixtures are synthetic. Every helper here is independent of the product renderer.
@Suite struct CaptureRendererTests {
    /// A deterministic opaque pattern; every pixel in a small image is distinct.
    static func pattern(width: Int, height: Int, seed: UInt8 = 0) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                bytes += [UInt8((x * 7 + y * 3) & 0xff), UInt8((y * 11 + Int(seed)) & 0xff), UInt8((x * 5 + y * 13) & 0xff), 0xff]
            }
        }
        return bytes
    }

    static func encode(_ bytes: [UInt8], width: Int, height: Int, space: CFString = CGColorSpace.sRGB,
                       properties: [CFString: Any]? = nil) throws -> Data {
        let colourSpace = try #require(CGColorSpace(name: space))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colourSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// Draws any PNG into a fixed sRGB RGBA8 premultiplied bitmap.
    static func decode(_ png: Data) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
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
        return (image.width, image.height, bytes)
    }

    /// The same snapping the editor documents: minimum edges down, maximum edges up, in output pixels.
    static func snapped(_ x: Double, _ y: Double, _ width: Double, _ height: Double, scale: Double)
    -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        (Int((x * scale).rounded(.down)), Int((y * scale).rounded(.down)),
         Int(((x + width) * scale).rounded(.up)), Int(((y + height) * scale).rounded(.up)))
    }

    static func chunkTypes(_ png: Data) -> [String] {
        var types: [String] = []
        let bytes = [UInt8](png)
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            types.append(String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self))
            offset += 12 + length
        }
        return types
    }

    // 1. Crop is integer-aligned with no resampling.
    @Test(arguments: [1.0, 2.0])
    func cropCopiesWholeSourcePixelsWithNoResampling(scale: Double) throws {
        let width = 37, height = 23
        let source = Self.pattern(width: width, height: height)
        let png = try Self.encode(source, width: width, height: height)
        let crop = try #require(DocumentCrop(x: 3.3 / scale, y: 2.7 / scale, width: 20.2 / scale, height: 11.9 / scale))
        let edits = try #require(DocumentEdits(scale: scale, crop: crop))
        let output = try Self.decode(try CaptureRenderer().flatten(png, edits: edits))
        let box = Self.snapped(crop.x, crop.y, crop.width, crop.height, scale: scale)
        #expect(output.width == box.maxX - box.minX && output.height == box.maxY - box.minY)
        var expected = [UInt8]()
        for y in box.minY..<box.maxY {
            let start = (y * width + box.minX) * 4
            expected += source[start..<(start + (box.maxX - box.minX) * 4)]
        }
        #expect(output.bytes == expected, "the crop must copy whole source pixels, byte for byte")
    }

    // 2. Byte-exact redaction goldens, for the default fill and for fills passed as data (decision 61).
    @Test(arguments: [SolidRedaction.fill, RGBAPixel(red: 0xff, green: 0xff, blue: 0xff, alpha: 0xff),
                      RGBAPixel(red: 0x80, green: 0x80, blue: 0x80, alpha: 0xff)])
    func solidRedactionIsByteExactInTheChosenColour(colour: RGBAPixel) throws {
        let width = 48, height = 32, scale = 2.0
        let source = Self.pattern(width: width, height: height)
        let png = try Self.encode(source, width: width, height: height)
        let marks = [(1.25, 2.5, 5.5, 3.3), (15.0, 9.75, 7.0, 6.0)]
        let redactions = try marks.map { try #require(SolidRedaction(x: $0.0, y: $0.1, width: $0.2, height: $0.3, colour: colour)) }
        let crop = try #require(DocumentCrop(x: 0.5, y: 0.75, width: 22.5, height: 14.5))
        let edits = try #require(DocumentEdits(scale: scale, crop: crop, redactions: redactions))
        let output = try Self.decode(try CaptureRenderer().flatten(png, edits: edits))

        let origin = Self.snapped(crop.x, crop.y, crop.width, crop.height, scale: scale)
        var expected = [UInt8]()
        for y in origin.minY..<origin.maxY {
            let start = (y * width + origin.minX) * 4
            expected += source[start..<(start + (origin.maxX - origin.minX) * 4)]
        }
        let outputWidth = origin.maxX - origin.minX, outputHeight = origin.maxY - origin.minY
        for mark in marks {
            let box = Self.snapped(mark.0, mark.1, mark.2, mark.3, scale: scale)
            for y in max(0, box.minY - origin.minY)..<min(outputHeight, box.maxY - origin.minY) {
                for x in max(0, box.minX - origin.minX)..<min(outputWidth, box.maxX - origin.minX) {
                    let i = (y * outputWidth + x) * 4
                    expected.replaceSubrange(i..<(i + 4), with: [colour.red, colour.green, colour.blue, colour.alpha])
                }
            }
        }
        #expect(output.width == outputWidth && output.height == outputHeight)
        #expect(output.bytes == expected, "every redacted pixel is the chosen colour at alpha 255; every other pixel is the source")
    }

    @Test func aTranslucentRedactionColourIsRefused() {
        #expect(SolidRedaction(x: 0, y: 0, width: 4, height: 4,
                               colour: RGBAPixel(red: 0, green: 0, blue: 0, alpha: 254)) == nil)
    }

    // 3. Effects never read outside their box or under a redaction.
    @Test func effectsReadNeitherUnderARedactionNorOutsideTheirBox() throws {
        let width = 64, height = 48
        let redaction = try #require(SolidRedaction(x: 20, y: 16, width: 10, height: 8))
        let blur = try #require(DocumentEffect(.blur(x: 14, y: 10, width: 24, height: 20)))
        let magnify = try #require(DocumentEffect(.magnify(x: 18, y: 14, width: 16, height: 12)))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction], effects: [blur, magnify]))
        let effectBox = (minX: 14, minY: 10, maxX: 38, maxY: 30)
        let secretBox = (minX: 20, minY: 16, maxX: 30, maxY: 24)
        let base = Self.pattern(width: width, height: height)
        // Same pixels inside the effect box except under the redaction; different pixels everywhere else.
        var other = Self.pattern(width: width, height: height, seed: 97)
        for y in effectBox.minY..<effectBox.maxY {
            for x in effectBox.minX..<effectBox.maxX {
                let i = (y * width + x) * 4
                let secret = x >= secretBox.minX && x < secretBox.maxX && y >= secretBox.minY && y < secretBox.maxY
                if !secret { other.replaceSubrange(i..<(i + 4), with: base[i..<(i + 4)]) }
            }
        }
        let first = try Self.decode(try CaptureRenderer().flatten(try Self.encode(base, width: width, height: height), edits: edits))
        let second = try Self.decode(try CaptureRenderer().flatten(try Self.encode(other, width: width, height: height), edits: edits))
        var differing = 0
        for y in effectBox.minY..<effectBox.maxY {
            for x in effectBox.minX..<effectBox.maxX {
                let i = (y * width + x) * 4
                if first.bytes[i..<(i + 4)] != second.bytes[i..<(i + 4)] { differing += 1 }
            }
        }
        #expect(differing == 0, "effect output depends on pixels under a redaction or outside the effect box")
    }

    /// Ticket 67: a Solid redaction under Blur and Magnify stays exactly its colour at alpha 255,
    /// whatever the colour (decision 61), including where Magnify enlarges the redacted pixels.
    @Test(arguments: [SolidRedaction.fill, RGBAPixel(red: 0xff, green: 0xff, blue: 0xff, alpha: 0xff),
                      RGBAPixel(red: 0x80, green: 0x80, blue: 0x80, alpha: 0xff)])
    func redactionUnderBlurAndMagnifyStaysItsExactColour(colour: RGBAPixel) throws {
        let width = 40, height = 40
        let redaction = try #require(SolidRedaction(x: 8, y: 8, width: 12, height: 10, colour: colour))
        let blur = try #require(DocumentEffect(.blur(x: 4, y: 4, width: 24, height: 20)))
        let magnify = try #require(DocumentEffect(.magnify(x: 6, y: 6, width: 30, height: 30)))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction], effects: [blur, magnify]))
        let output = try Self.decode(try CaptureRenderer().flatten(
            try Self.encode(Self.pattern(width: width, height: height), width: width, height: height), edits: edits))
        for y in 8..<18 {
            for x in 8..<20 {
                let i = (y * width + x) * 4
                #expect(Array(output.bytes[i..<(i + 4)]) == [colour.red, colour.green, colour.blue, 0xff],
                        "redacted pixel (\(x), \(y)) is not exactly the redaction colour")
            }
        }
    }

    /// Ticket 67: Blur (vImage) and Magnify (CoreGraphics) are deterministic. The golden is the
    /// FNV-1a hash of the decoded pixels, measured on x86_64; arm64 must match it too (decision 56).
    @Test func effectOutputHashIsStable() throws {
        let width = 96, height = 80, scale = 2.0
        let redaction = try #require(SolidRedaction(x: 10, y: 10, width: 6, height: 5))
        let blur = try #require(DocumentEffect(.blur(x: 2.25, y: 3.5, width: 30, height: 20.5)))
        let magnify = try #require(DocumentEffect(.magnify(x: 20, y: 15, width: 21.5, height: 17)))
        let crop = try #require(DocumentCrop(x: 0.5, y: 1, width: 45, height: 37))
        let edits = try #require(DocumentEdits(scale: scale, crop: crop, redactions: [redaction], effects: [blur, magnify]))
        let output = try Self.decode(try CaptureRenderer().flatten(
            try Self.encode(Self.pattern(width: width, height: height), width: width, height: height), edits: edits))
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in output.bytes { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        #expect(String(hash, radix: 16) == "758bcf3ed5875618", "Blur and Magnify output changed")
    }

    // 4. A fixed sRGB working space.
    @Test func outputIsInSRGBWhateverTheCaptureSpace() throws {
        let width = 8, height = 4
        let bytes: [UInt8] = Array(repeating: [UInt8(0xe0), 0x40, 0x20, 0xff], count: width * height).flatMap { $0 }
        let png = try Self.encode(bytes, width: width, height: height, space: CGColorSpace.displayP3)
        let mark = try #require(SolidRedaction(x: 0, y: 0, width: 1, height: 1))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [mark]))
        let flattened = try CaptureRenderer().flatten(png, edits: edits)
        let source = try #require(CGImageSourceCreateWithData(flattened as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB, "the delivered PNG is tagged sRGB")
        let expected = try Self.decode(png)
        let output = try Self.decode(flattened)
        #expect(Array(output.bytes[4...]) == Array(expected.bytes[4...]), "P3 pixels are converted to sRGB once, not copied raw")
        #expect(Array(output.bytes[4..<8]) != [0xe0, 0x40, 0x20, 0xff])
    }

    // 7. The PNG carries no metadata.
    @Test func deliveredPNGCarriesNoMetadata() throws {
        let width = 6, height = 5
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "canary-description",
                                           kCGImagePropertyPNGAuthor: "canary-author"],
            kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144
        ]
        let png = try Self.encode(Self.pattern(width: width, height: height), width: width, height: height, properties: properties)
        #expect(String(decoding: png, as: UTF8.self).contains("canary-description"), "the fixture carries text metadata")
        let mark = try #require(SolidRedaction(x: 1, y: 1, width: 2, height: 2))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [mark]))
        let flattened = try CaptureRenderer().flatten(png, edits: edits)
        let types = Self.chunkTypes(flattened)
        #expect(types.first == "IHDR" && types.last == "IEND")
        let allowed: Set<String> = ["IHDR", "sRGB", "iCCP", "gAMA", "cHRM", "IDAT", "IEND"]
        #expect(Set(types).isSubset(of: allowed), "unexpected chunks: \(Set(types).subtracting(allowed).sorted())")
        #expect(!String(decoding: flattened, as: UTF8.self).contains("canary"))
    }

    // DA-6: taller output is refused before the capture is decoded or any output is allocated.
    @Test func outputTallerThanTheCapIsRefusedBeforeDecoding() throws {
        let tall = CaptureRenderer.maximumOutputHeight + 1
        // A valid signature and IHDR, followed by an IDAT that cannot decode.
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        func chunk(_ type: String, _ payload: [UInt8]) {
            let length = UInt32(payload.count)
            png.append(contentsOf: [UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
            var crc: UInt32 = 0xffff_ffff
            for byte in Array(type.utf8) + payload {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
            }
            crc ^= 0xffff_ffff
            png.append(contentsOf: Array(type.utf8) + payload
                       + [UInt8(crc >> 24), UInt8(crc >> 16 & 0xff), UInt8(crc >> 8 & 0xff), UInt8(crc & 0xff)])
        }
        chunk("IHDR", [0, 0, 0, 1, UInt8(tall >> 24), UInt8(tall >> 16 & 0xff), UInt8(tall >> 8 & 0xff), UInt8(tall & 0xff), 8, 6, 0, 0, 0])
        chunk("IDAT", [1, 2, 3])
        chunk("IEND", [])
        let edits = try #require(DocumentEdits(scale: 1))
        #expect(throws: RenderFailure.outputTooTall(height: tall)) { try CaptureRenderer().flatten(png, edits: edits) }
    }

    @Test func aCropBackUnderTheCapIsRendered() throws {
        let width = 2, height = CaptureRenderer.maximumOutputHeight + 1
        let bytes: [UInt8] = Array(repeating: [UInt8(9), 8, 7, 255], count: width * height).flatMap { $0 }
        let png = try Self.encode(bytes, width: width, height: height)
        let full = try #require(DocumentEdits(scale: 1))
        #expect(throws: RenderFailure.outputTooTall(height: height)) { try CaptureRenderer().flatten(png, edits: full) }
        let cropped = try #require(DocumentEdits(scale: 1, crop: DocumentCrop(x: 0, y: 1, width: 2, height: Double(height - 1))))
        let output = try Self.decode(try CaptureRenderer().flatten(png, edits: cropped))
        #expect(output.width == width && output.height == CaptureRenderer.maximumOutputHeight)
    }

    @Test func aCaptureThatIsNotAPNGIsRefused() throws {
        let edits = try #require(DocumentEdits(scale: 1))
        #expect(throws: RenderFailure.unreadableCapture) { try CaptureRenderer().flatten(Data([1, 2, 3]), edits: edits) }
    }

    /// D1 at the production seam: on the live repro (400 × 500, an arrow at row 450, a label near
    /// the bottom) and on taller outputs, the delivered image equals the preview exactly. Every
    /// arrow and label appears once, where it was drawn: its ink is present in its own rows only.
    @Test(arguments: [(400, 500), (48, 257), (64, 2000)])
    func d1DeliveredAnnotationsEqualThePreviewAndAppearWhereDrawn(width: Int, height: Int) throws {
        let png = try Self.encode(Self.pattern(width: width, height: height), width: width, height: height)
        let w = Double(width), h = Double(height)
        let arrow = try #require(DocumentAnnotation(.arrow(x0: w * 0.1, y0: h * 0.9, x1: w * 0.8, y1: h * 0.9 - 3)))
        let label = try #require(DocumentAnnotation(.text(x: 2, y: h - 30, characters: "v2.1 $4.99 -10%")))
        let outline = try #require(DocumentAnnotation(.rectangle(x: 3, y: h * 0.4, width: w / 2, height: h / 3)))
        let redaction = try #require(SolidRedaction(x: 1, y: h * 0.45, width: w / 3, height: h / 4))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction], annotations: [outline, arrow, label]))
        let preview = try previewed(try CaptureRenderer().preview(png), edits)
        let output = try Self.decode(try CaptureRenderer().flatten(png, edits: edits))
        #expect(output.bytes == preview.bytes, "D1: delivered annotations differ from the preview")
        let ink = DocumentAnnotation.stroke
        var inkRows = Set<Int>()
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if output.bytes[i] == ink.red && output.bytes[i + 1] == ink.green && output.bytes[i + 2] == ink.blue {
                    inkRows.insert(y)
                }
            }
        }
        let arrowRow = Int(h * 0.9)
        #expect(inkRows.contains(arrowRow - 1) || inkRows.contains(arrowRow), "D1: the arrow at row \(arrowRow) is missing")
        #expect(inkRows.contains { $0 > height - 30 && $0 < height - 8 }, "D1: the label is missing")
        #expect(!inkRows.contains { $0 < Int(h * 0.4) - 2 }, "D1: ink appears above every mark (a repeated label?)")
    }

    /// Delivered image = editor preview: at full size the flattened output equals the preview's render.
    @Test func flattenedOutputEqualsThePreviewRenderAtFullSize() throws {
        let width = 120, height = 90, scale = 2.0
        let png = try Self.encode(Self.pattern(width: width, height: height), width: width, height: height)
        let label = try #require(DocumentAnnotation(.text(x: 2, y: 3, characters: "HI")))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 2, y0: 40, x1: 50, y1: 30)))
        let redaction = try #require(SolidRedaction(x: 10.3, y: 12.6, width: 8, height: 6))
        let blur = try #require(DocumentEffect(.blur(x: 6, y: 10, width: 20, height: 15)))
        let magnify = try #require(DocumentEffect(.magnify(x: 30, y: 20, width: 12, height: 10)))
        let crop = try #require(DocumentCrop(x: 1.5, y: 2.25, width: 55, height: 40))
        let edits = try #require(DocumentEdits(scale: scale, crop: crop, redactions: [redaction],
                                               annotations: [label, arrow], effects: [blur, magnify]))
        let preview = try previewed(try CaptureRenderer().preview(png), edits)
        let output = try Self.decode(try CaptureRenderer().flatten(png, edits: edits))
        #expect(output.width == preview.width && output.height == preview.height)
        #expect(output.bytes == preview.bytes)
    }
}

/// Records when the one capture it produced is freed. The test itself never holds the bytes.
private final class ReleaseFlag: Sendable {
    let value = Mutex(false)
}

private final class ReleaseTrackingPixels: CapturePixelSource {
    private let freed = ReleaseFlag()
    private let png: [UInt8]
    init(png: Data) { self.png = [UInt8](png) }
    var released: Bool { freed.value.withLock { $0 } }

    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: png.count, alignment: 1)
        png.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: png.count) }
        let data = Data(bytesNoCopy: storage, count: png.count, deallocator: .custom { [freed] pointer, _ in
            pointer.deallocate()
            freed.value.withLock { $0 = true }
        })
        return .success(CaptureImage(pngData: data))
    }
}

private actor AcceptingClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

private actor RecordingRecognizer: TextRecognizer {
    private(set) var inputs: [Data] = []
    func recognize(_ image: CaptureImage) async -> String {
        inputs.append(image.pngData)
        return "text"
    }
}

private actor AcceptingTextClipboard: TextClipboard {
    func writeText(_ text: String) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 2))
    }
}

/// Privacy checklist items 5 and 6, at the coordinator's flatten seam.
@Suite struct CaptureRendererLifecycleTests {
    // 6. The original is released on Delete, and on Done once the rendered revision replaces it.
    @Test(arguments: [EditorLeave.delete, .finalize(DocumentEdits(scale: 1, redactions: [SolidRedaction(x: 1, y: 1, width: 2, height: 2)!]))])
    func leavingTheEditorReleasesTheOriginalCapture(leave: EditorLeave) async throws {
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: 8, height: 6), width: 8, height: 6)
        let source = ReleaseTrackingPixels(png: png)
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: source, clipboard: AcceptingClipboard(),
                                           pendingByteLimit: 4_000_000, flattener: CaptureRenderer())
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: 1_000_000)) == .pending(revision))
        #expect(!source.released)
        _ = await commands.execute(leave.command(for: revision))
        #expect(await commands.image(for: revision) == nil)
        #expect(source.released, "the original capture's bytes are still held after \(leave)")
    }

    // 5. OCR reads only the rendered result.
    @Test func copyTextAfterDoneReadsOnlyTheFlattenedOutput() async throws {
        let original = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: 8, height: 6), width: 8, height: 6)
        let flattened = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: 8, height: 6, seed: 5), width: 8, height: 6)
        let flattener = ScriptedFlattener(always: flattened)
        let recognizer = RecordingRecognizer()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: ReleaseTrackingPixels(png: original),
                                           clipboard: AcceptingClipboard(), pendingByteLimit: 4_000_000, flattener: flattener,
                                           textRecognizer: recognizer, textClipboard: AcceptingTextClipboard())
        let id = CaptureID()
        let first = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        let mark = try #require(SolidRedaction(x: 0, y: 0, width: 4, height: 4))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [mark]))
        #expect(await commands.execute(.render(first, edits)) == .rendered(rendered, clipboardFailure: nil))
        #expect(flattener.inputs == [original])
        _ = await commands.execute(.copyRecognizedText(rendered))
        #expect(await recognizer.inputs == [flattened])
    }
}
