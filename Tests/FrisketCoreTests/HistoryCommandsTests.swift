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

private enum HistoryCaptureKind: CaseIterable, Sendable {
    case area, fullScreen

    func command(_ id: CaptureID, maximumBytes: Int) -> CaptureCommand {
        switch self {
        case .area: .capture(id, maximumBytes: maximumBytes)
        case .fullScreen: .captureFullScreen(id, maximumBytes: maximumBytes)
        }
    }
}

@Suite struct HistoryCommandsTests {
    @Test(arguments: HistoryCaptureKind.allCases)
    private func dismissKeepsExactlyOneFinalizedImageAndReleasesPendingBytes(kind: HistoryCaptureKind) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("fixture.bundle/History.noindex")
        let store = HistoryStore(root: root, clock: { Date(timeIntervalSince1970: 1234) })
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, fullScreenSource: source, clipboard: HistoryClipboard(),
            pendingByteLimit: source.bytes.count, history: store)
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(kind.command(id, maximumBytes: source.bytes.count)) == .pending(revision))
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
        #expect(await commands.execute(kind.command(CaptureID(), maximumBytes: source.bytes.count)) != .rejected(.pendingByteBudgetExceeded))
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
    @Test(arguments: [false, true], HistoryCaptureKind.allCases)
    private func thumbnailIsDisposableAndOnlyGeneratedAfterTheRowCommits(stopAfterRow: Bool, kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { point in
            if point == .rowCommitted {
                #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("thumbnails").path))
                if stopAfterRow { throw StopAfterCommit.stop }
            }
        })
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024, history: store)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(kind.command(revision.captureID, maximumBytes: 1024))
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
    @Test(arguments: HistoryCaptureKind.allCases)
    private func committedCaptureCannotBeDiscardedAfterCopyDeliveryFails(kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, fullScreenSource: source, clipboard: RetryHistoryClipboard(),
            pendingByteLimit: source.bytes.count, history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .failed(.unavailable))))
        let before = try await commands.historyEntries().get()
        let entry = try #require(before.first)

        // Discard applies to pending captures. Finalized deletion belongs to ticket 15.
        #expect(await commands.execute(.discard(revision.captureID)) == .rejected(.alreadyFinalized))
        #expect(try await commands.historyEntries().get() == before)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        #expect(await commands.execute(kind.command(CaptureID(), maximumBytes: source.bytes.count)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 2)))))
        #expect(try await commands.historyEntries().get() == before)
        #expect(await commands.image(for: revision) == nil)
    }

    @Test(arguments: [false, true], HistoryCaptureKind.allCases)
    private func copyRetryOrDismissAfterDeliveryFailureKeepsTheSameCommittedRevision(dismiss: Bool, kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), fullScreenSource: HistoryPixels(), clipboard: RetryHistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(kind.command(revision.captureID, maximumBytes: 1024))
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
    @Test(arguments: [false, true], HistoryCaptureKind.allCases)
    private func unknownMigrationsAreRefusedWithoutChangingAnyExistingFiles(wal: Bool, kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        try migrationFixture(at: root, wal: wal)
        let before = try diskSnapshot(root)
        let log = LocalDiagnosticLog()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            diagnostics: log, history: HistoryStore(root: root))
        let failure: HistoryFailure = wal ? .recoveryRequired : .unknownMigrations
        let reason: CommitUnavailableReason = wal ? .recoveryRequired : .unknownMigrations
        let code: DiagnosticErrorCode = wal ? .recoveryRequired : .unknownMigrations
        #expect(await commands.historyEntries() == .failure(failure))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(kind.command(revision.captureID, maximumBytes: 1024))
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
    @Test(arguments: HistoryCaptureKind.allCases)
    private func baselineFixtureReopensWithoutWritesAndSurvivesTheNextCommit(kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/History/history-v1.sql")
        try seedSQL(String(contentsOf: fixture, encoding: .utf8), at: root)
        let before = try diskSnapshot(root)
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root, clock: { Date(timeIntervalSince1970: 1002) }))
        let oldEntries = try await commands.historyEntries().get()
        #expect(oldEntries.count == 1) // deleting is a valid state but hidden
        #expect(oldEntries.first?.key == 41)
        #expect(oldEntries.first?.captureID.rawValue.uuidString == "11111111-1111-1111-1111-111111111111")
        #expect(try diskSnapshot(root) == before)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(kind.command(revision.captureID, maximumBytes: 1024))
        #expect(try diskSnapshot(root) == before)
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let after = try await commands.historyEntries().get()
        #expect(after.count == 2)
        #expect(after.first == oldEntries.first)
        #expect(after.last?.captureID == revision.captureID)
    }
}

private let historyFinalizationPoints: [HistoryCommitPoint] = [
    .pngStaged, .pngSynced, .recordStaged, .recordSynced, .imageRenamed, .recordRenamed,
    .directorySynced, .rowCommitted, .thumbnailCached
]

extension HistoryCommandsTests {
    @Test(arguments: historyFinalizationPoints, HistoryCaptureKind.allCases)
    private func eachCommitPointLeavesOnlyAuthorizedFilesAndNeverAPrematureRow(point: HistoryCommitPoint, kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { reached in
            if reached == point { throw StopAfterCommit.stop }
        })
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024, history: store)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        let id = revision.captureID.rawValue.uuidString
        _ = await commands.execute(kind.command(revision.captureID, maximumBytes: 1024))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let committed = point == .rowCommitted || point == .thumbnailCached
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision,
            committed ? .committed : .notCommitted(.recoveryRequired)))
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
        case .dragStaged, .dragPromiseWritten:
            // Dismiss never reaches a drag point. DragHandoffTests injects those faults.
            expected = []
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

    @Test(arguments: HistoryCaptureKind.allCases)
    private func discardedAndStaleCommandsCannotCreateStorage(kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.unknownCapture))
        _ = await commands.execute(kind.command(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(CaptureRevision(captureID: revision.captureID, number: 2))) == .rejected(.staleRevision))
        #expect(await commands.execute(.discard(revision.captureID)) == .discarded(revision.captureID))
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.discardedCapture))
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

private actor HistoryPermission: CapturePermissionSource {
    private var state: CapturePermissionState
    init(_ state: CapturePermissionState) { self.state = state }
    func capturePermission() -> CapturePermissionState { state }
    func revoke() { state = .revokedWhileRunning }
}

extension HistoryCommandsTests {
    @Test(arguments: [CapturePermissionState.notAsked, .denied, .revokedWhileRunning, .needsRelaunch], HistoryCaptureKind.allCases)
    private func missingPermissionCannotCreatePendingOrHistory(state: CapturePermissionState, kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = CaptureCommandLayer(permission: HistoryPermission(state), source: HistoryPixels(),
            fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: 1024)) == .permissionRequired(state))
        #expect(await commands.image(for: revision) == nil)
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.unknownCapture))
        #expect(await commands.execute(.copy(revision)) == .rejected(.unknownCapture))
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test(arguments: HistoryCaptureKind.allCases)
    private func revokedPermissionStillAllowsPendingCaptureToFinalize(kind: HistoryCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let permission = HistoryPermission(.granted)
        let commands = CaptureCommandLayer(permission: permission, source: HistoryPixels(),
            fullScreenSource: HistoryPixels(), clipboard: HistoryClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: 1024)) == .pending(revision))
        await permission.revoke()
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await commands.historyEntries().get().map(\.captureID) == [revision.captureID])
        #expect(await commands.image(for: revision) == nil)
    }
}

extension HistoryCommandsTests {
    @Test func deletingAHistoryItemUnlinksFilesAndRemovesTheRowWithoutTrash() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source,
            clipboard: HistoryClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let entry = try #require(try await commands.historyEntries().get().first)
        let image = root.appendingPathComponent(entry.imageLocation)
        #expect(FileManager.default.fileExists(atPath: image.path))
        #expect(await commands.execute(.deleteHistory(revision.captureID)) == .historyDeleted(revision.captureID))
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: image.path))
        #expect(!FileManager.default.fileExists(atPath: image.appendingPathExtension("Trash").path))
        #expect(await commands.execute(.deleteHistory(revision.captureID)) == .rejected(.unknownCapture))
    }

    @Test func historyItemsListNewestFirstWithoutFileLocations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source,
            clipboard: HistoryClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root))
        let first = try await finalize(commands, source: source)
        let second = try await finalize(commands, source: source)
        let items = try await commands.historyItems().get()
        #expect(items.map(\.captureID) == [second.captureID, first.captureID])
        #expect(items.allSatisfy { $0.width == 2 && $0.height == 1 })
        #expect(await commands.historyImage(second.captureID)?.pngData == source.bytes)
        #expect(await commands.execute(.done(second, try #require(DocumentEdits(scale: 1)))) == .rejected(.alreadyFinalized))
    }

    @Test func historyCopySaveAndDragReuseDeliveryAndLeaveTheOwnedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let folder = directory.appendingPathComponent("Exports")
        let source = HistoryPixels()
        let handoff = RecordingDragHandoff()
        let clipboard = HistoryClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, clipboard: clipboard,
            pendingByteLimit: source.bytes.count, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { folder }, historyRoot: root),
            drag: handoff, dragStaging: DragStagingLifetime(directory: root.appendingPathComponent("staging/drag")))
        let revision = try await finalize(commands, source: source)
        let owned = root.appendingPathComponent("images/\(revision.captureID.rawValue.uuidString).png")
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        guard case let .save(saved) = await commands.execute(.save(revision)), case let .saved(receipt) = saved.delivery else {
            Issue.record("History Save should succeed"); return
        }
        #expect(saved.commit == .committed)
        let exported = folder.appendingPathComponent(receipt.filename)
        #expect(exported.path.hasPrefix(folder.path))
        #expect(!exported.path.hasPrefix(root.path))
        #expect(try Data(contentsOf: exported) == source.bytes)
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision,
            commit: .committed, delivery: .copied)))
        #expect(await handoff.bytes() == [source.bytes])
        #expect(try Data(contentsOf: owned) == source.bytes)
        #expect(try await commands.historyItems().get().map(\.captureID) == [revision.captureID])
        #expect(await commands.execute(.copy(CaptureRevision(captureID: revision.captureID, number: 2))) ==
            .rejected(.staleRevision))
    }

    @Test func interruptedHistoryDeleteResumesOnTheNextLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        var commands: CaptureCommandLayer? = CaptureCommandLayer(permission: GrantedTestPermission(), source: source,
            clipboard: HistoryClipboard(), pendingByteLimit: source.bytes.count,
            history: HistoryStore(root: root, evictionPoint: { if $0 == .markedDeleting { throw HistoryDeleteStop.interrupted } }))
        let revision = try await finalize(commands!, source: source)
        #expect(await commands!.execute(.deleteHistory(revision.captureID)) == .rejected(.unknownCapture))
        commands = nil
        let reopened = CaptureCommandLayer(permission: GrantedTestPermission(), source: source,
            clipboard: HistoryClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root))
        _ = try await reopened.recoverHistory().get()
        #expect(try await reopened.historyItems().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(
            "images/\(revision.captureID.rawValue.uuidString).png").path))
    }

    private enum HistoryDeleteStop: Error { case interrupted }

    private func finalize(_ commands: CaptureCommandLayer, source: HistoryPixels) async throws -> CaptureRevision {
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        try #require(await commands.execute(.capture(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        try #require(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        return revision
    }
}

/// Stands in for the editor renderer: Done always yields a valid synthetic PNG History accepts.
private struct RenderedPNGCodec: BitmapCodec {
    func decode(_ pngData: Data) -> Bitmap? {
        Bitmap(width: 2, height: 1, pixels: Array(repeating: RGBAPixel(red: 255, green: 0, blue: 0, alpha: 255), count: 2))
    }
    func encode(_ bitmap: Bitmap) -> Data? { HistoryPixels().bytes }
}

/// The two ways a capture is already in History while its Thumbnail is still open.
private enum FinalizedWithOpenThumbnail: CaseIterable, Sendable {
    /// Done commits the rendered revision and leaves its Thumbnail open.
    case afterDone
    /// Copy commits, the clipboard write fails, and the Thumbnail stays open for Retry.
    case afterFailedCopy
}

extension HistoryCommandsTests {
    /// D10 (DA-4, story 91): deleting a History item whose Thumbnail is open closes that Thumbnail
    /// and deletes. Today the core refuses (`alreadyFinalized`) and the UI says "Delete failed. Try again.",
    /// which retrying can never fix.
    @Test(arguments: FinalizedWithOpenThumbnail.allCases)
    private func d10DeletingAHistoryItemClosesItsOpenThumbnailAndDeletes(state: FinalizedWithOpenThumbnail) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard: any ImageClipboard = state == .afterFailedCopy ? RetryHistoryClipboard() : HistoryClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: HistoryPixels(), clipboard: clipboard,
            pendingByteLimit: 1024, history: HistoryStore(root: root), codec: RenderedPNGCodec())
        let id = CaptureID()
        let original = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1024)) == .pending(original))
        let open: CaptureRevision
        switch state {
        case .afterDone:
            let edits = try #require(DocumentEdits(scale: 1))
            open = CaptureRevision(captureID: id, number: 2)
            #expect(await commands.execute(.done(original, edits)) == .edited(open, .committed))
        case .afterFailedCopy:
            open = original
            #expect(await commands.execute(.copy(original)) == .copy(CopyOutcome(revision: original,
                commit: .committed, delivery: .failed(.unavailable))))
        }
        let before = try await commands.historyEntries().get()
        #expect(before.map(\.captureID) == [id])
        #expect(await commands.thumbnails().map(\.revision) == [open])

        let deleted = await commands.execute(.deleteHistory(id))
        #expect(deleted == .historyDeleted(id), "D10: History Delete was refused while the Thumbnail is open")
        let after = try await commands.historyEntries().get()
        #expect(after.isEmpty, "D10: the History item survived Delete")
        let thumbnails = await commands.thumbnails().map(\.revision)
        #expect(thumbnails.isEmpty, "D10: the capture's Thumbnail stayed open after Delete")
        let held = await commands.image(for: open)
        #expect(held == nil, "D10: the deleted capture's pixels are still held")
    }
}

extension HistoryCommandsTests {
    /// D19 (story 97): after "Try Again" recovery succeeds, History row actions (open the image,
    /// Copy, Delete) work at once. Today recovery closes the writer and they fail until the next commit.
    @Test func d19HistoryRowActionsWorkRightAfterRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, clipboard: HistoryClipboard(),
            pendingByteLimit: 1024, history: HistoryStore(root: root))
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 1024)) == .pending(revision))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let recovered = await commands.recoverHistory()
        #expect((try? recovered.get()) != nil)
        let items = try await commands.historyItems().get()
        #expect(items.map(\.captureID) == [id])

        let image = await commands.historyImage(id)
        #expect(image?.pngData == source.bytes, "D19: the History image is unavailable after recovery")
        let copied = await commands.execute(.copy(revision))
        #expect(copied == .copy(CopyOutcome(revision: revision, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 1)))), "D19: History Copy fails after recovery")
        let deleted = await commands.execute(.deleteHistory(id))
        #expect(deleted == .historyDeleted(id), "D19: History Delete fails after recovery")
    }

    /// D19, same cause at launch: the launch sweep also leaves the writer closed, so a History row
    /// can't be opened, copied or deleted after relaunch until something new is committed.
    @Test func d19HistoryRowActionsWorkAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HistoryPixels()
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        do {
            let firstStore = HistoryStore(root: root)
            let first = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, clipboard: HistoryClipboard(),
                pendingByteLimit: 1024, history: firstStore)
            #expect(await first.execute(.capture(id, maximumBytes: 1024)) == .pending(revision))
            #expect(await first.execute(.dismiss(revision)) == .finalized(revision, .committed))
            let closed = await firstStore.close()
            #expect((try? closed.get()) != nil)
        }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, clipboard: HistoryClipboard(),
            pendingByteLimit: 1024, history: HistoryStore.launch(root: root))
        #expect(await commands.historyAvailability() == nil)
        let items = try await commands.historyItems().get()
        #expect(items.map(\.captureID) == [id])

        let image = await commands.historyImage(id)
        #expect(image?.pngData == source.bytes, "D19: the History image is unavailable after relaunch")
        let copied = await commands.execute(.copy(revision))
        #expect(copied == .copy(CopyOutcome(revision: revision, commit: .committed,
            delivery: .copied(ClipboardReceipt(changeCount: 1)))), "D19: History Copy fails after relaunch")
        let deleted = await commands.execute(.deleteHistory(id))
        #expect(deleted == .historyDeleted(id), "D19: History Delete fails after relaunch")
    }
}
