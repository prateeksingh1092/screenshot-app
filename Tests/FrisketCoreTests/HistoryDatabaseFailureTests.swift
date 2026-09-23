import Foundation
import Darwin
import FrisketCore
import Testing

private struct FailurePixels: CapturePixelSource {
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private struct FailureClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

private actor FailureDragHandoff: DragHandoff {
    private var recorded: [Data] = []
    func bytes() -> [Data] { recorded }
    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        recorded.append(image.pngData)
        try await events.promiseWriteReturned()
        await events.dragSessionEnded()
        return .copied
    }
}

private func snapshot(_ root: URL, locking: Bool) throws -> [String: Data] {
    let sqlite = root.appendingPathComponent("history.sqlite")
    if locking { #expect(chmod(sqlite.path, 0o644) == 0) }
    defer { if locking { #expect(chmod(sqlite.path, 0) == 0) } }
    return try diskSnapshot(root)
}

private func diskSnapshot(_ root: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    guard FileManager.default.fileExists(atPath: root.path) else { return result }
    let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
    while let file = items.nextObject() as? URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
        result[String(file.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: file)
    }
    return result
}

private enum HistoryOpenFailure: String, CaseIterable {
    case corrupt, unknownMigration, permissionDenied
}

@Suite struct HistoryDatabaseFailureTests {
    @Test(arguments: HistoryOpenFailure.allCases)
    private func openFailureDisablesHistoryWithoutWritingAndDeliveryContinues(kind: HistoryOpenFailure) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if kind == .permissionDenied {
                let sqlite = directory.appendingPathComponent("History.noindex/history.sqlite")
                _ = chmod(sqlite.path, 0o644)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        try prepareFailure(kind, root: root)
        let before = try snapshot(root, locking: kind == .permissionDenied)
        let source = FailurePixels()
        let handoff = FailureDragHandoff()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, clipboard: FailureClipboard(),
            pendingByteLimit: source.bytes.count, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { exports }, historyRoot: root),
            drag: handoff, dragStaging: DragStagingLifetime(directory: root.appendingPathComponent("staging/drag")))
        let availability = await commands.historyAvailability()
        #expect(availability != nil)
        if kind == .unknownMigration {
            #expect(availability == .unknownMigrations)
        }
        #expect(try snapshot(root, locking: kind == .permissionDenied) == before)
        #expect(await commands.recoverHistory().isFailure)
        #expect(try snapshot(root, locking: kind == .permissionDenied) == before)
        #expect(await commands.historyItems().isFailure)

        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .notCommitted(kind == .unknownMigration ? .unknownMigrations : .historyUnavailable),
            delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(try snapshot(root, locking: kind == .permissionDenied) == before)
        let next = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(next.captureID, maximumBytes: source.bytes.count)) == .pending(next))
        guard case let .save(saved) = await commands.execute(.save(next)), case .saved = saved.delivery else {
            Issue.record("Save should succeed"); return
        }
        #expect(saved.commit == .notCommitted(kind == .unknownMigration ? .unknownMigrations : .historyUnavailable))
        #expect(try snapshot(root, locking: kind == .permissionDenied) == before)
        let dragged = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(dragged.captureID, maximumBytes: source.bytes.count)) == .pending(dragged))
        #expect(await commands.execute(.drag(dragged, .copy)) == .drag(DragOutcome(revision: dragged,
            commit: .notCommitted(kind == .unknownMigration ? .unknownMigrations : .historyUnavailable),
            delivery: .copied)))
        #expect(await handoff.bytes() == [source.bytes])
        #expect(try snapshot(root, locking: kind == .permissionDenied) == before)
        let dismissed = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(dismissed.captureID, maximumBytes: source.bytes.count)) == .pending(dismissed))
        #expect(await commands.execute(.dismiss(dismissed)) == .finalized(dismissed,
            .notCommitted(kind == .unknownMigration ? .unknownMigrations : .historyUnavailable)))
        #expect(await commands.image(for: dismissed)?.pngData == source.bytes)
        #expect(try snapshot(root, locking: kind == .permissionDenied) == before)
    }

    @Test func retryAfterRepairReenablesHistoryWithoutDeletingTheEarlierDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sqlite = root.appendingPathComponent("history.sqlite")
        try Data("not a sqlite database".utf8).write(to: sqlite)
        let source = FailurePixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, clipboard: FailureClipboard(),
            pendingByteLimit: source.bytes.count, history: HistoryStore(root: root))
        #expect(await commands.historyAvailability() != nil)
        try FileManager.default.removeItem(at: sqlite)
        let recovered = try await commands.recoverHistory().get()
        #expect(recovered.removedMissingImages == 0)
        #expect(await commands.historyAvailability() == nil)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await commands.historyItems().get().map(\.captureID) == [revision.captureID])
    }
}

private extension HistoryDatabaseFailureTests {
    func prepareFailure(_ kind: HistoryOpenFailure, root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        switch kind {
        case .corrupt:
            try Data("not a sqlite database".utf8).write(to: root.appendingPathComponent("history.sqlite"))
        case .unknownMigration:
            try seedUnknownMigration(at: root)
        case .permissionDenied:
            try seedUnknownMigration(at: root, identifier: "history-v1")
            #expect(chmod(root.appendingPathComponent("history.sqlite").path, 0) == 0)
        }
    }

    func seedUnknownMigration(at root: URL, identifier: String = "future-history-v2") throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
            import sqlite3, sys
            db = sqlite3.connect(sys.argv[1])
            db.execute('CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY)')
            db.execute('INSERT INTO grdb_migrations VALUES (?)', (sys.argv[2],))
            db.commit()
            db.close()
            """, root.appendingPathComponent("history.sqlite").path, identifier]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
