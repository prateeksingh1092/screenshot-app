/// A button on the Screen Recording permission message.
public enum PermissionRecoveryAction: Equatable, Sendable {
    case requestScreenRecording, openSystemSettings, quitAndReopen

    public var title: String {
        switch self {
        case .requestScreenRecording: "Request Screen Recording"
        case .openSystemSettings: "Open System Settings"
        case .quitAndReopen: "Quit & Reopen"
        }
    }
}

/// The only copy for the Screen Recording permission message (docs/permission-recovery.md).
/// Once macOS has asked, a second request is silent, so only a first run offers Request
/// (decision 100, D34, ticket 103). Every other state sends the user to System Settings.
public struct PermissionRecoveryContent: Equatable, Sendable {
    public let explanation: String
    public let actions: [PermissionRecoveryAction]

    public init(state: CapturePermissionState) {
        let settings = "Turn Frisket on in System Settings › Privacy & Security › Screen & System Audio Recording"
        switch state {
        case .notAsked:
            explanation = "Allow Frisket to capture your screen before selecting an area. Choose Request Screen Recording and allow it when macOS asks."
        case .denied:
            explanation = "Screen Recording is off for Frisket. \(settings), then try again; quit and reopen Frisket if macOS asks."
        case .revokedWhileRunning:
            explanation = "Frisket lost Screen Recording access while running. \(settings), then quit and reopen Frisket if macOS asks."
        case .needsRelaunch:
            explanation = "Screen Recording access has changed, but this process cannot use it. Quit and reopen Frisket to continue."
        case .granted:
            explanation = "Screen Recording is available. Close this panel and try capture again."
        }
        actions = state == .notAsked
            ? [.requestScreenRecording, .openSystemSettings, .quitAndReopen]
            : [.openSystemSettings, .quitAndReopen]
    }
}
