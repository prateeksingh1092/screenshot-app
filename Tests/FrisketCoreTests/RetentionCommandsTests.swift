import Foundation
import Darwin
import Synchronization
import FrisketCore
import Testing

private final class RetentionClock: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_700_000_000))
    func now() -> Date { value.withLock { $0 } }
    func advance(days: Double) { value.withLock { $0.addTimeInterval(days * 86_400) } }
}

private struct RetentionPixels: CapturePixelSource {
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}
private struct RetentionClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}
private func commands(_ store: HistoryStore, exporter: (any CaptureExport)? = nil) -> CaptureLifecycleCoordinator {
    CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: RetentionPixels(), clipboard: RetentionClipboard(),
        pendingByteLimit: 4096, history: store, exporter: exporter)
}
private func capture(_ commands: CaptureLifecycleCoordinator) async -> CaptureRevision {
    let revision = CaptureRevision(captureID: CaptureID(), number: 1)
    #expect(await commands.execute(.capture(revision.captureID, maximumBytes: 4096)) == .pending(revision))
    return revision
}
private func keep(_ commands: CaptureLifecycleCoordinator) async -> CaptureRevision {
    let revision = await capture(commands)
    #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
    return revision
}

@Suite struct RetentionCommandsTests {
    @Test func ageLimitRemovesOldestAndKeepsJustCommitted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let history = HistoryStore(root: root, clock: clock.now)
        let layer = commands(history)
        _ = await keep(layer)
        clock.advance(days: 20)
        let second = await keep(layer)
        clock.advance(days: 11)
        let newest = await keep(layer)
        #expect(try await history.entries().get().map(\.captureID) == [second.captureID, newest.captureID])
    }
}

extension RetentionCommandsTests {
    @Test func quotaUsesOldestKeyForEqualDatesAndReportsNoticeOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let history = HistoryStore(root: root, clock: clock.now)
        let layer = commands(history)
        _ = await keep(layer)
        let second = await keep(layer)
        let third = await keep(layer)
        let before = try await history.status(consumeNotice: false).get()
        let entries = try await history.entries().get()
        let first = try #require(entries.first)
        let bytes = first.imageBytes + first.thumbnailBytes
        let status = try await history.maintain(limits: HistoryLimits(retentionDays: 30,
            maximumBytes: before.usageBytes - bytes)).get()
        #expect(try await history.entries().get().map(\.captureID) == [second.captureID, third.captureID])
        #expect(status.usageBytes <= status.limits.maximumBytes)
        #expect(status.lastQuotaEviction != nil)
        #expect(try await history.status(consumeNotice: true).get().quotaNoticePending)
        #expect(try await !history.status(consumeNotice: true).get().quotaNoticePending)
    }
}

extension RetentionCommandsTests {
    @Test(arguments: [false, true]) func oversizedCaptureStillDelivers(save: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        let history = HistoryStore(root: root, limits: HistoryLimits(maximumBytes: 1))
        let layer = commands(history,
            exporter: PNGFileExporter(folder: { exports }, historyRoot: root))
        let revision = await capture(layer)
        let result = await layer.execute(save ? .save(revision) : .copy(revision))
        if save {
            guard case .save(let outcome) = result else { Issue.record("Expected Save outcome"); return }
            #expect(outcome.commit == .notCommitted(.captureExceedsHistoryLimit))
            guard case .saved = outcome.delivery else { Issue.record("Export must still succeed"); return }
        } else {
            #expect(result == .copy(CopyOutcome(revision: revision, commit: .notCommitted(.captureExceedsHistoryLimit),
                delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        }
        #expect(try await history.entries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

extension RetentionCommandsTests {
    @Test(arguments: [-10.0, 31.0]) func anomalousClockDefersAgeEvictionAndNormalizesFutureDatesOnlyOnce(jump: Double) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let history = HistoryStore(root: root, clock: clock.now)
        let layer = commands(history)
        let kept = await keep(layer)
        clock.advance(days: jump)
        let status = try await history.maintain(limits: nil).get()
        #expect(status.ageEvictionDeferred)
        let first = try #require(try await history.entries().get().first)
        #expect(first.captureID == kept.captureID)
        if jump < 0 {
            #expect(first.finalizedAt == clock.now())
            clock.advance(days: -1)
            #expect(try await history.maintain(limits: nil).get().ageEvictionDeferred)
            #expect(try await history.entries().get().first?.finalizedAt == first.finalizedAt)
        } else {
            // A stable second observation permits the deferred sweep.
            #expect(try await !history.maintain(limits: nil).get().ageEvictionDeferred)
            #expect(try await history.entries().get().isEmpty)
        }
    }
}

extension RetentionCommandsTests {
    @Test(arguments: [false, true]) func launchRemeasuresOwnedFilesAndFailedReadBlocksCommit(missing: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        var history: HistoryStore? = HistoryStore(root: root, clock: clock.now)
        var layer: CaptureLifecycleCoordinator? = commands(history!)
        _ = await keep(layer!)
        let entry = try #require(try await history!.entries().get().first)
        let before = try await history!.status(consumeNotice: false).get().usageBytes
        layer = nil
        history = nil
        let image = root.appendingPathComponent(entry.imageLocation)
        if missing { try FileManager.default.removeItem(at: image) }
        else { try (RetentionPixels().bytes + Data(repeating: 0, count: 1234)).write(to: image) }
        let unrelated = root.appendingPathComponent("unowned.png")
        try Data(repeating: 0, count: 5000).write(to: unrelated)
        let reopenedHistory = HistoryStore(root: root, clock: clock.now)
        let reopened = commands(reopenedHistory)
        let result = await reopenedHistory.maintain(limits: nil)
        if missing {
            #expect(result == .failure(.unavailable))
            let revision = await capture(reopened)
            #expect(await reopened.execute(.dismiss(revision)) == .finalized(revision, .notCommitted(.historyUnavailable)))
        } else {
            #expect(try result.get().usageBytes == before + 1234)
            #expect(try await reopenedHistory.entries().get().first?.imageBytes == Int64(RetentionPixels().bytes.count + 1234))
        }
        #expect(try Data(contentsOf: unrelated).count == 5000)
    }
}

private enum EvictionStop: Error { case interrupted }

extension RetentionCommandsTests {
    @Test(arguments: HistoryEvictionPoint.allCases) func interruptedEvictionResumesTwiceWithoutTouchingExports(point: HistoryEvictionPoint) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        let history = HistoryStore(root: root, evictionPoint: { reached in
            if reached == point { throw EvictionStop.interrupted }
        })
        let layer = commands(history, exporter: PNGFileExporter(folder: { exports }, historyRoot: root))
        let old = await capture(layer)
        guard case .save(let outcome) = await layer.execute(.save(old)), case .saved = outcome.delivery else {
            Issue.record("Expected synthetic export"); return
        }
        let exportFile = try #require(try FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: exportFile)
        let surviving = await keep(layer)
        let oldest = try #require(try await history.entries().get().first)
        let usage = try await history.status(consumeNotice: false).get().usageBytes
        #expect(await history.maintain(limits: HistoryLimits(maximumBytes: usage - oldest.imageBytes - oldest.thumbnailBytes)) == .failure(.unavailable))
        try await history.close().get()
        // Reopen as the app does: the launch sweep drops the rows whose files are gone.
        let reopenedHistory = HistoryStore.launch(root: root)
        let first = try await reopenedHistory.maintain(limits: nil).get()
        let second = try await reopenedHistory.maintain(limits: nil).get()
        #expect(first.usageBytes == second.usageBytes)
        #expect(first.usageBytes <= usage)
        #expect(try await reopenedHistory.entries().get().map(\.captureID) == [surviving.captureID])
        #expect(try Data(contentsOf: exportFile) == original)
        #expect(first.lastQuotaEviction != nil)
    }
}

extension RetentionCommandsTests {
    @Test func evictionProcessChild() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FRISKET_EVICTION_TEST_ROOT"],
              let value = environment["FRISKET_EVICTION_TEST_POINT"],
              let point = HistoryEvictionPoint(rawValue: value),
              let limit = environment["FRISKET_EVICTION_TEST_LIMIT"].flatMap(Int64.init) else { return }
        let history = HistoryStore(root: URL(fileURLWithPath: path), evictionPoint: { reached in
            if reached == point { kill(getpid(), SIGKILL) }
        })
        _ = await history.maintain(limits: HistoryLimits(maximumBytes: limit))
        Issue.record("Child did not reach its kill point")
    }

    @Test(arguments: HistoryEvictionPoint.allCases) func processKillAtEveryEvictionPointResumesIdempotently(point: HistoryEvictionPoint) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        var layer: CaptureLifecycleCoordinator? = commands(store)
        _ = await keep(layer!)
        let survivor = await keep(layer!)
        let usage = try await store.status(consumeNotice: false).get().usageBytes
        let oldest = try #require(try await store.entries().get().first)
        layer = nil
        try await store.close().get()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundleArgument = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path"))
        let bundle = CommandLine.arguments[bundleArgument + 1]
        child.arguments = ["--test-bundle-path", bundle, "--testing-library", "swift-testing", "--filter", "evictionProcessChild"]
        var environment = ProcessInfo.processInfo.environment
        environment["FRISKET_EVICTION_TEST_ROOT"] = root.path
        environment["FRISKET_EVICTION_TEST_POINT"] = point.rawValue
        // Over quota by the oldest capture only, so one survives the batch.
        environment["FRISKET_EVICTION_TEST_LIMIT"] = String(usage - oldest.imageBytes - oldest.thumbnailBytes)
        child.environment = environment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGKILL)
        // Reopen as the app does after a crash: launch recovery runs before maintenance.
        let reopenedHistory = HistoryStore.launch(root: root)
        try await verifyEvictionResume(reopenedHistory, root: root, survivor: survivor)
    }

    private func verifyEvictionResume(_ reopenedHistory: HistoryStore, root: URL, survivor: CaptureRevision) async throws {
        let first = try await reopenedHistory.maintain(limits: nil).get()
        let second = try await reopenedHistory.maintain(limits: nil).get()
        #expect(first == second)
        #expect(try await reopenedHistory.entries().get().map(\.captureID) == [survivor.captureID])
        let entries = try await reopenedHistory.entries().get()
        var diskBytes: Int64 = 0
        for entry in entries {
            for path in [entry.imageLocation, entry.thumbnailLocation].compactMap({ $0 }) {
                diskBytes += Int64(try Data(contentsOf: root.appendingPathComponent(path)).count)
            }
        }
        for suffix in ["", "-wal", "-shm"] {
            let file = root.appendingPathComponent("history.sqlite" + suffix)
            if FileManager.default.fileExists(atPath: file.path) { diskBytes += Int64(try Data(contentsOf: file).count) }
        }
        #expect(second.usageBytes == diskBytes)
    }

    @Test func everyCommitEnforcesConfiguredQuotaButProtectsTheNewCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = HistoryStore(root: root)
        let layer = commands(history)
        _ = await keep(layer)
        let usage = try await history.status(consumeNotice: false).get().usageBytes
        _ = try await history.maintain(limits: HistoryLimits(maximumBytes: usage + 100)).get()
        let newest = await keep(layer)
        #expect(try await history.entries().get().map(\.captureID) == [newest.captureID])
        #expect(try await history.status(consumeNotice: false).get().quotaNoticePending)
    }

    @Test func failedFinalizedFileSizeReadBlocksRowWhileCopyStillWorks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { point in
            if point == .imageWritten {
                let images = root.appendingPathComponent("images")
                for file in try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil) where file.pathExtension == "png" {
                    try FileManager.default.removeItem(at: file)
                }
            }
        })
        let layer = commands(store)
        let revision = await capture(layer)
        #expect(await layer.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .notCommitted(.recoveryRequired), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(try await store.entries().get().isEmpty)
    }

    @Test func configurableDaysAndEmptyLaunchDoNotCreateHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let history = HistoryStore(root: root, clock: clock.now)
        let layer = commands(history)
        let defaults = try await history.maintain(limits: nil).get()
        #expect(defaults.limits.retentionDays == 30)
        #expect(defaults.limits.maximumBytes == 1_000_000_000)
        #expect(defaults.usageBytes == 0)
        _ = try await history.maintain(limits: HistoryLimits(retentionDays: 1)).get()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        _ = await keep(layer)
        clock.advance(days: 0.75)
        let second = await keep(layer)
        clock.advance(days: 0.5)
        _ = try await history.maintain(limits: nil).get()
        #expect(try await history.entries().get().map(\.captureID) == [second.captureID])
    }
}

extension RetentionCommandsTests {
    /// D24's other half: an interrupted finalization is adopted at launch and counted once.
    @Test func interruptedFinalizationIsAdoptedAndCountedOnceAtLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = HistoryStore(root: root, commitPoint: { point in
            if point == .imageWritten { throw EvictionStop.interrupted }
        })
        let layer = commands(history)
        let revision = await capture(layer)
        #expect(await layer.execute(.dismiss(revision)) == .finalized(revision, .notCommitted(.recoveryRequired)))
        try await history.close().get()
        let reopenedHistory = HistoryStore.launch(root: root)
        let usage = try await reopenedHistory.maintain(limits: nil).get().usageBytes
        var disk: Int64 = Int64(RetentionPixels().bytes.count)
        for suffix in ["", "-wal", "-shm"] {
            let file = root.appendingPathComponent("history.sqlite" + suffix)
            if FileManager.default.fileExists(atPath: file.path) { disk += Int64(try Data(contentsOf: file).count) }
        }
        #expect(usage == disk)
        #expect(try await reopenedHistory.entries().get().map(\.captureID) == [revision.captureID])
    }

    /// One eviction batch takes one checkpoint: the files go, then every row in one transaction.
    @Test func quotaEvictsSeveralCapturesInOneBatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let batches = BatchCounter()
        let history = HistoryStore(root: root, evictionPoint: { if $0 == .rowsRemoved { batches.increment() } })
        let layer = commands(history)
        for _ in 0..<4 { _ = await keep(layer) }
        let newest = await keep(layer)
        let entries = try await history.entries().get()
        let usage = try await history.status(consumeNotice: false).get().usageBytes
        let evicted = entries.dropLast().reduce(Int64(0)) { $0 + $1.imageBytes + $1.thumbnailBytes }
        let status = try await history.maintain(limits: HistoryLimits(maximumBytes: usage - evicted)).get()
        #expect(try await history.entries().get().map(\.captureID) == [newest.captureID])
        #expect(batches.value == 1)
        #expect(status.usageBytes <= status.limits.maximumBytes)
    }
}

private final class BatchCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}
