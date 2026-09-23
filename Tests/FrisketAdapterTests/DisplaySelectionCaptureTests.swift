import Foundation
import FrisketCore
@testable import FrisketAdapters
import Testing

/// The display/pixel stand-in drives the same layout-change policy as AppKit.
@MainActor private final class DisplayFixturePlatform: AreaCapturePlatform {
    let retina = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let external = SelectionDisplay(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)
    var unplug = true
    var hidden = false
    var request: AreaCaptureRequest?
    var capturedWhileVisible = false

    func prefetchShareableContent() { hidden = false }
    func selectArea() async -> AreaSelection? {
        var session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: 20, y: 20))
        session.begin(at: CGPoint(x: -100, y: -100))
        session.update(to: CGPoint(x: 100, y: 100))
        session.updateDisplays(unplug ? [retina] : [external, retina])
        guard let display = session.originDisplay, let rect = session.acceptedRect else { return nil }
        return AreaSelection(displayID: display.id, displayFrame: display.frame, rect: rect, scale: display.scale)
    }
    func hideSelection() { hidden = true }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        capturedWhileVisible = !hidden
        self.request = request
        return Data([0x89, 0x50, 0x4e, 0x47])
    }
    func finishCapture() {}
}

private actor DisplayFixtureClipboard: ImageClipboard {
    private(set) var writes = 0
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        writes += 1
        return .success(ClipboardReceipt(changeCount: writes))
    }
}

@Suite @MainActor struct DisplaySelectionCaptureTests {
    @Test func unplugCancelsWithoutPixelsOrPendingCaptureAndNextSelectionCanUseTheBudget() async {
        let platform = DisplayFixturePlatform()
        let clipboard = DisplayFixtureClipboard()
        let commands = CaptureCommandLayer(source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
                                           clipboard: clipboard, pendingByteLimit: 100_000)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 100_000)) == .captureFailed(.cancelled))
        #expect(await commands.image(for: revision) == nil)
        #expect(platform.request == nil)
        #expect(platform.hidden)
        #expect(await clipboard.writes == 0)

        platform.unplug = false
        #expect(await commands.execute(.capture(id, maximumBytes: 100_000)) == .pending(revision))
        #expect(platform.request?.displayID == 2)
        #expect(platform.request?.sourceRect == CGRect(x: 1820, y: 800, width: 100, height: 200))
        #expect(platform.request?.pixelWidth == 100)
        #expect(platform.request?.pixelHeight == 200)
        #expect(!platform.capturedWhileVisible)
    }
}
