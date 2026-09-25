import AppKit
@preconcurrency import ScreenCaptureKit

/// ScreenCaptureKit's immutable snapshot and screenshot API boundary.
/// Fixtures replace this boundary without requesting permission or screen pixels.
@MainActor protocol ScreenCaptureContent {
    func captureImage(_ request: AreaCaptureRequest, additionalExclusions: Set<String>) async throws -> CGImage
    /// True only if this snapshot lists the running process under `bundleIdentifier`, so a
    /// filter built from it leaves out Frisket's on-screen windows.
    func listsOwnProcess(bundleIdentifier: String) -> Bool
}

extension ScreenCaptureContent {
    func listsOwnProcess(bundleIdentifier: String) -> Bool { false }
}

@MainActor struct ShareableScreenCaptureContent: ScreenCaptureContent {
    let content: SCShareableContent

    func captureImage(_ request: AreaCaptureRequest, additionalExclusions: Set<String>) async throws -> CGImage {
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw ContentError.unavailable
        }
        let filter = try ScreenCapturePolicy.filter(display: display, content: content,
            excluding: request.excludingBundleIdentifier,
            additionalExclusions: request.excludedBundleIdentifiers.union(additionalExclusions))
        let configuration = ScreenCapturePolicy.configuration(sourceRect: request.sourceRect,
            pixelWidth: request.pixelWidth, pixelHeight: request.pixelHeight)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    func listsOwnProcess(bundleIdentifier: String) -> Bool {
        let listed = content.applications.filter { $0.bundleIdentifier == bundleIdentifier }.map(\.processID)
        return ScreenCapturePolicy.ownProcessListing(listedProcessIDs: listed,
            currentProcessID: ProcessInfo.processInfo.processIdentifier) == .included
    }

    private enum ContentError: Error { case unavailable }
}
