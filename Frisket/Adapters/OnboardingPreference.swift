import Foundation
import FrisketCore

/// Bundle-scoped completion flag. Callers pass the running bundle's defaults.
/// The key is not a path, and this type never writes under the History root.
final class OnboardingPreference {
    private let read: (String) -> Bool
    private let write: (String, Bool) -> Void

    init(read: @escaping (String) -> Bool, write: @escaping (String, Bool) -> Void) {
        self.read = read
        self.write = write
    }

    convenience init(defaults: UserDefaults) {
        self.init(
            read: { defaults.bool(forKey: $0) },
            write: { defaults.set($1, forKey: $0) }
        )
    }

    var isComplete: Bool { read(OnboardingCompletion.preferenceKey) }

    func markComplete() { write(OnboardingCompletion.preferenceKey, true) }
}
