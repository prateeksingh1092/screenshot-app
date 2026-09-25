/// First-launch presentation. The completion flag is a bundle-scoped preference
/// key, never a file under the History root. Onboarding closes before any
/// permission request, and it stays hidden while a system alert is pending.
public struct OnboardingCompletion: Equatable, Sendable {
    public var isComplete: Bool

    public init(isComplete: Bool) {
        self.isComplete = isComplete
    }

    public var shouldPresent: Bool { !isComplete }

    public func markComplete() -> OnboardingCompletion {
        OnboardingCompletion(isComplete: true)
    }
}

public enum LaunchSurface: Equatable, Sendable {
    case onboarding
    case hiddenWhileSystemAlertPending
    case ready
}

public struct OnboardingHandoff: Equatable, Sendable {
    public var isComplete: Bool
    public var showsPermissionRecovery: Bool
    public var permission: CapturePermissionState
}

public enum FirstLaunch {
    /// `requested` is the menu's reopen command (ticket 101): it shows onboarding again even once completed.
    public static func surface(onboarding: OnboardingCompletion, systemAlertPending: Bool,
                               dismissedForLaunch: Bool = false, requested: Bool = false) -> LaunchSurface {
        if systemAlertPending { return .hiddenWhileSystemAlertPending }
        if requested { return .onboarding }
        return onboarding.shouldPresent && !dismissedForLaunch ? .onboarding : .ready
    }

    /// Recovery is ticket 23's request path. This does not request permission itself.
    public static func complete(permission: CapturePermissionState, systemAlertPending: Bool) -> OnboardingHandoff {
        OnboardingHandoff(
            isComplete: true,
            showsPermissionRecovery: !systemAlertPending && permission != .granted,
            permission: permission
        )
    }
}
