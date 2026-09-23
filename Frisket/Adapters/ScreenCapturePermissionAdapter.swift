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
    private var observedGrant = false
    private var requiresRelaunch = false
    init(access: any ScreenRecordingAccess) { self.access = access }

    func capturePermission() -> CapturePermissionState { refresh() }

    func refresh() -> CapturePermissionState {
        if requiresRelaunch { return .needsRelaunch }
        if access.preflight() {
            observedGrant = true
            if !access.hasRequested { access.hasRequested = true }
            return .granted
        }
        if observedGrant { return .revokedWhileRunning }
        return access.hasRequested ? .denied : .notAsked
    }

    /// Only the explicit recovery action calls this, with selection UI absent.
    func requestPermission() -> CapturePermissionState {
        if refresh() == .granted || requiresRelaunch { return refresh() }
        access.hasRequested = true
        if access.request(), !access.preflight() { requiresRelaunch = true }
        return refresh()
    }

    func failure(for error: Error) -> CaptureSourceFailure {
        let error = error as NSError
        guard error.domain == SCStreamErrorDomain,
              error.code == SCStreamError.Code.userDeclined.rawValue else { return .unavailable }
        access.hasRequested = true
        // Positive preflight plus SCK authorization refusal means this process
        // cannot use the apparent grant. Keep recovery latched until relaunch.
        if access.preflight() { requiresRelaunch = true }
        return .permissionRequired(refresh())
    }
}
