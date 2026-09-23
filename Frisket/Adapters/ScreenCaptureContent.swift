import AppKit
@preconcurrency import ScreenCaptureKit

/// ScreenCaptureKit's immutable snapshot and screenshot API boundary.
/// Fixtures replace this boundary without requesting permission or screen pixels.
@MainActor protocol ScreenCaptureContent {
    func captureImage(_ request: AreaCaptureRequest, additionalExclusions: Set<String>) async throws -> CGImage
    func prepareMagnifier(on screen: NSScreen, excluding bundleIdentifier: String,
                          additionalExclusions: Set<String>) async throws -> SelectionMagnifier
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

    func prepareMagnifier(on screen: NSScreen, excluding bundleIdentifier: String,
                          additionalExclusions: Set<String>) async throws -> SelectionMagnifier {
        try await SelectionMagnifier.prepare(on: screen, content: content, excluding: bundleIdentifier,
                                             additionalExclusions: additionalExclusions)
    }

    private enum ContentError: Error { case unavailable }
}
