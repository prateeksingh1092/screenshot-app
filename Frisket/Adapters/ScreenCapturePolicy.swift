import Foundation
@preconcurrency import ScreenCaptureKit

/// Shared policy for the frozen preview and final capture. Callers retain
/// their own size budgets, pixel-format needs, and image handling.
@MainActor enum ScreenCapturePolicy {
    static func filter(display: SCDisplay, content: SCShareableContent,
                       excluding bundleIdentifier: String,
                       additionalExclusions: Set<String> = []) throws -> SCContentFilter {
        let ownApplications = content.applications.filter { $0.bundleIdentifier == bundleIdentifier }
        // Fail closed: never capture unless this process is positively excluded.
        guard ownApplications.contains(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw PolicyError.unavailable
        }
        let identifiers = additionalExclusions.union([bundleIdentifier])
        let excludedApplications = content.applications.filter { identifiers.contains($0.bundleIdentifier) }
        return SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
    }

    static func configuration(sourceRect: CGRect, pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.ignoreShadowsDisplay = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.captureResolution = .best
        return configuration
    }

    private enum PolicyError: Error { case unavailable }
}
