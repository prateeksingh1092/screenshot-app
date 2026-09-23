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
            try await events.promiseWriteReturned()
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

private func makeDragCommands(root: URL, handoff: RecordingDragHandoff,
                              commitPoint: @escaping @Sendable (HistoryCommitPoint) throws -> Void = { _ in }) -> CaptureCommandLayer {
    let source = DragPixels()
    return CaptureCommandLayer(permission: GrantedTestPermission(), source: source, fullScreenSource: source,
        clipboard: DragClipboard(), pendingByteLimit: source.bytes.count, history: HistoryStore(root: root, commitPoint: commitPoint),
        drag: handoff, dragStaging: DragStagingLifetime(directory: root.appendingPathComponent("staging/drag"), commitPoint: commitPoint))
}

private func stagedDragFiles(root: URL) throws -> [URL] {
    let directory = root.appendingPathComponent("staging/drag")
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
}

private final class FirstEventFiles: @unchecked Sendable {
    var count = -1
    var bytes = Data()
}

@Suite struct DragHandoffTests {
    @Test func commitPointListIsClosed() {
        #expect(Set(HistoryCommitPoint.allCases.map(\.rawValue)) == [
            "pngStaged", "pngSynced", "recordStaged", "recordSynced", "imageRenamed", "recordRenamed",
            "directorySynced", "rowCommitted", "thumbnailCached", "dragStaged", "dragPromiseWritten"
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
        #expect(try stagedDragFiles(root: root).isEmpty)
        #expect(await commands.execute(.drag(revision, .copy)) == .rejected(.alreadyDelivered))
        #expect(await commands.execute(.dismiss(revision)) == .rejected(.alreadyFinalized))
        #expect(try await commands.historyEntries().get().count == 1)
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

    @Test(arguments: [RecordingDragHandoff.Order.writeThenSession, .sessionThenWrite], DragCaptureKind.allCases)
    private func stagingFileIsRemovedOnlyAfterBothDragEvents(order: RecordingDragHandoff.Order, kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff(order: order)
        let seen = FirstEventFiles()
        await handoff.setAfterFirstEvent {
            let files = (try? stagedDragFiles(root: root)) ?? []
            seen.count = files.count
            if let first = files.first, let data = try? Data(contentsOf: first) { seen.bytes = data }
        }
        let commands = makeDragCommands(root: root, handoff: handoff)
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .copied)))
        #expect(seen.count == 1)
        #expect(seen.bytes == source.bytes)
        #expect(try stagedDragFiles(root: root).isEmpty)
        let entry = try #require(try await commands.historyEntries().get().first)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
    }

    @Test(arguments: DragCaptureKind.allCases)
    private func failedPromiseWriteKeepsTheHistoryCommit(kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff(writeFails: true)
        let commands = makeDragCommands(root: root, handoff: handoff)
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .failed)))
        let before = try await commands.historyEntries().get()
        let entry = try #require(before.first)
        #expect(before.count == 1)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        #expect(try stagedDragFiles(root: root).isEmpty)
        #expect(await handoff.bytes() == [source.bytes])
        await handoff.setWriteFails(false)
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .copied)))
        #expect(try await commands.historyEntries().get() == before)
        #expect(try stagedDragFiles(root: root).isEmpty)
    }
}

private enum DragStop: Error { case stop }

extension DragHandoffTests {
    @Test(arguments: [HistoryCommitPoint.dragStaged, .dragPromiseWritten], DragCaptureKind.allCases)
    private func dragFaultLeavesHistoryCommittedAndTheStagingFile(point: HistoryCommitPoint, kind: DragCaptureKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = RecordingDragHandoff()
        let commands = makeDragCommands(root: root, handoff: handoff, commitPoint: { reached in
            if reached == point { throw DragStop.stop }
        })
        let source = DragPixels()
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(kind.command(revision.captureID, maximumBytes: source.bytes.count)) == .pending(revision))
        #expect(await commands.execute(.drag(revision, .copy)) == .drag(DragOutcome(revision: revision, commit: .committed, delivery: .failed)))
        let entries = try await commands.historyEntries().get()
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == source.bytes)
        let staged = try stagedDragFiles(root: root)
        #expect(staged.count == 1)
        #expect(try Data(contentsOf: staged[0]) == source.bytes)
        #expect(await commands.image(for: revision)?.pngData == source.bytes)
        if point == .dragStaged {
            #expect(await handoff.operations().isEmpty)
        } else {
            #expect(await handoff.operations() == [.copy])
        }
    }
}
