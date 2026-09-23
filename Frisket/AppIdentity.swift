import Foundation

struct AppIdentity {
    let bundleIdentifier: String
    // Resolve only: ticket 08 never creates the root or writes pending images to disk.
    var historyRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("History.noindex", isDirectory: true)
    }
}
