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
private func commands(_ store: HistoryStore, exporter: (any CaptureExport)? = nil) -> CaptureCommandLayer {
    CaptureCommandLayer(permission: GrantedTestPermission(), source: RetentionPixels(), clipboard: RetentionClipboard(),
        pendingByteLimit: 4096, history: store, exporter: exporter)
}
private func capture(_ commands: CaptureCommandLayer) async -> CaptureRevision {
    let revision = CaptureRevision(captureID: CaptureID(), number: 1)
    #expect(await commands.execute(.capture(revision.captureID, maximumBytes: 4096)) == .pending(revision))
    return revision
}
private func keep(_ commands: CaptureCommandLayer) async -> CaptureRevision {
    let revision = await capture(commands)
    #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
    return revision
}

@Suite struct RetentionCommandsTests {
    @Test func ageLimitRemovesOldestAndKeepsJustCommitted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let layer = commands(HistoryStore(root: root, clock: clock.now))
        _ = await keep(layer)
        clock.advance(days: 20)
        let second = await keep(layer)
        clock.advance(days: 11)
        let newest = await keep(layer)
        #expect(try await layer.historyEntries().get().map(\.captureID) == [second.captureID, newest.captureID])
    }
}

extension RetentionCommandsTests {
    @Test func quotaUsesOldestKeyForEqualDatesAndReportsNoticeOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let layer = commands(HistoryStore(root: root, clock: clock.now))
        _ = await keep(layer)
        let second = await keep(layer)
        let third = await keep(layer)
        let before = try await layer.historyStatus().get()
        let entries = try await layer.historyEntries().get()
        let first = try #require(entries.first)
        let bytes = first.imageBytes + first.recordBytes + first.thumbnailBytes
        let status = try await layer.maintainHistory(limits: HistoryLimits(retentionDays: 30,
            maximumBytes: before.usageBytes - bytes)).get()
        #expect(try await layer.historyEntries().get().map(\.captureID) == [second.captureID, third.captureID])
        #expect(status.usageBytes <= status.limits.maximumBytes)
        #expect(status.lastQuotaEviction != nil)
        #expect(try await layer.historyStatus(consumeNotice: true).get().quotaNoticePending)
        #expect(try await !layer.historyStatus(consumeNotice: true).get().quotaNoticePending)
    }
}

extension RetentionCommandsTests {
    @Test(arguments: [false, true]) func oversizedCaptureStillDelivers(save: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("History.noindex")
        let exports = directory.appendingPathComponent("Exports")
        let layer = commands(HistoryStore(root: root, limits: HistoryLimits(maximumBytes: 1)),
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
        #expect(try await layer.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

extension RetentionCommandsTests {
    @Test(arguments: [-10.0, 31.0]) func anomalousClockDefersAgeEvictionAndNormalizesFutureDatesOnlyOnce(jump: Double) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let layer = commands(HistoryStore(root: root, clock: clock.now))
        let kept = await keep(layer)
        clock.advance(days: jump)
        let status = try await layer.maintainHistory().get()
        #expect(status.ageEvictionDeferred)
        let first = try #require(try await layer.historyEntries().get().first)
        #expect(first.captureID == kept.captureID)
        if jump < 0 {
            #expect(first.finalizedAt == clock.now())
            clock.advance(days: -1)
            #expect(try await layer.maintainHistory().get().ageEvictionDeferred)
            #expect(try await layer.historyEntries().get().first?.finalizedAt == first.finalizedAt)
        } else {
            // A stable second observation permits the deferred sweep.
            #expect(try await !layer.maintainHistory().get().ageEvictionDeferred)
            #expect(try await layer.historyEntries().get().isEmpty)
        }
    }
}

extension RetentionCommandsTests {
    @Test(arguments: [false, true]) func launchRemeasuresOwnedFilesAndFailedReadBlocksCommit(missing: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        var layer: CaptureCommandLayer? = commands(HistoryStore(root: root, clock: clock.now))
        _ = await keep(layer!)
        let entry = try #require(try await layer!.historyEntries().get().first)
        let before = try await layer!.historyStatus().get().usageBytes
        layer = nil
        let image = root.appendingPathComponent(entry.imageLocation)
        if missing { try FileManager.default.removeItem(at: image) }
        else { try (RetentionPixels().bytes + Data(repeating: 0, count: 1234)).write(to: image) }
        let unrelated = root.appendingPathComponent("unowned.png")
        try Data(repeating: 0, count: 5000).write(to: unrelated)
        let reopened = commands(HistoryStore(root: root, clock: clock.now))
        let result = await reopened.maintainHistory()
        if missing {
            #expect(result == .failure(.unavailable))
            let revision = await capture(reopened)
            #expect(await reopened.execute(.dismiss(revision)) == .finalized(revision, .notCommitted(.historyUnavailable)))
        } else {
            #expect(try result.get().usageBytes == before + 1234)
            #expect(try await reopened.historyEntries().get().first?.imageBytes == Int64(RetentionPixels().bytes.count + 1234))
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
        var layer: CaptureCommandLayer? = commands(HistoryStore(root: root, evictionPoint: { reached in
            if reached == point { throw EvictionStop.interrupted }
        }), exporter: PNGFileExporter(folder: { exports }, historyRoot: root))
        let old = await capture(layer!)
        guard case .save(let outcome) = await layer!.execute(.save(old)), case .saved = outcome.delivery else {
            Issue.record("Expected synthetic export"); return
        }
        let exportFile = try #require(try FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: exportFile)
        let surviving = await keep(layer!)
        #expect(await layer!.maintainHistory(limits: HistoryLimits(maximumBytes: 1)) == .failure(.unavailable))
        #expect(try await !layer!.historyEntries().get().map(\.captureID).contains(old.captureID))
        let interruptedUsage = try await layer!.historyStatus().get().usageBytes
        layer = nil
        let reopened = commands(HistoryStore(root: root))
        let first = try await reopened.maintainHistory().get()
        let second = try await reopened.maintainHistory().get()
        #expect(first.usageBytes == second.usageBytes)
        #expect(first.usageBytes <= interruptedUsage)
        #expect(try await reopened.historyEntries().get().map(\.captureID) == [surviving.captureID])
        #expect(try Data(contentsOf: exportFile) == original)
        #expect(first.lastQuotaEviction != nil)
    }
}

extension RetentionCommandsTests {
    @Test func evictionProcessChild() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FRISKET_EVICTION_TEST_ROOT"],
              let value = environment["FRISKET_EVICTION_TEST_POINT"],
              let point = HistoryEvictionPoint(rawValue: value) else { return }
        let layer = commands(HistoryStore(root: URL(fileURLWithPath: path), evictionPoint: { reached in
            if reached == point { kill(getpid(), SIGKILL) }
        }))
        _ = await layer.maintainHistory(limits: HistoryLimits(maximumBytes: 1))
        Issue.record("Child did not reach its kill point")
    }

    @Test(arguments: HistoryEvictionPoint.allCases) func processKillAtEveryEvictionPointResumesIdempotently(point: HistoryEvictionPoint) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        var layer: CaptureCommandLayer? = commands(HistoryStore(root: root))
        _ = await keep(layer!)
        let survivor = await keep(layer!)
        _ = try await layer!.historyStatus().get()
        layer = nil
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundleArgument = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path"))
        let bundle = CommandLine.arguments[bundleArgument + 1]
        child.arguments = ["--test-bundle-path", bundle, "--testing-library", "swift-testing", "--filter", "evictionProcessChild"]
        var environment = ProcessInfo.processInfo.environment
        environment["FRISKET_EVICTION_TEST_ROOT"] = root.path
        environment["FRISKET_EVICTION_TEST_POINT"] = point.rawValue
        child.environment = environment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGKILL)
        let reopened = commands(HistoryStore(root: root))
        let first = try await reopened.maintainHistory().get()
        let second = try await reopened.maintainHistory().get()
        #expect(first == second)
        #expect(try await reopened.historyEntries().get().map(\.captureID) == [survivor.captureID])
        let entries = try await reopened.historyEntries().get()
        var diskBytes: Int64 = 0
        for entry in entries {
            for path in [entry.imageLocation, entry.recordLocation, entry.thumbnailLocation].compactMap({ $0 }) {
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
        let layer = commands(HistoryStore(root: root))
        _ = await keep(layer)
        let usage = try await layer.historyStatus().get().usageBytes
        _ = try await layer.maintainHistory(limits: HistoryLimits(maximumBytes: usage + 100)).get()
        let newest = await keep(layer)
        #expect(try await layer.historyEntries().get().map(\.captureID) == [newest.captureID])
        #expect(try await layer.historyStatus().get().quotaNoticePending)
    }

    @Test func failedFinalizedFileSizeReadBlocksRowWhileCopyStillWorks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root, commitPoint: { point in
            if point == .directorySynced {
                let images = root.appendingPathComponent("images")
                for file in try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil) where file.pathExtension == "png" {
                    try FileManager.default.removeItem(at: file)
                }
            }
        })
        let layer = commands(store)
        let revision = await capture(layer)
        #expect(await layer.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .notCommitted(.historyUnavailable), delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(try await layer.historyEntries().get().isEmpty)
    }

    @Test func configurableDaysAndEmptyLaunchDoNotCreateHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RetentionClock()
        let layer = commands(HistoryStore(root: root, clock: clock.now))
        let defaults = try await layer.maintainHistory().get()
        #expect(defaults.limits.retentionDays == 30)
        #expect(defaults.limits.maximumBytes == 1_000_000_000)
        #expect(defaults.usageBytes == 0)
        _ = try await layer.maintainHistory(limits: HistoryLimits(retentionDays: 1)).get()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        _ = await keep(layer)
        clock.advance(days: 0.75)
        let second = await keep(layer)
        clock.advance(days: 0.5)
        _ = try await layer.maintainHistory().get()
        #expect(try await layer.historyEntries().get().map(\.captureID) == [second.captureID])
    }
}

extension RetentionCommandsTests {
    @Test func interruptedFinalizationBytesAreStillAccountedAtLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        var layer: CaptureCommandLayer? = commands(HistoryStore(root: root, commitPoint: { point in
            if point == .pngSynced { throw EvictionStop.interrupted }
        }))
        let revision = await capture(layer!)
        #expect(await layer!.execute(.dismiss(revision)) == .finalized(revision, .notCommitted(.historyUnavailable)))
        _ = try await layer!.historyStatus().get()
        layer = nil
        let reopened = commands(HistoryStore(root: root))
        let usage = try await reopened.maintainHistory().get().usageBytes
        var disk: Int64 = Int64(RetentionPixels().bytes.count)
        for suffix in ["", "-wal", "-shm"] {
            let file = root.appendingPathComponent("history.sqlite" + suffix)
            if FileManager.default.fileExists(atPath: file.path) { disk += Int64(try Data(contentsOf: file).count) }
        }
        #expect(usage == disk)
        #expect(try await reopened.historyEntries().get().isEmpty)
    }
}
