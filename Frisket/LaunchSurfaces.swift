import AppKit
import FrisketAdapters
import FrisketCore

@MainActor final class LaunchSurfaces {
    private let preference: OnboardingPreference
    private var onboarding: OnboardingPanel?
    private var about: AboutPanel?
    private var deferredRecovery = false
    private var onboardingDismissedForLaunch = false

    init(preference: OnboardingPreference = OnboardingPreference(defaults: .standard)) {
        self.preference = preference
    }

    /// `requested` is the menu's "What Frisket Stores…" item: it shows onboarding again after it was completed (ticket 101).
    func presentOnboardingIfNeeded(systemAlertPending: @escaping () -> Bool, permission: @escaping () -> CapturePermissionState,
                                   recover: @escaping (CapturePermissionState) -> Void, requested: Bool = false) {
        if requested, focusOnboardingIfVisible() { return }
        let completion = OnboardingCompletion(isComplete: preference.isComplete)
        guard FirstLaunch.surface(onboarding: completion, systemAlertPending: systemAlertPending(),
                                  dismissedForLaunch: onboardingDismissedForLaunch, requested: requested) == .onboarding else { return }
        let panel = OnboardingPanel(content: .current, acknowledge: { [weak self] in
            guard let self else { return }
            self.preference.markComplete()
            self.onboarding = nil
            let pending = systemAlertPending()
            let handoff = FirstLaunch.complete(permission: permission(), systemAlertPending: pending)
            if handoff.showsPermissionRecovery {
                recover(handoff.permission)
            } else if pending {
                self.deferredRecovery = true
            }
        }, later: { [weak self] in
            self?.onboardingDismissedForLaunch = true
            self?.onboarding = nil
        })
        onboarding = panel
        panel.present()
    }

    func systemAlertEnded(systemAlertPending: @escaping () -> Bool, permission: @escaping () -> CapturePermissionState,
                          recover: @escaping (CapturePermissionState) -> Void) {
        if deferredRecovery {
            guard !systemAlertPending() else { return }
            deferredRecovery = false
            let handoff = FirstLaunch.complete(permission: permission(), systemAlertPending: false)
            if handoff.showsPermissionRecovery { recover(handoff.permission) }
            return
        }
        presentOnboardingIfNeeded(systemAlertPending: systemAlertPending, permission: permission, recover: recover)
    }

    func focusOnboardingIfVisible() -> Bool {
        guard onboarding?.window?.isVisible == true else { return false }
        onboarding?.present()
        return true
    }

    func presentAbout() {
        if about == nil { about = AboutPanel(content: BundledAbout.content()) }
        about?.present()
    }
}
