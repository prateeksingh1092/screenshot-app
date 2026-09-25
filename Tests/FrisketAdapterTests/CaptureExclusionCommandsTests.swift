import Foundation
import FrisketCore
@testable import FrisketAdapters
import Testing

@MainActor private final class ExclusionPlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    var spaceGeneration: UInt64 = 0
    var requests: [AreaCaptureRequest] = []
    func prefetchShareableContent() {}
    func prepareSelection() async {}
    func discardSelectionPreviews() {}
    func hideSelection() {}
    func finishCapture() {}
    func selectArea() async -> AreaSelection? {
        AreaSelection(displayID: 1, displayFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                      rect: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 1, spaceGeneration: 0)
    }
    func displayUnderPointer() -> SelectionDisplay? {
        SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 1)
    }
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        requests.append(request)
        return Data([0x89, 0x50, 0x4e, 0x47])
    }
}

private actor UnusedExclusionClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) -> Result<ClipboardReceipt, ClipboardFailure> {
        Issue.record("Capture must not use clipboard")
        return .success(ClipboardReceipt(changeCount: 1))
    }
}

@Suite @MainActor struct CaptureExclusionCommandsTests {
    @Test func areaUsesCurrentSettingsAndAlwaysExcludesFrisket() async throws {
        let exclusions = CaptureExclusionList()
        let platform = ExclusionPlatform()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.frisket",
                                      exclusions: { exclusions.bundleIdentifiers }),
            clipboard: UnusedExclusionClipboard(), pendingByteLimit: 10_000)
        #expect(exclusions.bundleIdentifiers.isEmpty)
        for expected: Set<String> in [["test.frisket"], ["test.frisket", "test.synthetic-vault"], ["test.frisket"]] {
            let id = CaptureID()
            #expect(await commands.execute(.capture(id, maximumBytes: 1_000)) == .pending(CaptureRevision(captureID: id, number: 1)))
            #expect(platform.requests.last?.excludedBundleIdentifiers == expected)
            if exclusions.bundleIdentifiers.isEmpty { exclusions.add("test.synthetic-vault") }
            else { exclusions.remove("test.synthetic-vault") }
        }
    }
    @Test func fullScreenUsesCurrentSettingsWithoutLoggingAppIdentities() async throws {
        let exclusions = CaptureExclusionList()
        let platform = ExclusionPlatform()
        let log = LocalDiagnosticLog()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: AreaCaptureSource(platform: platform, bundleIdentifier: "test.frisket"),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: "test.frisket",
                                                      exclusions: { exclusions.bundleIdentifiers }),
            clipboard: UnusedExclusionClipboard(), pendingByteLimit: 10_000, diagnostics: log)
        exclusions.add("test.synthetic-vault")
        exclusions.add("test.synthetic-vault")
        for expected: Set<String> in [["test.frisket", "test.synthetic-vault"], ["test.frisket"]] {
            let id = CaptureID()
            #expect(await commands.execute(.captureFullScreen(id, maximumBytes: 1_000)) == .pending(CaptureRevision(captureID: id, number: 1)))
            #expect(platform.requests.last?.excludedBundleIdentifiers == expected)
            exclusions.remove("test.synthetic-vault")
        }
        #expect(await log.entries().map(\.event) == [
            DiagnosticEvent(name: .capturePending, operation: .capture),
            DiagnosticEvent(name: .capturePending, operation: .capture)
        ])
    }

}
