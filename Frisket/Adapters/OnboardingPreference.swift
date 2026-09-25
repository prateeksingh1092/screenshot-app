import Foundation
import FrisketCore

/// Bundle-scoped completion flag. Callers pass the running bundle's defaults.
/// The key is not a path, and this type never writes under the History root.
public final class OnboardingPreference {
    private let read: (String) -> Bool
    private let write: (String, Bool) -> Void

    init(read: @escaping (String) -> Bool, write: @escaping (String, Bool) -> Void) {
        self.read = read
        self.write = write
    }

    public convenience init(defaults: UserDefaults) {
        self.init(
            read: { defaults.bool(forKey: $0) },
            write: { defaults.set($1, forKey: $0) }
        )
    }

    public var isComplete: Bool { read(PreferenceKey.onboardingCompleted.rawValue) }

    public func markComplete() { write(PreferenceKey.onboardingCompleted.rawValue, true) }
}
