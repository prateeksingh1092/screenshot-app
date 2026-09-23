import AppKit

@MainActor struct InstalledAppRelaunch {
    private let installed: URL

    /// Validate before accepting quit, while termination can still be cancelled.
    init() throws {
        let installed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Frisket.app", isDirectory: true)
        guard Bundle.main.bundleURL.resolvingSymlinksInPath() == installed.resolvingSymlinksInPath(),
              FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/MacOS/Frisket").path) else {
            throw RelaunchError.notInstalled
        }
        self.installed = installed
    }

    /// Called from applicationWillTerminate, after normal quit policy has accepted.
    /// A separate open process survives our exit; -n prevents reusing this instance.
    func openDuringTermination() throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        helper.arguments = ["-n", installed.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
    private enum RelaunchError: Error { case notInstalled }
}
