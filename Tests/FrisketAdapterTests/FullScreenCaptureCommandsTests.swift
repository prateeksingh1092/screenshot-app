import AppKit
import FrisketCore
@testable import FrisketAdapters
import Testing

@MainActor private final class FixtureDisplayPlatform: FullScreenCapturePlatform {
    let display: FullScreenDisplay
    var request: AreaCaptureRequest?
    init(frame: CGRect, scale: CGFloat) {
        display = FullScreenDisplay(displayID: 42, frame: frame, scale: scale)
    }
    func prefetchShareableContent() {}
    func displayUnderPointer() -> FullScreenDisplay? { display }
    func finishCapture() {}
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        self.request = request
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: request.pixelWidth, pixelsHigh: request.pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try #require(bitmap.bitmapData)
        for index in stride(from: 0, to: bitmap.bytesPerRow * bitmap.pixelsHigh, by: 4) {
            pixels[index] = 255; pixels[index + 1] = 0
            pixels[index + 2] = 0; pixels[index + 3] = 255
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

private struct UnavailableAreaSource: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .failure(.unavailable)
    }
}

private actor FixtureClipboard: ImageClipboard {
    private(set) var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return .success(ClipboardReceipt(changeCount: 1))
    }
}

@Suite @MainActor struct FullScreenCaptureCommandsTests {
    @Test func selectedDisplayStartsLatencyBeforeThumbnailSubmission() async {
        let platform = FixtureDisplayPlatform(frame: CGRect(x: 0, y: 0, width: 8, height: 6), scale: 1)
        var rows: [Data] = []
        let log = CaptureLatencyLog(enabled: true, clock: { 73 }, write: { rows.append($0) })
        let source = FullScreenCaptureSource(platform: platform, bundleIdentifier: "test.debug", latency: log)
        _ = await source.capture(maximumBytes: 1_000_000)
        #expect(rows.isEmpty)
        log.thumbnailSubmitted()
        #expect(rows == [Data("{\"run\":1,\"start_ns\":73,\"end_ns\":73}\n".utf8)])
    }

    @Test(arguments: [
        (0.0, 0.0, 1.0, 800, 600),
        (0.0, 0.0, 2.0, 1600, 1200),
        (-800.0, -200.0, 2.0, 1600, 1200)
    ])
    func fullScreenBecomesPendingAtNativeScaleExcludingOwnApp(
        x: Double, y: Double, scale: Double, width: Int, height: Int
    ) async throws {
        let platform = FixtureDisplayPlatform(frame: CGRect(x: x, y: y, width: 800, height: 600), scale: scale)
        let clipboard = FixtureClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailableAreaSource(),
            fullScreenSource: FullScreenCaptureSource(platform: platform,
                bundleIdentifier: "io.github.prateeksingh1092.frisket.debug"),
            clipboard: clipboard, pendingByteLimit: 16_000_000)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.captureFullScreen(id, maximumBytes: 16_000_000)) == .pending(revision))
        let request = try #require(platform.request)
        #expect(request.displayID == 42)
        #expect(request.sourceRect == CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(request.pixelWidth == width)
        #expect(request.pixelHeight == height)
        #expect(request.excludingBundleIdentifier == "io.github.prateeksingh1092.frisket.debug")
        let pending = try #require(await commands.image(for: revision))
        let bitmap = try #require(NSBitmapImageRep(data: pending.pngData))
        #expect(bitmap.pixelsWide == width)
        #expect(bitmap.pixelsHigh == height)
        let thumbnail = try #require(ThumbnailImage.make(from: pending.pngData, maximumPixelSize: 240))
        #expect(thumbnail.width == 240)
        #expect(thumbnail.height == 180)
        #expect(await clipboard.images.isEmpty)
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable),
            delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await clipboard.images.first?.pngData == pending.pngData)
    }
}
