import AppKit

@MainActor enum InstalledAppRelaunch {
    /// Called only after the app's normal quit policy accepts termination.
    /// The helper waits for this PID to exit before opening the one installed bundle.
    static func scheduleAfterExit() throws {
        let installed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Frisket.app", isDirectory: true)
        guard Bundle.main.bundleURL.resolvingSymlinksInPath() == installed.resolvingSymlinksInPath(),
              FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/MacOS/Frisket").path) else {
            throw RelaunchError.notInstalled
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Values are separate positional arguments, never interpolated shell code.
        helper.arguments = ["-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
            "frisket-reopen", String(ProcessInfo.processInfo.processIdentifier), installed.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
    private enum RelaunchError: Error { case notInstalled }
}
