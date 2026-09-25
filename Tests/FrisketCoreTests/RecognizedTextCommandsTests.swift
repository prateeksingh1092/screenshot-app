import Foundation
import FrisketCore
import Testing

private struct FixturePixels: CapturePixelSource {
    let bytes: Data
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private actor RecordingTextClipboard: TextClipboard {
    private(set) var texts: [String] = []
    func writeText(_ text: String) async -> Result<ClipboardReceipt, ClipboardFailure> {
        texts.append(text)
        return .success(ClipboardReceipt(changeCount: texts.count))
    }
}

private actor IgnoringImageClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

private struct FixedRecognizer: TextRecognizer {
    let text: String
    func recognize(_ image: CaptureImage) async -> String { text }
}

private actor GatedRecognizer: TextRecognizer {
    private let text: String
    private var waiting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(text: String) { self.text = text }

    func recognize(_ image: CaptureImage) async -> String {
        await withCheckedContinuation { continuation in
            waiting = continuation
            started?.resume()
            started = nil
        }
        return text
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            if waiting != nil {
                continuation.resume()
            } else {
                started = continuation
            }
        }
    }

    func release() {
        waiting?.resume()
        waiting = nil
    }
}

private struct ByteRecognizer: TextRecognizer {
    func recognize(_ image: CaptureImage) async -> String {
        image.pngData == Data([9, 9, 9]) ? "" : "CANARY"
    }
}

private struct LoopCodec: BitmapCodec {
    func decode(_ pngData: Data) -> Bitmap? {
        Bitmap(width: 1, height: 1, pixels: [RGBAPixel(red: 1, green: 2, blue: 3, alpha: 255)])
    }
    func encode(_ bitmap: Bitmap) -> Data? { Data([9, 9, 9]) }
}

private actor RecordingDiagnostics: DiagnosticSink {
    private(set) var events: [DiagnosticEvent] = []
    func record(_ event: DiagnosticEvent) async { events.append(event) }
}

@Suite struct RecognizedTextCommandsTests {
    @Test func copyRecognizedTextUsesTheCurrentRevisionAndReportsOnlyTheCount() async throws {
        let clipboard = RecordingTextClipboard()
        let diagnostics = RecordingDiagnostics()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: FixturePixels(bytes: Data([1, 2, 3])), clipboard: IgnoringImageClipboard(),
            pendingByteLimit: 1024, diagnostics: diagnostics,
            textRecognizer: FixedRecognizer(text: "secret-line"), textClipboard: clipboard)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 64)) == .pending(revision))
        #expect(await commands.execute(.copyRecognizedText(revision)) ==
            .recognizedText(RecognizedTextOutcome(revision: revision, characterCount: 11,
                                                  delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await clipboard.texts == ["secret-line"])
        let events = await diagnostics.events
        #expect(events.contains { $0.operation == .copyRecognizedText && $0.name == .deliverySucceeded })
        #expect(events.allSatisfy { "\($0)".contains("secret-line") == false })
    }

    @Test func staleRevisionResultsAreDroppedAndDoNotWriteTheClipboard() async throws {
        let recognizer = GatedRecognizer(text: "late-secret")
        let clipboard = RecordingTextClipboard()
        let codec = LoopCodec()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: FixturePixels(bytes: Data([1, 2, 3])), clipboard: IgnoringImageClipboard(),
            pendingByteLimit: 4_000_000, codec: codec,
            textRecognizer: recognizer, textClipboard: clipboard)
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        async let copied = commands.execute(.copyRecognizedText(original))
        await recognizer.waitUntilStarted()
        let redaction = try #require(SolidRedaction(x: 0, y: 0, width: 1, height: 1))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        #expect(await commands.execute(.done(original, edits)) ==
            .edited(CaptureRevision(captureID: id, number: 2), .notCommitted(.historyUnavailable)))
        await recognizer.release()
        #expect(await copied == .rejected(.staleRevision))
        #expect(await clipboard.texts.isEmpty)
    }

    @Test func copyRecognizedTextAfterDoneUsesTheRenderedRevisionStandIn() async throws {
        let clipboard = RecordingTextClipboard()
        let codec = LoopCodec()
        let recognizer = ByteRecognizer()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: FixturePixels(bytes: Data([1, 2, 3])), clipboard: IgnoringImageClipboard(),
            pendingByteLimit: 4_000_000, codec: codec,
            textRecognizer: recognizer, textClipboard: clipboard)
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        let rendered = CaptureRevision(captureID: id, number: 2)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        #expect(await commands.execute(.copyRecognizedText(original)) ==
            .recognizedText(RecognizedTextOutcome(revision: original, characterCount: 6,
                                                  delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await clipboard.texts == ["CANARY"])
        let redaction = try #require(SolidRedaction(x: 0, y: 0, width: 1, height: 1))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        #expect(await commands.execute(.done(original, edits)) ==
            .edited(rendered, .notCommitted(.historyUnavailable)))
        #expect(await commands.execute(.copyRecognizedText(rendered)) ==
            .recognizedText(RecognizedTextOutcome(revision: rendered, characterCount: 0,
                                                  delivery: .copied(ClipboardReceipt(changeCount: 2)))))
        #expect(await clipboard.texts == ["CANARY", ""])
    }

    @Test func missingRecognizerIsRejectedWithoutWritingText() async throws {
        let clipboard = RecordingTextClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: FixturePixels(bytes: Data([9])), clipboard: IgnoringImageClipboard(),
            pendingByteLimit: 1024, textClipboard: clipboard)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 16)) == .pending(revision))
        #expect(await commands.execute(.copyRecognizedText(revision)) == .rejected(.recognitionUnavailable))
        #expect(await clipboard.texts.isEmpty)
    }
}

extension RecognizedTextCommandsTests {
    /// D8 (DA-5, story 89): Copy Text on a capture with no text leaves the clipboard exactly as it
    /// was. Today it writes an empty string over whatever the user had copied.
    @Test func d8CopyTextWithNoTextLeavesTheClipboardUnwritten() async throws {
        try await knownDefect("D8") {
            let clipboard = RecordingTextClipboard()
            let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
                source: FixturePixels(bytes: Data([1, 2, 3])), clipboard: IgnoringImageClipboard(),
                pendingByteLimit: 1024, textRecognizer: FixedRecognizer(text: ""), textClipboard: clipboard)
            let id = CaptureID()
            let revision = CaptureRevision(captureID: id, number: 1)
            #expect(await commands.execute(.capture(id, maximumBytes: 64)) == .pending(revision))
            _ = await commands.execute(.copyRecognizedText(revision))
            let written = await clipboard.texts
            #expect(written.isEmpty, "D8: Copy Text with no text wrote \(written) to the clipboard")
            #expect(await commands.image(for: revision) != nil, "D8: the capture stays pending")
        }
    }
}
