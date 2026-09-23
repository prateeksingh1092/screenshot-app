/// Process-level Screen Recording access. No platform types cross this interface.
public enum CapturePermissionState: Equatable, Sendable {
    case notAsked, denied, granted, revokedWhileRunning, needsRelaunch
}

/// Checked for every capture, before the pixel source can create selection UI.
/// Checking must not request permission; the recovery UI owns explicit requests.
public protocol CapturePermissionSource: Sendable {
    func capturePermission() async -> CapturePermissionState
}
