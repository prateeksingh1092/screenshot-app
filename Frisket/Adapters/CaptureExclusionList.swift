import Combine
import Foundation
import FrisketCore

/// Bundle identities persist; display names are resolved only by Settings.
/// Nil defaults provide an in-memory list for synthetic command tests.
@MainActor public final class CaptureExclusionList: ObservableObject {
    @Published public private(set) var bundleIdentifiers: Set<String>
    private let defaults: UserDefaults?
    private let key = PreferenceKey.captureExclusions.rawValue

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        bundleIdentifiers = Set(defaults?.stringArray(forKey: key) ?? [])
    }

    public func add(_ identifier: String) {
        guard !identifier.isEmpty else { return }
        bundleIdentifiers.insert(identifier)
        defaults?.set(bundleIdentifiers.sorted(), forKey: key)
    }

    public func remove(_ identifier: String) {
        bundleIdentifiers.remove(identifier)
        defaults?.set(bundleIdentifiers.sorted(), forKey: key)
    }
}
