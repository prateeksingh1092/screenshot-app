import Foundation

actor CaptureLifecycleCoordinator {
    private let permission: any CapturePermissionSource
    private let pendingByteLimit: Int
    private var pendingBytes = 0
    private let source: any CapturePixelSource
    private let fullScreenSource: (any CapturePixelSource)?
    private let windowSource: (any CapturePixelSource)?
    private let clipboard: any ImageClipboard
    private let history: (any CaptureHistory)?
    private let exporter: (any CaptureExport)?
    private let drag: (any DragHandoff)?
    private let flattener: (any CaptureFlattening)?
    private let textRecognizer: (any TextRecognizer)?
    private let textClipboard: (any TextClipboard)?
    /// One record per capture whose pixels are in memory, that is, whose Thumbnail is open.
    private var pending: [CaptureID: PendingCapture] = [:]
    /// What stays known about a capture once its pixels are released.
    private var settled: [CaptureID: SettledCapture] = [:]
    /// Transient locks, not states: a command is running on this capture.
    private var inProgress: Set<CaptureID> = []
    /// Captures whose Copy Text is running. Every command waits except Done: the stale-revision
    /// check already drops a Copy Text result that Done overtook (D25).
    private var recognizing: Set<CaptureID> = []
    private var stackFocused = false
    private var focusedCapture: CaptureID?
    private var screenLocked = false
    // Holds exactly the captures in `pending`; update both together.
    private var stack: ThumbnailStack
    private let clock: @Sendable () -> ContinuousClock.Instant

    init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)?,
         windowSource: (any CapturePixelSource)?,
         clipboard: any ImageClipboard, pendingByteLimit: Int, history: (any CaptureHistory)?, exporter: (any CaptureExport)?,
         drag: (any DragHandoff)?,
         thumbnailPolicy: ThumbnailStackPolicy, clock: @escaping @Sendable () -> ContinuousClock.Instant,
         flattener: (any CaptureFlattening)?,
         textRecognizer: (any TextRecognizer)?, textClipboard: (any TextClipboard)?) {
        stack = ThumbnailStack(policy: thumbnailPolicy)
        self.clock = clock
        self.pendingByteLimit = max(0, pendingByteLimit)
        self.permission = permission
        self.source = source
        self.fullScreenSource = fullScreenSource
        self.windowSource = windowSource
        self.clipboard = clipboard
        self.history = history
        self.exporter = exporter
        self.drag = drag
        self.flattener = flattener
        self.textRecognizer = textRecognizer
        self.textClipboard = textClipboard
    }

    func recoverHistory() async -> Result<HistoryRecoveryReport, HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.recover()
    }

    func historyAvailability() async -> HistoryFailure? {
        guard let history else { return .unavailable }
        return await history.availability()
    }

    func maintainHistory(limits: HistoryLimits?) async -> Result<HistoryUsage, HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.maintain(limits: limits)
    }

    func historyStatus(consumeNotice: Bool) async -> Result<HistoryUsage, HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.status(consumeNotice: consumeNotice)
    }

    func historyEntries() async -> Result<[HistoryEntry], HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.entries()
    }

    func historyItems() async -> Result<[HistoryItem], HistoryFailure> {
        switch await historyEntries() {
        case let .success(entries):
            return .success(entries.reversed().map {
                HistoryItem(captureID: $0.captureID, revision: $0.revision, width: $0.width,
                            height: $0.height, finalizedAt: $0.finalizedAt)
            })
        case let .failure(failure):
            return .failure(failure)
        }
    }

    func historyThumbnail(_ id: CaptureID) async -> Data? {
        await history?.thumbnailPNG(id)
    }

    func historyImage(_ id: CaptureID) async -> CaptureImage? {
        guard case let .success((_, pngData)) = await history?.finalizedImage(id) else { return nil }
        return CaptureImage(pngData: pngData)
    }

    func image(for revision: CaptureRevision) -> CaptureImage? {
        guard revision.number == currentRevision(revision.captureID) else { return nil }
        return pending[revision.captureID]?.image
    }

    func setThumbnailStackFocus(_ focused: Bool) {
        stackFocused = focused
        focusedCapture = focused ? stack.cards(at: clock()).first?.revision.captureID : nil
    }

    func focusedThumbnail() -> CaptureRevision? {
        guard stackFocused else { return nil }
        let cards = stack.cards(at: clock())
        if let id = focusedCapture, let card = cards.first(where: { $0.revision.captureID == id }) {
            return card.revision
        }
        focusedCapture = cards.first?.revision.captureID
        return cards.first?.revision
    }

    func moveThumbnailFocus(_ move: ThumbnailFocusMove) -> CaptureRevision? {
        guard stackFocused else { return nil }
        let cards = stack.cards(at: clock())
        guard !cards.isEmpty else {
            focusedCapture = nil
            return nil
        }
        let current = focusedCapture.flatMap { id in cards.firstIndex { $0.revision.captureID == id } } ?? 0
        let next = switch move {
        case .newer: max(current - 1, 0)
        case .older: min(current + 1, cards.count - 1)
        }
        focusedCapture = cards[next].revision.captureID
        return cards[next].revision
    }

    func setThumbnailPolicy(_ policy: ThumbnailStackPolicy) {
        stack.setPolicy(policy)
    }

    func assignThumbnailDisplay(_ id: CaptureID, displayID: UInt32) {
        stack.assignDisplay(id, displayID: displayID)
    }

    func handleSystemEvent(_ event: ThumbnailSystemEvent) async -> [CaptureCommandOutcome] {
        switch event {
        case .quit:
            var outcomes: [CaptureCommandOutcome] = []
            // D25: try every Thumbnail; one that History refuses stays pending and is reported.
            for revision in stack.arrivalOrder() {
                outcomes.append(await execute(.dismiss(revision)))
            }
            return outcomes
        case .screenLocked:
            screenLocked = true
            return []
        case .screenUnlocked:
            screenLocked = false
            return []
        case let .displaysChanged(remaining):
            stack.rehome(remaining: remaining)
            return []
        }
    }

    func thumbnails() -> Thumbnails {
        let now = clock()
        let paused = stackFocused || screenLocked
        let cards = stack.cards(at: now).map { card in
            let record = pending[card.revision.captureID]
            let suppressed = record?.automaticExitSuppressed ?? false
            let pauseTimeout = paused && card.dueExit == .timeout
            let finalized = record?.finalized ?? false
            return ThumbnailCard(revision: card.revision, expiresAt: card.expiresAt,
                                 dueExit: (suppressed || pauseTimeout) ? nil : card.dueExit,
                                 automaticExitSuppressed: suppressed,
                                 displayID: card.displayID,
                                 status: finalized ? .finalized : .pending,
                                 editable: !finalized && record?.recoveryRequired != true)
        }
        let timing = cards.filter { $0.dueExit == nil && !$0.automaticExitSuppressed }
        let nextDueAt = paused ? nil : timing.compactMap(\.expiresAt).filter { $0 > now }.min()
        return Thumbnails(cards: cards, nextDueAt: nextDueAt)
    }

    func execute(_ command: CaptureCommand) async -> CaptureCommandOutcome {
        switch command {
        case let .dismiss(revision):
            let id = revision.captureID
            guard !isBusy(id) else { return .rejected(.commandInProgress) }
            guard !isDiscarded(id) else { return .rejected(.discardedCapture) }
            guard pending[id] != nil || isFinalized(id) else { return .rejected(.unknownCapture) }
            guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
            guard pending[id]?.unfinishedRedaction != true else { return .rejected(.editingUnavailable) }
            guard let record = pending[id] else { return .rejected(.alreadyFinalized) }
            inProgress.insert(id)
            let outcome: CommitOutcome
            if record.finalized { outcome = .committed }
            else {
                outcome = await history?.finalize(AuthorizedFinalization(revision: revision, pngData: record.image.pngData))
                    ?? .notCommitted(.historyUnavailable)
            }
            if outcome == .notCommitted(.recoveryRequired) { pending[id]?.recoveryRequired = true }
            if outcome == .committed {
                pending[id]?.finalized = true
                release(id)
            } else {
                pending[id]?.automaticExitSuppressed = true
            }
            inProgress.remove(id)
            return .finalized(revision, outcome)
        case let .done(revision, edits), let .render(revision, edits):
            let commits: Bool = if case .done = command { true } else { false }
            let id = revision.captureID
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }   // not isBusy: Done may run during Copy Text, whose result the stale check drops
            guard !isDiscarded(id) else { return .rejected(.discardedCapture) }
            guard pending[id] != nil || isFinalized(id) || isDelivered(id) else { return .rejected(.unknownCapture) }
            guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
            guard !isFinalized(id) else { return .rejected(.alreadyFinalized) }
            guard !needsRecovery(id) else { return .rejected(.editingUnavailable) }
            guard let image = pending[id]?.image else { return .rejected(.alreadyDelivered) }
            // Once redaction is submitted, a rejected render must not expose the
            // original to delivery or History. Only an accepted Done or Delete resolves it.
            if !edits.redactions.isEmpty { pending[id]?.unfinishedRedaction = true }
            // Synchronous on purpose: no suspension separates the guards above from the
            // replacement below. If flatten ever becomes async, insert `inProgress` before the await.
            guard let flattener, let pngData = try? flattener.flatten(image.pngData, edits: edits),
                  !pngData.isEmpty else { return .rejected(.editingUnavailable) }
            guard pngData.count <= pendingByteLimit - (pendingBytes - image.pngData.count) else {
                return .rejected(.pendingByteBudgetExceeded)
            }
            let next = CaptureRevision(captureID: id, number: revision.number + 1)
            // The rendered revision replaces the original before any suspension, so no
            // later command, retry or History commit can reach the unredacted pixels.
            pendingBytes += pngData.count - image.pngData.count
            pending[id]?.image = CaptureImage(pngData: pngData)
            pending[id]?.revision = next.number
            stack.replace(next)
            pending[id]?.unfinishedRedaction = false
            // Retry state belonged to the previous revision's Copy.
            pending[id]?.failedDeliveries = []
            pending[id]?.deliveryCommit = nil
            pending[id]?.delivered = false
            inProgress.insert(id)
            var clipboardFailure: ClipboardFailure?
            if !edits.redactions.isEmpty, let receipt = pending[id]?.copyReceipt {
                // Do this even if History is unavailable; clipboard privacy is independent
                // of persistence. The adapter checks and writes without a suspension.
                switch await clipboard.write(ClipboardImage(pngData: pngData, replacing: receipt)) {
                case let .success(replacement):
                    pending[id]?.copyReceipt = replacement
                case .failure(.changed):
                    pending[id]?.copyReceipt = nil
                case .failure(.unavailable):
                    clipboardFailure = .unavailable
                }
            }
            guard commits else {
                inProgress.remove(id)
                return .rendered(next, clipboardFailure: clipboardFailure)
            }
            let commit = await history?.finalize(AuthorizedFinalization(revision: next, pngData: pngData))
                ?? .notCommitted(.historyUnavailable)
            if commit == .committed { pending[id]?.finalized = true }
            if commit == .notCommitted(.recoveryRequired) { pending[id]?.recoveryRequired = true }
            if isFinalized(id) || needsRecovery(id) { pending[id]?.copyReceipt = nil }
            if commit != .committed { pending[id]?.automaticExitSuppressed = true }
            inProgress.remove(id)
            return .edited(next, commit, clipboardFailure: clipboardFailure)
        case let .discard(id):
            guard !isBusy(id) else { return .rejected(.commandInProgress) }
            guard !isDiscarded(id) else { return .rejected(.discardedCapture) }
            guard !isFinalized(id) else { return .rejected(.alreadyFinalized) }
            guard pending[id] != nil else {
                return .rejected(isDelivered(id) ? .alreadyDelivered : .unknownCapture)
            }
            release(id, discarded: true)
            return .discarded(id)
        case let .deleteHistory(id):
            guard !isBusy(id) else { return .rejected(.commandInProgress) }
            // A pending capture has no History row. A finalized one may still have its Thumbnail open.
            guard pending[id] == nil || isFinalized(id) else { return .rejected(.alreadyFinalized) }
            inProgress.insert(id)   // D25: nothing else may use this capture while it is deleted
            let deleted = await history?.delete(id)
            inProgress.remove(id)
            switch deleted {
            case .success:
                release(id)   // D10: Delete closes the capture's open Thumbnail and releases its pixels
                return .historyDeleted(id)
            case .failure, nil: return .rejected(.unknownCapture)
            }
        case let .capture(id, maximumBytes), let .captureFullScreen(id, maximumBytes), let .captureWindow(id, maximumBytes):
            guard !isBusy(id) else { return .rejected(.commandInProgress) }
            guard !isDiscarded(id) else { return .rejected(.discardedCapture) }
            guard pending[id] == nil, settled[id] == nil else { return .rejected(.duplicateCapture) }
            guard maximumBytes > 0 else { return .rejected(.invalidByteAllowance) }
            guard maximumBytes <= pendingByteLimit - pendingBytes else {
                return .rejected(.pendingByteBudgetExceeded)
            }
            let captureSource: any CapturePixelSource
            if case .captureFullScreen = command {
                guard let fullScreenSource else { return .captureFailed(.unavailable) }
                captureSource = fullScreenSource
            } else if case .captureWindow = command {
                guard let windowSource else { return .captureFailed(.unavailable) }
                captureSource = windowSource
            } else {
                captureSource = source
            }
            pendingBytes += maximumBytes
            inProgress.insert(id)
            let access = await permission.capturePermission()
            guard access == .granted else {
                pendingBytes -= maximumBytes
                inProgress.remove(id)
                return .permissionRequired(access)
            }
            let result = await captureSource.capture(maximumBytes: maximumBytes)
            pendingBytes -= maximumBytes
            inProgress.remove(id)
            switch result {
            case let .success(image):
                guard !image.pngData.isEmpty else { return .captureFailed(.emptyImage) }
                guard image.pngData.count <= maximumBytes else { return .rejected(.pendingByteBudgetExceeded) }
                pendingBytes += image.pngData.count
                pending[id] = PendingCapture(image: image)
                stack.insert(CaptureRevision(captureID: id, number: 1), at: clock())
                if let display = image.displayID { stack.assignDisplay(id, displayID: display) }
                return .pending(CaptureRevision(captureID: id, number: 1))
            case let .failure(.permissionRequired(state)):
                return .permissionRequired(state)
            case let .failure(error):
                return .captureFailed(error)
            }
        case let .copyRecognizedText(revision):
            return await copyRecognizedText(revision)
        case let .copy(revision), let .retryCopy(revision):
            let retrying: Bool = if case .retryCopy = command { true } else { false }
            return await deliver(revision, kind: .copy, retrying: retrying,
                using: { [clipboard] request in await clipboard.write(ClipboardImage(pngData: request.pngData)) },
                outcome: { commit, result in
                    let delivery: DeliveryOutcome
                    switch result {
                    case let .success(receipt): delivery = .copied(receipt)
                    case let .failure(error): delivery = .failed(error)
                    }
                    return .copy(CopyOutcome(revision: revision, commit: commit ?? .notCommitted(.historyUnavailable),
                                             delivery: delivery))
                })
        case let .save(revision), let .retrySave(revision):
            let retrying: Bool = if case .retrySave = command { true } else { false }
            return await deliver(revision, kind: .save, retrying: retrying,
                using: { [exporter] request in await exporter?.export(request) ?? .failure(.unavailable) },
                outcome: { commit, result in
                    let delivery: SaveDeliveryOutcome
                    switch result {
                    case let .success(receipt): delivery = .saved(receipt)
                    case let .failure(error): delivery = .failed(error)
                    }
                    return .save(SaveOutcome(revision: revision, commit: commit ?? .notCommitted(.historyUnavailable),
                                             delivery: delivery))
                })
        case let .exitThumbnail(revision, exit):
            let id = revision.captureID
            if let record = pending[id], !isBusy(id) {
                guard revision.number == record.revision else { return .rejected(.staleRevision) }
                guard !record.unfinishedRedaction else { return .rejected(.editingUnavailable) }
                if exit == .timeout || exit == .overflow {
                    guard !record.automaticExitSuppressed else { return .rejected(.thumbnailExitNotDue) }
                }
                if exit == .timeout {
                    guard !stackFocused, !screenLocked else { return .rejected(.thumbnailExitNotDue) }
                }
                guard stack.admits(exit, for: id, at: clock()) else { return .rejected(.thumbnailExitNotDue) }
            }
            switch exit.outcome {
            case .finalizeToHistory: return await execute(.dismiss(revision))
            case .discard: return await execute(.discard(id))
            }
        case let .drag(revision, operation):
            guard operation == .copy else { return .rejected(.dragOperationRefused) }
            // DA-3: hand off first. The promised file is written from memory, and only a drop
            // the destination accepted authorizes finalization.
            return await deliver(revision, kind: .drag, retrying: false,
                using: { [drag] request in
                    let delivery = (try? await drag?.deliver(.copy, image: DragImage(pngData: request.pngData),
                                                             events: DragSessionEvents())) ?? .failed
                    return delivery == .copied ? .success(delivery) : .failure(DragNotAccepted())
                },
                outcome: { commit, result in
                    .drag(DragOutcome(revision: revision, commit: commit, delivery: (try? result.get()) ?? .failed))
                })
        }
    }

    /// Every delivery (Copy, Save and drag) shares authorization, commit caching, retry gating and byte ownership.
    /// Copy and Save commit before the adapter write. A drag commits only after the destination accepted
    /// the drop (DA-3), and has no retry gate: dragging again is the retry.
    private func deliver<Receipt: Sendable, Failure: Error & Sendable>(
        _ revision: CaptureRevision, kind: DeliveryKind, retrying: Bool,
        using operation: @Sendable (AuthorizedFinalization) async -> Result<Receipt, Failure>,
        outcome: (CommitOutcome?, Result<Receipt, Failure>) -> CaptureCommandOutcome
    ) async -> CaptureCommandOutcome {
        let id = revision.captureID
        guard !isBusy(id) else { return .rejected(.commandInProgress) }
        guard !isDiscarded(id) else { return .rejected(.discardedCapture) }
        let pngData: Data
        let fromHistory: Bool
        if let record = pending[id] {
            guard revision.number == record.revision else { return .rejected(.staleRevision) }
            guard !record.unfinishedRedaction else { return .rejected(.editingUnavailable) }
            guard !record.delivered else { return .rejected(.alreadyDelivered) }
            pngData = record.image.pngData
            fromHistory = false
        } else {
            switch await history?.finalizedImage(id) {
            case let .success((number, data)):
                guard revision.number == number else { return .rejected(.staleRevision) }
                pngData = data
                fromHistory = true
            default:
                return .rejected(isDelivered(id) ? .alreadyDelivered : .unknownCapture)
            }
        }
        if kind != .drag {
            let previouslyFailed = pending[id]?.failedDeliveries.contains(kind) == true
            if fromHistory {
                // History delivery is a new adapter write each time; retry belongs to pending captures.
                if retrying { return .rejected(.retryNotAvailable) }
            } else if retrying {
                guard previouslyFailed else { return .rejected(.retryNotAvailable) }
            } else if previouslyFailed {
                return .rejected(.retryRequired)
            }
        }
        inProgress.insert(id)
        defer { inProgress.remove(id) }
        let request = AuthorizedFinalization(revision: revision, pngData: pngData)
        var commit: CommitOutcome? = fromHistory ? .committed : nil
        if kind != .drag, !fromHistory { commit = await commitOnce(request) }
        let result = await operation(request)
        if fromHistory { return outcome(commit, result) }
        switch result {
        case let .success(receipt):
            if kind == .drag { commit = await commitOnce(request) }
            pending[id]?.failedDeliveries = []
            pending[id]?.delivered = true
            // A failed History commit leaves an editable Pending capture when a flattener
            // can replace the earlier copy. Keep its byte charge and receipt.
            if kind == .copy, commit != .committed, !needsRecovery(id), flattener != nil,
               let copyReceipt = receipt as? ClipboardReceipt {
                pending[id]?.copyReceipt = copyReceipt
                pending[id]?.automaticExitSuppressed = true
            } else {
                release(id)
            }
        case .failure:
            if kind == .drag {
                // A cancelled or failed drag commits nothing: the capture stays pending and its Thumbnail stays open.
                commit = isFinalized(id) ? .committed : pending[id]?.deliveryCommit
            } else {
                pending[id]?.failedDeliveries.insert(kind)
            }
            pending[id]?.automaticExitSuppressed = true
        }
        return outcome(commit, result)
    }

    /// The first delivery of a revision asks History to commit it; a retry or later delivery
    /// reuses that outcome, including a failed one.
    private func commitOnce(_ request: AuthorizedFinalization) async -> CommitOutcome {
        let id = request.revision.captureID
        let commit: CommitOutcome
        if let prior = pending[id]?.deliveryCommit {
            commit = prior
        } else if isFinalized(id) {
            commit = .committed
            pending[id]?.deliveryCommit = commit
        } else {
            commit = await history?.finalize(request) ?? .notCommitted(.historyUnavailable)
            pending[id]?.deliveryCommit = commit
            if commit == .committed { pending[id]?.finalized = true }
        }
        if commit == .notCommitted(.recoveryRequired) { pending[id]?.recoveryRequired = true }
        return commit
    }

    private func copyRecognizedText(_ revision: CaptureRevision) async -> CaptureCommandOutcome {
        let id = revision.captureID
        guard let textRecognizer, let textClipboard else { return .rejected(.recognitionUnavailable) }
        guard !isBusy(id) else { return .rejected(.commandInProgress) }
        guard !isDiscarded(id) else { return .rejected(.discardedCapture) }
        guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
        let image: CaptureImage
        if let record = pending[id] {
            image = record.image
        } else if isFinalized(id), let stored = await historyImage(id) {
            image = stored
        } else {
            return .rejected(isDelivered(id) ? .alreadyDelivered : .unknownCapture)
        }
        recognizing.insert(id)
        defer { recognizing.remove(id) }
        let text = await textRecognizer.recognize(image)
        guard revision.number == currentRevision(id), pending[id] != nil || isFinalized(id) else {
            return .rejected(.staleRevision)
        }
        // D8: no text leaves the clipboard exactly as it was.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noTextFound(revision) }
        switch await textClipboard.writeText(text) {
        case let .success(receipt):
            return .recognizedText(RecognizedTextOutcome(revision: revision, characterCount: text.count,
                                                         delivery: .copied(receipt)))
        case let .failure(error):
            return .recognizedText(RecognizedTextOutcome(revision: revision, characterCount: text.count,
                                                         delivery: .failed(error)))
        }
    }

    private func isBusy(_ id: CaptureID) -> Bool { inProgress.contains(id) || recognizing.contains(id) }

    private func currentRevision(_ id: CaptureID) -> UInt64 { pending[id]?.revision ?? settled[id]?.revision ?? 1 }
    private func isFinalized(_ id: CaptureID) -> Bool { pending[id]?.finalized ?? settled[id]?.finalized ?? false }
    private func isDelivered(_ id: CaptureID) -> Bool { pending[id]?.delivered ?? settled[id]?.delivered ?? false }
    private func isDiscarded(_ id: CaptureID) -> Bool { settled[id]?.discarded ?? false }
    private func needsRecovery(_ id: CaptureID) -> Bool {
        pending[id]?.recoveryRequired ?? settled[id]?.recoveryRequired ?? false
    }

    /// Closes the capture's Thumbnail and releases its pixels. The settled map keeps how it ended.
    private func release(_ id: CaptureID, discarded: Bool = false) {
        guard let record = pending.removeValue(forKey: id) else { return }
        pendingBytes -= record.image.pngData.count
        stack.remove(id)
        settled[id] = SettledCapture(revision: record.revision, finalized: record.finalized,
                                     delivered: record.delivered, recoveryRequired: record.recoveryRequired,
                                     discarded: discarded)
    }
}

private enum DeliveryKind { case copy, save, drag }

/// Everything the coordinator holds for one capture while its Thumbnail is open. There is no
/// editing or delivering state: the core never sees editing, and a delivery is the `inProgress` lock.
private struct PendingCapture {
    var image: CaptureImage
    var revision: UInt64 = 1
    /// History committed this capture; its Thumbnail stays open after a failed delivery or a Done.
    var finalized = false
    /// A delivery took this revision while History could not commit it (Copy keeps it editable).
    var delivered = false
    /// The first delivery's commit; a retry or later delivery reuses it.
    var deliveryCommit: CommitOutcome?
    var failedDeliveries: Set<DeliveryKind> = []
    /// A failed action requires an explicit user retry, so no automatic exit.
    var automaticExitSuppressed = false
    /// The clipboard write a redacting Done must replace.
    var copyReceipt: ClipboardReceipt?
    var recoveryRequired = false
    /// Redaction was submitted and no Done or Delete has resolved it yet.
    var unfinishedRedaction = false
}

/// What stays known about a capture after its pixels are released.
private struct SettledCapture {
    let revision: UInt64
    let finalized: Bool
    let delivered: Bool
    let recoveryRequired: Bool
    let discarded: Bool
}

private struct DragNotAccepted: Error {}

/// Drag events need no bookkeeping: nothing is staged, and `deliver` returns `.copied`
/// only after the promise write succeeded and the session ended.
private struct DragSessionEvents: DragCopyEvents {
    func promiseWriteReturned() async throws {}
    func dragSessionEnded() async {}
}
