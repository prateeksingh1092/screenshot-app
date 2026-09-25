import Foundation
@preconcurrency import ScreenCaptureKit

/// Shared policy for the Loupe and the final capture. Callers retain
/// their own size budgets, pixel-format needs, and image handling.
@MainActor enum ScreenCapturePolicy {
    enum OwnProcessListing: Equatable, Sendable {
        case unlisted
        case included
        case staleIdentity
    }

    /// `onScreenWindowsOnly` snapshots omit this process after the overlay hides.
    /// Fail closed only when the bundle is listed under a different PID.
    nonisolated static func ownProcessListing(listedProcessIDs: [pid_t], currentProcessID: pid_t) -> OwnProcessListing {
        if listedProcessIDs.isEmpty { return .unlisted }
        if listedProcessIDs.contains(currentProcessID) { return .included }
        return .staleIdentity
    }

    static func filter(display: SCDisplay, content: SCShareableContent,
                       excluding bundleIdentifier: String,
                       additionalExclusions: Set<String> = []) throws -> SCContentFilter {
        let ownApplications = content.applications.filter { $0.bundleIdentifier == bundleIdentifier }
        switch ownProcessListing(listedProcessIDs: ownApplications.map(\.processID),
                                 currentProcessID: ProcessInfo.processInfo.processIdentifier) {
        case .staleIdentity:
            throw PolicyError.unavailable
        case .unlisted, .included:
            break
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
