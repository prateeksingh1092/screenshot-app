import Foundation
import FrisketCore
@testable import FrisketAdapters
import Testing

/// The display/pixel stand-in drives the same layout-change policy as AppKit.
@MainActor private final class DisplayFixturePlatform: AreaCapturePlatform {
    let spaceGeneration: UInt64 = 0
    let retina = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let external = SelectionDisplay(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)
    var unplug = true
    var hidden = false
    var request: AreaCaptureRequest?
    var capturedWhileVisible = false

    func prefetchShareableContent() { hidden = false }
    func prepareSelection() async {}
    func selectArea() async -> AreaSelection? {
        var session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: 20, y: 20))
        session.begin(at: CGPoint(x: -100, y: -100))
        session.update(to: CGPoint(x: 100, y: 100))
        session.updateDisplays(unplug ? [retina] : [external, retina])
        guard let display = session.originDisplay, let rect = session.acceptedRect else { return nil }
        return AreaSelection(displayID: display.id, displayFrame: display.frame, rect: rect, scale: display.scale, spaceGeneration: spaceGeneration)
    }
    func hideSelection() { hidden = true }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        capturedWhileVisible = !hidden
        self.request = request
        return Data([0x89, 0x50, 0x4e, 0x47])
    }
    func finishCapture() {}
}

/// Explicit handshakes suspend the OS stand-in without timing or real capture.
@MainActor private final class CapturePause {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            completion = continuation
            entered = true
            entry?.resume()
            entry = nil
        }
    }

    func waitUntilSuspended() async {
        if entered { return }
        await withCheckedContinuation { entry = $0 }
    }

    func resume() {
        completion?.resume()
        completion = nil
    }
}

@MainActor private final class SpaceFixturePlatform: AreaCapturePlatform {
    var spaceGeneration: UInt64 = 0
    var pixelPause: CapturePause?
    var previewPause: CapturePause?
    var prefetchPause: CapturePause?
    var previewsPrepared = false
    var selectionShown = false
    var request: AreaCaptureRequest?
    var hidden = false
    var finished = false

    func prefetchShareableContent() async throws {
        hidden = false
        finished = false
        if let prefetchPause { await prefetchPause.suspend() }
    }
    func prepareSelection() async {
        previewsPrepared = true
        if let previewPause { await previewPause.suspend() }
    }
    func selectArea() async -> AreaSelection? {
        selectionShown = true
        return AreaSelection(displayID: 1, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                      rect: CGRect(x: 10, y: 20, width: 10, height: 10), scale: 1, spaceGeneration: spaceGeneration)
    }
    func hideSelection() { hidden = true }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        self.request = request
        if let pixelPause { await pixelPause.suspend() }
        return Data([0x89, 0x50, 0x4e, 0x47])
    }
    func finishCapture() { finished = true }
}

private actor DisplayFixtureClipboard: ImageClipboard {
    private(set) var writes = 0
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        writes += 1
        return .success(ClipboardReceipt(changeCount: writes))
    }
}

@Suite @MainActor struct DisplaySelectionCaptureTests {
    @Test(arguments: [false, true])
    func prefetchCompletesBeforePreviewsAndSelectionAndTracksSpaceChanges(spaceSwitch: Bool) async {
        let platform = SpaceFixturePlatform()
        let pause = CapturePause()
        platform.prefetchPause = pause
        let clipboard = DisplayFixtureClipboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(),
            source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
            clipboard: clipboard, pendingByteLimit: 400)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        let capture = Task { await commands.execute(.capture(id, maximumBytes: 400)) }
        await pause.waitUntilSuspended()
        #expect(!platform.previewsPrepared)
        #expect(!platform.selectionShown)
        #expect(platform.request == nil)
        if spaceSwitch { platform.spaceGeneration += 1 }
        pause.resume()
        #expect(await capture.value == .pending(revision))
        #expect(platform.previewsPrepared)
        #expect(platform.selectionShown)
        #expect(platform.hidden)
        #expect(platform.finished)
        #expect(await clipboard.writes == 0)
    }

    @Test(arguments: [false, true])
    func selectionPreparationCompletesAcrossASpaceSwitch(spaceSwitch: Bool) async {
        let platform = SpaceFixturePlatform()
        let pause = CapturePause()
        platform.previewPause = pause
        let clipboard = DisplayFixtureClipboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
                                           clipboard: clipboard, pendingByteLimit: 400)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        let capture = Task { await commands.execute(.capture(id, maximumBytes: 400)) }
        await pause.waitUntilSuspended()
        if spaceSwitch { platform.spaceGeneration += 1 }
        pause.resume()
        #expect(await capture.value == .pending(revision))
        #expect(platform.request?.sourceRect == CGRect(x: 10, y: 70, width: 10, height: 10))
        #expect(platform.hidden)
        #expect(platform.finished)
        #expect(await clipboard.writes == 0)
    }

    @Test func spaceSwitchDuringFinalCaptureDiscardsPixelsAndRecoversBudget() async {
        let platform = SpaceFixturePlatform()
        let pause = CapturePause()
        platform.pixelPause = pause
        let clipboard = DisplayFixtureClipboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
                                           clipboard: clipboard, pendingByteLimit: 400)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        let capture = Task { await commands.execute(.capture(id, maximumBytes: 400)) }
        await pause.waitUntilSuspended()
        #expect(platform.hidden)
        platform.spaceGeneration += 1
        pause.resume()
        #expect(await capture.value == .captureFailed(.cancelled))
        #expect(await commands.image(for: revision) == nil)
        #expect(platform.finished)
        #expect(await clipboard.writes == 0)

        platform.pixelPause = nil
        #expect(await commands.execute(.capture(id, maximumBytes: 400)) == .pending(revision))
        #expect(await commands.image(for: revision)?.pngData == Data([0x89, 0x50, 0x4e, 0x47]))
    }

    @Test func unplugCancelsWithoutPixelsOrPendingCaptureAndNextSelectionCanUseTheBudget() async {
        let platform = DisplayFixturePlatform()
        let clipboard = DisplayFixtureClipboard()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
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
