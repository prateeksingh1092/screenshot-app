import CoreGraphics
import Foundation
import FrisketCore
import ImageIO
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
    let commands: CaptureLifecycleCoordinator
    let history: HistoryStore

    init(clipboard: any ImageClipboard = StackClipboard(), policy: ThumbnailStackPolicy = ThumbnailStackPolicy(),
         flattener: (any CaptureFlattening)? = nil) {
        let clock = clock
        let history = HistoryStore(root: root)
        self.history = history
        commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: StackPixels(), clipboard: clipboard,
            pendingByteLimit: 1024, history: history, thumbnailPolicy: policy, clock: { clock.now },
            flattener: flattener)
    }

    func capture() async throws -> CaptureRevision {
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        try #require(await commands.execute(.capture(id, maximumBytes: 128)) == .pending(revision))
        return revision
    }

    func historyIDs() async throws -> [CaptureID] {
        try await history.entries().get().map(\.captureID)
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
        // Ticket 91: the copied card stays, finalized, until it leaves.
        #expect(await fixture.commands.execute(.exitThumbnail(second, .close)) == .finalized(second, .committed))
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
        #expect(await fixture.commands.thumbnails().cards == [
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
        // Ticket 91: a committed capture keeps its finalized Thumbnail; an uncommitted one closes.
        let kept = await fixture.commands.thumbnails().first { $0.revision == revision }
        #expect(kept?.status == (historyUnavailable ? nil : .finalized))
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
        #expect(ThumbnailKeys.command(characters: "t", keyCode: 17) == .copyText)
        #expect(ThumbnailKeys.command(characters: "\u{7f}", keyCode: 51) == .deleteCapture)
        #expect(ThumbnailKeys.command(characters: "\u{1b}", keyCode: 53) == .dismiss)
        #expect(ThumbnailKeys.command(characters: "", keyCode: 126) == .older)
        #expect(ThumbnailKeys.command(characters: "", keyCode: 125) == .newer)
        #expect(ThumbnailKeys.command(characters: "c", keyCode: 8, command: true) == nil)
        #expect(ThumbnailKeys.command(characters: "x", keyCode: 7) == nil)
    }
}

extension ThumbnailStackCommandsTests {
    @Test func neverAutoDismissRejectsTimeoutWhileOverflowStillFinalizes() async throws {
        let fixture = StackFixture(policy: ThumbnailStackPolicy(maximumCount: 1, autoDismiss: .never))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.capture()
        fixture.clock.advance(by: .seconds(86_400))
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil])
        #expect(await fixture.commands.execute(.exitThumbnail(first, .timeout)) == .rejected(.thumbnailExitNotDue))
        let second = try await fixture.capture()
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil, .overflow])
        #expect(await fixture.commands.execute(.exitThumbnail(first, .overflow)) == .finalized(first, .committed))
        #expect(await fixture.commands.thumbnails().map(\.revision) == [second])
        #expect(try await fixture.historyIDs() == [first.captureID])
    }

    @Test func zeroSecondDelayTimesOutImmediatelyAndIsNotNever() async throws {
        let fixture = StackFixture(policy: ThumbnailStackPolicy(autoDismiss: .after(.zero)))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [.timeout])
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .timeout)) == .finalized(revision, .committed))
        #expect(try await fixture.historyIDs() == [revision.captureID])
    }

    @Test func preferenceKeepsZeroSecondsDistinctFromNever() {
        #expect(ThumbnailAutoDismissPreference.load(never: false, seconds: 0).autoDismiss == .after(.zero))
        #expect(ThumbnailAutoDismissPreference.load(never: true, seconds: 0).autoDismiss == .never)
        #expect(ThumbnailAutoDismissPreference.load(never: false, seconds: nil).autoDismiss == .after(.seconds(10)))
        #expect(ThumbnailAutoDismissPreference(never: true, seconds: 15).autoDismiss == .never)
        #expect(ThumbnailAutoDismissPreference(never: false, seconds: 15).autoDismiss == .after(.seconds(15)))
    }

    @Test func applyingNeverThenADelayUsesTheNewPolicyOnExistingCards() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        await fixture.commands.setThumbnailPolicy(ThumbnailStackPolicy(autoDismiss: .never))
        fixture.clock.advance(by: ThumbnailStackPolicy().autoDismissDelay)
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil])
        await fixture.commands.setThumbnailPolicy(ThumbnailStackPolicy(autoDismiss: .after(.zero)))
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [.timeout])
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .timeout)) == .finalized(revision, .committed))
    }
}

extension ThumbnailStackCommandsTests {
    @Test func quitFinalizesUneditedThumbnailsOldestFirst() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.capture()
        let second = try await fixture.capture()
        #expect(await fixture.commands.handleSystemEvent(.quit) == [
            .finalized(first, .committed), .finalized(second, .committed)
        ])
        #expect(await fixture.commands.thumbnails().isEmpty)
        #expect(try await fixture.historyIDs() == [first.captureID, second.captureID])
    }

    /// D25: quit tries every Thumbnail; each one History refuses stays pending and is reported.
    @Test func quitTriesEveryCardWhenHistoryIsBlockedAndLeavesThemPending() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.capture()
        let second = try await fixture.capture()
        try Data("blocked history root".utf8).write(to: fixture.root)
        #expect(await fixture.commands.handleSystemEvent(.quit) == [
            .finalized(first, .notCommitted(.historyUnavailable)),
            .finalized(second, .notCommitted(.historyUnavailable))
        ])
        try FileManager.default.removeItem(at: fixture.root)
        #expect(await fixture.commands.thumbnails().map(\.revision) == [second, first])
        #expect(try await fixture.historyIDs().isEmpty)
    }

    @Test func screenLockLeavesPendingAndPausesTimeoutWhileOverflowStillFinalizes() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.capture()
        #expect(await fixture.commands.handleSystemEvent(.screenLocked).isEmpty)
        fixture.clock.advance(by: ThumbnailStackPolicy().autoDismissDelay)
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil])
        #expect(await fixture.commands.execute(.exitThumbnail(first, .timeout)) == .rejected(.thumbnailExitNotDue))
        var newest = first
        for _ in 0..<4 { newest = try await fixture.capture() }
        #expect(await fixture.commands.thumbnails().map(\.dueExit) == [nil, nil, nil, nil, .overflow])
        #expect(await fixture.commands.execute(.exitThumbnail(first, .overflow)) == .finalized(first, .committed))
        #expect(await fixture.commands.thumbnails().first?.revision == newest)
        #expect(await fixture.commands.handleSystemEvent(.screenUnlocked).isEmpty)
        fixture.clock.advance(by: ThumbnailStackPolicy().autoDismissDelay)
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.dueExit == .timeout })
    }

    @Test func unpluggingADisplayMovesItsCardsAndLeavesThemPending() async throws {
        let fixture = StackFixture(policy: ThumbnailStackPolicy(autoDismiss: .never))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let external = try await fixture.capture()
        let builtIn = try await fixture.capture()
        await fixture.commands.assignThumbnailDisplay(external.captureID, displayID: 2)
        await fixture.commands.assignThumbnailDisplay(builtIn.captureID, displayID: 1)
        #expect(await fixture.commands.thumbnails().map(\.displayID) == [1, 2])
        #expect(await fixture.commands.handleSystemEvent(.displaysChanged(remaining: [1])).isEmpty)
        #expect(await fixture.commands.thumbnails().map(\.displayID) == [1, 1])
        #expect(await fixture.commands.thumbnails().map(\.revision) == [builtIn, external])
        #expect(try await fixture.historyIDs().isEmpty)
        fixture.clock.advance(by: .seconds(86_400))
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.dueExit == nil })
    }

    @Test func crashLosesUneditedPendingCapturesAndWritesNothing() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.image(for: revision)?.pngData == StackPixels.bytes)
        #expect(try await fixture.historyIDs().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("history.sqlite").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("images").path))
    }
}

/// A synthetic noise PNG, too large for a small History limit. No screen content.
private func noisePNG(width: Int, height: Int) throws -> Data {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for index in stride(from: 0, to: bytes.count, by: 4) {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        bytes[index] = UInt8(truncatingIfNeeded: state)
        bytes[index + 1] = UInt8(truncatingIfNeeded: state >> 8)
        bytes[index + 2] = UInt8(truncatingIfNeeded: state >> 16)
    }
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

/// The first capture is too large for History's size limit; later ones are the small stack PNG.
private actor OversizedFirstPixels: CapturePixelSource {
    private let oversized: Data
    private var captures = 0
    init(oversized: Data) { self.oversized = oversized }
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        captures += 1
        return .success(CaptureImage(pngData: captures == 1 ? oversized : StackPixels.bytes))
    }
}

extension ThumbnailStackCommandsTests {
    /// D25: quit finalizes every Thumbnail it can and reports the rest, instead of stopping at the
    /// first capture History refuses and silently leaving later captures unfinalized.
    @Test func d25QuitFinalizesEveryCaptureItCanAndReportsTheRest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let oversizedPNG = try noisePNG(width: 700, height: 700)
        #expect(oversizedPNG.count > 1_000_000)
        let history = HistoryStore(root: root, limits: HistoryLimits(maximumBytes: 1_000_000))
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: OversizedFirstPixels(oversized: oversizedPNG),
            clipboard: StackClipboard(), pendingByteLimit: 8_000_000,
            history: history)
        let oversized = CaptureRevision(captureID: CaptureID(), number: 1)
        let small = CaptureRevision(captureID: CaptureID(), number: 1)
        #expect(await commands.execute(.capture(oversized.captureID, maximumBytes: 4_000_000)) == .pending(oversized))
        #expect(await commands.execute(.capture(small.captureID, maximumBytes: 4_000_000)) == .pending(small))

        let outcomes = await commands.handleSystemEvent(.quit)
        #expect(outcomes == [.finalized(oversized, .notCommitted(.captureExceedsHistoryLimit)), .finalized(small, .committed)],
                "D25: quit stopped at the first capture History refused")
        let committed = try await history.entries().get().map(\.captureID)
        #expect(committed == [small.captureID], "D25: a capture History could accept was left unfinalized at quit")
    }
}

private struct DisplayPixels: CapturePixelSource {
    let displayID: UInt32?
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: StackPixels.bytes, displayID: displayID))
    }
}

extension ThumbnailStackCommandsTests {
    /// Ticket 75: the capture itself names its display; no side channel reports it afterwards.
    @Test(arguments: [UInt32(2), nil])
    func thumbnailAppearsOnTheDisplayTheCaptureCameFrom(display: UInt32?) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = HistoryStore(root: root)
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: DisplayPixels(displayID: display),
            clipboard: StackClipboard(), pendingByteLimit: 1024, history: history)
        let id = CaptureID()
        try #require(await commands.execute(.capture(id, maximumBytes: 128)) == .pending(CaptureRevision(captureID: id, number: 1)))
        #expect(await commands.thumbnails().map(\.displayID) == [display])
        #expect(await commands.image(for: CaptureRevision(captureID: id, number: 1))?.displayID == display)
    }
}

/// Ticket 73: the core reports each Thumbnail's status, so the UI never guesses it from an outcome.
extension ThumbnailStackCommandsTests {
    @Test func thumbnailStatusIsPendingUntilHistoryCommitsThenFinalizedWithNoEditOrDelete() async throws {
        let fixture = StackFixture(clipboard: FailingOnceClipboard())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        let pending = try #require(await fixture.commands.thumbnails().first)
        #expect(pending.status == .pending)
        #expect(pending.editable)

        // History commits before the clipboard write fails, so the Thumbnail stays open, finalized.
        guard case .copy(let outcome) = await fixture.commands.execute(.copy(revision)) else {
            Issue.record("Copy did not report a copy outcome")
            return
        }
        #expect(outcome.commit == .committed)
        let finalized = try #require(await fixture.commands.thumbnails().first)
        #expect(finalized.revision == revision)
        #expect(finalized.status == .finalized)
        #expect(!finalized.editable)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .delete)) == .rejected(.alreadyFinalized))

        // Close works on a finalized Thumbnail: it releases the card and the pixels.
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .close)) == .finalized(revision, .committed))
        #expect(await fixture.commands.thumbnails().isEmpty)
        #expect(await fixture.commands.image(for: revision) == nil)
        #expect(try await fixture.historyIDs() == [revision.captureID])
    }

    @Test func thumbnailsReportTheNextDueTimeUnlessTimeoutIsPausedOrNever() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let start = fixture.clock.now
        _ = try await fixture.capture()
        fixture.clock.advance(by: .seconds(1))
        _ = try await fixture.capture()
        #expect(await fixture.commands.thumbnails().nextDueAt == start + delay)

        await fixture.commands.setThumbnailStackFocus(true)
        #expect(await fixture.commands.thumbnails().nextDueAt == nil)
        await fixture.commands.setThumbnailStackFocus(false)
        #expect(await fixture.commands.thumbnails().nextDueAt == start + delay)

        await fixture.commands.setThumbnailPolicy(ThumbnailStackPolicy(autoDismiss: .never))
        #expect(await fixture.commands.thumbnails().nextDueAt == nil)
    }

    @Test func aThumbnailWaitingForARetryHasNoDueTime() async throws {
        let fixture = StackFixture(clipboard: FailingOnceClipboard())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        _ = await fixture.commands.execute(.copy(revision))
        let thumbnails = await fixture.commands.thumbnails()
        #expect(thumbnails.first?.automaticExitSuppressed == true)
        #expect(thumbnails.nextDueAt == nil)
    }
}

/// Ticket 91: a finalized Thumbnail stays until its timeout, a Close or overflow, and an open
/// editor pauses its timeout; leaving the editor restarts it in full.
extension ThumbnailStackCommandsTests {
    @Test(arguments: [ThumbnailExit.timeout, .close])
    func copyKeepsAFinalizedThumbnailUntilItsTimeoutOrClose(exit: ThumbnailExit) async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let start = fixture.clock.now
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))

        let after = await fixture.commands.thumbnails()
        #expect(after.map(\.revision) == [revision])
        #expect(after.first?.status == .finalized)
        #expect(after.first?.editable == false)
        #expect(after.first?.dueExit == nil)
        #expect(after.nextDueAt == start + delay)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .delete)) == .rejected(.alreadyFinalized))
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .timeout)) == .rejected(.thumbnailExitNotDue))
        // The kept card still delivers, now from History.
        #expect(await fixture.commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await fixture.commands.thumbnails().count == 1)

        if exit == .timeout {
            fixture.clock.advance(by: delay)
            #expect(await fixture.commands.thumbnails().first?.dueExit == .timeout)
        }
        #expect(await fixture.commands.execute(.exitThumbnail(revision, exit)) == .finalized(revision, .committed))
        #expect(await fixture.commands.thumbnails().isEmpty)
        #expect(try await fixture.historyIDs() == [revision.captureID])
    }

    @Test func anOpenEditorPausesTheTimeoutAndDoneRestartsItInFull() async throws {
        let fixture = StackFixture(flattener: ScriptedFlattener(always: StackPixels.bytes))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let revision = try await fixture.capture()
        await fixture.commands.setEditorOpen(true, for: revision.captureID)
        #expect(await fixture.commands.thumbnails().nextDueAt == nil)

        fixture.clock.advance(by: .seconds(12))
        #expect(await fixture.commands.thumbnails().first?.dueExit == nil)
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .timeout)) == .rejected(.thumbnailExitNotDue))

        let edits = try #require(DocumentEdits(scale: 1))
        let edited = CaptureRevision(captureID: revision.captureID, number: 2)
        #expect(await fixture.commands.execute(.done(revision, edits)) == .edited(edited, .committed))
        await fixture.commands.setEditorOpen(false, for: revision.captureID)
        let restarted = fixture.clock.now
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == [edited])
        #expect(cards.first?.status == .finalized)
        #expect(cards.first?.dueExit == nil)
        #expect(cards.first?.expiresAt == restarted + delay)
        #expect(cards.nextDueAt == restarted + delay)

        fixture.clock.advance(by: delay)
        #expect(await fixture.commands.thumbnails().first?.dueExit == .timeout)
        #expect(await fixture.commands.execute(.exitThumbnail(edited, .timeout)) == .finalized(edited, .committed))
        #expect(await fixture.commands.thumbnails().isEmpty)
    }

    @Test func closingAnUnchangedEditorKeepsTheThumbnailAndRestartsItsTimeout() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let revision = try await fixture.capture()
        await fixture.commands.setEditorOpen(true, for: revision.captureID)
        fixture.clock.advance(by: .seconds(12))
        // The editor's Close finalizes an unchanged capture (EditorLeave.finalize(nil)).
        #expect(await fixture.commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        await fixture.commands.setEditorOpen(false, for: revision.captureID)
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == [revision])
        #expect(cards.first?.status == .finalized)
        #expect(cards.first?.expiresAt == fixture.clock.now + delay)
        #expect(cards.first?.dueExit == nil)
        #expect(try await fixture.historyIDs() == [revision.captureID])
    }

    @Test func aQuickEditStillReturnsAFinalizedThumbnail() async throws {
        let fixture = StackFixture(flattener: ScriptedFlattener(always: StackPixels.bytes))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let revision = try await fixture.capture()
        await fixture.commands.setEditorOpen(true, for: revision.captureID)
        fixture.clock.advance(by: .seconds(1))
        let edited = CaptureRevision(captureID: revision.captureID, number: 2)
        #expect(await fixture.commands.execute(.done(revision, try #require(DocumentEdits(scale: 1))))
                == .edited(edited, .committed))
        await fixture.commands.setEditorOpen(false, for: revision.captureID)
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == [edited])
        #expect(cards.first?.status == .finalized)
        #expect(cards.first?.expiresAt == fixture.clock.now + delay)
        // Copy from the edited card keeps it listed too.
        #expect(await fixture.commands.execute(.copy(edited)) == .copy(CopyOutcome(revision: edited,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await fixture.commands.thumbnails().map(\.revision) == [edited])
    }

    /// Ticket 95: overflow exits the oldest other card while the editor is open for a capture.
    @Test func overflowSparesTheCaptureBeingEditedAndExitsTheOldestOtherCard() async throws {
        let fixture = StackFixture(flattener: ScriptedFlattener(always: StackPixels.bytes))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let maximum = ThumbnailStackPolicy().maximumCount
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let editing = try await fixture.capture()
        await fixture.commands.setEditorOpen(true, for: editing.captureID)
        var others: [CaptureRevision] = []
        for _ in 0..<maximum { others.append(try await fixture.capture()) }

        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == others.reversed() + [editing])
        #expect(cards.map(\.dueExit) == Array(repeating: nil, count: maximum - 1) + [.overflow, nil])
        #expect(await fixture.commands.execute(.exitThumbnail(editing, .overflow)) == .rejected(.thumbnailExitNotDue))
        #expect(await fixture.commands.execute(.exitThumbnail(others[0], .overflow)) == .finalized(others[0], .committed))
        #expect(await fixture.commands.thumbnails().allSatisfy { $0.dueExit == nil })

        // Done then leaving the editor: the card stays and its timeout restarts in full (decision 76).
        fixture.clock.advance(by: .seconds(1))
        let edited = CaptureRevision(captureID: editing.captureID, number: 2)
        #expect(await fixture.commands.execute(.done(editing, try #require(DocumentEdits(scale: 1))))
                == .edited(edited, .committed))
        await fixture.commands.setEditorOpen(false, for: editing.captureID)
        let after = await fixture.commands.thumbnails()
        #expect(after.map(\.revision) == others.dropFirst().reversed() + [edited])
        #expect(after.allSatisfy { $0.dueExit == nil })
        #expect(after.last?.expiresAt == fixture.clock.now + delay)
    }

    @Test func quitAndHistoryDeleteCloseAKeptThumbnail() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let quitting = try await fixture.capture()
        let deleting = try await fixture.capture()
        for revision in [quitting, deleting] {
            #expect(await fixture.commands.execute(.copy(revision)) == .copy(CopyOutcome(revision: revision,
                commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        }
        #expect(await fixture.commands.thumbnails().count == 2)
        #expect(await fixture.commands.execute(.deleteHistory(deleting.captureID)) == .historyDeleted(deleting.captureID))
        #expect(await fixture.commands.thumbnails().map(\.revision) == [quitting])
        #expect(await fixture.commands.handleSystemEvent(.quit) == [.finalized(quitting, .committed)])
        #expect(await fixture.commands.thumbnails().isEmpty)
    }

    // Ticket 79 (story 98, DA-10, decision 28): History restores an item to a kept, finalized Thumbnail.
    @Test func aRestoredHistoryItemIsAFinalizedThumbnailWithoutEdit() async throws {
        let fixture = StackFixture(flattener: ScriptedFlattener(always: StackPixels.bytes))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let revision = try await fixture.capture()
        let edits = try #require(DocumentEdits(scale: 1))
        let edited = CaptureRevision(captureID: revision.captureID, number: 2)
        #expect(await fixture.commands.execute(.done(revision, edits)) == .edited(edited, .committed))
        #expect(await fixture.commands.execute(.exitThumbnail(edited, .close)) == .finalized(edited, .committed))
        #expect(await fixture.commands.thumbnails().isEmpty)

        #expect(await fixture.commands.execute(.restoreFromHistory(revision.captureID)) == .restored(edited))
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == [edited])
        #expect(cards.first?.status == .finalized)
        #expect(cards.first?.editable == false)
        #expect(cards.first?.expiresAt == fixture.clock.now + delay)
        #expect(cards.nextDueAt == fixture.clock.now + delay)
        // Nothing comes back into memory: the card delivers from History, and Edit is refused.
        #expect(await fixture.commands.image(for: edited) == nil)
        #expect(await fixture.commands.execute(.done(edited, edits)) == .rejected(.alreadyFinalized))
        #expect(await fixture.commands.execute(.copy(edited)) == .copy(CopyOutcome(revision: edited,
            commit: .committed, delivery: .copied(ClipboardReceipt(changeCount: 1)))))
        #expect(await fixture.commands.execute(.dismiss(edited)) == .rejected(.alreadyFinalized))

        fixture.clock.advance(by: delay)
        #expect(await fixture.commands.thumbnails().first?.dueExit == .timeout)
        #expect(await fixture.commands.execute(.exitThumbnail(edited, .timeout)) == .finalized(edited, .committed))
        #expect(await fixture.commands.thumbnails().isEmpty)
        #expect(try await fixture.historyIDs() == [revision.captureID])
    }

    @Test(arguments: [ThumbnailExit.close, .swipe, .escape, .overflow])
    func leavingARestoredThumbnailNeverAddsASecondHistoryRow(exit: ThumbnailExit) async throws {
        let fixture = StackFixture(policy: ThumbnailStackPolicy(maximumCount: 1))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .close)) == .finalized(revision, .committed))
        // A new session (say, after a relaunch) restores an item it never captured.
        let session = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: StackPixels(),
            clipboard: StackClipboard(), pendingByteLimit: 1024, history: fixture.history,
            thumbnailPolicy: ThumbnailStackPolicy(maximumCount: 1), clock: { fixture.clock.now })
        #expect(await session.execute(.restoreFromHistory(revision.captureID)) == .restored(revision))
        if exit == .overflow {
            let newer = CaptureID()
            #expect(await session.execute(.capture(newer, maximumBytes: 128)) == .pending(CaptureRevision(captureID: newer, number: 1)))
            #expect(await session.thumbnails().first { $0.revision == revision }?.dueExit == .overflow)
        }
        #expect(await session.execute(.exitThumbnail(revision, exit)) == .finalized(revision, .committed))
        #expect(await session.thumbnails().allSatisfy { $0.revision != revision })
        #expect(try await fixture.historyIDs() == [revision.captureID])
        #expect(await session.handleSystemEvent(.quit).allSatisfy { $0 != .finalized(revision, .committed) })
        #expect(try await fixture.historyIDs().filter { $0 == revision.captureID }.count == 1)
    }

    @Test func restoringTwiceKeepsOneThumbnailAndRestartsItsTimeout() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let delay = ThumbnailStackPolicy().autoDismissDelay
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .close)) == .finalized(revision, .committed))
        #expect(await fixture.commands.execute(.restoreFromHistory(revision.captureID)) == .restored(revision))
        fixture.clock.advance(by: .seconds(3))
        #expect(await fixture.commands.execute(.restoreFromHistory(revision.captureID)) == .restored(revision))
        let cards = await fixture.commands.thumbnails()
        #expect(cards.map(\.revision) == [revision])
        #expect(cards.first?.expiresAt == fixture.clock.now + delay)
    }

    @Test func deletingARestoredHistoryItemClosesItsThumbnail() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.exitThumbnail(revision, .close)) == .finalized(revision, .committed))
        #expect(await fixture.commands.execute(.restoreFromHistory(revision.captureID)) == .restored(revision))
        #expect(await fixture.commands.execute(.deleteHistory(revision.captureID)) == .historyDeleted(revision.captureID))
        #expect(await fixture.commands.thumbnails().isEmpty)
        #expect(await fixture.commands.execute(.copy(revision)) == .rejected(.unknownCapture))
        #expect(await fixture.commands.execute(.restoreFromHistory(revision.captureID)) == .rejected(.unknownCapture))
    }

    @Test func aPendingCaptureCannotBeRestored() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revision = try await fixture.capture()
        #expect(await fixture.commands.execute(.restoreFromHistory(revision.captureID)) == .rejected(.unknownCapture))
        #expect(await fixture.commands.execute(.restoreFromHistory(CaptureID())) == .rejected(.unknownCapture))
        #expect(await fixture.commands.thumbnails().map(\.revision) == [revision])
        #expect(try await fixture.historyIDs().isEmpty)
    }
}

extension ThumbnailStackCommandsTests {
    /// D17: Copy Latest and Delete Latest have nothing to act on without a Thumbnail, and Delete Latest
    /// skips a card History already keeps (ticket 81).
    @Test func copyAndDeleteLatestActOnlyWhenThereIsSomethingToActOn() async throws {
        let fixture = StackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(await fixture.commands.thumbnails().latestToCopy == nil)
        #expect(await fixture.commands.thumbnails().latestToDelete == nil)
        let older = try await fixture.capture()
        fixture.clock.advance(by: .milliseconds(10))
        let newer = try await fixture.capture()
        #expect(await fixture.commands.thumbnails().latestToCopy?.revision == newer)
        #expect(await fixture.commands.thumbnails().latestToDelete?.revision == newer)
        guard case .copy = await fixture.commands.execute(.copy(newer)) else { Issue.record("Copy should run"); return }
        // The kept card still copies again from History, but it can't be deleted from the stack.
        #expect(await fixture.commands.thumbnails().latestToCopy?.revision == newer)
        #expect(await fixture.commands.thumbnails().latestToDelete?.revision == older)
        #expect(await fixture.commands.execute(.exitThumbnail(older, .delete)) == .discarded(older.captureID))
        #expect(await fixture.commands.thumbnails().latestToDelete == nil)
    }
}
