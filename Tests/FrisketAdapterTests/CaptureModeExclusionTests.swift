import AppKit
import FrisketCore
@testable import FrisketAdapters
import Testing

/// Regression guard: whichever mode starts a capture, the content filter that ScreenCaptureKit
/// receives excludes Frisket and every app on the Capture exclusion list (decision 37).
/// Window capture filters a single foreign window instead; `WindowCaptureCommandsTests`
/// covers Frisket's own windows there.
@MainActor private final class GrantedScreenAccess: ScreenRecordingAccess {
    var hasRequested = true
    func preflight() -> Bool { true }
    func request() -> Bool { Issue.record("Must not request permission"); return false }
}

/// Records the bundle identifiers handed to `ScreenCapturePolicy.filter`, exactly as the
/// production content computes them, and returns a 1×1 image instead of screen pixels.
@MainActor private final class FilterRecorder {
    var excluded: [Set<String>] = []
}

@MainActor private struct RecordingContent: ScreenCaptureContent {
    let recorder: FilterRecorder

    func captureImage(_ request: AreaCaptureRequest, additionalExclusions: Set<String>) async throws -> CGImage {
        recorder.excluded.append(request.excludedBundleIdentifiers.union(additionalExclusions))
        let context = try #require(CGContext(data: nil, width: request.pixelWidth, height: request.pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: request.pixelWidth, height: request.pixelHeight))
        return try #require(context.makeImage())
    }
}

/// The production ScreenCapturePlatform with only its on-screen UI (overlay and pointer) stubbed.
@MainActor private final class HeadlessPlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    let real: ScreenCapturePlatform
    private let display = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 4, height: 2), scale: 1)

    init(real: ScreenCapturePlatform) { self.real = real }

    var spaceGeneration: UInt64 { real.spaceGeneration }
    func prefetchShareableContent() async throws { try await real.prefetchShareableContent() }
    func prepareSelection() async {}
    func selectArea() async -> AreaSelection? {
        AreaSelection(displayID: display.id, displayFrame: display.frame, rect: display.frame,
                      scale: display.scale, spaceGeneration: real.spaceGeneration)
    }
    func hideSelection() {}
    func displayUnderPointer() -> SelectionDisplay? {
        SelectionDisplay(id: display.id, frame: display.frame, scale: display.scale)
    }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        try await real.capture(request, maximumBytes: maximumBytes)
    }
    func finishCapture() { real.finishCapture() }
}

@Suite @MainActor struct CaptureModeExclusionTests {
    private let frisket = "test.frisket"
    private let exclusionList: Set<String> = ["test.synthetic-vault", "test.synthetic-notes"]

    @Test(arguments: ["area", "full screen"])
    func contentFilterExcludesFrisketAndTheExclusionList(mode: String) async throws {
        let recorder = FilterRecorder()
        let list = exclusionList
        // Wired as FrisketApp wires it: the platform and the sources read the same Settings list.
        let real = ScreenCapturePlatform(permission: ScreenCapturePermissionAdapter(access: GrantedScreenAccess()),
            exclusions: { list }, loadContent: { RecordingContent(recorder: recorder) },
            connectedDisplays: { [SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 4, height: 2), scale: 1)] },
            applicationNotifications: NotificationCenter())
        let platform = HeadlessPlatform(real: real)
        switch mode {
        case "area":
            let source = AreaCaptureSource(platform: platform, bundleIdentifier: frisket, exclusions: { list })
            _ = try await source.capture(maximumBytes: 100_000).get()
        default:
            let source = FullScreenCaptureSource(platform: platform, bundleIdentifier: frisket, exclusions: { list })
            _ = try await source.capture(maximumBytes: 100_000).get()
        }
        #expect(recorder.excluded == [exclusionList.union([frisket])])
    }
}
