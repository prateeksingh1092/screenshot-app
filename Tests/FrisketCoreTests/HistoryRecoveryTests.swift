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

private func recoveryCommands(_ store: HistoryStore) -> CaptureLifecycleCoordinator {
    CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: RecoveryPixels(), clipboard: RecoveryClipboard(), pendingByteLimit: 1024, history: store)
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
    /// A crash between the atomic PNG write and the row leaves a UUID-named PNG and no row.
    /// The launch sweep adopts it: its size and dimensions come from the file, its date from the
    /// file's modification date, and its revision is 1 (DA-4; ticket 78).
    @Test func launchAdoptsAnOrphanPNG() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try await interruptedCommit(at: root, point: .imageWritten, id: id)
        let image = root.appendingPathComponent("images/\(id.rawValue.uuidString).png")
        let written = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: image.path)
        let history = HistoryStore(root: root)
        _ = try await history.recover().get()
        let entries = try await history.entries().get()
        let entry = try #require(entries.first)
        #expect(entries.map(\.captureID) == [id])
        #expect(entry.revision == 1)
        #expect(entry.width == 2 && entry.height == 1)
        #expect(entry.imageBytes == Int64(RecoveryPixels().bytes.count))
        #expect(entry.finalizedAt == written)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == RecoveryPixels().bytes)
        #expect(try await history.finalizedImage(id).get().pngData == RecoveryPixels().bytes)
    }

    /// The other half of the contract: a row whose image is gone is dropped, with a diagnostic,
    /// and the row actions no longer offer it.
    @Test func launchDropsARowWhoseImageIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = [CaptureID(), CaptureID()]
        let before = try await committedEntries(root, ids: ids)
        try FileManager.default.removeItem(at: root.appendingPathComponent(before[0].imageLocation))
        let log = LocalDiagnosticLog()
        let history = HistoryStore(root: root, diagnostics: log)
        let report = try await history.recover().get()
        #expect(report.removedMissingImages == 1)
        #expect(try await history.entries().get().map(\.captureID) == [ids[1]])
        #expect((try? await history.finalizedImage(ids[0]).get()) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(try #require(before[0].thumbnailLocation)).path))
        #expect(await log.entries().map(\.event) == [
            DiagnosticEvent(name: .historyImageMissing, operation: .launchRecovery,
                error: DiagnosticError(domain: .history, code: .missingHistoryImage)),
            DiagnosticEvent(name: .historyRecovered, operation: .launchRecovery)
        ])
    }
}

// Explicit cases are intentional: additions to the production enum must extend
// these expectations and the independent subprocess tier.
private let tierOnePoints: [HistoryCommitPoint] = [.imageStaged, .imageWritten, .rowCommitted, .thumbnailCached]

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
    let history = HistoryStore(root: root)
    let first = try await history.recover().get()
    let entries = try await history.entries().get()
    // Only a crash before the rename loses the write; from the rename on, the capture is kept.
    let survives = point != .imageStaged
    #expect(entries.map(\.captureID) == (survives ? [id] : []))
    let snapshot = try recoverySnapshot(root)
    #expect(first.logicalBytes == snapshot.values.reduce(Int64(0)) { $0 + Int64($1.count) })
    #expect(!snapshot.keys.contains { $0.hasPrefix("staging/") || $0.hasSuffix(".partial") || $0.hasSuffix(".json") })
    var expectedFiles = Set<String>()
    for entry in entries {
        expectedFiles.insert(entry.imageLocation)
        #expect(snapshot[entry.imageLocation] == RecoveryPixels().bytes)
        #expect(entry.imageBytes == Int64(try #require(snapshot[entry.imageLocation]).count))
        if let thumbnail = entry.thumbnailLocation {
            expectedFiles.insert(thumbnail)
            #expect(entry.thumbnailBytes == Int64(try #require(snapshot[thumbnail]).count))
        } else { #expect(entry.thumbnailBytes == 0) }
    }
    #expect(Set(snapshot.keys.filter { $0.hasPrefix("images/") || $0.hasPrefix("thumbnails/") }) == expectedFiles)
    let second = try await history.recover().get()
    #expect(second.logicalBytes == first.logicalBytes)
    #expect(try await history.entries().get() == entries)
    let after = try recoverySnapshot(root)
    #expect(Set(after.keys) == Set(snapshot.keys))
    for name in snapshot.keys { #expect(after[name] == snapshot[name], Comment(rawValue: name)) }
    // History usage counts the adopted image once (D24's double count is gone).
    let usage = try await history.maintain(limits: HistoryLimits(retentionDays: 40_000)).get().usageBytes
    var disk: Int64 = 0
    for entry in entries {
        disk += Int64(try #require(snapshot[entry.imageLocation]).count)
        if let thumbnail = entry.thumbnailLocation { disk += Int64(try #require(snapshot[thumbnail]).count) }
    }
    for suffix in ["", "-wal", "-shm"] {
        let file = root.appendingPathComponent("history.sqlite" + suffix)
        if FileManager.default.fileExists(atPath: file.path) { disk += Int64(try Data(contentsOf: file).count) }
    }
    #expect(usage == disk)
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

private let tierTwoPoints: [HistoryCommitPoint] = [.imageStaged, .imageWritten, .rowCommitted, .thumbnailCached]

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
        let all = Set(HistoryCommitPoint.allCases)
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
    let entries = try await store.entries().get()
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
    @Test func recoveryRemovesMissingImagesStrayFilesAndReconcilesAllSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = [CaptureID(), CaptureID()]
        let before = try await committedEntries(root, ids: ids)
        try FileManager.default.removeItem(at: root.appendingPathComponent(before[0].imageLocation))
        try recoverySQL("UPDATE history SET image_bytes = 1, thumbnail_bytes = 1 WHERE id = \(before[1].key)", root: root)
        let orphan = "thumbnails/\(UUID().uuidString).png"
        try RecoveryPixels().bytes.write(to: root.appendingPathComponent(orphan))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("staging"), withIntermediateDirectories: false)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("staging/interrupted"))
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("images/\(UUID().uuidString).partial"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("archives"), withIntermediateDirectories: false)
        try Data(repeating: 42, count: 117).write(to: root.appendingPathComponent("archives/recovery.sqlite"))
        let log = LocalDiagnosticLog()
        let history = HistoryStore(root: root, diagnostics: log)
        let report = try await history.recover().get()
        let after = try await history.entries().get()
        #expect(after.map(\.captureID) == [ids[1]])
        let survivor = try #require(after.first)
        let snapshot = try recoverySnapshot(root)
        #expect(survivor.imageBytes == 70)
        let thumbnailLocation = try #require(survivor.thumbnailLocation)
        #expect(survivor.thumbnailBytes == Int64(try #require(snapshot[thumbnailLocation]).count))
        #expect(report.removedMissingImages == 1)
        #expect(report.logicalBytes == snapshot.values.reduce(Int64(0)) { $0 + Int64($1.count) })
        #expect(snapshot["archives/recovery.sqlite"]?.count == 117)
        #expect(snapshot[try #require(before[0].thumbnailLocation)] == nil)
        #expect(snapshot[orphan] == nil)
        #expect(!snapshot.keys.contains { $0.hasPrefix("staging/") || $0.hasSuffix(".partial") })
        _ = try await history.recover().get()
        #expect(try recoverySnapshot(root) == snapshot)
        #expect(try await history.entries().get() == after)
    }
}

extension HistoryRecoveryTests {
    /// Only a whole, decodable PNG named by a canonical capture identifier is adopted. Anything
    /// else in `images/` is not a capture and is removed.
    @Test(arguments: ["notPNG", "compressedPixels", "fileName", "partial"])
    func rowlessFilesThatAreNotCapturesAreRemoved(damage: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        try await interruptedCommit(at: root, point: .imageWritten, id: id)
        let image = root.appendingPathComponent("images/\(id.rawValue.uuidString).png")
        switch damage {
        case "notPNG": try Data(repeating: 0, count: 70).write(to: image)
        case "compressedPixels":
            var bytes = RecoveryPixels().bytes
            bytes[41] = 0 // Keep the PNG header/dimensions; invalidate the compressed pixel stream.
            try bytes.write(to: image)
        case "fileName": try FileManager.default.moveItem(at: image, to: root.appendingPathComponent("images/not-an-identifier.png"))
        default: try FileManager.default.moveItem(at: image, to: root.appendingPathComponent("images/\(id.rawValue.uuidString).partial"))
        }
        let history = HistoryStore(root: root)
        _ = try await history.recover().get()
        #expect(try await history.entries().get().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("images").path).isEmpty)
        let snapshot = try recoverySnapshot(root)
        _ = try await history.recover().get()
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
        let history = HistoryStore(root: root)
        let commands = recoveryCommands(history)
        #expect(await history.recover() == .failure(.unavailable))
        #expect(try recoverySnapshot(external) == before)
    }
}

extension HistoryRecoveryTests {
    @Test func recoveryDoesNotAdoptAnImageSymlinkOutsideTheRoot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let id = CaptureID()
        try await interruptedCommit(at: root, point: .imageWritten, id: id)
        let image = root.appendingPathComponent("images/\(id.rawValue.uuidString).png")
        let outside = directory.appendingPathComponent("outside.png")
        try FileManager.default.moveItem(at: image, to: outside)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
        let history = HistoryStore(root: root)
        let commands = recoveryCommands(history)
        #expect(await history.recover() == .failure(.unavailable))
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
        let history = HistoryStore(root: newRoot)
        let commands = recoveryCommands(history)
        _ = try await history.recover().get()
        #expect(try await history.entries().get() == before)
        for entry in before {
            for location in [entry.imageLocation, entry.thumbnailLocation].compactMap({ $0 }) {
                #expect(!location.hasPrefix("/") && !location.contains(".."))
                #expect(FileManager.default.fileExists(atPath: newRoot.appendingPathComponent(location).path))
            }
        }
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await history.entries().get().count == 2)
        #expect(!FileManager.default.fileExists(atPath: oldRoot.path))
    }

    @Test func aMissingDisposableThumbnailDoesNotLoseHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try #require(try await committedEntries(root, ids: [CaptureID()]).first)
        try FileManager.default.removeItem(at: root.appendingPathComponent(try #require(entry.thumbnailLocation)))
        let history = HistoryStore(root: root)
        let commands = recoveryCommands(history)
        _ = try await history.recover().get()
        let after = try #require(try await history.entries().get().first)
        #expect(after.captureID == entry.captureID)
        #expect(after.thumbnailLocation == nil && after.thumbnailBytes == 0)
        #expect(await history.thumbnailPNG(after.captureID) == nil)
        #expect(try Data(contentsOf: root.appendingPathComponent(after.imageLocation)) == RecoveryPixels().bytes)
        let snapshot = try recoverySnapshot(root)
        _ = try await history.recover().get()
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
        let history = HistoryStore(root: root, diagnostics: log)
        let commands = recoveryCommands(history)
        #expect(await history.recover() == .failure(.unknownMigrations))
        #expect(await history.entries() == .failure(.unknownMigrations))
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
        // Crash-helper rows are stamped 1970. Keep them past the default 30-day
        // window so this launch-gate case is not also an age-eviction case.
        let history = HistoryStore.launch(root: root,
            limits: HistoryLimits(retentionDays: 40_000), diagnostics: log)
        let commands = recoveryCommands(history)
        #expect(try await history.entries().get().map(\.captureID) == [id])
        #expect(try await history.entries().get().map(\.captureID) == [id])
        #expect(await log.entries().map(\.event) == [DiagnosticEvent(name: .historyRecovered, operation: .launchRecovery)])
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(revision.captureID, maximumBytes: 1024)) == .pending(revision))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        #expect(try await history.entries().get().map(\.captureID) == [id, revision.captureID])
        #expect(await log.entries().count == 1)
    }

    @Test func launchAndPendingCaptureCreateNothingInANewRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = HistoryStore.launch(root: root)
        let commands = recoveryCommands(history)
        #expect(try await history.entries().get().isEmpty)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 1024)) == .pending(CaptureRevision(captureID: id, number: 1)))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await commands.execute(.discard(id)) == .discarded(id))
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

extension HistoryRecoveryTests {
    /// D27 is gone with the lock (ticket 78): `.rootLocked` is retired, and a store reopened
    /// right after the previous one closed recovers and reads, even while child processes start.
    @Test func reopeningARootRightAfterACloseWorksWhileChildProcessesStart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        _ = try await committedEntries(root, ids: [id])
        let spawner = Task.detached {
            for _ in 0..<40 {
                let child = Process()
                child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
                try? child.run()
                child.waitUntilExit()
            }
        }
        for _ in 0..<40 {
            let store = HistoryStore(root: root)
            #expect(await store.availability() == nil)
            #expect(try await store.rows().get().map(\.captureID) == [id])
            let revision = CaptureRevision(captureID: CaptureID(), number: 1)
            let commands = recoveryCommands(store)
            _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
            #expect(await commands.execute(.discard(revision.captureID)) == .discarded(revision.captureID))
            try await store.close().get()
        }
        await spawner.value
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
        #expect(await store.entries() == .failure(.unavailable))
        let nextHistory = HistoryStore(root: root)
        let next = recoveryCommands(nextHistory)
        _ = try await nextHistory.recover().get()
        #expect(try await nextHistory.entries().get().map(\.captureID) == [id])
    }
}

extension HistoryRecoveryTests {
    /// Ticket 54 (DA-3): drags no longer stage on disk. The launch sweep removes drag staging an
    /// earlier build left behind, such as a 744 B PNG under `staging/drag/`, and keeps History.
    @Test func launchSweepRemovesLeftoverDragStagingAndKeepsHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CaptureID()
        let before = try await committedEntries(root, ids: [id])
        let drag = root.appendingPathComponent("staging/drag")
        try FileManager.default.createDirectory(at: drag, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 744).write(to: drag.appendingPathComponent("\(UUID().uuidString).png"))
        let history = HistoryStore(root: root)
        let commands = recoveryCommands(history)
        let report = try await history.recover().get()
        #expect(!FileManager.default.fileExists(atPath: drag.path))
        #expect(try await history.entries().get() == before)
        let snapshot = try recoverySnapshot(root)
        #expect(!snapshot.keys.contains { $0.hasPrefix("staging/") })
        #expect(report.logicalBytes == snapshot.values.reduce(Int64(0)) { $0 + Int64($1.count) })
        _ = try await history.recover().get()
        #expect(try recoverySnapshot(root) == snapshot)
    }
}
