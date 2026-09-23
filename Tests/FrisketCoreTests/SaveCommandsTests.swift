import Foundation
import FrisketCore
import Testing

private struct SavePixels: CapturePixelSource {
    // Synthetic 2 x 1 opaque red PNG, never screen content.
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private struct UnusedClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        Issue.record("Save must not use the clipboard")
        return .failure(.unavailable)
    }
}

@Suite struct SaveCommandsTests {
    @Test func saveCreatesAnIndependentPNGAndCommitsHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let folder = directory.appendingPathComponent("Pictures/Frisket")
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root), exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: 1024)) == .pending(revision))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        guard case let .save(outcome) = await commands.execute(.save(revision)),
              case let .saved(receipt) = outcome.delivery else { Issue.record("Save should succeed"); return }
        #expect(outcome.revision == revision)
        #expect(outcome.commit == .committed)
        let entry = try #require(try await commands.historyEntries().get().first)
        let exported = folder.appendingPathComponent(receipt.filename)
        #expect(try Data(contentsOf: exported) == SavePixels().bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: exported.path)[.posixPermissions] as? Int == 0o644)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [receipt.filename])
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == SavePixels().bytes)
        #expect(await commands.image(for: revision) == nil)
        #expect(await commands.execute(.save(revision)) == .rejected(.alreadyDelivered))
        // Simulate removal of all History files: the external copy remains intact.
        try FileManager.default.removeItem(at: root.appendingPathComponent(entry.imageLocation))
        #expect(try Data(contentsOf: exported) == SavePixels().bytes)
    }
}

extension SaveCommandsTests {
    @Test func failedSaveRetainsHistoryAndRetriesTheSameRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("History.noindex")
        let folder = directory.appendingPathComponent("export-folder")
        // A regular file blocks directory creation until the user repairs the destination.
        try Data("occupied".utf8).write(to: folder)
        let diagnostics = LocalDiagnosticLog()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: SavePixels().bytes.count,
            diagnostics: diagnostics, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: SavePixels().bytes.count))
        guard case let .save(failed) = await commands.execute(.save(revision)), case .failed = failed.delivery else {
            Issue.record("Blocked export must fail"); return
        }
        #expect(failed.commit == .committed)
        let before = try await commands.historyEntries().get()
        #expect(before.count == 1)
        #expect(await commands.image(for: revision)?.pngData == SavePixels().bytes)
        #expect(await commands.execute(.discard(revision.captureID)) == .rejected(.alreadyFinalized))
        #expect(await commands.execute(.save(revision)) == .rejected(.retryRequired))
        #expect(await commands.execute(.retryCopy(revision)) == .rejected(.retryNotAvailable))
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: SavePixels().bytes.count)) == .rejected(.pendingByteBudgetExceeded))
        try FileManager.default.removeItem(at: folder)
        guard case let .save(retried) = await commands.execute(.retrySave(revision)), case let .saved(receipt) = retried.delivery else {
            Issue.record("Retry Save should succeed"); return
        }
        #expect(retried.revision == revision)
        #expect(retried.commit == .committed)
        #expect(try await commands.historyEntries().get() == before)
        #expect(try Data(contentsOf: folder.appendingPathComponent(receipt.filename)) == SavePixels().bytes)
        #expect(await commands.image(for: revision) == nil)
        #expect(await commands.execute(.retrySave(revision)) == .rejected(.alreadyDelivered))
        let events = await diagnostics.entries().map(\.event)
        #expect(events.contains { $0.name == .deliveryFailed && $0.operation == .save && $0.error?.domain == .fileExport })
        #expect(events.contains { $0.name == .deliverySucceeded && $0.operation == .retrySave && $0.error == nil })
        let log = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
        #expect(!log.contains(directory.path) && !log.contains(receipt.filename))
    }
}

extension SaveCommandsTests {
    @Test(arguments: ["root", "descendant", "symlink", "caseAlias"])
    func saveRefusesHistoryDestinations(kind: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let folder: URL
        switch kind {
        case "descendant": folder = root.appendingPathComponent("exports/new")
        case "symlink": folder = alias.appendingPathComponent("exports")
        case "caseAlias":
            if try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames == true { return }
            folder = directory.appendingPathComponent("HISTORY.NOINDEX/exports")
        default: folder = root
        }
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root), exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.save(revision)) == .save(SaveOutcome(revision: revision, commit: .committed, delivery: .failed(.insideHistory))))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("exports").path))
        #expect(try await commands.historyEntries().get().count == 1)
    }
}

extension SaveCommandsTests {
    @Test func exportFilenameNeverOverwritesExistingFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let folder = directory.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = "Frisket-11111111-2222-3333-4444-555555555555-r1.png"
        let second = "Frisket-11111111-2222-3333-4444-555555555555-r1-2.png"
        try Data("existing export".utf8).write(to: folder.appendingPathComponent(existing))
        // Even an existing symlink must count as a collision, without touching its target.
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(second), withDestinationURL: folder.appendingPathComponent(existing))
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root), exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.save(revision)) == .save(SaveOutcome(revision: revision, commit: .committed,
            delivery: .saved(ExportReceipt(filename: "Frisket-11111111-2222-3333-4444-555555555555-r1-3.png")))))
        #expect(try Data(contentsOf: folder.appendingPathComponent(existing)) == Data("existing export".utf8))
        #expect(try Data(contentsOf: folder.appendingPathComponent(second)) == Data("existing export".utf8))
        #expect(try Data(contentsOf: folder.appendingPathComponent("Frisket-11111111-2222-3333-4444-555555555555-r1-3.png")) == SavePixels().bytes)
    }
}

extension SaveCommandsTests {
    @Test(arguments: [false, true])
    func historyFailureDoesNotBlockSaveOrRepeatOnRetry(retry: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("History.noindex")
        let folder = directory.appendingPathComponent("Exports")
        try Data("blocked history".utf8).write(to: root)
        if retry { try Data("blocked export".utf8).write(to: folder) }
        let diagnostics = LocalDiagnosticLog()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            diagnostics: diagnostics, history: HistoryStore(root: root),
            exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        guard case var .save(outcome) = await commands.execute(.save(revision)) else { Issue.record("Expected Save"); return }
        #expect(outcome.commit == .notCommitted(.historyUnavailable))
        if retry {
            guard case .failed = outcome.delivery else { Issue.record("Expected failed export"); return }
            try FileManager.default.removeItem(at: folder)
            try FileManager.default.removeItem(at: root)
            guard case let .save(retried) = await commands.execute(.retrySave(revision)) else { Issue.record("Expected retry"); return }
            outcome = retried
            #expect(!FileManager.default.fileExists(atPath: root.path))
        }
        #expect(outcome.commit == .notCommitted(.historyUnavailable))
        #expect(outcome.revision == revision)
        guard case let .saved(receipt) = outcome.delivery else { Issue.record("Expected export despite History failure"); return }
        #expect(try Data(contentsOf: folder.appendingPathComponent(receipt.filename)) == SavePixels().bytes)
        #expect(await commands.image(for: revision) == nil)
        #expect(await diagnostics.entries().last?.event.error == DiagnosticError(domain: .history, code: .unavailable))
    }

    @Test func staleUnknownPrematureRetryAndDiscardedSavesHaveNoDiskSideEffects() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let folder = directory.appendingPathComponent("Exports")
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root), exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.save(revision)) == .rejected(.unknownCapture))
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.save(CaptureRevision(captureID: revision.captureID, number: 2))) == .rejected(.staleRevision))
        #expect(await commands.execute(.retrySave(revision)) == .rejected(.retryNotAvailable))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        _ = await commands.execute(.discard(revision.captureID))
        #expect(await commands.execute(.save(revision)) == .rejected(.discardedCapture))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func saveRefusesAnExistingUnwritableDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = directory.appendingPathComponent("Exports")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        let root = directory.appendingPathComponent("History.noindex")
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root), exporter: PNGFileExporter(folder: { folder }, historyRoot: root))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.save(revision)) == .save(SaveOutcome(revision: revision, commit: .committed, delivery: .failed(.unwritable))))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}

private actor HeldExport: CaptureExport {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Result<ExportReceipt, ExportFailure>, Never>?

    func export(_ request: AuthorizedFinalization) async -> Result<ExportReceipt, ExportFailure> {
        entered = true
        waiter?.resume()
        waiter = nil
        return await withCheckedContinuation { completion = $0 }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { waiter = $0 } }
    }
    func fail() { completion?.resume(returning: .failure(.unavailable)); completion = nil }
}

extension SaveCommandsTests {
    @Test func inFlightSaveGatesEveryExitAndFailedDeliveryCanBeDismissed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = HeldExport()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: SavePixels(), clipboard: UnusedClipboard(), pendingByteLimit: 1024,
            history: HistoryStore(root: root), exporter: exporter)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        let saving = Task { await commands.execute(.save(revision)) }
        await exporter.waitUntilEntered()
        // History is finalized before the delivery adapter is allowed to run.
        let before = try await commands.historyEntries().get()
        #expect(before.count == 1)
        for command: CaptureCommand in [.save(revision), .retrySave(revision), .copy(revision), .dismiss(revision), .discard(revision.captureID)] {
            #expect(await commands.execute(command) == .rejected(.commandInProgress))
        }
        await exporter.fail()
        #expect(await saving.value == .save(SaveOutcome(revision: revision, commit: .committed, delivery: .failed(.unavailable))))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await commands.historyEntries().get() == before)
        #expect(await commands.image(for: revision) == nil)
    }
}
