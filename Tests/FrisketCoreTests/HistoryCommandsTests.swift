import Foundation
import Darwin
import FrisketCore
import Testing

private struct HistoryPixels: CapturePixelSource {
    // A synthetic 2 x 1 opaque red PNG; no screen content.
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private struct HistoryClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

@Suite struct HistoryCommandsTests {
    @Test func dismissKeepsExactlyOneFinalizedImageAndReleasesPendingBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("fixture.bundle/History.noindex")
        let store = HistoryStore(root: root, clock: { Date(timeIntervalSince1970: 1234) })
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(source: source, clipboard: HistoryClipboard(),
            pendingByteLimit: source.bytes.count, history: store)
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let entries = try await commands.historyEntries().get()
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.captureID == id)
        #expect(entry.width == 2 && entry.height == 1)
        #expect(entry.imageBytes == Int64(source.bytes.count))
        #expect(entry.finalizedAt == Date(timeIntervalSince1970: 1234))
        #expect(entry.state == .finalized)
        #expect(!entry.imageLocation.hasPrefix("/"))
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await commands.image(for: revision) == nil)
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.alreadyFinalized))
        #expect(try await commands.historyEntries().get().count == 1)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: source.bytes.count)) != .rejected(.pendingByteBudgetExceeded))
        // The sandbox's URL getter returns false even when the setter writes the
        // exclusion. Verify the actual Time Machine marker on the directory.
        var marker = [UInt8](repeating: 0, count: 256)
        let markerSize = getxattr(root.path, "com.apple.metadata:com_apple_backup_excludeItem", &marker, marker.count, 0, 0)
        #expect(markerSize > 0)
        let exclusion = try PropertyListSerialization.propertyList(from: Data(marker.prefix(max(0, markerSize))), format: nil)
        #expect(exclusion as? String == "com.apple.backupd")
    }
}

private enum StopAfterCommit: Error { case stop }

extension HistoryCommandsTests {
    @Test(arguments: [false, true])
    func thumbnailIsDisposableAndOnlyGeneratedAfterTheRowCommits(stopAfterRow: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { point in
            if point == .rowCommitted {
                #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("thumbnails").path))
                if stopAfterRow { throw StopAfterCommit.stop }
            }
        })
        let commands = CaptureCommandLayer(source: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024, history: store)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let entry = try #require(try await commands.historyEntries().get().first)
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(entry.recordLocation))) as? [String: Any]
        #expect(record?["marker"] as? String == "frisket.finalized.v1")
        #expect(record?["captureIdentifier"] as? String == revision.captureID.rawValue.uuidString)
        #expect(record?["width"] as? Int == 2)
        #expect(record?["height"] as? Int == 1)
        #expect(entry.recordBytes == Int64(try Data(contentsOf: root.appendingPathComponent(entry.recordLocation)).count))
        if stopAfterRow {
            #expect(entry.thumbnailLocation == nil)
            #expect(entry.thumbnailBytes == 0)
        } else {
            let thumbnail = try #require(entry.thumbnailLocation)
            let url = root.appendingPathComponent(thumbnail)
            #expect(entry.thumbnailBytes == Int64(try Data(contentsOf: url).count))
            #expect(entry.thumbnailBytes > 0)
            try FileManager.default.removeItem(at: url)
        }
        // Deleting a disposable cache cannot lose the committed History item.
        #expect(try await commands.historyEntries().get().map(\.captureID) == [revision.captureID])
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == HistoryPixels().bytes)
    }
}

private actor RetryHistoryClipboard: ImageClipboard {
    private var attempts = 0
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        attempts += 1
        return attempts == 1 ? .failure(.unavailable) : .success(ClipboardReceipt(changeCount: 2))
    }
}

extension HistoryCommandsTests {
    @Test func committedCaptureCannotBeDiscardedAfterCopyDeliveryFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(source: source, clipboard: RetryHistoryClipboard(),
            pendingByteLimit: source.bytes.count, history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .failed(.unavailable))))
        let before = try await commands.historyEntries().get()
        let entry = try #require(before.first)

        // Discard applies to pending captures. Finalized deletion belongs to ticket 15.
        #expect(await commands.execute(.discard(revision.captureID)) == .rejected(.alreadyFinalized))
        #expect(try await commands.historyEntries().get() == before)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: source.bytes.count)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 2)))))
        #expect(try await commands.historyEntries().get() == before)
        #expect(await commands.image(for: revision) == nil)
    }

    @Test(arguments: [false, true])
    func copyRetryOrDismissAfterDeliveryFailureKeepsTheSameCommittedRevision(dismiss: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(source: HistoryPixels(), clipboard: RetryHistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .failed(.unavailable))))
        let before = try await commands.historyEntries().get()
        #expect(before.count == 1)
        if dismiss {
            #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        } else {
            #expect(await commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(revision: revision,
                commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 2)))))
        }
        #expect(try await commands.historyEntries().get() == before)
        #expect(await commands.image(for: revision) == nil)
    }
}

private func migrationFixture(at root: URL, wal: Bool) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", """
        import os, sqlite3, sys
        db = sqlite3.connect(sys.argv[1])
        db.execute('PRAGMA journal_mode=' + ('WAL' if sys.argv[2] == 'wal' else 'DELETE'))
        db.execute('CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY)')
        db.execute("INSERT INTO grdb_migrations VALUES ('future-history-v2')")
        db.execute('CREATE TABLE future_data(value TEXT)')
        db.execute("INSERT INTO future_data VALUES ('must survive unchanged')")
        db.commit()
        if sys.argv[2] == 'wal':
            os.unlink(sys.argv[1] + '-shm')
            os._exit(0)
        db.close()
        """, root.appendingPathComponent("history.sqlite").path, wal ? "wal" : "delete"]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private func diskSnapshot(_ root: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
        result[file.lastPathComponent] = try Data(contentsOf: file)
    }
    return result
}

extension HistoryCommandsTests {
    @Test(arguments: [false, true])
    func unknownMigrationsAreRefusedWithoutChangingAnyExistingFiles(wal: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        try migrationFixture(at: root, wal: wal)
        let before = try diskSnapshot(root)
        let log = LocalDiagnosticLog()
        let commands = CaptureCommandLayer(source: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            diagnostics: log, history: HistoryStore(root: root))
        let failure: HistoryFailure = wal ? .recoveryRequired : .unknownMigrations
        let reason: CommitUnavailableReason = wal ? .recoveryRequired : .unknownMigrations
        let code: DiagnosticErrorCode = wal ? .recoveryRequired : .unknownMigrations
        #expect(await commands.historyEntries() == .failure(failure))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .notCommitted(reason)))
        #expect(await commands.image(for: revision)?.pngData == HistoryPixels().bytes)
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .notCommitted(reason), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(try diskSnapshot(root) == before)
        #expect(await log.entries().map(\.event) == [
            DiagnosticEvent(name: .capturePending, operation: .capture),
            DiagnosticEvent(name: .finalizationFailed, operation: .dismiss,
                error: DiagnosticError(domain: .history, code: code)),
            DiagnosticEvent(name: .deliverySucceeded, operation: .copy,
                error: DiagnosticError(domain: .history, code: code))
        ])
    }
}

private func seedSQL(_ sql: String, at root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [root.appendingPathComponent("history.sqlite").path]
    process.standardOutput = Pipe()
    let input = Pipe()
    process.standardInput = input
    try process.run()
    input.fileHandleForWriting.write(Data(sql.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
}

extension HistoryCommandsTests {
    @Test func baselineFixtureReopensWithoutWritesAndSurvivesTheNextCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/History/history-v1.sql")
        try seedSQL(String(contentsOf: fixture, encoding: .utf8), at: root)
        let before = try diskSnapshot(root)
        let commands = CaptureCommandLayer(source: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let oldEntries = try await commands.historyEntries().get()
        #expect(oldEntries.count == 1) // deleting is a valid state but hidden
        #expect(oldEntries.first?.key == 41)
        #expect(oldEntries.first?.captureID.rawValue.uuidString == "11111111-1111-1111-1111-111111111111")
        #expect(try diskSnapshot(root) == before)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(try diskSnapshot(root) == before)
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let after = try await commands.historyEntries().get()
        #expect(after.count == 2)
        #expect(after.first == oldEntries.first)
        #expect(after.last?.captureID == revision.captureID)
    }
}

extension HistoryCommandsTests {
    @Test(arguments: HistoryCommitPoint.allCases)
    func eachCommitPointLeavesOnlyAuthorizedFilesAndNeverAPrematureRow(point: HistoryCommitPoint) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { reached in
            if reached == point { throw StopAfterCommit.stop }
        })
        let commands = CaptureCommandLayer(source: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024, history: store)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        let id = revision.captureID.rawValue.uuidString
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let committed = point == .rowCommitted || point == .thumbnailCached
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision,
            committed ? .committed : .notCommitted(.historyUnavailable)))
        #expect(try await commands.historyEntries().get().count == (committed ? 1 : 0))
        let expected: Set<String>
        switch point {
        case .pngStaged, .pngSynced:
            expected = ["staging/\(id).png"]
        case .recordStaged, .recordSynced:
            expected = ["staging/\(id).png", "staging/\(id).finalization.json"]
        case .imageRenamed:
            expected = ["images/\(id).png", "staging/\(id).finalization.json"]
        case .recordRenamed, .directorySynced, .rowCommitted:
            expected = ["images/\(id).png", "images/\(id).finalization.json"]
        case .thumbnailCached:
            expected = ["images/\(id).png", "images/\(id).finalization.json", "thumbnails/\(id).png"]
        }
        var files = Set<String>()
        for subdirectory in ["staging", "images", "thumbnails"] {
            let url = root.appendingPathComponent(subdirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            for item in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                files.insert("\(subdirectory)/\(item.lastPathComponent)")
            }
        }
        #expect(files == expected)
        for image in files.filter({ $0.hasSuffix(".png") && !$0.hasPrefix("thumbnails/") }) {
            #expect(try Data(contentsOf: root.appendingPathComponent(image)) == HistoryPixels().bytes)
        }
        #expect((await commands.image(for: revision) == nil) == committed)
    }

    @Test func discardedAndStaleCommandsCannotCreateStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(source: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.unknownCapture))
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(CaptureRevision(captureID: revision.captureID, number: 2))) == .rejected(.staleRevision))
        #expect(await commands.execute(.discard(revision.captureID)) == .discarded(revision.captureID))
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.discardedCapture))
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
