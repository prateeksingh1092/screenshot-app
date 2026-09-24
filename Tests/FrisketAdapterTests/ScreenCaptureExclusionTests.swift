import AppKit
import FrisketCore
@testable import FrisketAdapters
import Testing

@MainActor private final class ExclusionScreenAccess: ScreenRecordingAccess {
    var hasRequested = true
    func preflight() -> Bool { true }
    func request() -> Bool { Issue.record("Must not request permission"); return false }
}

/// Models the OS boundary: an application filter excludes process identities
/// from its snapshot, while the desktop can contain a newly launched process.
@MainActor private final class SyntheticDesktop {
    var vaultProcess: Int?
    var snapshotFails = false
    var duringScreenshot: () -> Void = {}

    func snapshot() throws -> any ScreenCaptureContent {
        if snapshotFails { throw CaptureSourceFailure.unavailable }
        return Snapshot(desktop: self, vaultProcess: vaultProcess)
    }

    private struct Snapshot: ScreenCaptureContent {
        let desktop: SyntheticDesktop
        let vaultProcess: Int?

        func captureImage(_ request: AreaCaptureRequest, additionalExclusions: Set<String>) async throws -> CGImage {
            await Task.yield()
            desktop.duringScreenshot()
            let excluded = request.excludedBundleIdentifiers.union(additionalExclusions)
                .contains("test.vault") && vaultProcess != nil && vaultProcess == desktop.vaultProcess
            let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // A red canary means a running vault process escaped the snapshot filter.
            context.setFillColor(CGColor(red: desktop.vaultProcess != nil && !excluded ? 1 : 0,
                                         green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            return try #require(context.makeImage())
        }
    }
}

@Suite @MainActor struct ScreenCaptureExclusionTests {
    private let request = AreaCaptureRequest(displayID: 1,
        sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), pixelWidth: 1, pixelHeight: 1,
        excludingBundleIdentifier: "test.frisket", additionalExcludedBundleIdentifiers: ["test.vault"])

    private func platform(_ desktop: SyntheticDesktop,
                          notifications: NotificationCenter = NotificationCenter()) -> ScreenCapturePlatform {
        ScreenCapturePlatform(permission: ScreenCapturePermissionAdapter(access: ExclusionScreenAccess()),
            loadContent: { try desktop.snapshot() }, connectedDisplays: {
                [SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1)]
            }, applicationNotifications: notifications)
    }

    @Test(arguments: [nil, 41] as [Int?])
    func excludesAppLaunchedDuringSelection(previousProcess: Int?) async throws {
        let desktop = SyntheticDesktop()
        desktop.vaultProcess = previousProcess
        let platform = platform(desktop)
        defer { platform.finishCapture() }
        try await platform.prefetchShareableContent()
        // During selection the vault either launched or relaunched with a new PID.
        desktop.vaultProcess = 42
        let png = try await platform.capture(request, maximumBytes: 10_000)
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let pixel = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        #expect(pixel.redComponent == 0)
    }

    @Test func refreshFailureDoesNotFallBackToPrefetchedApplications() async throws {
        let desktop = SyntheticDesktop()
        let platform = platform(desktop)
        defer { platform.finishCapture() }
        try await platform.prefetchShareableContent()
        desktop.vaultProcess = 42
        desktop.snapshotFails = true
        await #expect(throws: CaptureSourceFailure.unavailable) {
            try await platform.capture(request, maximumBytes: 10_000)
        }
    }

    @Test(arguments: [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification])
    func discardsImageWhenApplicationsChangeDuringScreenshot(notification: Notification.Name) async throws {
        let desktop = SyntheticDesktop()
        let notifications = NotificationCenter()
        let platform = platform(desktop, notifications: notifications)
        defer { platform.finishCapture() }
        try await platform.prefetchShareableContent()
        desktop.duringScreenshot = {
            desktop.vaultProcess = 43
            notifications.post(name: notification, object: nil)
        }
        await #expect(throws: (any Error).self) {
            try await platform.capture(request, maximumBytes: 10_000)
        }
    }
}
