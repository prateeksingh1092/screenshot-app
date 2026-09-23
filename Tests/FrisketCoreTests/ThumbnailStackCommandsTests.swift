import Foundation
import FrisketCore
import Synchronization
import Testing

private struct StackPixels: CapturePixelSource {
    // A synthetic 2 x 1 opaque red PNG; no screen content.
    static let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: Self.bytes))
    }
}

private struct StackClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

private final class ManualClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func advance(by duration: Duration) { instant.withLock { $0 = $0.advanced(by: duration) } }
}

private struct StackFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
    let clock = ManualClock()
    let commands: CaptureCommandLayer

    init(clipboard: any ImageClipboard = StackClipboard(), policy: ThumbnailStackPolicy = ThumbnailStackPolicy()) {
        let clock = clock
        commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: StackPixels(), clipboard: clipboard,
            pendingByteLimit: 1024, history: HistoryStore(root: root), thumbnailPolicy: policy, clock: { clock.now })
    }

    func capture() async throws -> CaptureRevision {
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        try #require(await commands.execute(.capture(id, maximumBytes: 128)) == .pending(revision))
        return revision
    }

    func historyIDs() async throws -> [CaptureID] {
        try await commands.historyEntries().get().map(\.captureID)
    }
}

@Suite struct ThumbnailStackCommandsTests {
    @Test(arguments: [ThumbnailExit.swipe, .close, .escape])
    func swipeCloseAndEscapeEachFinalizeTheCardIntoHistory(exit: ThumbnailExit) async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.exitThumbnail(revision, exit)) == .finalized(revision, .committed))
        #expect(try await fixture.historyIDs() == [revision.captureID])
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("images/\(revision.captureID.rawValue.uuidString).png")) == StackPixels.bytes)
        #expect(await fixture.commands.image(for: revision) == nil)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, exit)) == .rejected(.alreadyFinalized))
    }

    @Test func deleteCaptureDiscardsThePendingCaptureAndWritesNothing() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        let stale = CaptureRevision(captureID: revision.captureID, number: 2)
        #expect(await fixture.commands.execute(.exitThumbnail(stale, .delete)) == .rejected(.staleRevision))
        #expect(await fixture.commands.image(for: revision)?.pngData == StackPixels.bytes)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .delete)) == .discarded(revision.captureID))
        #expect(await fixture.commands.image(for: revision) == nil)
        #expect(try await fixture.historyIDs().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .close)) == .rejected(.discardedCapture))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
    }
}

extension ThumbnailStackCommandsTests {
    @Test func overflowFinalizesTheOldestCardOnceTheStackExceedsTheDefaultMaximum() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let maximum = ThumbnailStackPolicy().maximumCount
        var arrivals: [CaptureRevision] = []
        for _ in 0..<maximum { arrivals.append(try await fixture.capture()) }
        #expect(await fixture.commands.thumbnails().map(\.revision) == arrivals.reversed())
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.dueExit == nil })
        #expect(await fixture.commands.execute(.exitThumbnail(arrivals[0], .overflow)) == .rejected(.thumbnailExitNotDue))

        let newest = try await fixture.capture()
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == [newest] + arrivals.reversed())
        #expect(cards.map(\.dueExit) == Array(repeating: nil, count: maximum) + [.overflow])
        #expect(await fixture.commands.execute(.exitThumbnail(arrivals[1], .overflow)) == .rejected(.thumbnailExitNotDue))
        #expect(await fixture.commands.execute(.exitThumbnail(newest, .overflow)) == .rejected(.thumbnailExitNotDue))
        #expect(try await fixture.historyIDs().isEmpty)

        #expect(await fixture.commands.execute(.exitThumbnail(arrivals[0], .overflow)) == .finalized(arrivals[0], .committed))
        #expect(try await fixture.historyIDs() == [arrivals[0].captureID])
        #expect(await fixture.commands.image(for: arrivals[0]) == nil)
        let remaining = await fixture.commands.thumbnails()
        #expect(remaining.map(\.revision) == [newest] + arrivals.dropFirst().reversed())
        #expect(remaining.allSatisfy { $0.dueExit == nil })
    }

    @Test func leavingCardsFreeTheirPlaceInTheStack() async throws {
        let fixture = StackFixture(policy: ThumbnailStackPolicy(maximumCount: 2))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.capture()
        let second = try await fixture.capture()
        #expect(await fixture.commands.execute(.copy(second)) == .copy(CopyOutcome(revision: second,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        let third = try await fixture.capture()
        #expect(await fixture.commands.execute(.exitThumbnail(first, .delete)) == .discarded(first.captureID))
        let fourth = try await fixture.capture()
        #expect(await fixture.commands.thumbnails().map(\.revision) == [fourth, third])
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.dueExit == nil })
        #expect(try await fixture.historyIDs() == [second.captureID])
    }
}

extension ThumbnailStackCommandsTests {
    @Test func timeoutFinalizesEachCardOnlyAfterTheDefaultDelayFromItsOwnArrival() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let start = fixture.clock.now
        let first = try await fixture.capture()
        fixture.clock.advance(by: .seconds(1))
        let second = try await fixture.capture()
        #expect(await fixture.commands.thumbnails() == [
            ThumbnailCard(revision: second, expiresAt: start + .seconds(1) + delay, dueExit: nil),
            ThumbnailCard(revision: first, expiresAt: start + delay, dueExit: nil)
        ])

        fixture.clock.advance(by: delay - .seconds(1) - .milliseconds(1))
        #expect(await fixture.commands.execute(.exitThumbnail(first, .timeout)) == .rejected(.thumbnailExitNotDue))
        #expect(await fixture.commands.image(for: first)?.pngData == StackPixels.bytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))

        fixture.clock.advance(by: .milliseconds(1))
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil, .timeout])
        #expect(await fixture.commands.execute(.exitThumbnail(second, .timeout)) == .rejected(.thumbnailExitNotDue))
        #expect(await fixture.commands.execute(.exitThumbnail(first, .timeout)) == .finalized(first, .committed))
        #expect(try await fixture.historyIDs() == [first.captureID])
        #expect(await fixture.commands.thumbnails().map(\.revision) == [second])

        fixture.clock.advance(by: .seconds(1))
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [.timeout])
        #expect(await fixture.commands.execute(.exitThumbnail(second, .timeout)) == .finalized(second, .committed))
        #expect(try await fixture.historyIDs() == [first.captureID, second.captureID])
        #expect(await fixture.commands.thumbnails().isEmpty)
    }
}

private actor FailingOnceClipboard: ImageClipboard {
    private var attempts = 0
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        attempts += 1
        return attempts == 1 ? .failure(.unavailable) : .success(ClipboardReceipt(changeCount: 2))
    }
}

extension ThumbnailStackCommandsTests {
    @Test(arguments: [false, true])
    func failedCopyDeliveryWaitsForExplicitRetryEvenWhenAutomaticExitsAreDue(historyUnavailable: Bool) async throws {
        let fixture = StackFixture(clipboard: FailingOnceClipboard(), policy: ThumbnailStackPolicy(maximumCount: 1))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        if historyUnavailable { try Data("blocked history root".utf8).write(to: fixture.root) }
        let commit: CommitOutcome = historyUnavailable ? .notCommitted(.historyUnavailable) : .committed
        #expect(await fixture.commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: commit, delivery: .failed(.unavailable))))
        if historyUnavailable { try FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.capture()
        fixture.clock.advance(by: .seconds(10))
        let card = try #require(await fixture.commands.thumbnails().first { $0.revision == revision })
        #expect(card.dueExit == nil)
        #expect(card.automaticExitSuppressed)
        for exit in [ThumbnailExit.timeout, .overflow] {
            #expect(await fixture.commands.execute(.exitThumbnail(revision, exit)) == .rejected(.thumbnailExitNotDue))
        }
        #expect(await fixture.commands.image(for: revision)?.pngData == StackPixels.bytes)
        #expect(try await fixture.historyIDs() == (historyUnavailable ? [] : [revision.captureID]))
        #expect(await fixture.commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: commit, delivery: .copied(ClipboardReceipt(changeCount: 2)))))
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.revision != revision })
        #expect(try await fixture.historyIDs() == (historyUnavailable ? [] : [revision.captureID]))
    }

    @Test(arguments: [ThumbnailExit.timeout, .overflow])
    func failedDismissalWaitsForExplicitCloseAfterHistoryRecovers(exit: ThumbnailExit) async throws {
        let fixture = StackFixture(policy: ThumbnailStackPolicy(maximumCount: 1))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        if exit == .overflow { _ = try await fixture.capture() }
        fixture.clock.advance(by: .seconds(10))
        try Data("blocked history root".utf8).write(to: fixture.root)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, exit)) ==
            .finalized(revision, .notCommitted(.historyUnavailable)))
        try FileManager.default.removeItem(at: fixture.root)
        let card = try #require(await fixture.commands.thumbnails().first { $0.revision == revision })
        #expect(card.dueExit == nil)
        #expect(card.automaticExitSuppressed)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, exit)) == .rejected(.thumbnailExitNotDue))
        #expect(await fixture.commands.image(for: revision)?.pngData == StackPixels.bytes)
        #expect(try await fixture.historyIDs().isEmpty)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .close)) == .finalized(revision, .committed))
        #expect(try await fixture.historyIDs() == [revision.captureID])
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.revision != revision })
    }

    @Test func deleteStaysRefusedAfterACommittedCopyWhoseDeliveryFailed() async throws {
        let fixture = StackFixture(clipboard: FailingOnceClipboard())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .failed(.unavailable))))
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .delete)) == .rejected(.alreadyFinalized))
        #expect(try await fixture.historyIDs() == [revision.captureID])
        #expect(await fixture.commands.image(for: revision)?.pngData == StackPixels.bytes)
        #expect(await fixture.commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 2)))))
        #expect(try await fixture.historyIDs() == [revision.captureID])
    }
}

extension ThumbnailStackCommandsTests {
    @Test func stackFocusPausesTimeoutWhileOverflowStillFinalizes() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.capture()
        await fixture.commands.setThumbnailStackFocus(true)
        fixture.clock.advance(by: ThumbnailStackPolicy().autoDismissDelay)
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil])
        #expect(await fixture.commands.execute(.exitThumbnail(first, .timeout)) == .rejected(.thumbnailExitNotDue))
        var newest = first
        for _ in 0..<4 { newest = try await fixture.capture() }
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.dueExit) == [nil, nil, nil, nil, .overflow])
        #expect(await fixture.commands.execute(.exitThumbnail(first, .overflow)) == .finalized(first, .committed))
        #expect(await fixture.commands.thumbnails().map(\.revision) == [newest,
            cards[1].revision, cards[2].revision, cards[3].revision])
        await fixture.commands.setThumbnailStackFocus(false)
        fixture.clock.advance(by: ThumbnailStackPolicy().autoDismissDelay)
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [.timeout, .timeout, .timeout, .timeout])
    }

    @Test func focusingTheStackSelectsTheNewestCardAndArrowsMoveBetweenCards() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let older = try await fixture.capture()
        let newest = try await fixture.capture()
        #expect(await fixture.commands.focusedThumbnail() == nil)
        await fixture.commands.setThumbnailStackFocus(true)
        #expect(await fixture.commands.focusedThumbnail() == newest)
        #expect(await fixture.commands.moveThumbnailFocus(.older) == older)
        #expect(await fixture.commands.focusedThumbnail() == older)
        #expect(await fixture.commands.moveThumbnailFocus(.older) == older)
        #expect(await fixture.commands.moveThumbnailFocus(.newer) == newest)
        await fixture.commands.setThumbnailStackFocus(false)
        #expect(await fixture.commands.focusedThumbnail() == nil)
        #expect(await fixture.commands.moveThumbnailFocus(.older) == nil)
    }

    @Test func singleKeysAndArrowsMapToThumbnailCommands() {
        #expect(ThumbnailKeys.command(characters: "c", keyCode: 8) == .copy)
        #expect(ThumbnailKeys.command(characters: "s", keyCode: 1) == .save)
        #expect(ThumbnailKeys.command(characters: "e", keyCode: 14) == .edit)
        #expect(ThumbnailKeys.command(characters: "\u{7f}", keyCode: 51) == .deleteCapture)
        #expect(ThumbnailKeys.command(characters: "\u{1b}", keyCode: 53) == .dismiss)
        #expect(ThumbnailKeys.command(characters: "", keyCode: 126) == .older)
        #expect(ThumbnailKeys.command(characters: "", keyCode: 125) == .newer)
        #expect(ThumbnailKeys.command(characters: "c", keyCode: 8, command: true) == nil)
        #expect(ThumbnailKeys.command(characters: "x", keyCode: 7) == nil)
    }
}
