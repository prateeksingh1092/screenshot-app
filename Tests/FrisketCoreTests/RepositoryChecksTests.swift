import Foundation
import Testing

// Xcode-only with the installed CLT 6.3.3: it has no Testing module.
// These remain Swift Testing tests; the checker also has a standalone CLI.
private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func runCheck(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [repository.appendingPathComponent("Checks/check_repository.py").path] + arguments
    process.environment = ProcessInfo.processInfo.environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
}

@Test(arguments: ["dependencies", "imports", "identity", "provenance", "diagnostics", "capture-memory", "input-monitoring", "app-sources",
                  "network", "silgen", "modals"])
func repositorySatisfiesStaticChecks(check: String) throws {
    let result = try runCheck(["--root", repository.path, "--check", check])
    #expect(result.status == 0, Comment(rawValue: result.output))
}

@Test(arguments: [
    "app-sources-rejected", "app-sources-accepted", "app-sources-adapters-rejected",
    "input-hot-key-duplicate-rejected", "input-hot-key-single-accepted",
    "input-monitoring-rejected", "input-monitoring-accepted", "dependencies-rejected", "dependencies-accepted", "dependencies-lockfile-rejected",
    "imports-rejected", "imports-accepted", "imports-qualified-type-rejected", "imports-interpolation-rejected",
    "identity-rejected", "identity-accepted", "identity-after-header-rejected",
    "provenance-rejected", "provenance-accepted", "provenance-tampered", "provenance-hash-tampered",
    "diagnostics-rejected", "diagnostics-accepted", "diagnostics-collection-rejected",
    "capture-memory-rejected", "capture-memory-accepted", "capture-memory-render-accepted", "capture-memory-render-url-rejected", "capture-finalization-rejected", "capture-finalization-accepted",
    "capture-latency-stdout-accepted", "capture-latency-stdout-rejected",
    "network-rejected", "network-accepted", "modals-rejected", "modals-accepted", "silgen-rejected", "silgen-accepted"
])
func staticCheckFixturesHaveExpectedOutcomes(fixture: String) throws {
    let path = repository.appendingPathComponent("Checks/Fixtures/\(fixture).json")
    let result = try runCheck(["--fixture", path.path])
    #expect(result.status == 0, Comment(rawValue: result.output))
}

/// D22: `@_silgen_name` calls C functions with the Swift calling convention. Tickets 63 and 67 removed every use.
@Test
func d22ProductCodeBindsNoCFunctionThroughSilgenName() throws {
    let result = try runCheck(["--root", repository.path, "--check", "silgen"])
    #expect(result.status == 0, "D22: \(result.output)")
}

@Test
func performanceToolingSatisfiesOfflineChecks() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-B", "-m", "unittest", "discover", "-s",
                         repository.appendingPathComponent("Tools/Performance").path,
                         "-p", "test_*.py"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: output, as: UTF8.self)))
}

@Test
func firstRunRecordSatisfiesOfflineChecks() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-B", "-m", "unittest", "discover", "-s",
                         repository.appendingPathComponent("Tools/FirstRun").path,
                         "-p", "test_*.py"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: output, as: UTF8.self)))
}

@Test
func releaseProjectSatisfiesOfflineChecks() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-B", "-m", "unittest", "discover", "-s",
                         repository.appendingPathComponent("Tools/Release").path,
                         "-p", "test_*.py"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: output, as: UTF8.self)))
}
