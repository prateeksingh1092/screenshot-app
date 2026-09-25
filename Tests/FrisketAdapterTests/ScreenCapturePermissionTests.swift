import Foundation
import FrisketCore
import ScreenCaptureKit
@testable import FrisketAdapters
import Testing

@MainActor private final class ScreenAccessStandIn: ScreenRecordingAccess {
    var hasRequested = false
    var allowed = false
    var acceptsRequest = false
    var usableAfterRequest = false
    func preflight() -> Bool { allowed }
    func request() -> Bool {
        allowed = usableAfterRequest
        return acceptsRequest
    }
}

private struct PermissionFixturePixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: Data([1])))
    }
}

private struct PermissionFixtureClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

@Suite @MainActor struct ScreenCapturePermissionTests {
    @Test func firstRequestDenialSurvivesAdapterRecreation() async {
        let access = ScreenAccessStandIn()
        let permission = ScreenCapturePermissionAdapter(access: access)
        let commands = CaptureLifecycleCoordinator(permission: permission, source: PermissionFixturePixels(),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 4)) == .permissionRequired(.notAsked))
        #expect(permission.requestPermission() == .denied)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 4)) == .permissionRequired(.denied))
        let reopened = CaptureLifecycleCoordinator(permission: ScreenCapturePermissionAdapter(access: access),
            source: PermissionFixturePixels(), clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        #expect(await reopened.execute(.capture(CaptureID(), maximumBytes: 4)) == .permissionRequired(.denied))
    }
}

extension ScreenCapturePermissionTests {
    @Test func observesExistingGrantRevocationAndRestoredGrantOnEveryCommand() async {
        let access = ScreenAccessStandIn()
        access.allowed = true
        let commands = CaptureLifecycleCoordinator(permission: ScreenCapturePermissionAdapter(access: access),
            source: PermissionFixturePixels(), clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 1)) == .pending(CaptureRevision(captureID: id, number: 1)))
        access.allowed = false
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 1)) == .permissionRequired(.revokedWhileRunning))
        access.allowed = true
        let restored = CaptureID()
        #expect(await commands.execute(.capture(restored, maximumBytes: 1)) == .pending(CaptureRevision(captureID: restored, number: 1)))
    }
}

extension ScreenCapturePermissionTests {
    @Test func acceptedRequestWithoutUsableAccessRequiresANewProcess() async {
        let access = ScreenAccessStandIn()
        access.acceptsRequest = true
        let permission = ScreenCapturePermissionAdapter(access: access)
        #expect(permission.requestPermission() == .needsRelaunch)
        let commands = CaptureLifecycleCoordinator(permission: permission, source: PermissionFixturePixels(),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 4)) == .permissionRequired(.needsRelaunch))
        access.allowed = true
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 4)) == .permissionRequired(.needsRelaunch))
        let reopened = CaptureLifecycleCoordinator(permission: ScreenCapturePermissionAdapter(access: access),
            source: PermissionFixturePixels(), clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let id = CaptureID()
        #expect(await reopened.execute(.capture(id, maximumBytes: 4)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }
}

@MainActor private final class AuthorizationFailurePixels: CapturePixelSource {
    let permission: ScreenCapturePermissionAdapter
    let access: ScreenAccessStandIn
    let stillGranted: Bool
    let error: NSError
    init(permission: ScreenCapturePermissionAdapter, access: ScreenAccessStandIn, stillGranted: Bool, error: NSError) {
        self.permission = permission; self.access = access; self.stillGranted = stillGranted; self.error = error
    }
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        access.allowed = stillGranted
        return .failure(permission.failure(for: error))
    }
}

extension ScreenCapturePermissionTests {
    @Test(arguments: [false, true])
    func screenCaptureKitDenialDistinguishesRevocationFromRelaunch(_ stillGranted: Bool) async {
        let access = ScreenAccessStandIn()
        access.allowed = true
        let permission = ScreenCapturePermissionAdapter(access: access)
        let pixels = AuthorizationFailurePixels(permission: permission, access: access, stillGranted: stillGranted,
            error: NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue))
        let commands = CaptureLifecycleCoordinator(permission: permission, source: pixels, fullScreenSource: pixels,
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let expected: CaptureCommandOutcome = .permissionRequired(stillGranted ? .needsRelaunch : .revokedWhileRunning)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 4)) == expected)
        #expect(await commands.execute(.captureFullScreen(CaptureID(), maximumBytes: 4)) == expected)
    }
}

@MainActor private final class RefusedCapturePreparation: AreaCapturePlatform, FullScreenCapturePlatform {
    let spaceGeneration: UInt64 = 0
    var previewsPrepared = false
    func prepareSelection() async { previewsPrepared = true }
    func discardSelectionPreviews() {}
    var selectionShown = false
    var pixelsTaken = false
    var finished = false
    func prefetchShareableContent() async throws { throw CaptureSourceFailure.permissionRequired(.needsRelaunch) }
    func selectArea() async -> AreaSelection? { selectionShown = true; return nil }
    func displayUnderPointer() -> SelectionDisplay? { nil }
    func hideSelection() {}
    func finishCapture() { finished = true }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        pixelsTaken = true
        return Data([1])
    }
}

extension ScreenCapturePermissionTests {
    @Test(arguments: [false, true])
    func shareableContentRefusalNeverCreatesSelectionOrTakesPixels(_ fullScreen: Bool) async {
        let platform = RefusedCapturePreparation()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(),
            source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let command: CaptureCommand = fullScreen ? .captureFullScreen(CaptureID(), maximumBytes: 4) : .capture(CaptureID(), maximumBytes: 4)
        #expect(await commands.execute(command) == .permissionRequired(.needsRelaunch))
        #expect(!platform.selectionShown)
        #expect(!platform.previewsPrepared)
        #expect(!platform.pixelsTaken)
        #expect(platform.finished)
    }
}

extension ScreenCapturePermissionTests {
    @Test(arguments: [
        NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.failedToStart.rawValue),
        NSError(domain: "fixture.other", code: SCStreamError.Code.userDeclined.rawValue)
    ])
    func unrelatedPlatformErrorsDoNotInventPermissionLoss(_ error: NSError) async {
        let access = ScreenAccessStandIn()
        access.allowed = true
        let permission = ScreenCapturePermissionAdapter(access: access)
        let commands = CaptureLifecycleCoordinator(permission: permission,
            source: AuthorizationFailurePixels(permission: permission, access: access, stillGranted: true, error: error),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 4)) == .captureFailed(.unavailable))
        let retry = CaptureLifecycleCoordinator(permission: permission, source: PermissionFixturePixels(),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let id = CaptureID()
        #expect(await retry.execute(.capture(id, maximumBytes: 4)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }

    @Test func acceptedRequestWithImmediateAccessCanCapture() async {
        let access = ScreenAccessStandIn()
        access.acceptsRequest = true
        access.usableAfterRequest = true
        let permission = ScreenCapturePermissionAdapter(access: access)
        #expect(permission.requestPermission() == .granted)
        let commands = CaptureLifecycleCoordinator(permission: permission, source: PermissionFixturePixels(),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 4)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }
}

@MainActor private final class PendingCapturePreparation: AreaCapturePlatform {
    let spaceGeneration: UInt64 = 0
    var previewsPrepared = false
    func prepareSelection() async { previewsPrepared = true }
    func discardSelectionPreviews() {}
    private var started: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    var selectionShown = false
    func waitUntilPreparing() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func prefetchShareableContent() async throws {
        await withCheckedContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
        throw CaptureSourceFailure.permissionRequired(.denied)
    }
    func deny() { pending?.resume(); pending = nil }
    func selectArea() async -> AreaSelection? { selectionShown = true; return nil }
    func hideSelection() {}
    func finishCapture() {}
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data { Data([1]) }
}

extension ScreenCapturePermissionTests {
    @Test func pendingSystemAuthorizationCompletesBeforeSelectionCanAppear() async {
        let platform = PendingCapturePreparation()
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(),
            source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.debug"),
            clipboard: PermissionFixtureClipboard(), pendingByteLimit: 4)
        let id = CaptureID()
        let capture = Task { await commands.execute(.capture(id, maximumBytes: 4)) }
        await platform.waitUntilPreparing()
        #expect(!platform.selectionShown)
        #expect(!platform.previewsPrepared)
        #expect(await commands.execute(.capture(id, maximumBytes: 4)) == .rejected(.commandInProgress))
        platform.deny()
        #expect(await capture.value == .permissionRequired(.denied))
        #expect(!platform.selectionShown)
        #expect(!platform.previewsPrepared)
    }
}
