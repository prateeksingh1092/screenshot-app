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

/// A system clipboard stand-in whose change count moves on every replacement, as NSPasteboard's does.
@MainActor private final class CountingPasteboard: PasteboardDestination {
    private(set) var changeCount = 11
    private(set) var replacements = 0
    func replace(with items: [NSPasteboardItem], options: NSPasteboard.ContentsOptions) -> Int? {
        replacements += 1
        changeCount += 1
        return changeCount
    }
}

private struct SyntheticPixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: Data([1, 2, 3])))
    }
}

private struct NoTextRecognizer: TextRecognizer {
    func recognize(_ image: CaptureImage) async -> String { "" }
}

@Suite struct RecognizedTextClipboardTests {
    /// D8 (DA-5, story 89), through the real pasteboard adapter: an empty recognition result must
    /// not change the system clipboard's change count or contents.
    @Test func d8CopyTextWithNoTextLeavesTheSystemClipboardUnchanged() async throws {
        try await knownDefect("D8") {
            let destination = await CountingPasteboard()
            let adapter = await PasteboardAdapter(destination: destination)
            let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SyntheticPixels(),
                clipboard: adapter, pendingByteLimit: 1024, textRecognizer: NoTextRecognizer(), textClipboard: adapter)
            let id = CaptureID()
            let revision = CaptureRevision(captureID: id, number: 1)
            #expect(await commands.execute(.capture(id, maximumBytes: 64)) == .pending(revision))
            _ = await commands.execute(.copyRecognizedText(revision))
            let changeCount = await destination.changeCount
            #expect(changeCount == 11, "D8: the clipboard's change count moved")
            let replacements = await destination.replacements
            #expect(replacements == 0, "D8: the clipboard's contents were replaced")
        }
    }
}
