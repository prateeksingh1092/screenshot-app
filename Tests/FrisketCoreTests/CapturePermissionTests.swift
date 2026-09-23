import Foundation
import FrisketCore
import Testing

private actor PermissionStandIn: CapturePermissionSource {
    var state: CapturePermissionState
    init(_ state: CapturePermissionState) { self.state = state }
    func capturePermission() -> CapturePermissionState { state }
    func set(_ state: CapturePermissionState) { self.state = state }
}

private actor PermissionPixels: CapturePixelSource {
    private(set) var captures = 0
    func capture(maximumBytes: Int) -> Result<CaptureImage, CaptureSourceFailure> {
        captures += 1
        return .success(CaptureImage(pngData: Data([1, 2, 3])))
    }
}

private struct PermissionClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

@Suite struct CapturePermissionTests {
    @Test func notAskedReturnsRecoveryBeforeStartingEitherCaptureSource() async {
        let pixels = PermissionPixels()
        let commands = CaptureCommandLayer(permission: PermissionStandIn(.notAsked), source: pixels, fullScreenSource: pixels,
            clipboard: PermissionClipboard(), pendingByteLimit: 32)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 32)) == .permissionRequired(.notAsked))
        #expect(await commands.execute(.captureFullScreen(CaptureID(), maximumBytes: 32)) == .permissionRequired(.notAsked))
        #expect(await pixels.captures == 0)
    }
}

extension CapturePermissionTests {
    @Test(arguments: [CapturePermissionState.denied, .revokedWhileRunning, .needsRelaunch])
    func missingAccessBlocksBothToolsAndCanRecoverWithoutLosingBudget(_ state: CapturePermissionState) async {
        let pixels = PermissionPixels(), permission = PermissionStandIn(state)
        let commands = CaptureCommandLayer(permission: permission, source: pixels, fullScreenSource: pixels,
            clipboard: PermissionClipboard(), pendingByteLimit: 3)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 3)) == .permissionRequired(state))
        #expect(await commands.execute(.captureFullScreen(id, maximumBytes: 3)) == .permissionRequired(state))
        #expect(await pixels.captures == 0)
        await permission.set(.granted)
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.captureFullScreen(id, maximumBytes: 3)) == .pending(revision))
        await permission.set(.revokedWhileRunning)
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .notCommitted(.historyUnavailable), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 3)) == .permissionRequired(.revokedWhileRunning))
        #expect(await pixels.captures == 1)
    }
}

private struct PermissionFailurePixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .failure(.permissionRequired(.revokedWhileRunning))
    }
}

extension CapturePermissionTests {
    @Test func permissionLossDuringCaptureBecomesRecoveryAndReleasesReservation() async {
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: PermissionFailurePixels(),
            clipboard: PermissionClipboard(), pendingByteLimit: 3)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 3)) == .permissionRequired(.revokedWhileRunning))
        #expect(await commands.execute(.capture(id, maximumBytes: 3)) == .permissionRequired(.revokedWhileRunning))
        #expect(await commands.image(for: CaptureRevision(captureID: id, number: 1)) == nil)
    }
}
