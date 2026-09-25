import Foundation
import Darwin
import FrisketCore
import Testing

/// Ticket 78: History written by the sidecar store migrates to one row per capture at launch.
/// No capture is lost, the sidecars, staging and ledger go, and the database backup taken
/// before the migration is deleted once the migration's check passes.
private let pixels = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
private let edited = "33333333-3333-3333-3333-333333333333"
private let deleting = "44444444-4444-4444-4444-444444444444"
private let interrupted = "55555555-5555-5555-5555-555555555555"

private struct MigrationPixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> { .success(CaptureImage(pngData: pixels)) }
}

private struct MigrationClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> { .success(ClipboardReceipt(changeCount: 1)) }
}

private func sqlite(_ root: URL, _ sql: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [root.appendingPathComponent("history.sqlite").path]
    let output = Pipe()
    let input = Pipe()
    process.standardOutput = output
    process.standardInput = input
    try process.run()
    input.fileHandleForWriting.write(Data(sql.utf8))
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    return String(decoding: data, as: UTF8.self)
}

/// The pre-ticket layout: rows, sidecars, a cached thumbnail, a deleting row, a ledger-owned
/// interrupted finalization, and staging leftovers (including a drag's).
private func seedSidecarHistory(at root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/History/history-v2-sidecars.sql")
    _ = try sqlite(root, String(contentsOf: fixture, encoding: .utf8))
    for directory in ["images", "thumbnails", "staging/drag"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
    }
    for id in [edited, deleting, interrupted] {
        try pixels.write(to: root.appendingPathComponent("images/\(id).png"))
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("images/\(id).finalization.json"))
    }
    for id in [edited, deleting] { try pixels.write(to: root.appendingPathComponent("thumbnails/\(id).png")) }
    try pixels.write(to: root.appendingPathComponent("staging/\(UUID().uuidString).png"))
    try pixels.write(to: root.appendingPathComponent("staging/drag/\(UUID().uuidString).png"))
}

private func files(_ root: URL) -> Set<String> {
    var result = Set<String>()
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return result }
    for case let relative as String in enumerator {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path, isDirectory: &isDirectory),
           !isDirectory.boolValue { result.insert(relative) }
    }
    return result
}

@Suite struct HistoryMigrationTests {
    @Test func sidecarHistoryMigratesAtLaunchWithoutLosingACapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        try seedSidecarHistory(at: root)
        let history = HistoryStore.launch(root: root, limits: HistoryLimits(retentionDays: 40_000))
        let entries = try await history.entries().get()
        #expect(entries.map(\.captureID.rawValue.uuidString) == [edited, interrupted])
        let kept = try #require(entries.first)
        #expect(kept.key == 7 && kept.revision == 2)
        #expect(kept.finalizedAt == Date(timeIntervalSince1970: 1000))
        #expect(kept.imageBytes == Int64(pixels.count) && kept.thumbnailBytes == Int64(pixels.count))
        #expect(await history.thumbnailPNG(kept.captureID) == pixels)
        #expect(try await history.finalizedImage(entries[1].captureID).get().pngData == pixels)
        // macOS's SQLite keeps an empty -wal and the -shm after close.
        #expect(Set(files(root).filter { !$0.hasPrefix("history.sqlite") }) == Set([
            "images/\(edited).png", "thumbnails/\(edited).png", "images/\(interrupted).png"
        ]))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("staging").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-backup").path))
        let tables = try sqlite(root, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;")
        #expect(!tables.contains("history_auxiliary_files"))
        #expect(try sqlite(root, "SELECT identifier FROM grdb_migrations ORDER BY identifier;")
            == "history-retention-v1\nhistory-rows-v1\nhistory-v1\n")

        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: MigrationPixels(),
            clipboard: MigrationClipboard(), pendingByteLimit: 1024, history: history)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await history.rows().get().count == 3)
    }

    /// A migration whose check fails rolls back: the database keeps its old schema and rows,
    /// every capture stays on disk, and the Time Machine-excluded backup is left in place.
    @Test func aFailedMigrationKeepsTheOldDatabaseAndItsExcludedBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        try seedSidecarHistory(at: root)
        _ = try sqlite(root, """
            INSERT INTO history VALUES (9, 'not-a-capture-identifier', 1, 'images/x.png', 'images/x.json', NULL,
                2, 1, 70, 10, 0, 1002, 'finalized', 0);
            """)
        let history = HistoryStore(root: root)
        #expect(await history.recover() == .failure(.unavailable))
        #expect(try sqlite(root, "SELECT identifier FROM grdb_migrations ORDER BY identifier;")
            == "history-retention-v1\nhistory-v1\n")
        #expect(try sqlite(root, "SELECT id FROM history WHERE state = 'finalized' ORDER BY id;") == "7\n9\n")
        for id in [edited, interrupted] {
            #expect(try Data(contentsOf: root.appendingPathComponent("images/\(id).png")) == pixels)
        }
        let backup = root.appendingPathComponent("migration-backup/history.sqlite")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        var marker = [UInt8](repeating: 0, count: 256)
        let markerSize = getxattr(backup.deletingLastPathComponent().path,
                                  "com.apple.metadata:com_apple_backup_excludeItem", &marker, marker.count, 0, 0)
        #expect(markerSize > 0)
    }
}
