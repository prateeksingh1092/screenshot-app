import Foundation
import FrisketCore
import Testing

private struct DragPixels: CapturePixelSource {
    // A synthetic 2 x 1 opaque red PNG; no screen content.
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private struct DragClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

private enum DragCaptureKind: CaseIterable, Sendable {
    case area, fullScreen

    func command(_ id: CaptureID, maximumBytes: Int) -> CaptureCommand {
        switch self {
        case .area: .capture(id, maximumBytes: maximumBytes)
        case .fullScreen: .captureFullScreen(id, maximumBytes: maximumBytes)
        }
    }
}

actor RecordingDragHandoff: DragHandoff {
    enum Order: Sendable { case writeThenSession, sessionThenWrite }

    private let order: Order
    private var writeFails: Bool
    private var recordedOperations: [DragFileOperation] = []
    private var recordedBytes: [Data] = []
    private var afterFirstEvent: (@Sendable () async -> Void)?

    init(order: Order = .writeThenSession, writeFails: Bool = false) {
        self.order = order
        self.writeFails = writeFails
    }

    func setWriteFails(_ fails: Bool) { writeFails = fails }

    func setAfterFirstEvent(_ probe: @escaping @Sendable () async -> Void) { afterFirstEvent = probe }

    func operations() -> [DragFileOperation] { recordedOperations }

    func bytes() -> [Data] { recordedBytes }

    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        recordedOperations.append(operation)
        recordedBytes.append(image.pngData)
        switch order {
        case .writeThenSession:
            do { try await events.promiseWriteReturned() }
            catch {
                // AppKit can still end the session after the write event faults.
                await events.dragSessionEnded()
                throw error
            }
            if let afterFirstEvent { await afterFirstEvent() }
            await events.dragSessionEnded()
        case .sessionThenWrite:
            await events.dragSessionEnded()
            if let afterFirstEvent { await afterFirstEvent() }
            try await events.promiseWriteReturned()
        }
        return writeFails ? .failed : .copied
    }
}

private func makeDragCommands(root: URL, handoff: RecordingDragHandoff) -> CaptureCommandLayer {
    let source = DragPixels()
    return CaptureCommandLayer(permission: GrantedTestPermission(), source: source, fullScreenSource: source,
        clipboard: DragClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root), drag: handoff)
}

/// Drags stage nothing: no `staging/drag` directory is ever created (DA-3).
private func dragStagingExists(root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent("staging/drag").path)
}

private final class FirstEventFiles: @unchecked Sendable {
    var files: [String]?
}

@Suite struct DragHandoffTests {
    @Test func commitPointListIsClosed() {
        #expect(Set(HistoryCommitPoint.allCases.map(\.rawValue)) == [
            "pngStaged", "pngSynced", "recordStaged", "recordSynced", "imageRenamed", "recordRenamed",
            "directorySynced", "rowCommitted", "thumbnailCached"
        ])
    }

    @Test(arguments: DragCaptureKind.allCases)
    private func dragFinalizesTheRenderedRevisionOnce(kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff()
        let commands = makeDragCommands(root: root, handoff: handoff)
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .copied)))
        let entries = try await commands.historyEntries().get()
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.captureID == revision.captureID)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await handoff.operations() == [.copy])
        #expect(await handoff.bytes() == [source.bytes])
        #expect(!dragStagingExists(root: root))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .copied)))
        #expect(await handoff.operations() == [.copy, .copy])
        #expect(await handoff.bytes() == [source.bytes, source.bytes])
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.alreadyFinalized))
        #expect(try await commands.historyEntries().get().count == 1)
        #expect(!dragStagingExists(root: root))
        let next = CaptureID()
        #expect(await commands.execute(kind.command(next, maximumBytes: source.bytes.count)) == .pending(CaptureRevision(captureID: next, number: 1)))
    }

    @Test(arguments: DragCaptureKind.allCases)
    private func moveAndDeleteAreRefusedWithoutTouchingHistory(kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff()
        let commands = makeDragCommands(root: root, handoff: handoff)
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .move)) == .rejected(.dragOperationRefused))
        #expect(await commands.execute(.drag(revision, .delete)) == .rejected(.dragOperationRefused))
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        #expect(try await commands.historyEntries().get().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await handoff.operations().isEmpty)
    }

    /// DA-3: while the drag session runs, in either event order, nothing about the capture is on disk.
    /// It is committed only after the handoff reports the accepted drop.
    @Test(arguments: [RecordingDragHandoff.Order.writeThenSession, .sessionThenWrite], DragCaptureKind.allCases)
    private func nothingReachesDiskUntilTheDropIsAccepted(order: RecordingDragHandoff.Order, kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff(order: order)
        let seen = FirstEventFiles()
        await handoff.setAfterFirstEvent { seen.files = filesUnder(root) }
        let commands = makeDragCommands(root: root, handoff: handoff)
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .copied)))
        #expect(seen.files == [])
        #expect(!dragStagingExists(root: root))
        let entries = try await commands.historyEntries().get()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await commands.image(for: revision) == nil)
        #expect(await commands.thumbnails().isEmpty)
    }

    @Test(arguments: DragCaptureKind.allCases)
    private func failedPromiseWriteCommitsNothingAndARetriedDropCommitsOnce(kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff(writeFails: true)
        let commands = makeDragCommands(root: root, handoff: handoff)
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: nil, delivery: .failed)))
        #expect(filesUnder(root).isEmpty)
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        let cards = await commands.thumbnails()
        #expect(cards.map(\.revision) == [revision])
        #expect(cards.first?.automaticExitSuppressed == true)
        #expect(await handoff.bytes() == [source.bytes])
        await handoff.setWriteFails(false)
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .copied)))
        let entries = try await commands.historyEntries().get()
        #expect(entries.map(\.captureID) == [revision.captureID])
        #expect(try Data(contentsOf: root.appendingPathComponent(try #require(entries.first).imageLocation)) == source.bytes)
        #expect(!dragStagingExists(root: root))
    }
}

private enum DragStop: Error { case stop }

/// A handoff whose session faults (for example, AppKit reports an error) before any drop.
private struct ThrowingDragHandoff: DragHandoff {
    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        await events.dragSessionEnded()
        throw DragStop.stop
    }
}

extension DragHandoffTests {
    @Test(arguments: DragCaptureKind.allCases)
    private func aFaultedDragCommitsNothingAndKeepsTheCapturePending(kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = DragPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, fullScreenSource: source,
            clipboard: DragClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root),
            drag: ThrowingDragHandoff())
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: nil, delivery: .failed)))
        #expect(filesUnder(root).isEmpty)
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        #expect(await commands.thumbnails().map(\.revision) == [revision])
    }
}

/// What `FilePromiseDragAdapter` does when the user cancels a drag (Esc, or a drop nowhere):
/// the session ends without an accepted operation or a promise destination, so the promise is
/// never written and delivery fails.
private actor CancellingDragHandoff: DragHandoff {
    private(set) var sessions = 0
    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        sessions += 1
        await events.dragSessionEnded()
        return .failed
    }
}

private func filesUnder(_ root: URL) -> [String] {
    let base = root.resolvingSymlinksInPath().path
    guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
    var files: [String] = []
    while let item = items.nextObject() as? URL {
        if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
        files.append(String(item.resolvingSymlinksInPath().path.dropFirst(base.count + 1)))
    }
    return files.sorted()
}

extension DragHandoffTests {
    /// D7 (DA-3, story 88): only a drop a destination accepts finalizes a drag. A cancelled drag
    /// leaves the capture pending, with nothing in History and nothing on disk.
    @Test(arguments: DragCaptureKind.allCases)
    private func d7CancelledDragLeavesTheCapturePendingWithNothingOnDisk(kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = CancellingDragHandoff()
        let source = DragPixels()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: source, fullScreenSource: source,
            clipboard: DragClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root),
            drag: handoff)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))

        guard case let .drag(outcome) = await commands.execute(.drag(revision, .copy)) else {
            Issue.record("a drag command returns a drag outcome")
            return
        }
        #expect(await handoff.sessions == 1)
        #expect(outcome.delivery == .failed)
        let entries = try await commands.historyEntries().get()
        #expect(entries.isEmpty, "D7: a cancelled drag committed the capture to History")
        #expect(filesUnder(root).isEmpty, "D7: a cancelled drag left files on disk: \(filesUnder(root))")
        #expect(await commands.image(for: revision)?.pngData == source.bytes, "D7: the capture is still pending")
        #expect(await commands.thumbnails().map(\.revision) == [revision], "D7: its Thumbnail is still open")
    }
}
