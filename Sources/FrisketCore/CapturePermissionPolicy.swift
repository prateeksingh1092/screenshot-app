/// Process-local permission policy. Feed raw observations in order; persist only
/// `hasRequested` and create a fresh policy when a new app process starts.
public struct CapturePermissionPolicy: Sendable {
    public enum Observation: Sendable {
        case preflight(Bool)
        case requestCompleted(accepted: Bool, preflight: Bool)
        /// The adapter maps only ScreenCaptureKit's authorization refusal here.
        case authorizationDenied(preflight: Bool)
    }

    public private(set) var hasRequested: Bool
    private var state: CapturePermissionState
    private var observedGrant = false
    private var requiresRelaunch = false

    public init(hasRequested: Bool) {
        self.hasRequested = hasRequested
        state = hasRequested ? .denied : .notAsked
    }

    /// Only an explicit recovery action may request; capture checks never do.
    public var canRequest: Bool { state != .granted && state != .needsRelaunch }

    @discardableResult
    public mutating func observe(_ observation: Observation) -> CapturePermissionState {
        let preflight: Bool
        switch observation {
        case let .preflight(allowed): preflight = allowed
        case let .requestCompleted(accepted, allowed):
            hasRequested = true
            preflight = allowed
            if accepted && !allowed { requiresRelaunch = true }
        case let .authorizationDenied(allowed):
            hasRequested = true
            preflight = allowed
            if allowed { requiresRelaunch = true }
        }
        if requiresRelaunch {
            state = .needsRelaunch
        } else if preflight {
            observedGrant = true
            hasRequested = true
            state = .granted
        } else {
            state = observedGrant ? .revokedWhileRunning : (hasRequested ? .denied : .notAsked)
        }
        return state
    }
}
