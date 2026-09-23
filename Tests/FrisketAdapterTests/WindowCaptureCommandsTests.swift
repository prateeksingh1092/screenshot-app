import Foundation
import FrisketCore
@testable import FrisketAdapters
import Testing

private let ownBundle = "io.github.prateeksingh1092.frisket.debug"
private let fixturePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!

private func window(_ id: UInt32, x: Double = -800, y: Double = -200,
                    owner: Int32 = 99, bundle: String? = "fixture.app",
                    layer: Int = 0, onScreen: Bool = true, minimized: Bool = false) -> WindowCandidate {
    WindowCandidate(id: id, ownerProcessID: owner, bundleIdentifier: bundle,
        frame: CGRect(x: x, y: y, width: 600, height: 400),
        layer: layer, isOnScreen: onScreen, isMinimized: minimized)
}

@MainActor private final class FixtureWindowPlatform: WindowCapturePlatform {
    var windows = [window(7), window(8)] // Front to back; IDs do not encode order.
    var pointer: CGPoint? = CGPoint(x: -500, y: -50)
    var captured: [UInt32] = []
    var selectionVisible = false
    var prepared = false
    var offered: [UInt32] = []
    var selections = 0
    var prepareFailure: CaptureSourceFailure?
    var captureFailure: CaptureSourceFailure?
    var bytes = fixturePNG
    var suspendPreparation = false
    private var preparationStarted: CheckedContinuation<Void, Never>?
    private var preparationRelease: CheckedContinuation<Void, Never>?
    func waitUntilPreparing() async {
        if prepared { return }
        await withCheckedContinuation { preparationStarted = $0 }
    }
    func releasePreparation() { preparationRelease?.resume(); preparationRelease = nil }
    func prepareWindows() async throws -> [WindowCandidate] {
        prepared = true
        if suspendPreparation {
            await withCheckedContinuation {
                preparationRelease = $0
                preparationStarted?.resume()
                preparationStarted = nil
            }
        }
        if let prepareFailure { throw prepareFailure }
        return windows
    }
    func selectWindow(from selection: WindowSelection) async -> UInt32? {
        selections += 1
        selectionVisible = true
        offered = selection.candidates.map(\.id)
        return pointer.flatMap { selection.window(at: $0)?.id }
    }
    func hideSelection() { selectionVisible = false }
    func finishCapture() {}
    func capture(_ window: WindowCandidate, maximumBytes: Int) async throws -> Data {
        #expect(!selectionVisible)
        if let captureFailure { throw captureFailure }
        captured.append(window.id)
        return bytes
    }
}

private struct UnavailablePixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> { .failure(.unavailable) }
}
private actor WindowClipboard: ImageClipboard {
    var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return .success(ClipboardReceipt(changeCount: 1))
    }
}

@Suite @MainActor struct WindowCaptureCommandsTests {
    @Test func frontmostWindowAtNegativeCoordinatesBecomesPendingAndCopiesUnchanged() async throws {
        let platform = FixtureWindowPlatform(), clipboard = WindowClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: clipboard, pendingByteLimit: 1024)
        let id = CaptureID(), revision = CaptureRevision(captureID: CaptureID(), number: 1)
        let expected = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(expected))
        #expect(platform.captured == [7])
        #expect(await commands.image(for: expected)?.pngData == fixturePNG)
        #expect(await commands.image(for: revision) == nil)
        #expect(await clipboard.images.isEmpty)
        #expect(await commands.execute(.copy(expected)) == .copy(CopyOutcome(revision: expected,
            commit: .notCommitted(.historyUnavailable), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await clipboard.images.first?.pngData == fixturePNG)
    }
}

extension WindowCaptureCommandsTests {
    @Test(arguments: [CGPoint(x: -500, y: -50), CGPoint(x: 900, y: 400)])
    func onlyVisibleNormalForeignWindowsParticipateInZOrder(pointer: CGPoint) async {
        let platform = FixtureWindowPlatform()
        platform.pointer = pointer
        let x = pointer.x - 100, y = pointer.y - 100
        platform.windows = [
            window(1, x: x, y: y, owner: 42, bundle: nil), // Own process, absent bundle metadata.
            window(2, x: x, y: y, bundle: ownBundle), // Another instance of Frisket.
            window(3, x: x, y: y, layer: 3),
            window(4, x: x, y: y, onScreen: false), // Other Space.
            window(5, x: x, y: y, minimized: true),
            window(6, x: x, y: y, bundle: nil), // Fail closed for unknown app identity.
            window(80, x: x, y: y), window(7, x: x, y: y)
        ]
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        let id = CaptureID()
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(CaptureRevision(captureID: id, number: 1)))
        #expect(platform.offered == [80, 7])
        #expect(platform.captured == [80])
    }
}

extension WindowCaptureCommandsTests {
    @Test func noEligibleWindowsDoesNotOpenSelectionOrConsumeTheBudget() async {
        let platform = FixtureWindowPlatform()
        platform.windows = [window(1, owner: 42)]
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        let id = CaptureID()
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .captureFailed(.unavailable))
        #expect(platform.captured.isEmpty)
        #expect(platform.selections == 0)
        platform.windows = [window(7)]
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }
}

private struct AvailableFixturePixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: fixturePNG))
    }
}

private struct WindowPermission: CapturePermissionSource {
    let state: CapturePermissionState
    func capturePermission() async -> CapturePermissionState { state }
}

extension WindowCaptureCommandsTests {
    @Test(arguments: [CapturePermissionState.notAsked, .denied, .revokedWhileRunning, .needsRelaunch])
    func missingPermissionNeverPreparesWindowsOrSelection(_ state: CapturePermissionState) async {
        let platform = FixtureWindowPlatform()
        let commands = CaptureCommandLayer(permission: WindowPermission(state: state), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        #expect(await commands.execute(.captureWindow(CaptureID(), maximumBytes: 1024)) == .permissionRequired(state))
        #expect(!platform.prepared)
        #expect(platform.selections == 0)
        #expect(platform.captured.isEmpty)
    }

    @Test func selectionWaitsUntilPreparationCompletes() async {
        let platform = FixtureWindowPlatform()
        platform.suspendPreparation = true
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        let id = CaptureID()
        let task = Task { await commands.execute(.captureWindow(id, maximumBytes: 1024)) }
        await platform.waitUntilPreparing()
        #expect(platform.selections == 0)
        #expect(platform.captured.isEmpty)
        platform.releasePreparation()
        #expect(await task.value == .pending(CaptureRevision(captureID: id, number: 1)))
    }

    @Test(arguments: [false, true])
    func permissionLossDuringPreparationOrPixelsReleasesReservation(duringPixels: Bool) async {
        let platform = FixtureWindowPlatform()
        if duringPixels { platform.captureFailure = .permissionRequired(.revokedWhileRunning) }
        else { platform.prepareFailure = .permissionRequired(.needsRelaunch) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        let id = CaptureID(), revision: CaptureRevision
        revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .permissionRequired(duringPixels ? .revokedWhileRunning : .needsRelaunch))
        #expect(await commands.image(for: revision) == nil)
        #expect(!platform.selectionVisible)
        if !duringPixels { #expect(platform.selections == 0) }
        platform.captureFailure = nil
        platform.prepareFailure = nil
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(revision))
    }

    @Test(arguments: [CGPoint?.none, CGPoint(x: 5000, y: 5000)])
    func cancelOrNoHitTakesNoPixelsAndAllowsAnotherCapture(_ pointer: CGPoint?) async {
        let platform = FixtureWindowPlatform()
        platform.pointer = pointer
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        let id = CaptureID()
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .captureFailed(.cancelled))
        #expect(platform.captured.isEmpty)
        #expect(!platform.selectionVisible)
        platform.pointer = CGPoint(x: -500, y: -50)
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }

    @Test func windowAndOtherToolsSharePendingBudgetAndDeleteReleasesIt() async {
        let platform = FixtureWindowPlatform()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            fullScreenSource: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: fixturePNG.count)
        let id = CaptureID(), revision: CaptureRevision
        revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.captureWindow(id, maximumBytes: fixturePNG.count)) == .pending(revision))
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 1)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.captureFullScreen(CaptureID(), maximumBytes: 1)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.captureWindow(CaptureID(), maximumBytes: 1)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.discard(id)) == .discarded(id))
        #expect(await commands.image(for: revision) == nil)
        let next = CaptureID()
        #expect(await commands.execute(.captureWindow(next, maximumBytes: fixturePNG.count)) == .pending(CaptureRevision(captureID: next, number: 1)))
    }

    @Test(arguments: [Data(), Data(repeating: 1, count: 1025)])
    func invalidSourceBytesNeverBecomePendingAndReleaseTheBudget(_ bytes: Data) async {
        let platform = FixtureWindowPlatform()
        platform.bytes = bytes
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        let id = CaptureID()
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) ==
            (bytes.isEmpty ? .captureFailed(.emptyImage) : .rejected(.pendingByteBudgetExceeded)))
        platform.bytes = fixturePNG
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }

    @Test func selectedWindowIsMemoryOnlyUntilDismissCommitsToRealHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let platform = FixtureWindowPlatform()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: UnavailablePixels(),
            windowSource: WindowCaptureSource(platform: platform, ownProcessID: 42, bundleIdentifier: ownBundle),
            clipboard: WindowClipboard(), pendingByteLimit: 1024, history: HistoryStore(root: root))
        let id = CaptureID(), revision: CaptureRevision
        revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.captureWindow(id, maximumBytes: 1024)) == .pending(revision))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let entries = try await commands.historyEntries().get()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.captureID == id)
        #expect(entry.width == 2 && entry.height == 1)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == fixturePNG)
        #expect(await commands.image(for: revision) == nil)
    }

    @Test func absentWindowSourceCannotFallBackToArea() async {
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: AvailableFixturePixels(),
            clipboard: WindowClipboard(), pendingByteLimit: 1024)
        #expect(await commands.execute(.captureWindow(CaptureID(), maximumBytes: 1024)) == .captureFailed(.unavailable))
    }
}
