import Foundation
import Testing

// The repository checks themselves run from scripts/ci.sh (ticket 80); these run the tools' own unit tests.
private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

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
