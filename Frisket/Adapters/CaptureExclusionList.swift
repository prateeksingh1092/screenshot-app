import Combine
import Foundation

/// Bundle identities persist; display names are resolved only by Settings.
/// Nil defaults provide an in-memory list for synthetic command tests.
@MainActor final class CaptureExclusionList: ObservableObject {
    @Published private(set) var bundleIdentifiers: Set<String>
    private let defaults: UserDefaults?
    private let key = "captureExcludedBundleIdentifiers"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        bundleIdentifiers = Set(defaults?.stringArray(forKey: key) ?? [])
    }

    func add(_ identifier: String) {
        guard !identifier.isEmpty else { return }
        bundleIdentifiers.insert(identifier)
        defaults?.set(bundleIdentifiers.sorted(), forKey: key)
    }

    func remove(_ identifier: String) {
        bundleIdentifiers.remove(identifier)
        defaults?.set(bundleIdentifiers.sorted(), forKey: key)
    }
}
