import CoreGraphics
import Foundation
import FrisketCore
import Testing
@testable import FrisketAdapters

@Suite @MainActor struct ScrollingCaptureAdapterTests {
    @Test func framesComeFromTheSelectedRegionOnTheExistingCapturePath() async throws {
        let platform = RecordingScrollingRegion()
        let capture = ManualScrollingCapture(platform: platform, bundleIdentifier: "io.github.prateeksingh1092.frisket.debug")
        guard case let .viewport(viewport) = await capture.nextFrame() else {
            Issue.record("Expected one sampled viewport")
            return
        }
        let request = try #require(platform.requests.first)
        #expect(platform.requests.count == 1)
        #expect(platform.didPrepareSelection)
        #expect(platform.didHideSelection)
        #expect(request.excludingBundleIdentifier == "io.github.prateeksingh1092.frisket.debug")
        #expect(request.displayID == 7)
        #expect(request.pixelWidth == 4)
        #expect(request.pixelHeight == 2)
        #expect(viewport.width == 4)
        #expect(viewport.height == 2)
    }
}

@MainActor private final class RecordingScrollingRegion: ScrollingRegionCapturing {
    private(set) var requests: [AreaCaptureRequest] = []
    private(set) var didHideSelection = false
    private(set) var didPrepareSelection = false
    var beforeCapture: (() async throws -> Void)?

    func prefetchShareableContent() async throws {}
    func prepareSelection() async { didPrepareSelection = true }
    func selectArea() async -> AreaSelection? {
        AreaSelection(displayID: 7, displayFrame: CGRect(x: 0, y: 0, width: 80, height: 40),
                      rect: CGRect(x: 0, y: 0, width: 4, height: 2), scale: 1, spaceGeneration: 0)
    }
    func hideSelection() { didHideSelection = true }
    func finishCapture() {}
    func captureRegion(_ request: AreaCaptureRequest) async throws -> CGImage {
        requests.append(request)
        try await beforeCapture?()
        var pixels = [UInt8](repeating: 0, count: 4 * 2 * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        let data = Data(pixels) as CFData
        let provider = try #require(CGDataProvider(data: data))
        return try #require(CGImage(width: 4, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}


extension ScrollingCaptureAdapterTests {
    @Test(arguments: [false, true])
    func cancelDuringLimitTriggeringViewportDiscardsTheCapture(captureFails: Bool) async throws {
        let platform = RecordingScrollingRegion()
        let gate = SuspendedRegion()
        platform.beforeCapture = {
            if platform.requests.count == 2 {
                await gate.suspend()
                if captureFails { throw CaptureSourceFailure.unavailable }
            }
        }
        let capture = ManualScrollingCapture(platform: platform, bundleIdentifier: "fixture.bundle")
        defer { capture.hide() }
        let commands = CaptureCommandLayer(permission: ScrollingAdapterPermission(),
            source: UnusedScrollingPixels(), clipboard: UnusedScrollingClipboard(), pendingByteLimit: 100_000,
            scrollingFrames: capture,
            scrollingBudget: ScrollingCaptureBudget(pixelCap: 8, memoryBudgetBytes: 100_000))
        let id = CaptureID()
        let task = Task { await commands.execute(.captureScrolling(id, maximumBytes: 100_000)) }
        await gate.waitUntilSuspended()
        capture.cancel()
        gate.resume()
        #expect(await task.value == .captureFailed(.cancelled))
        #expect(await commands.image(for: CaptureRevision(captureID: id, number: 1)) == nil)
        #expect(await capture.nextFrame() == .cancel)
    }
}

extension ScrollingCaptureAdapterTests {
    /// DA-9: ⌘⇧6 during a scrolling capture calls `finish()`, which means Done.
    @Test func finishDuringASessionMeansDoneAndDoesNothingOtherwise() async throws {
        let platform = RecordingScrollingRegion()
        let capture = ManualScrollingCapture(platform: platform, bundleIdentifier: "fixture.bundle")
        defer { capture.hide() }
        #expect(!capture.isRunning)
        capture.finish()   // no session yet: nothing to finish
        guard case .viewport = await capture.nextFrame() else {
            Issue.record("Expected the first sampled viewport")
            return
        }
        #expect(capture.isRunning)
        capture.finish()
        #expect(!capture.isRunning)
        #expect(await capture.nextFrame() == .done)
    }
}

@MainActor private final class SuspendedRegion {
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitUntilSuspended() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() {
        pending?.resume()
        pending = nil
    }
}

private struct ScrollingAdapterPermission: CapturePermissionSource {
    func capturePermission() async -> CapturePermissionState { .granted }
}
private struct UnusedScrollingPixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> { .failure(.unavailable) }
}
private struct UnusedScrollingClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> { .failure(.unavailable) }
}
