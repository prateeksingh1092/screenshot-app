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

    func prefetchShareableContent() async throws {}
    func selectArea() async -> AreaSelection? {
        AreaSelection(displayID: 7, displayFrame: CGRect(x: 0, y: 0, width: 80, height: 40),
                      rect: CGRect(x: 0, y: 0, width: 4, height: 2), scale: 1)
    }
    func hideSelection() { didHideSelection = true }
    func finishCapture() {}
    func captureRegion(_ request: AreaCaptureRequest) async throws -> CGImage {
        requests.append(request)
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
