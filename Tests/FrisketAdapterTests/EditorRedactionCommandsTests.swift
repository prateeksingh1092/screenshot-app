import AppKit
import CoreGraphics
import Foundation
import FrisketCore
@testable import FrisketAdapters
import ImageIO
import Synchronization
import Testing

private struct RGBA: Hashable { let r, g, b, a: UInt8 }
private let background = RGBA(r: 0x30, g: 0x50, b: 0x70, a: 0xff)
private let opaqueBlack = RGBA(r: 0, g: 0, b: 0, a: 0xff)

/// Synthetic canary fixture: unique colours fill exactly the output pixels each redaction must cover.
private struct CanaryCase: Sendable, CustomTestStringConvertible {
    let scale: Double
    let width: Int, height: Int
    /// Rectangles in document points, and the hand-computed covered output pixels (inclusive ranges).
    let redactions: [(x: Double, y: Double, width: Double, height: Double)]
    let covered: [(columns: ClosedRange<Int>, rows: ClosedRange<Int>, canary: UInt32)]
    var testDescription: String { "\(Int(scale))x" }

    static let all = [
        CanaryCase(scale: 1, width: 40, height: 30,
                   redactions: [(4.5, 3.25, 10, 6.5), (20, 15, 8.25, 5.5)],
                   covered: [(4...14, 3...9, 0xc17a3e), (20...28, 15...20, 0x3ec17a)]),
        CanaryCase(scale: 2, width: 80, height: 60,
                   redactions: [(4.5, 3.25, 10, 6.5), (20, 15, 8.25, 5.5)],
                   covered: [(9...28, 6...19, 0xc17a3e), (40...56, 30...40, 0x3ec17a)])
    ]

    var canaries: Set<RGBA> { Set(covered.map { rgba($0.canary) }) }
    func isCovered(x: Int, y: Int) -> Bool { covered.contains { $0.columns.contains(x) && $0.rows.contains(y) } }
    func edits() throws -> DocumentEdits {
        let redactions = try redactions.map { try #require(SolidRedaction(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
        return try #require(DocumentEdits(scale: scale, redactions: redactions))
    }

    func cropped(_ crop: (x: Double, y: Double, width: Double, height: Double)) throws -> DocumentEdits {
        let redactions = try redactions.map { try #require(SolidRedaction(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
        return try #require(DocumentEdits(scale: scale,
            crop: DocumentCrop(x: crop.x, y: crop.y, width: crop.width, height: crop.height), redactions: redactions))
    }

    func png() throws -> Data {
        var bytes = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let colour = covered.first { $0.columns.contains(x) && $0.rows.contains(y) }.map { rgba($0.canary) } ?? background
                bytes += [colour.r, colour.g, colour.b, colour.a]
            }
        }
        return try encodeSRGB(bytes, width: width, height: height)
    }
}

private func rgba(_ value: UInt32) -> RGBA {
    RGBA(r: UInt8(value >> 16 & 0xff), g: UInt8(value >> 8 & 0xff), b: UInt8(value & 0xff), a: 0xff)
}

private func encodeSRGB(_ bytes: [UInt8], width: Int, height: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

/// Independent of the product codec: draws any output into a fixed sRGB RGBA8 context.
private func decodeSRGB(_ image: CGImage) throws -> (width: Int, height: Int, pixels: [RGBA]) {
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
    let pixels = stride(from: 0, to: bytes.count, by: 4).map { RGBA(r: bytes[$0], g: bytes[$0 + 1], b: bytes[$0 + 2], a: bytes[$0 + 3]) }
    return (image.width, image.height, pixels)
}

private func decodeSRGB(_ png: Data) throws -> (width: Int, height: Int, pixels: [RGBA]) {
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    return try decodeSRGB(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
}

/// Every covered pixel is opaque fill; no canary colour survives anywhere; uncovered pixels are untouched.
private func expectRedacted(_ output: (width: Int, height: Int, pixels: [RGBA]), _ fixture: CanaryCase,
                            sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(output.width == fixture.width && output.height == fixture.height, sourceLocation: sourceLocation)
    guard output.width == fixture.width, output.height == fixture.height else { return }
    var coveredMismatches = 0, uncoveredMismatches = 0, canaries = 0
    for y in 0..<fixture.height {
        for x in 0..<fixture.width {
            let pixel = output.pixels[y * fixture.width + x]
            if fixture.canaries.contains(pixel) { canaries += 1 }
            if fixture.isCovered(x: x, y: y) { coveredMismatches += pixel == opaqueBlack ? 0 : 1 }
            else { uncoveredMismatches += pixel == background ? 0 : 1 }
        }
    }
    #expect(coveredMismatches == 0, sourceLocation: sourceLocation)
    #expect(canaries == 0, sourceLocation: sourceLocation)
    #expect(uncoveredMismatches == 0, sourceLocation: sourceLocation)
}

private struct CanaryPixels: CapturePixelSource {
    let png: Data
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> { .success(CaptureImage(pngData: png)) }
}

private actor RecordingClipboard: ImageClipboard {
    private(set) var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return .success(ClipboardReceipt(changeCount: 100 + images.count))
    }
}

private func historyRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
}

/// Crop in document points; covered ranges are in the cropped output.
private struct CropCanary: Sendable, CustomTestStringConvertible {
    let scale: Double
    let source: CanaryCase
    let crop: (x: Double, y: Double, width: Double, height: Double)
    let outputWidth: Int
    let outputHeight: Int
    let covered: [(columns: ClosedRange<Int>, rows: ClosedRange<Int>)]
    var testDescription: String { "crop \(Int(scale))x" }

    static let all = [
        CropCanary(scale: 1, source: CanaryCase.all[0], crop: (10, 8, 18, 14),
                   outputWidth: 18, outputHeight: 14, covered: [(0...4, 0...1), (10...17, 7...12)]),
        CropCanary(scale: 2, source: CanaryCase.all[1], crop: (10, 8, 18, 14),
                   outputWidth: 36, outputHeight: 28, covered: [(0...8, 0...3), (20...35, 14...24)])
    ]

    func edits() throws -> DocumentEdits { try source.cropped(crop) }

    func expectRedacted(_ output: (width: Int, height: Int, pixels: [RGBA]),
                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(output.width == outputWidth && output.height == outputHeight, sourceLocation: sourceLocation)
        guard output.width == outputWidth, output.height == outputHeight else { return }
        var coveredMismatches = 0, canaries = 0
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let pixel = output.pixels[y * outputWidth + x]
                if source.canaries.contains(pixel) { canaries += 1 }
                if covered.contains(where: { $0.columns.contains(x) && $0.rows.contains(y) }) {
                    coveredMismatches += pixel == opaqueBlack ? 0 : 1
                }
            }
        }
        #expect(coveredMismatches == 0, sourceLocation: sourceLocation)
        #expect(canaries == 0, sourceLocation: sourceLocation)
    }
}

@Suite struct EditorRedactionCommandsTests {
    @Test(arguments: CanaryCase.all)
    private func doneFinalizesTheRenderedRevisionAndHistoryHoldsNoCanaryPixel(fixture: CanaryCase) async throws {
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try fixture.png()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: png),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))

        let rendered = CaptureRevision(captureID: id, number: 2)
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))

        let entry = try #require(try await commands.historyEntries().get().first)
        #expect(entry.revision == 2)
        expectRedacted(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))), fixture)
    }

    @Test(arguments: CanaryCase.all)
    private func thumbnailsRefreshFromTheRenderedRevisionOnly(fixture: CanaryCase) async throws {
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(CaptureRevision(captureID: id, number: 2), .committed))

        #expect(await commands.image(for: original) == nil)
        let rendered = try #require(await commands.image(for: CaptureRevision(captureID: id, number: 2)))
        // Fixtures are smaller than the thumbnail limit, so every output pixel is comparable.
        expectRedacted(try decodeSRGB(try #require(ThumbnailImage.make(from: rendered.pngData, maximumPixelSize: 480))), fixture)
        let entry = try #require(try await commands.historyEntries().get().first)
        let cached = try Data(contentsOf: root.appendingPathComponent(try #require(entry.thumbnailLocation)))
        expectRedacted(try decodeSRGB(cached), fixture)
    }

    @Test(arguments: CanaryCase.all)
    private func doneLeavesOtherClipboardContentAloneAndCopyDeliversOnlyTheRenderedRevision(fixture: CanaryCase) async throws {
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: HistoryStore(root: root), codec: PNGBitmapCodec())
        let other = CaptureID()
        _ = await commands.execute(.capture(other, maximumBytes: 1_000_000))
        _ = await commands.execute(.copy(CaptureRevision(captureID: other, number: 1)))
        #expect(await clipboard.images.count == 1)

        // Frisket never copied this capture, so Done must not touch the clipboard.
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))
        #expect(await clipboard.images.count == 1)

        #expect(await commands.execute(.copy(original)) == .rejected(.staleRevision))
        #expect(await commands.execute(.copy(rendered)) == .copy(CopyOutcome(revision: rendered, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 102)))))
        let delivered = try #require(await clipboard.images.last)
        #expect(await clipboard.images.count == 2)
        expectRedacted(try decodeSRGB(delivered.pngData), fixture)
        let entries = try await commands.historyEntries().get().filter { $0.captureID == id }
        #expect(entries.map(\.revision) == [2])
    }

    @Test func staleAndRepeatedCommandsAfterDoneCannotReachTheOriginal() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: HistoryStore(root: root), codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        _ = await commands.execute(.done(original, try fixture.edits()))

        #expect(await commands.execute(.done(original, try fixture.edits())) == .rejected(.staleRevision))
        #expect(await commands.execute(.dismiss(original)) == .rejected(.staleRevision))
        #expect(await commands.execute(.done(rendered, try fixture.edits())) == .rejected(.alreadyFinalized))
        #expect(await commands.execute(.discard(id)) == .rejected(.alreadyFinalized))
        #expect(await commands.execute(.dismiss(rendered)) == .finalized(rendered, .committed))
        #expect(await commands.image(for: rendered) == nil)
        #expect(try await commands.historyEntries().get().map(\.revision) == [2])
    }

    @Test func doneAfterACommittedCopyIsRefusedSoHistoryNeverHoldsAnUnredactedEditedCapture() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: HistoryStore(root: root), codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        _ = await commands.execute(.copy(original))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .rejected(.alreadyFinalized))
        #expect(await clipboard.images.count == 1)
    }
}

/// Fails the first finalization, then commits through the real store; records every authorized payload.
private actor FlakyHistory: CaptureHistory {
    let store: HistoryStore
    private(set) var requests: [Data] = []
    init(root: URL) { store = HistoryStore(root: root) }
    func recover() async -> Result<HistoryRecoveryReport, HistoryFailure> { await store.recover() }
    func finalize(_ request: AuthorizedFinalization) async -> CommitOutcome {
        requests.append(request.pngData)
        return requests.count == 1 ? .notCommitted(.historyUnavailable) : await store.finalize(request)
    }
    func entries() async -> Result<[HistoryEntry], HistoryFailure> { await store.entries() }
}

extension EditorRedactionCommandsTests {
    @Test func doneCannotGrowThePendingImagePastTheSessionBudget() async throws {
        let png = try encodeSRGB(Array(repeating: [UInt8(48), 80, 112, 255], count: 256).flatMap { $0 }, width: 16, height: 16)
        let codec = PNGBitmapCodec()
        let redaction = try #require(SolidRedaction(x: 3, y: 4, width: 5, height: 7))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        let base = try #require(codec.decode(png))
        let rendered = try #require(codec.encode(DocumentRenderer.render(EditorDocument(base: base, edits: edits))))
        try #require(rendered.count > png.count)
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: png),
            clipboard: RecordingClipboard(), pendingByteLimit: png.count, codec: codec)
        let id = CaptureID(), revision = CaptureRevision(captureID: CaptureID(), number: 1)
        let original = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: png.count))
        #expect(await commands.execute(.done(original, edits)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.image(for: original)?.pngData == png)
        _ = await commands.execute(.discard(id))
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: png.count)) == .pending(revision))
    }

    @Test(arguments: CanaryCase.all)
    private func doneReplacesAnEarlierCopyWhenHistoryFailedWithoutPersistingOriginalPixels(fixture: CanaryCase) async throws {
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: FlakyHistory(root: root), codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        #expect(await commands.execute(.copy(original)) == .copy(CopyOutcome(revision: original,
            commit: .notCommitted(.historyUnavailable), delivery: .copied(ClipboardReceipt(changeCount: 101)))))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))
        expectRedacted(try decodeSRGB(try #require(await clipboard.images.last).pngData), fixture)
        let entry = try #require(try await commands.historyEntries().get().first)
        #expect(entry.revision == 2)
        expectRedacted(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))), fixture)
        let image = try #require(await commands.image(for: rendered))
        expectRedacted(try decodeSRGB(try #require(ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480))), fixture)
        #expect(await commands.image(for: original) == nil)
    }

    @Test(arguments: CanaryCase.all)
    private func failedDoneCommitKeepsOnlyTheRenderedRevisionPendingForRetry(fixture: CanaryCase) async throws {
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let history = FlakyHistory(root: root)
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: history, codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .notCommitted(.historyUnavailable)))
        #expect(await commands.image(for: original) == nil)
        expectRedacted(try decodeSRGB(try #require(await commands.image(for: rendered)).pngData), fixture)
        #expect(await commands.execute(.dismiss(original)) == .rejected(.staleRevision))

        #expect(await commands.execute(.dismiss(rendered)) == .finalized(rendered, .committed))
        let entry = try #require(try await commands.historyEntries().get().first)
        #expect(entry.revision == 2)
        expectRedacted(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))), fixture)
        let requests = await history.requests
        #expect(requests.count == 2)
        for request in requests { expectRedacted(try decodeSRGB(request), fixture) }
    }
}

private actor FailingOnceClipboard: ImageClipboard {
    private(set) var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return images.count == 1 ? .failure(.unavailable) : .success(ClipboardReceipt(changeCount: 7))
    }
}

private enum InterruptedCommit: Error { case stopped }

/// Fault injection at the encoding boundary; subsequent attempts use the real PNG codec.
private final class RejectOnceCodec: BitmapCodec {
    private let attempted = Mutex(false)
    let oversizedBytes: Int?
    init(oversizedBytes: Int?) { self.oversizedBytes = oversizedBytes }
    func decode(_ pngData: Data) -> Bitmap? { PNGBitmapCodec().decode(pngData) }
    func encode(_ bitmap: Bitmap) -> Data? {
        let first = attempted.withLock { attempted in
            defer { attempted = true }
            return !attempted
        }
        if first { return oversizedBytes.map { Data(repeating: 0, count: $0) } }
        return PNGBitmapCodec().encode(bitmap)
    }
}

extension EditorRedactionCommandsTests {
    @Test(arguments: [false, true])
    private func rejectedRedactionDoneCannotDeliverTheOriginalAndCanRetry(oversized: Bool) async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = RecordingClipboard()
        let png = try fixture.png()
        let limit = png.count + 1_000
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: png),
            clipboard: clipboard, pendingByteLimit: limit, history: HistoryStore(root: root),
            codec: RejectOnceCodec(oversizedBytes: oversized ? limit + 1 : nil))
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        let edits = try fixture.edits()
        _ = await commands.execute(.capture(id, maximumBytes: limit))
        #expect(await commands.execute(.done(original, edits)) ==
            .rejected(oversized ? .pendingByteBudgetExceeded : .editingUnavailable))

        // A failed Done must not turn Dismiss, Copy or Quit's Dismiss into an original-pixel leak.
        #expect(await commands.execute(.dismiss(original)) == .rejected(.editingUnavailable))
        #expect(await commands.execute(.copy(original)) == .rejected(.editingUnavailable))
        #expect(await commands.execute(.retryCopy(original)) == .rejected(.editingUnavailable))
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(await clipboard.images.isEmpty)

        #expect(await commands.execute(.done(original, edits)) == .edited(rendered, .committed))
        let entry = try #require(try await commands.historyEntries().get().first)
        expectRedacted(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))), fixture)
        let image = try #require(await commands.image(for: rendered))
        expectRedacted(try decodeSRGB(try #require(ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480))), fixture)
        guard case .copy = await commands.execute(.copy(rendered)) else {
            Issue.record("The accepted redaction must remain deliverable")
            return
        }
        expectRedacted(try decodeSRGB(try #require(await clipboard.images.last).pngData), fixture)
    }
}

extension EditorRedactionCommandsTests {
    @Test(arguments: HistoryCommitPoint.allCases.filter {
        $0 != .rowCommitted && $0 != .thumbnailCached && $0 != .dragStaged && $0 != .dragPromiseWritten
    })
    private func anInterruptedHistoryWriteCannotBecomeAnEditableOriginal(point: HistoryCommitPoint) async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { reached in
            if reached == point { throw InterruptedCommit.stopped }
        })
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: store, codec: PNGBitmapCodec())
        let original = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(original.captureID, maximumBytes: 1_000_000))
        #expect(await commands.execute(.copy(original)) == .copy(CopyOutcome(revision: original,
            commit: .notCommitted(.recoveryRequired), delivery: .copied(ClipboardReceipt(changeCount: 101)))))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .rejected(.editingUnavailable))
    }
}

/// System-boundary stand-in: no general pasteboard is obtained or read by these tests.
@MainActor private final class ConditionalPasteboard: PasteboardDestination {
    var changeCount = 40
    var items: [NSPasteboardItem] = []
    var options: NSPasteboard.ContentsOptions = []
    var succeeds = true
    func replace(with items: [NSPasteboardItem], options: NSPasteboard.ContentsOptions) -> Int? {
        guard succeeds else { return nil }
        self.items = items
        self.options = options
        changeCount += 1
        return changeCount
    }
}

extension EditorRedactionCommandsTests {
    @Test(arguments: CanaryCase.all) @MainActor
    private func repeatedDoneReplacesTheEarlierCopyWhileHistoryRemainsUnavailable(fixture: CanaryCase) async throws {
        let destination = ConditionalPasteboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: PasteboardAdapter(destination: destination), pendingByteLimit: 4_000_000, codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        let first = CaptureRevision(captureID: id, number: 2)
        let second = CaptureRevision(captureID: id, number: 3)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        _ = await commands.execute(.copy(original))
        let allEdits = try fixture.edits()
        let firstEdits = try #require(DocumentEdits(scale: fixture.scale, redactions: [allEdits.redactions[0]]))
        #expect(await commands.execute(.done(original, firstEdits)) == .edited(first, .notCommitted(.historyUnavailable)))
        let secondEdits = try #require(DocumentEdits(scale: fixture.scale, redactions: [allEdits.redactions[1]]))
        #expect(await commands.execute(.done(first, secondEdits)) == .edited(second, .notCommitted(.historyUnavailable)))

        #expect(destination.changeCount == 43)
        expectRedacted(try decodeSRGB(try #require(destination.items.first?.data(forType: .png))), fixture)
        expectRedacted(try decodeSRGB(try #require(await commands.image(for: second)).pngData), fixture)
    }

    @Test @MainActor
    private func replacementFailureIsReportedAndExplicitCopyCanDeliverTheRenderedRevision() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = ConditionalPasteboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: PasteboardAdapter(destination: destination), pendingByteLimit: 4_000_000,
            history: FlakyHistory(root: root), codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        _ = await commands.execute(.copy(original))
        destination.succeeds = false
        #expect(await commands.execute(.done(original, try fixture.edits())) ==
            .edited(rendered, .committed, clipboardFailure: .unavailable))
        destination.succeeds = true
        #expect(await commands.execute(.copy(rendered)) == .copy(CopyOutcome(revision: rendered, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 42)))))
        let item = try #require(destination.items.first)
        expectRedacted(try decodeSRGB(try #require(item.data(forType: .png))), fixture)
    }

    @Test(arguments: [false, true]) @MainActor
    private func earlierCopyIsReplacedOnlyWhileItsChangeCountMatches(changed: Bool) async throws {
        let fixture = CanaryCase.all[1]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = ConditionalPasteboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: PasteboardAdapter(destination: destination), pendingByteLimit: 4_000_000,
            history: FlakyHistory(root: root), codec: PNGBitmapCodec())
        let id = CaptureID(), other = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        _ = await commands.execute(.copy(original))
        let foreign = NSPasteboardItem()
        foreign.setString("synthetic other clipboard content", forType: .string)
        if changed { _ = destination.replace(with: [foreign], options: []) }
        let countBeforeDone = destination.changeCount
        #expect(await commands.execute(.done(original, try fixture.edits())) ==
            .edited(CaptureRevision(captureID: id, number: 2), .committed))
        if changed {
            #expect(destination.changeCount == countBeforeDone)
            #expect(destination.items.first === foreign)
        } else {
            #expect(destination.changeCount == countBeforeDone + 1)
            let item = try #require(destination.items.first)
            #expect(Set(item.types.map(\.rawValue)) == ["public.png", "org.nspasteboard.ConcealedType"])
            #expect(destination.options == [.currentHostOnly])
            expectRedacted(try decodeSRGB(try #require(item.data(forType: .png))), fixture)
        }
        // A receipt belongs to one capture; another capture's Done cannot replace it.
        let beforeOtherDone = destination.changeCount
        _ = await commands.execute(.capture(other, maximumBytes: 1_000_000))
        _ = await commands.execute(.done(CaptureRevision(captureID: other, number: 1), try fixture.edits()))
        #expect(destination.changeCount == beforeOtherDone)
    }
}

extension EditorRedactionCommandsTests {
    @Test func doneAfterAFailedUncommittedCopyStartsTheRenderedRevisionAfresh() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = FailingOnceClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: FlakyHistory(root: root), codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1), rendered = CaptureRevision(captureID: id, number: 2)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        #expect(await commands.execute(.copy(original)) == .copy(CopyOutcome(revision: original,
            commit: .notCommitted(.historyUnavailable), delivery: .failed(.unavailable))))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))

        #expect(await commands.execute(.retryCopy(original)) == .rejected(.staleRevision))
        #expect(await commands.execute(.copy(rendered)) == .copy(CopyOutcome(revision: rendered, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 7)))))
        expectRedacted(try decodeSRGB(try #require(await clipboard.images.last).pngData), fixture)
    }
}

private actor CropDragHandoff: DragHandoff {
    private var recorded: [Data] = []
    func bytes() -> [Data] { recorded }
    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        recorded.append(image.pngData)
        try await events.promiseWriteReturned()
        await events.dragSessionEnded()
        return .copied
    }
}

extension EditorRedactionCommandsTests {
    @Test(arguments: CropCanary.all)
    private func cropKeepsRedactionsCompleteOnEveryOutput(fixture: CropCanary) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        let clipboard = RecordingClipboard()
        let drag = CropDragHandoff()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.source.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { exports }, historyRoot: root),
            drag: drag, dragStaging: DragStagingLifetime(directory: root.appendingPathComponent("staging/drag")),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        let rendered = CaptureRevision(captureID: id, number: 2)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))

        let entry = try #require(try await commands.historyEntries().get().first)
        fixture.expectRedacted(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))))
        let pending = try #require(await commands.image(for: rendered))
        fixture.expectRedacted(try decodeSRGB(pending.pngData))
        fixture.expectRedacted(try decodeSRGB(try #require(ThumbnailImage.make(from: pending.pngData, maximumPixelSize: 480))))
        let cached = try Data(contentsOf: root.appendingPathComponent(try #require(entry.thumbnailLocation)))
        fixture.expectRedacted(try decodeSRGB(cached))

        #expect(await commands.execute(.copy(rendered)) == .copy(CopyOutcome(revision: rendered, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 101)))))
        fixture.expectRedacted(try decodeSRGB(try #require(await clipboard.images.last).pngData))
        guard case let .save(saved) = await commands.execute(.save(rendered)), case let .saved(receipt) = saved.delivery else {
            Issue.record("Cropped Save should succeed"); return
        }
        fixture.expectRedacted(try decodeSRGB(try Data(contentsOf: exports.appendingPathComponent(receipt.filename))))
        #expect(await commands.execute(.drag(rendered, .copy)) == .drag(DragOutcome(revision: rendered, commit: .committed, delivery: .copied)))
        fixture.expectRedacted(try decodeSRGB(try #require(await drag.bytes().last)))
    }
}

private let annotationStroke = RGBA(r: 0xff, g: 0x3b, b: 0x30, a: 0xff)

/// Rectangle outline in output pixels; redaction canaries stay gone, fill stays black off-stroke.
private struct AnnotationCanary: Sendable, CustomTestStringConvertible {
    let source: CanaryCase
    let rectangle: (x: Double, y: Double, width: Double, height: Double)
    let minX: Int, minY: Int, maxX: Int, maxY: Int
    var testDescription: String { "annotation \(Int(source.scale))x" }

    static let all = [
        AnnotationCanary(source: CanaryCase.all[0], rectangle: (2, 2, 8, 6), minX: 2, minY: 2, maxX: 10, maxY: 8),
        AnnotationCanary(source: CanaryCase.all[1], rectangle: (2, 2, 8, 6), minX: 4, minY: 4, maxX: 20, maxY: 16)
    ]

    func edits() throws -> DocumentEdits {
        let annotation = try #require(DocumentAnnotation(.rectangle(x: rectangle.x, y: rectangle.y,
                                                                    width: rectangle.width, height: rectangle.height)))
        return try #require(DocumentEdits(scale: source.scale, redactions: try source.edits().redactions,
                                          annotations: [annotation]))
    }

    func isOutline(x: Int, y: Int) -> Bool {
        (x == minX || x == maxX - 1) && (minY..<maxY).contains(y)
            || (y == minY || y == maxY - 1) && (minX..<maxX).contains(x)
    }

    func expectAnnotated(_ output: (width: Int, height: Int, pixels: [RGBA]),
                         sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(output.width == source.width && output.height == source.height, sourceLocation: sourceLocation)
        guard output.width == source.width, output.height == source.height else { return }
        var strokeMismatches = 0, coveredMismatches = 0, canaries = 0
        for y in 0..<source.height {
            for x in 0..<source.width {
                let pixel = output.pixels[y * source.width + x]
                if source.canaries.contains(pixel) { canaries += 1 }
                if isOutline(x: x, y: y) {
                    strokeMismatches += pixel == annotationStroke ? 0 : 1
                } else if source.isCovered(x: x, y: y) {
                    coveredMismatches += pixel == opaqueBlack ? 0 : 1
                }
            }
        }
        #expect(strokeMismatches == 0, sourceLocation: sourceLocation)
        #expect(coveredMismatches == 0, sourceLocation: sourceLocation)
        #expect(canaries == 0, sourceLocation: sourceLocation)
    }
}

extension EditorRedactionCommandsTests {
    @Test(arguments: AnnotationCanary.all)
    private func annotationsAppearOnEveryOutputWithoutWeakeningRedactions(fixture: AnnotationCanary) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        let clipboard = RecordingClipboard()
        let drag = CropDragHandoff()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.source.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { exports }, historyRoot: root),
            drag: drag, dragStaging: DragStagingLifetime(directory: root.appendingPathComponent("staging/drag")),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        let rendered = CaptureRevision(captureID: id, number: 2)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))

        let entry = try #require(try await commands.historyEntries().get().first)
        fixture.expectAnnotated(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))))
        let pending = try #require(await commands.image(for: rendered))
        fixture.expectAnnotated(try decodeSRGB(pending.pngData))
        fixture.expectAnnotated(try decodeSRGB(try #require(ThumbnailImage.make(from: pending.pngData, maximumPixelSize: 480))))
        let cached = try Data(contentsOf: root.appendingPathComponent(try #require(entry.thumbnailLocation)))
        fixture.expectAnnotated(try decodeSRGB(cached))

        #expect(await commands.execute(.copy(rendered)) == .copy(CopyOutcome(revision: rendered, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 101)))))
        fixture.expectAnnotated(try decodeSRGB(try #require(await clipboard.images.last).pngData))
        guard case let .save(saved) = await commands.execute(.save(rendered)), case let .saved(receipt) = saved.delivery else {
            Issue.record("Annotated Save should succeed"); return
        }
        fixture.expectAnnotated(try decodeSRGB(try Data(contentsOf: exports.appendingPathComponent(receipt.filename))))
        #expect(await commands.execute(.drag(rendered, .copy)) == .drag(DragOutcome(revision: rendered, commit: .committed, delivery: .copied)))
        fixture.expectAnnotated(try decodeSRGB(try #require(await drag.bytes().last)))
    }

    @Test func unchangedEditorLeaveFinalizesToHistory() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        #expect(await commands.execute(EditorLeave.finalize(nil).command(for: original)) == .finalized(original, .committed))
        #expect(try await commands.historyEntries().get().map(\.captureID) == [id])
    }

    @Test func editorDeleteDiscardsWithoutHistory() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        #expect(await commands.execute(EditorLeave.delete.command(for: original)) == .discarded(id))
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(await commands.image(for: original) == nil)
    }

    @Test func logoutDuringAnUnansweredPromptDiscardsThroughTheSameCommand() async throws {
        let fixture = CanaryCase.all[0]
        let root = historyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.png()),
            clipboard: RecordingClipboard(), pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        let leave = try #require(EditorLeave.forInterruptedPrompt(.logout))
        #expect(await commands.execute(leave.command(for: original)) == .discarded(id))
        #expect(try await commands.historyEntries().get().isEmpty)
    }
}

private struct EffectCanary: Sendable, CustomTestStringConvertible {
    let source: CanaryCase
    var testDescription: String { "effect \(Int(source.scale))x" }

    static let all = CanaryCase.all.map(EffectCanary.init)

    func edits() throws -> DocumentEdits {
        let redactions = try source.edits().redactions
        let effects = try source.redactions.flatMap { rectangle -> [DocumentEffect] in
            let blur = try #require(DocumentEffect(.blur(x: rectangle.x, y: rectangle.y,
                                                         width: rectangle.width, height: rectangle.height)))
            let magnify = try #require(DocumentEffect(.magnify(x: rectangle.x, y: rectangle.y,
                                                               width: rectangle.width, height: rectangle.height)))
            return [blur, magnify]
        }
        return try #require(DocumentEdits(scale: source.scale, redactions: redactions, effects: effects))
    }
}

extension EditorRedactionCommandsTests {
    @Test(arguments: EffectCanary.all)
    private func overlappingBlurAndMagnifyCannotRevealARedactionOnAnyOutput(fixture: EffectCanary) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        let clipboard = RecordingClipboard()
        let drag = CropDragHandoff()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: CanaryPixels(png: try fixture.source.png()),
            clipboard: clipboard, pendingByteLimit: 4_000_000, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { exports }, historyRoot: root),
            drag: drag, dragStaging: DragStagingLifetime(directory: root.appendingPathComponent("staging/drag")),
            codec: PNGBitmapCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        let rendered = CaptureRevision(captureID: id, number: 2)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(original))
        #expect(await commands.execute(.done(original, try fixture.edits())) == .edited(rendered, .committed))

        let entry = try #require(try await commands.historyEntries().get().first)
        expectRedacted(try decodeSRGB(Data(contentsOf: root.appendingPathComponent(entry.imageLocation))), fixture.source)
        let pending = try #require(await commands.image(for: rendered))
        expectRedacted(try decodeSRGB(pending.pngData), fixture.source)
        expectRedacted(try decodeSRGB(try #require(ThumbnailImage.make(from: pending.pngData, maximumPixelSize: 480))), fixture.source)
        let cached = try Data(contentsOf: root.appendingPathComponent(try #require(entry.thumbnailLocation)))
        expectRedacted(try decodeSRGB(cached), fixture.source)

        #expect(await commands.execute(.copy(rendered)) == .copy(CopyOutcome(revision: rendered, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 101)))))
        expectRedacted(try decodeSRGB(try #require(await clipboard.images.last).pngData), fixture.source)
        guard case let .save(saved) = await commands.execute(.save(rendered)), case let .saved(receipt) = saved.delivery else {
            Issue.record("Effect Save should succeed"); return
        }
        expectRedacted(try decodeSRGB(try Data(contentsOf: exports.appendingPathComponent(receipt.filename))), fixture.source)
        #expect(await commands.execute(.drag(rendered, .copy)) == .drag(DragOutcome(revision: rendered, commit: .committed, delivery: .copied)))
        expectRedacted(try decodeSRGB(try #require(await drag.bytes().last)), fixture.source)
    }
}
