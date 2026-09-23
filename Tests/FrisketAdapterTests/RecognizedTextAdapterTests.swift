import AppKit
import CoreGraphics
import Foundation
import FrisketCore
@testable import FrisketAdapters
import ImageIO
import Testing

@MainActor private final class RecordingPasteboard: PasteboardDestination {
    var changeCount = 11
    var items: [NSPasteboardItem] = []
    var options: NSPasteboard.ContentsOptions = []
    var succeeds = true
    func replace(with items: [NSPasteboardItem], options: NSPasteboard.ContentsOptions) -> Int? {
        self.items = items
        self.options = options
        return succeeds ? 11 : nil
    }
}

@Suite @MainActor struct RecognizedTextAdapterTests {
    @Test func writeTextPutsConcealedStringOnCurrentHostOnly() async throws {
        let destination = RecordingPasteboard()
        let adapter = PasteboardAdapter(destination: destination)
        #expect(await adapter.writeText("secret-line") == .success(ClipboardReceipt(changeCount: 11)))
        #expect(destination.options == [.currentHostOnly])
        let item = try #require(destination.items.first)
        #expect(Set(item.types.map(\.rawValue)) == ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        #expect(item.string(forType: .string) == "secret-line")
        #expect(item.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == Data())
    }
}

@Suite @MainActor struct RecognizedTextVisionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_VISION_OCR"] == "1"))
    func realVisionRecognizesUnredactedCanaryAndDropsItAfterRedaction() async throws {
        let png = try canaryTextPNG()
        let recognizer = VisionTextRecognizer()
        let unredacted = await recognizer.recognize(CaptureImage(pngData: png))
        let build = ProcessInfo.processInfo.operatingSystemVersionString
        print("VISION_OCR os_build=\(build) unredacted_count=\(unredacted.count)")
        #expect(unredacted.uppercased().contains("CANARY"),
                "Vision should read CANARY on \(build)")

        let codec = PNGBitmapCodec()
        let base = try #require(codec.decode(png))
        let redaction = try #require(SolidRedaction(x: 0, y: 0, width: Double(base.width), height: Double(base.height)))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        let redactedPNG = try #require(codec.encode(DocumentRenderer.render(EditorDocument(base: base, edits: edits))))
        let redacted = await recognizer.recognize(CaptureImage(pngData: redactedPNG))
        print("VISION_OCR os_build=\(build) redacted_count=\(redacted.count)")
        #expect(redacted.uppercased().contains("CANARY") == false,
                "Redacted canary must be absent on \(build)")
    }
}

private func canaryTextPNG() throws -> Data {
    let width = 640, height = 160
    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        ("CANARY" as NSString).draw(at: NSPoint(x: 32, y: 44), withAttributes: [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black
        ])
        return true
    }
    let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cgImage, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}
