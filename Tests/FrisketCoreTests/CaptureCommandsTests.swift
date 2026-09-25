import Foundation
import FrisketCore
import Testing
import Synchronization

private struct FixturePixelSource: CapturePixelSource {
    let bytes: Data
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: bytes))
    }
}

private actor RecordingClipboard: ImageClipboard {
    private(set) var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return .success(ClipboardReceipt(changeCount: 41))
    }
}

@Suite struct CaptureCommandsTests {
    @Test func captureThenCopyDeliversOnlyImageDataWithPrivacyFlagsAndReceipt() async throws {
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: FixturePixelSource(bytes: Data([0x89, 0x50, 0x4e, 0x47])),
            clipboard: clipboard, pendingByteLimit: 16
        )
        let id = CaptureID()
        guard case let .pending(revision) = await commands.execute(.capture(id, maximumBytes: 4)) else {
            Issue.record("Expected a pending capture")
            return
        }
        let result = await commands.execute(.copy(revision))
        #expect(result == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable),
            delivery: .copied(ClipboardReceipt(changeCount: 41))
        )))
        let images = await clipboard.images
        let image = try #require(images.first)
        #expect(images.count == 1)
        #expect(image.pngData == Data([0x89, 0x50, 0x4e, 0x47]))
        #expect(image.currentHostOnly)
        #expect(image.concealed)
    }
}

extension CaptureCommandsTests {
    @Test func duplicateAndStaleCommandsCannotDeliverOrReplacePixels() async {
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([1, 2])),
                                            clipboard: clipboard, pendingByteLimit: 16)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.copy(revision)) == .rejected(.unknownCapture))
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .pending(revision))
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .rejected(.duplicateCapture))
        #expect(await commands.execute(.copy(CaptureRevision(captureID: id, number: 2))) == .rejected(.staleRevision))
        _ = await commands.execute(.copy(revision))
        #expect(await commands.execute(.copy(revision)) == .rejected(.alreadyDelivered))
        #expect(await clipboard.images.map(\.pngData) == [Data([1, 2])])
    }
}

private actor RecoveringClipboard: ImageClipboard {
    private(set) var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return images.count == 1 ? .failure(.unavailable) : .success(ClipboardReceipt(changeCount: 72))
    }
}

extension CaptureCommandsTests {
    @Test func failedDeliveryRetriesTheSameRevisionWithoutClaimingACommit() async {
        let clipboard = RecoveringClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([3, 4])),
                                            clipboard: clipboard, pendingByteLimit: 16)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 2))
        #expect(await commands.execute(.retryCopy(revision)) == .rejected(.retryNotAvailable))
        #expect(await commands.execute(.copy(revision)) == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable), delivery: .failed(.unavailable))))
        #expect(await commands.execute(.copy(revision)) == .rejected(.retryRequired))
        #expect(await commands.execute(.retryCopy(CaptureRevision(captureID: id, number: 2))) == .rejected(.staleRevision))
        #expect(await commands.execute(.retryCopy(revision)) == .copy(CopyOutcome(
            revision: revision, commit: .notCommitted(.historyUnavailable),
            delivery: .copied(ClipboardReceipt(changeCount: 72)))))
        #expect(await commands.execute(.retryCopy(revision)) == .rejected(.alreadyDelivered))
        #expect(await clipboard.images.map(\.pngData) == [Data([3, 4]), Data([3, 4])])
    }
}

extension CaptureCommandsTests {
    @Test func discardMakesCommandsStaleAndNeverWritesClipboard() async {
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([5, 6])),
                                            clipboard: clipboard, pendingByteLimit: 16)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.discard(id)) == .rejected(.unknownCapture))
        _ = await commands.execute(.capture(id, maximumBytes: 2))
        #expect(await commands.execute(.discard(id)) == .discarded(id))
        #expect(await commands.execute(.copy(revision)) == .rejected(.discardedCapture))
        #expect(await commands.execute(.retryCopy(revision)) == .rejected(.discardedCapture))
        #expect(await commands.execute(.discard(id)) == .rejected(.discardedCapture))
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .rejected(.discardedCapture))
        #expect(await clipboard.images.isEmpty)
    }
}

extension CaptureCommandsTests {
    @Test func globalBudgetCountsAllPendingBytesAndReleasesOnlyAfterDiscardOrDelivery() async {
        let clipboard = RecoveringClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([7, 8])),
                                            clipboard: clipboard, pendingByteLimit: 4)
        let first = CaptureID(), second = CaptureID(), third = CaptureID()
        let firstRevision = CaptureRevision(captureID: first, number: 1)
        let secondRevision = CaptureRevision(captureID: second, number: 1)
        #expect(await commands.execute(.capture(first, maximumBytes: 4)) == .pending(firstRevision))
        #expect(await commands.execute(.capture(second, maximumBytes: 2)) == .pending(secondRevision))
        #expect(await commands.execute(.capture(third, maximumBytes: 2)) == .rejected(.pendingByteBudgetExceeded))
        _ = await commands.execute(.copy(firstRevision)) // failed delivery still owns its bytes
        #expect(await commands.execute(.capture(third, maximumBytes: 2)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.discard(second)) == .discarded(second))
        #expect(await commands.execute(.capture(third, maximumBytes: 2)) == .pending(CaptureRevision(captureID: third, number: 1)))
        _ = await commands.execute(.retryCopy(firstRevision))
        let fourth = CaptureID()
        #expect(await commands.execute(.capture(fourth, maximumBytes: 2)) == .pending(CaptureRevision(captureID: fourth, number: 1)))
    }
}

extension CaptureCommandsTests {
    @Test func sourceCannotExceedItsByteAllowanceOrConsumeBudgetOnRefusal() async {
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([9, 10, 11])),
                                            clipboard: clipboard, pendingByteLimit: 3)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await commands.execute(.copy(CaptureRevision(captureID: id, number: 1))) == .rejected(.unknownCapture))
        #expect(await commands.execute(.capture(id, maximumBytes: 3)) == .pending(CaptureRevision(captureID: id, number: 1)))
        #expect(await clipboard.images.isEmpty)
    }
}

private actor SuspensionGate {
    private var started = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var blocked: CheckedContinuation<Void, Never>?

    func pauseFirst() async {
        guard !started else { return }
        started = true
        await withCheckedContinuation { continuation in
            blocked = continuation
            for waiter in waiting { waiter.resume() }
            waiting.removeAll()
        }
    }
    func waitUntilBlocked() async {
        if started { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() { blocked?.resume(); blocked = nil }
}

private struct GatedPixelSource: CapturePixelSource {
    let gate: SuspensionGate
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        await gate.pauseFirst()
        return .success(CaptureImage(pngData: Data([12, 13])))
    }
}

extension CaptureCommandsTests {
    @Test func inFlightCaptureReservesGlobalBudgetAndRejectsCommandsForItsIdentifier() async {
        let gate = SuspensionGate()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: GatedPixelSource(gate: gate),
                                            clipboard: RecordingClipboard(), pendingByteLimit: 4)
        let id = CaptureID(), other = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        let capture = Task { await commands.execute(.capture(id, maximumBytes: 4)) }
        await gate.waitUntilBlocked()
        #expect(await commands.execute(.capture(id, maximumBytes: 4)) == .rejected(.commandInProgress))
        #expect(await commands.execute(.copy(revision)) == .rejected(.commandInProgress))
        #expect(await commands.execute(.discard(id)) == .rejected(.commandInProgress))
        #expect(await commands.execute(.capture(other, maximumBytes: 2)) == .rejected(.pendingByteBudgetExceeded))
        await gate.release()
        #expect(await capture.value == .pending(revision))
        #expect(await commands.execute(.capture(other, maximumBytes: 2)) == .pending(CaptureRevision(captureID: other, number: 1)))
    }
}

private actor GatedClipboard: ImageClipboard {
    let gate: SuspensionGate
    private(set) var images: [ClipboardImage] = []
    init(gate: SuspensionGate) { self.gate = gate }
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        await gate.pauseFirst()
        return .success(ClipboardReceipt(changeCount: 90))
    }
}

extension CaptureCommandsTests {
    @Test func inFlightCopyCannotBeDuplicatedRetriedOrDiscarded() async {
        let gate = SuspensionGate()
        let clipboard = GatedClipboard(gate: gate)
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([14, 15])),
                                            clipboard: clipboard, pendingByteLimit: 2)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 2))
        let copy = Task { await commands.execute(.copy(revision)) }
        await gate.waitUntilBlocked()
        #expect(await commands.execute(.copy(revision)) == .rejected(.commandInProgress))
        #expect(await commands.execute(.retryCopy(revision)) == .rejected(.commandInProgress))
        #expect(await commands.execute(.discard(id)) == .rejected(.commandInProgress))
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 2)) == .rejected(.pendingByteBudgetExceeded))
        await gate.release()
        #expect(await copy.value == .copy(CopyOutcome(revision: revision, commit: .notCommitted(.historyUnavailable),
                                                      delivery: .copied(ClipboardReceipt(changeCount: 90)))))
        #expect(await clipboard.images.map(\.pngData) == [Data([14, 15])])
    }
}

extension CaptureCommandsTests {
    @Test(arguments: [Int.min, -1, 0])
    func nonpositiveCaptureAllowanceIsRejectedWithoutConsumingBudget(allowance: Int) async {
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([16])),
                                            clipboard: RecordingClipboard(), pendingByteLimit: 1)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: allowance)) == .rejected(.invalidByteAllowance))
        #expect(await commands.execute(.capture(id, maximumBytes: 1)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }
}

private actor RecoveringPixelSource: CapturePixelSource {
    private var attempt = 0
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        attempt += 1
        if attempt == 1 { return .failure(.unavailable) }
        return .success(CaptureImage(pngData: attempt == 2 ? Data() : Data([17])))
    }
}

extension CaptureCommandsTests {
    @Test func failedOrEmptyCaptureReleasesReservationAndCanBeRetried() async {
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: RecoveringPixelSource(),
                                            clipboard: RecordingClipboard(), pendingByteLimit: 1)
        let id = CaptureID()
        #expect(await commands.execute(.capture(id, maximumBytes: 1)) == .captureFailed(.unavailable))
        #expect(await commands.execute(.capture(id, maximumBytes: 1)) == .captureFailed(.emptyImage))
        #expect(await commands.execute(.capture(id, maximumBytes: 1)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }
}

extension CaptureCommandsTests {
    @Test func plantedPixelsTextAndPathsNeverReachDiagnostics() async throws {
        // Synthetic canaries, not user data. An adapter must never put payloads in diagnostics.
        let text = "CANARY_TEXT_6E9871"
        let path = "/CANARY_HOME_19D2/capture-secret.png"
        let pixels = Data([0xde, 0xad, 0xbe, 0xef]) + Data((text + path).utf8)
        let log = LocalDiagnosticLog()
        let clipboard = RecoveringClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: pixels), clipboard: clipboard,
                                            pendingByteLimit: 1024, diagnostics: log)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        _ = await commands.execute(.capture(id, maximumBytes: 1024))
        _ = await commands.execute(.copy(revision))
        _ = await commands.execute(.retryCopy(revision))
        _ = await commands.execute(.copy(revision))
        let events = await log.entries().map(\.event)
        #expect(events == [
            DiagnosticEvent(name: .capturePending, operation: .capture),
            DiagnosticEvent(name: .deliveryFailed, operation: .copy,
                            error: DiagnosticError(domain: .clipboard, code: .unavailable)),
            DiagnosticEvent(name: .deliverySucceeded, operation: .retryCopy,
                            error: DiagnosticError(domain: .history, code: .unavailable)),
            DiagnosticEvent(name: .commandRejected, operation: .copy,
                            error: DiagnosticError(domain: .lifecycle, code: .alreadyDelivered))
        ])
        let encoded = try JSONEncoder().encode(await log.entries())
        let serialized = String(decoding: encoded, as: UTF8.self)
        #expect(!serialized.contains(text))
        #expect(!serialized.contains("CANARY_HOME_19D2"))
        #expect(!serialized.contains(path))
        #expect(!serialized.contains(pixels.base64EncodedString()))
        #expect(encoded.range(of: Data([0xde, 0xad, 0xbe, 0xef])) == nil)
        #expect(await clipboard.images.map(\.pngData) == [pixels, pixels])
    }
}

private final class TestClock: Sendable {
    private let date: Mutex<Date>
    init(_ value: TimeInterval) { date = Mutex(Date(timeIntervalSince1970: value)) }
    func now() -> Date { date.withLock { $0 } }
    func set(_ value: TimeInterval) { date.withLock { $0 = Date(timeIntervalSince1970: value) } }
}

extension CaptureCommandsTests {
    @Test func localDiagnosticsExpireAtSevenDaysOnReadAndOnWrite() async {
        let clock = TestClock(1_000_000)
        let log = LocalDiagnosticLog(clock: { clock.now() })
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([18])),
                                            clipboard: RecordingClipboard(), pendingByteLimit: 2, diagnostics: log)
        let id = CaptureID()
        _ = await commands.execute(.capture(id, maximumBytes: 1))
        clock.set(1_604_799) // one second before the seven-day boundary
        #expect(await log.entries().map(\.event.name) == [.capturePending])
        clock.set(1_604_800)
        #expect(await log.entries().isEmpty)
        _ = await commands.execute(.discard(id))
        clock.set(2_209_600)
        _ = await commands.execute(.copy(CaptureRevision(captureID: id, number: 1)))
        let entries = await log.entries()
        #expect(entries.map(\.event.name) == [.commandRejected])
        #expect(entries.first?.recordedAt == Date(timeIntervalSince1970: 2_209_600))
    }
}

extension CaptureCommandsTests {
    @Test func doneWithoutAnEditingCodecIsRefusedAndKeepsThePendingCaptureUnchanged() async throws {
        let log = LocalDiagnosticLog()
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([23, 24])),
                                            clipboard: clipboard, pendingByteLimit: 16, diagnostics: log)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 2))
        let redaction = try #require(SolidRedaction(x: 0, y: 0, width: 1, height: 1))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        #expect(await commands.execute(.done(revision, edits)) == .rejected(.editingUnavailable))
        #expect(await commands.image(for: revision)?.pngData == Data([23, 24]))
        #expect(await clipboard.images.isEmpty)
        #expect(await log.entries().last?.event == DiagnosticEvent(name: .commandRejected, operation: .done,
            error: DiagnosticError(domain: .lifecycle, code: .editingUnavailable)))
    }

    @Test func pendingImageQueryIsRevisionBoundAndReleasesAfterCopyOrDiscard() async {
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([21, 22])),
                                            clipboard: RecordingClipboard(), pendingByteLimit: 16)
        let id = CaptureID(), second = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.image(for: revision) == nil)
        _ = await commands.execute(.capture(id, maximumBytes: 2))
        #expect(await commands.image(for: revision)?.pngData == Data([21, 22]))
        #expect(await commands.image(for: CaptureRevision(captureID: id, number: 2)) == nil)
        _ = await commands.execute(.copy(revision))
        #expect(await commands.image(for: revision) == nil)
        _ = await commands.execute(.capture(second, maximumBytes: 2))
        _ = await commands.execute(.discard(second))
        #expect(await commands.image(for: CaptureRevision(captureID: second, number: 1)) == nil)
    }
}

/// Holds one adapter call open so a test can issue a second command while the first is in progress.
private actor Gate {
    private var entered = false
    private var opened = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var held: CheckedContinuation<Void, Never>?

    func pass() async {
        entered = true
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters = []
        guard !opened else { return }
        await withCheckedContinuation { held = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        opened = true
        held?.resume()
        held = nil
    }
}

/// In-memory History whose Delete waits at a gate.
private actor GatedDeleteHistory: CaptureHistory {
    nonisolated let deleteGate = Gate()
    private var stored: [CaptureID: (revision: UInt64, pngData: Data)] = [:]

    func recover() async -> Result<HistoryRecoveryReport, HistoryFailure> { .failure(.unavailable) }
    func availability() async -> HistoryFailure? { nil }
    func finalize(_ request: AuthorizedFinalization) async -> CommitOutcome {
        stored[request.revision.captureID] = (request.revision.number, request.pngData)
        return .committed
    }
    func entries() async -> Result<[HistoryEntry], HistoryFailure> { .success([]) }
    func delete(_ id: CaptureID) async -> Result<Void, HistoryFailure> {
        await deleteGate.pass()
        stored[id] = nil
        return .success(())
    }
    func finalizedImage(_ id: CaptureID) async -> Result<(revision: UInt64, pngData: Data), HistoryFailure> {
        guard let image = stored[id] else { return .failure(.unavailable) }
        return .success(image)
    }
}

private actor GatedImageClipboard: ImageClipboard {
    nonisolated let gate = Gate()
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        await gate.pass()
        return .success(ClipboardReceipt(changeCount: 5))
    }
}

private actor GatedTextRecognizer: TextRecognizer {
    nonisolated let gate = Gate()
    func recognize(_ image: CaptureImage) async -> String {
        await gate.pass()
        return "words"
    }
}

private actor WrittenText: TextClipboard {
    private(set) var texts: [String] = []
    func writeText(_ text: String) async -> Result<ClipboardReceipt, ClipboardFailure> {
        texts.append(text)
        return .success(ClipboardReceipt(changeCount: 9))
    }
}

private struct WordsRecognizer: TextRecognizer {
    func recognize(_ image: CaptureImage) async -> String { "words" }
}

extension CaptureCommandsTests {
    /// D25: Delete from History takes the in-progress guard like every other command, so nothing
    /// can deliver a capture while it is being deleted.
    @Test func d25DeleteFromHistoryTakesTheInProgressGuard() async throws {
        let history = GatedDeleteHistory()
        let clipboard = RecordingClipboard()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([1, 2])),
                                            clipboard: clipboard, pendingByteLimit: 16, history: history)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .pending(revision))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))

        async let deleting = commands.execute(.deleteHistory(id))
        await history.deleteGate.waitUntilEntered()
        let copied = await commands.execute(.copy(revision))
        #expect(copied == .rejected(.commandInProgress), "D25: History Copy ran while the same capture was being deleted")
        let written = await clipboard.images.count
        #expect(written == 0, "D25: pixels of a capture being deleted reached the clipboard")
        await history.deleteGate.open()
        #expect(await deleting == .historyDeleted(id))
    }

    /// D25: Copy Text respects the in-progress guard: it waits its turn behind a Copy of the same capture.
    @Test func d25CopyTextIsRejectedWhileACopyOfTheSameCaptureIsInProgress() async throws {
        let clipboard = GatedImageClipboard()
        let text = WrittenText()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([1, 2])),
                                            clipboard: clipboard, pendingByteLimit: 16,
                                            textRecognizer: WordsRecognizer(), textClipboard: text)
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .pending(revision))

        async let copying = commands.execute(.copy(revision))
        await clipboard.gate.waitUntilEntered()
        let read = await commands.execute(.copyRecognizedText(revision))
        #expect(read == .rejected(.commandInProgress), "D25: Copy Text ran while a Copy of the same capture was in progress")
        let texts = await text.texts
        #expect(texts.isEmpty, "D25: Copy Text wrote the clipboard during another command")
        await clipboard.gate.open()
        #expect(await copying == .copy(CopyOutcome(revision: revision, commit: .notCommitted(.historyUnavailable),
                                                    delivery: .copied(ClipboardReceipt(changeCount: 5)))))
    }

    /// D25: Copy Text takes the in-progress guard, so a Copy of the same capture waits for it.
    @Test func d25CopyIsRejectedWhileCopyTextOfTheSameCaptureIsInProgress() async throws {
        let clipboard = RecordingClipboard()
        let recognizer = GatedTextRecognizer()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: FixturePixelSource(bytes: Data([1, 2])),
                                            clipboard: clipboard, pendingByteLimit: 16,
                                            textRecognizer: recognizer, textClipboard: WrittenText())
        let id = CaptureID()
        let revision = CaptureRevision(captureID: id, number: 1)
        #expect(await commands.execute(.capture(id, maximumBytes: 2)) == .pending(revision))

        async let reading = commands.execute(.copyRecognizedText(revision))
        await recognizer.gate.waitUntilEntered()
        let copied = await commands.execute(.copy(revision))
        #expect(copied == .rejected(.commandInProgress), "D25: Copy ran while Copy Text of the same capture was in progress")
        await recognizer.gate.open()
        _ = await reading
    }
}
