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

@Test(arguments: ["dependencies", "imports", "identity", "provenance"])
func repositorySatisfiesStaticChecks(check: String) throws {
    let result = try runCheck(["--root", repository.path, "--check", check])
    #expect(result.status == 0, Comment(rawValue: result.output))
}

@Test(arguments: [
    "dependencies-rejected", "dependencies-accepted", "dependencies-lockfile-rejected",
    "imports-rejected", "imports-accepted", "imports-qualified-type-rejected", "imports-interpolation-rejected",
    "identity-rejected", "identity-accepted", "identity-after-header-rejected",
    "provenance-rejected", "provenance-accepted", "provenance-tampered",
    "trial-provenance-inventory", "trial-identity-inventory", "trial-imports-inventory"
])
func staticCheckFixturesHaveExpectedOutcomes(fixture: String) throws {
    let path = repository.appendingPathComponent("Checks/Fixtures/\(fixture).json")
    let result = try runCheck(["--fixture", path.path])
    #expect(result.status == 0, Comment(rawValue: result.output))
}
