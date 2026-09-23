import Foundation
import Darwin
import FrisketCore
import Testing

private struct RecoveryPixels: CapturePixelSource {
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private struct RecoveryClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

private enum RecoveryStop: Error { case stop }

private func recoveryCommands(_ store: HistoryStore) -> CaptureCommandLayer {
    CaptureCommandLayer(permission: GrantedTestPermission(), source: RecoveryPixels(), clipboard: RecoveryClipboard(), pendingByteLimit: 1024, history: store)
}

private func interruptedCommit(at root: URL, point: HistoryCommitPoint, id: CaptureID) async throws {
    let store = HistoryStore(root: root, clock: { Date(timeIntervalSince1970: 1234) }, commitPoint: {
        if $0 == point { throw RecoveryStop.stop }
    })
    let commands = recoveryCommands(store)
    _ = await commands.execute(.capture(id, maximumBytes: 1024))
    let result = await commands.execute(.dismiss(CaptureRevision(captureID: id, number: 1)))
    #expect(result == .finalized(CaptureRevision(captureID: id, number: 1), (point == .rowCommitted || point == .thumbnailCached) ? .committed : .notCommitted(.recoveryRequired)))
    try await store.close().get()
}

@Suite struct HistoryRecoveryTests {
    @Test func launchAdoptsAnAuthorizedRowlessImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try await interruptedCommit(at: root, point: .recordRenamed, id: id)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("images/\(id.rawValue.uuidString).finalization.json").path))
        let commands = recoveryCommands(HistoryStore(root: root))
        _ = try await commands.recoverHistory().get()
        let entries = try await commands.historyEntries().get()
        #expect(entries.map(\.captureID) == [id])
        #expect(entries.first?.width == 2)
        #expect(entries.first?.height == 1)
        #expect(entries.first?.finalizedAt == Date(timeIntervalSince1970: 1234))
        #expect(try Data(contentsOf: root.appendingPathComponent(try #require(entries.first).imageLocation)) == RecoveryPixels().bytes)
    }
}

// Explicit cases are intentional: additions to the production enum must extend
// these expectations and the independent subprocess tier.
private let tierOnePoints: [HistoryCommitPoint] = [
    .pngStaged, .pngSynced, .recordStaged, .recordSynced, .imageRenamed,
    .recordRenamed, .directorySynced, .rowCommitted, .thumbnailCached
]

private func recoverySnapshot(_ root: URL) throws -> [String: Data] {
    var files: [String: Data] = [:]
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return files }
    for case let relative as String in enumerator {
        let file = root.appendingPathComponent(relative)
        if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files[relative] = try Data(contentsOf: file)
        }
    }
    return files
}

private func verifyRecoveredRoot(_ root: URL, point: HistoryCommitPoint, id: CaptureID) async throws {
    let commands = recoveryCommands(HistoryStore(root: root))
    let first = try await commands.recoverHistory().get()
    let entries = try await commands.historyEntries().get()
    let survives = [.recordRenamed, .directorySynced, .rowCommitted, .thumbnailCached].contains(point)
    #expect(entries.map(\.captureID) == (survives ? [id] : []))
    let snapshot = try recoverySnapshot(root)
    #expect(first.logicalBytes == snapshot.values.reduce(Int64(0)) { $0 + Int64($1.count) })
    #expect(!snapshot.keys.contains { $0.hasPrefix("staging/") })
    var expectedFiles = Set<String>()
    for entry in entries {
        expectedFiles.insert(entry.imageLocation)
        expectedFiles.insert(entry.recordLocation)
        #expect(snapshot[entry.imageLocation] == RecoveryPixels().bytes)
        #expect(entry.imageBytes == Int64(try #require(snapshot[entry.imageLocation]).count))
        #expect(entry.recordBytes == Int64(try #require(snapshot[entry.recordLocation]).count))
        if let thumbnail = entry.thumbnailLocation {
            expectedFiles.insert(thumbnail)
            #expect(entry.thumbnailBytes == Int64(try #require(snapshot[thumbnail]).count))
        } else { #expect(entry.thumbnailBytes == 0) }
    }
    #expect(Set(snapshot.keys.filter { $0.hasPrefix("images/") || $0.hasPrefix("thumbnails/") }) == expectedFiles)
    let second = try await commands.recoverHistory().get()
    #expect(second.logicalBytes == first.logicalBytes)
    #expect(try await commands.historyEntries().get() == entries)
    let after = try recoverySnapshot(root)
    #expect(Set(after.keys) == Set(snapshot.keys))
    for name in snapshot.keys { #expect(after[name] == snapshot[name], Comment(rawValue: name)) }
}

extension HistoryRecoveryTests {
    @Test(arguments: tierOnePoints)
    func tierOneRecoversEveryInterruptedCommitTwice(point: HistoryCommitPoint) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try await interruptedCommit(at: root, point: point, id: id)
        try await verifyRecoveredRoot(root, point: point, id: id)
    }
}

extension HistoryRecoveryTests {
    @Test func anotherInstanceCannotRecoverReadOrCommitWhileTheRootIsOwned() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = recoveryCommands(HistoryStore(root: root, commitPoint: { if $0 == .recordRenamed { throw RecoveryStop.stop } }))
        let id = CaptureID()
        _ = await owner.execute(.capture(id, maximumBytes: 1024))
        _ = await owner.execute(.dismiss(CaptureRevision(captureID: id, number: 1)))
        let before = try recoverySnapshot(root)
        let contender = recoveryCommands(HistoryStore(root: root))
        #expect(await contender.recoverHistory() == .failure(.rootLocked))
        #expect(await contender.historyEntries() == .failure(.rootLocked))
        let second = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await contender.execute(.capture(second.captureID, maximumBytes: 1024))
        #expect(await contender.execute(.copy(second)) == .copy(CopyOutcome(revision: second,
            commit: .notCommitted(.historyUnavailable), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(try recoverySnapshot(root) == before)
        _ = try await owner.recoverHistory().get()
        #expect(try await owner.historyEntries().get().map(\.captureID) == [id])
    }
}

private let tierTwoPoints: [HistoryCommitPoint] = [
    .pngStaged, .pngSynced, .recordStaged, .recordSynced, .imageRenamed,
    .recordRenamed, .directorySynced, .rowCommitted, .thumbnailCached
]

private func killAtCommitPoint(_ point: HistoryCommitPoint, root: URL, id: CaptureID) throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let helper = repository.appendingPathComponent(".build/debug/HistoryCrashHelper")
    try #require(FileManager.default.isExecutableFile(atPath: helper.path))
    let process = Process()
    process.executableURL = helper
    process.arguments = [root.path, point.rawValue, id.rawValue.uuidString]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationReason == .uncaughtSignal)
    #expect(process.terminationStatus == SIGKILL)
}

extension HistoryRecoveryTests {
    @Test func bothCrashTiersCoverTheClosedCommitPointList() {
        // Drag staging points are covered by DragHandoffTests, not History finalize.
        let all = Set(HistoryCommitPoint.allCases).subtracting([.dragStaged, .dragPromiseWritten])
        #expect(Set(tierOnePoints) == all)
        #expect(Set(tierTwoPoints) == all)
        #expect(tierOnePoints.count == all.count)
        #expect(tierTwoPoints.count == all.count)
    }

    @Test(arguments: tierTwoPoints)
    func tierTwoRecoversAfterProcessDeathAtEveryCommitPoint(point: HistoryCommitPoint) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try killAtCommitPoint(point, root: root, id: id)
        try await verifyRecoveredRoot(root, point: point, id: id)
    }
}

private func committedEntries(_ root: URL, ids: [CaptureID]) async throws -> [HistoryEntry] {
    let store = HistoryStore(root: root)
    let commands = recoveryCommands(store)
    for id in ids {
        let revision = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
    }
    let entries = try await commands.historyEntries().get()
    try await store.close().get()
    return entries
}

private func recoverySQL(_ sql: String, root: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [root.appendingPathComponent("history.sqlite").path, sql]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
}

extension HistoryRecoveryTests {
    @Test func recoveryFinishesDeletionsRemovesMissingImagesAndReconcilesAllSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = [CaptureID(), CaptureID(), CaptureID()]
        let before = try await committedEntries(root, ids: ids)
        try FileManager.default.removeItem(at: root.appendingPathComponent(before[0].imageLocation))
        try recoverySQL("UPDATE history SET state = 'deleting' WHERE id = \(before[1].key); UPDATE history SET image_bytes = 1, record_bytes = 1, thumbnail_bytes = 1 WHERE id = \(before[2].key)", root: root)
        let orphan = "thumbnails/\(UUID().uuidString).png"
        try RecoveryPixels().bytes.write(to: root.appendingPathComponent(orphan))
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("staging/interrupted"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("archives"), withIntermediateDirectories: false)
        try Data(repeating: 42, count: 117).write(to: root.appendingPathComponent("archives/recovery.sqlite"))
        let log = LocalDiagnosticLog()
        let commands = recoveryCommands(HistoryStore(root: root, diagnostics: log))
        let report = try await commands.recoverHistory().get()
        let after = try await commands.historyEntries().get()
        #expect(after.map(\.captureID) == [ids[2]])
        let survivor = try #require(after.first)
        let snapshot = try recoverySnapshot(root)
        #expect(survivor.imageBytes == 70)
        #expect(survivor.recordBytes == Int64(try #require(snapshot[survivor.recordLocation]).count))
        let thumbnailLocation = try #require(survivor.thumbnailLocation)
        #expect(survivor.thumbnailBytes == Int64(try #require(snapshot[thumbnailLocation]).count))
        #expect(report.removedMissingImages == 1)
        #expect(report.logicalBytes == snapshot.values.reduce(Int64(0)) { $0 + Int64($1.count) })
        #expect(snapshot["archives/recovery.sqlite"]?.count == 117)
        for entry in before.prefix(2) {
            #expect(snapshot[entry.imageLocation] == nil)
            #expect(snapshot[entry.recordLocation] == nil)
            #expect(snapshot[try #require(entry.thumbnailLocation)] == nil)
        }
        #expect(snapshot[orphan] == nil)
        #expect(snapshot["staging/interrupted"] == nil)
        #expect(await log.entries().map(\.event) == [
            DiagnosticEvent(name: .historyImageMissing, operation: .launchRecovery,
                error: DiagnosticError(domain: .history, code: .missingHistoryImage)),
            DiagnosticEvent(name: .historyRecovered, operation: .launchRecovery)
        ])
        _ = try await commands.recoverHistory().get()
        #expect(try recoverySnapshot(root) == snapshot)
        #expect(try await commands.historyEntries().get() == after)
    }
}

extension HistoryRecoveryTests {
    @Test(arguments: ["marker", "identifier", "dimensions", "revision", "size", "json", "png", "missingRecord", "missingImage", "fileName", "compressedPixels"])
    func rowlessImagesRequireAValidMatchingFinalizationRecord(damage: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try await interruptedCommit(at: root, point: .recordRenamed, id: id)
        let image = root.appendingPathComponent("images/\(id.rawValue.uuidString).png")
        let record = root.appendingPathComponent("images/\(id.rawValue.uuidString).finalization.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
        switch damage {
        case "marker": json["marker"] = "not-finalized"
        case "identifier": json["captureIdentifier"] = UUID().uuidString
        case "dimensions": json["width"] = 3
        case "revision": json["revision"] = 0
        case "size": json["imageBytes"] = 1
        default: break
        }
        try JSONSerialization.data(withJSONObject: json).write(to: record)
        switch damage {
        case "json": try Data("invalid".utf8).write(to: record)
        case "png": try Data(repeating: 0, count: 70).write(to: image)
        case "compressedPixels":
            var bytes = RecoveryPixels().bytes
            bytes[41] = 0 // Keep the PNG header/dimensions; invalidate the compressed pixel stream.
            try bytes.write(to: image)
        case "missingRecord": try FileManager.default.removeItem(at: record)
        case "missingImage": try FileManager.default.removeItem(at: image)
        case "fileName": try FileManager.default.moveItem(at: image, to: root.appendingPathComponent("images/not-an-identifier.png"))
        default: break
        }
        let commands = recoveryCommands(HistoryStore(root: root))
        _ = try await commands.recoverHistory().get()
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: image.path))
        #expect(!FileManager.default.fileExists(atPath: record.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("images").path).isEmpty)
        let snapshot = try recoverySnapshot(root)
        _ = try await commands.recoverHistory().get()
        #expect(try recoverySnapshot(root) == snapshot)
    }

    @Test func recoveryRefusesASymlinkedImageDirectoryWithoutTouchingItsTarget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        _ = try await committedEntries(root, ids: [CaptureID()])
        let external = directory.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: root.appendingPathComponent("images"), to: external)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("images"), withDestinationURL: external)
        let before = try recoverySnapshot(external)
        let commands = recoveryCommands(HistoryStore(root: root))
        #expect(await commands.recoverHistory() == .failure(.unavailable))
        #expect(try recoverySnapshot(external) == before)
    }
}

extension HistoryRecoveryTests {
    @Test func recoveryDoesNotAdoptAnImageSymlinkOutsideTheRoot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let id = CaptureID()
        try await interruptedCommit(at: root, point: .recordRenamed, id: id)
        let image = root.appendingPathComponent("images/\(id.rawValue.uuidString).png")
        let outside = directory.appendingPathComponent("outside.png")
        try FileManager.default.moveItem(at: image, to: outside)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
        let commands = recoveryCommands(HistoryStore(root: root))
        #expect(await commands.recoverHistory() == .failure(.unavailable))
        #expect(try Data(contentsOf: outside) == RecoveryPixels().bytes)
    }
}

extension HistoryRecoveryTests {
    @Test func movedRootKeepsHistoryAndAcceptsANewCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldRoot = directory.appendingPathComponent("old-home/History.noindex")
        let newRoot = directory.appendingPathComponent("restored-home/History.noindex")
        let id = CaptureID()
        let before = try await committedEntries(oldRoot, ids: [id])
        try FileManager.default.createDirectory(at: newRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: oldRoot, to: newRoot)
        let commands = recoveryCommands(HistoryStore(root: newRoot))
        _ = try await commands.recoverHistory().get()
        #expect(try await commands.historyEntries().get() == before)
        for entry in before {
            for location in [entry.imageLocation, entry.recordLocation, entry.thumbnailLocation].compactMap({ $0 }) {
                #expect(!location.hasPrefix("/") && !location.contains(".."))
                #expect(FileManager.default.fileExists(atPath: newRoot.appendingPathComponent(location).path))
            }
        }
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await commands.historyEntries().get().count == 2)
        #expect(!FileManager.default.fileExists(atPath: oldRoot.path))
    }

    @Test func aMissingDisposableThumbnailDoesNotLoseHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try #require(try await committedEntries(root, ids: [CaptureID()]).first)
        try FileManager.default.removeItem(at: root.appendingPathComponent(try #require(entry.thumbnailLocation)))
        let commands = recoveryCommands(HistoryStore(root: root))
        _ = try await commands.recoverHistory().get()
        let after = try #require(try await commands.historyEntries().get().first)
        #expect(after.captureID == entry.captureID)
        #expect(after.thumbnailLocation == nil && after.thumbnailBytes == 0)
        #expect(try Data(contentsOf: root.appendingPathComponent(after.imageLocation)) == RecoveryPixels().bytes)
        let snapshot = try recoverySnapshot(root)
        _ = try await commands.recoverHistory().get()
        #expect(try recoverySnapshot(root) == snapshot)
    }

    @Test(arguments: [false, true])
    func unknownSchemasIncludingOutstandingWALAreRefusedWithoutChangingFiles(wal: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
            import os, sqlite3, sys
            db = sqlite3.connect(sys.argv[1])
            db.execute('PRAGMA journal_mode=' + sys.argv[2])
            db.execute('CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY)')
            db.execute("INSERT INTO grdb_migrations VALUES ('future-history-v2')")
            db.commit()
            if sys.argv[2] == 'WAL':
                os.unlink(sys.argv[1] + '-shm')
                os._exit(0)
            db.close()
            """, root.appendingPathComponent("history.sqlite").path, wal ? "WAL" : "DELETE"]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        let before = try recoverySnapshot(root)
        let log = LocalDiagnosticLog()
        let commands = recoveryCommands(HistoryStore(root: root, diagnostics: log))
        #expect(await commands.recoverHistory() == .failure(.unknownMigrations))
        #expect(await commands.historyEntries() == .failure(.unknownMigrations))
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .notCommitted(.unknownMigrations), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(try recoverySnapshot(root) == before)
        #expect(await log.entries().map(\.event) == [DiagnosticEvent(name: .historyRecoveryFailed, operation: .launchRecovery,
            error: DiagnosticError(domain: .history, code: .unknownMigrations))])
    }
}

extension HistoryRecoveryTests {
    @Test func launchRunsRecoveryOnceBeforeHistoryIsServed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try killAtCommitPoint(.rowCommitted, root: root, id: id)
        let log = LocalDiagnosticLog()
        let commands = recoveryCommands(HistoryStore.launch(root: root, diagnostics: log))
        #expect(try await commands.historyEntries().get().map(\.captureID) == [id])
        #expect(try await commands.historyEntries().get().map(\.captureID) == [id])
        #expect(await log.entries().map(\.event) == [DiagnosticEvent(name: .historyRecovered, operation: .launchRecovery)])
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await commands.historyEntries().get().count == 2)
        #expect(await log.entries().count == 1)
    }

    @Test func launchAndPendingCaptureCreateNothingInANewRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = recoveryCommands(HistoryStore.launch(root: root))
        #expect(try await commands.historyEntries().get().isEmpty)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 1024)) == .pending(CaptureRevision(captureID: id, number: 1)))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await commands.execute(.discard(id)) == .discarded(id))
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

extension HistoryRecoveryTests {
    @Test func aSeparateProcessHoldsTheLockUntilItDies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let child = Process()
        child.executableURL = repository.appendingPathComponent(".build/debug/HistoryCrashHelper")
        let id = CaptureID()
        child.arguments = [root.path, HistoryCommitPoint.recordRenamed.rawValue, id.rawValue.uuidString, "hold"]
        let ready = Pipe()
        let release = Pipe()
        child.standardOutput = ready
        child.standardInput = release
        child.standardError = FileHandle.nullDevice
        try child.run()
        try ready.fileHandleForWriting.close()
        defer {
            try? release.fileHandleForWriting.close()
            if child.isRunning { child.waitUntilExit() }
        }
        try #require(ready.fileHandleForReading.readData(ofLength: 1) == Data([1]))
        let before = try recoverySnapshot(root)
        let commands = recoveryCommands(HistoryStore(root: root))
        #expect(await commands.recoverHistory() == .failure(.rootLocked))
        #expect(try recoverySnapshot(root) == before)
        try release.fileHandleForWriting.close()
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
        _ = try await commands.recoverHistory().get()
        #expect(try await commands.historyEntries().get().map(\.captureID) == [id])
    }
}

extension HistoryRecoveryTests {
    @Test func closingAStoreReleasesOwnershipAndPreventsItFromReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let commands = recoveryCommands(store)
        let id = CaptureID()
        _ = await commands.execute(.capture(id, maximumBytes: 1024))
        _ = await commands.execute(.dismiss(CaptureRevision(captureID: id, number: 1)))
        try await store.close().get()
        #expect(await commands.historyEntries() == .failure(.unavailable))
        let next = recoveryCommands(HistoryStore(root: root))
        _ = try await next.recoverHistory().get()
        #expect(try await next.historyEntries().get().map(\.captureID) == [id])
    }
}
