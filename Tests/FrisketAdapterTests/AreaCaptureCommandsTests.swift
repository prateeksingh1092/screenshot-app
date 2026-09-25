import AppKit
import FrisketCore
@testable import FrisketAdapters
import Testing

@MainActor private final class RecordingPasteboard: PasteboardDestination {
    var changeCount = 73
    var items: [NSPasteboardItem] = []
    var options: NSPasteboard.ContentsOptions = []
    var succeeds = true
    func replace(with items: [NSPasteboardItem], options: NSPasteboard.ContentsOptions) -> Int? {
        self.items = items
        self.options = options
        return succeeds ? 73 : nil
    }
}

private struct FixtureSource: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: Data([0x89, 0x50, 0x4e, 0x47])))
    }
}

@Suite @MainActor struct AreaCaptureCommandsTests {
    @Test func copyWritesPNGAndConcealedMarkerWithCurrentHostOnly() async throws {
        let destination = RecordingPasteboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: FixtureSource(), clipboard: PasteboardAdapter(destination: destination),
                                            pendingByteLimit: 32)
        let id = CaptureID()
        _ = await commands.execute(.capture(id, maximumBytes: 32))
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable),
            delivery: .copied(ClipboardReceipt(changeCount: 73)))))
        #expect(destination.options == [.currentHostOnly])
        #expect(destination.items.count == 1)
        let item = try #require(destination.items.first)
        #expect(Set(item.types.map(\.rawValue)) == ["public.png", "org.nspasteboard.ConcealedType"])
        #expect(item.data(forType: .png) == Data([0x89, 0x50, 0x4e, 0x47]))
        #expect(item.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == Data())
    }
}

@MainActor private final class RecordingCapturePlatform: AreaCapturePlatform {
    let spaceGeneration: UInt64 = 0
    var events: [String] = []
    var selection: AreaSelection? = AreaSelection(displayID: 7,
        displayFrame: CGRect(x: -800, y: -200, width: 800, height: 600),
        rect: CGRect(x: -900, y: -100, width: 300, height: 150), scale: 2, spaceGeneration: 0)
    var request: AreaCaptureRequest?
    func prefetchShareableContent() { events.append("prefetch") }
    func prepareSelection() async {}
    func selectArea() async -> AreaSelection? { events.append("select"); return selection }
    func hideSelection() { events.append("hide") }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        events.append("pixels")
        self.request = request
        return Data([0x89, 0x50, 0x4e, 0x47])
    }
    func finishCapture() { events.append("finish") }
}

extension AreaCaptureCommandsTests {
    @Test func acceptedAreaStartsLatencyButCancelledSelectionDoesNot() async {
        let platform = RecordingCapturePlatform()
        var rows: [Data] = []
        let log = CaptureLatencyLog(enabled: true, clock: { 42 }, write: { rows.append($0) })
        let source = AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug", latency: log)
        _ = await source.capture(maximumBytes: 1_000_000)
        #expect(rows.isEmpty)
        log.thumbnailSubmitted()
        #expect(rows == [Data("{\"run\":1,\"start_ns\":42,\"end_ns\":42}\n".utf8)])
        platform.selection = nil
        _ = await source.capture(maximumBytes: 1_000_000)
        log.thumbnailSubmitted()
        #expect(rows.count == 1)
    }

    @Test func areaCapturePrefetchesHidesOverlayAndExcludesOwnIdentityBeforeCopy() async throws {
        let platform = RecordingCapturePlatform()
        let destination = RecordingPasteboard()
        let source = AreaCaptureSource(platform: platform, bundleIdentifier: "io.github.prateeksingh1092.frisket.debug")
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: source, clipboard: PasteboardAdapter(destination: destination),
                                            pendingByteLimit: 1_000_000)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(revision))
        #expect(platform.events == ["prefetch", "select", "hide", "pixels", "finish"])
        let request = try #require(platform.request)
        #expect(request.displayID == 7)
        #expect(await commands.thumbnails().map(\.displayID) == [7], "Ticket 75: the Thumbnail goes to the Origin display")
        #expect(request.sourceRect == CGRect(x: 0, y: 350, width: 200, height: 150))
        #expect(request.pixelWidth == 400)
        #expect(request.pixelHeight == 300)
        #expect(request.excludingBundleIdentifier == "io.github.prateeksingh1092.frisket.debug")
        #expect(await commands.image(for: revision)?.pngData == Data([0x89, 0x50, 0x4e, 0x47]))
        _ = await commands.execute(.copy(revision))
        #expect(destination.items.first?.data(forType: .png) == Data([0x89, 0x50, 0x4e, 0x47]))
    }
}

extension AreaCaptureCommandsTests {
    @Test func cancellingSelectionTakesNoPixelsAndReleasesTheBudget() async {
        let platform = RecordingCapturePlatform()
        platform.selection = nil
        let destination = RecordingPasteboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(),
            source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
            clipboard: PasteboardAdapter(destination: destination), pendingByteLimit: 1_000_000)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .captureFailed(.cancelled))
        #expect(platform.events == ["prefetch", "select", "hide", "finish"])
        #expect(destination.items.isEmpty)
        platform.selection = AreaSelection(displayID: 1, displayFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                           rect: CGRect(x: 20.25, y: 30.25, width: 100.5, height: 50.5), scale: 1, spaceGeneration: 0)
        #expect(await commands.execute(.capture(id, maximumBytes: 1_000_000)) == .pending(CaptureRevision(captureID: id, number: 1)))
        #expect(platform.request?.sourceRect == CGRect(x: 20, y: 519, width: 101, height: 51))
    }
}

private struct SyntheticPNGSource: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let pixels = bitmap.bitmapData else { return .failure(.unavailable) }
        for index in stride(from: 0, to: bitmap.bytesPerRow * bitmap.pixelsHigh, by: 4) {
            pixels[index] = 255; pixels[index + 1] = 0; pixels[index + 2] = 0; pixels[index + 3] = 255
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return .failure(.unavailable) }
        return .success(CaptureImage(pngData: png))
    }
}

extension AreaCaptureCommandsTests {
    @Test func thumbnailDownsamplesPendingImageWithoutChangingDeliveredPixels() async throws {
        let destination = RecordingPasteboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: SyntheticPNGSource(), clipboard: PasteboardAdapter(destination: destination),
                                            pendingByteLimit: 1_000_000)
        let id = CaptureID(), revision: CaptureRevision
        revision = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 1_000_000))
        let pending = try #require(await commands.image(for: revision))
        let thumbnail = try #require(ThumbnailImage.make(from: pending.pngData, maximumPixelSize: 240))
        #expect(thumbnail.width == 240)
        #expect(thumbnail.height == 120)
        _ = await commands.execute(.copy(revision))
        let delivered = try #require(destination.items.first?.data(forType: .png))
        #expect(delivered == pending.pngData)
        let bitmap = try #require(NSBitmapImageRep(data: delivered))
        #expect(bitmap.pixelsWide == 640)
        #expect(bitmap.pixelsHigh == 320)
    }
}

extension AreaCaptureCommandsTests {
    @Test func pasteboardWriteFailureRetainsTheRevisionForExplicitRetry() async {
        let destination = RecordingPasteboard()
        destination.succeeds = false
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: FixtureSource(), clipboard: PasteboardAdapter(destination: destination),
                                            pendingByteLimit: 32)
        let id = CaptureID(), revision: CaptureRevision
        revision = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 32))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable), delivery: .failed(.unavailable))))
        #expect(await commands.image(for: revision)?.pngData == Data([0x89, 0x50, 0x4e, 0x47]))
        destination.succeeds = true
        #expect(await commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable), delivery: .copied(ClipboardReceipt(changeCount: 73)))))
        #expect(await commands.image(for: revision) == nil)
    }

    @Test func overBudgetSelectionNeverRequestsPixelsOrWritesClipboard() async {
        let platform = RecordingCapturePlatform()
        let destination = RecordingPasteboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
                                            clipboard: PasteboardAdapter(destination: destination), pendingByteLimit: 32)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 32)) == .captureFailed(.unavailable))
        #expect(platform.events == ["prefetch", "select", "hide", "finish"])
        #expect(destination.items.isEmpty)
    }
}
