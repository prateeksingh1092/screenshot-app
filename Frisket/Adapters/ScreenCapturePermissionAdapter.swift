import CoreGraphics
import Foundation
import FrisketCore
import ScreenCaptureKit

/// The platform and request-history seam. Test adapters never touch TCC or defaults.
@MainActor protocol ScreenRecordingAccess: AnyObject {
    var hasRequested: Bool { get set }
    func preflight() -> Bool
    func request() -> Bool
}

@MainActor final class SystemScreenRecordingAccess: ScreenRecordingAccess {
    // Standard defaults are scoped to the running bundle identity. This marker is
    // request history, never a cached grant or a substitute for OS authorization.
    private let key = "screenRecordingPermissionWasRequested"
    var hasRequested: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }
}

@MainActor final class ScreenCapturePermissionAdapter: CapturePermissionSource {
    private let access: any ScreenRecordingAccess
    private var policy: CapturePermissionPolicy
    init(access: any ScreenRecordingAccess) {
        self.access = access
        policy = CapturePermissionPolicy(hasRequested: access.hasRequested)
    }

    func capturePermission() -> CapturePermissionState { refresh() }

    func refresh() -> CapturePermissionState {
        observe(.preflight(access.preflight()))
    }

    /// Only the explicit recovery action calls this, with selection UI absent.
    func requestPermission() -> CapturePermissionState {
        let state = refresh()
        guard policy.canRequest else { return state }
        // Persist before invoking the OS, which may terminate this process.
        access.hasRequested = true
        let accepted = access.request()
        return observe(.requestCompleted(accepted: accepted, preflight: access.preflight()))
    }

    func failure(for error: Error) -> CaptureSourceFailure {
        let error = error as NSError
        guard error.domain == SCStreamErrorDomain,
              error.code == SCStreamError.Code.userDeclined.rawValue else { return .unavailable }
        return .permissionRequired(observe(.authorizationDenied(preflight: access.preflight())))
    }

    private func observe(_ observation: CapturePermissionPolicy.Observation) -> CapturePermissionState {
        let state = policy.observe(observation)
        if access.hasRequested != policy.hasRequested { access.hasRequested = policy.hasRequested }
        return state
    }
}
