import Foundation

struct AppIdentity {
    let bundleIdentifier: String
    // Resolving the identity does not create storage. History creates it on finalization.
    var historyRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("History.noindex", isDirectory: true)
    }
}
