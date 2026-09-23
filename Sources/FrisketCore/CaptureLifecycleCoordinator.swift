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
    private let dragStaging: (any DragCopyStaging)?
    private let codec: (any BitmapCodec)?
    private let scrollingFrames: (any ScrollingFrameFeed)?
    private let scrollingPreview: (any ScrollingPreviewSurface)?
    private let scrollingBudget: ScrollingCaptureBudget
    private var finalized: Set<CaptureID> = []
    private var deliveryCommits: [CaptureID: CommitOutcome] = [:]
    private var inProgress: Set<CaptureID> = []
    private var discarded: Set<CaptureID> = []
    private enum DeliveryKind { case copy, save }
    private var failedDeliveries: [CaptureID: Set<DeliveryKind>] = [:]
    private var automaticExitSuppressed: Set<CaptureID> = []
    private var delivered: Set<CaptureID> = []
    private var images: [CaptureID: CaptureImage] = [:]
    private var revisions: [CaptureID: UInt64] = [:]
    private var copyReceipts: [CaptureID: ClipboardReceipt] = [:]
    private var recoveryRequired: Set<CaptureID> = []
    private var unfinishedRedactions: Set<CaptureID> = []
    private var stackFocused = false
    private var focusedCapture: CaptureID?
    private var screenLocked = false
    // Holds exactly the captures in `images`; update both together.
    private var stack: ThumbnailStack
    private let clock: @Sendable () -> ContinuousClock.Instant

    init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)?,
         windowSource: (any CapturePixelSource)?,
         clipboard: any ImageClipboard, pendingByteLimit: Int, history: (any CaptureHistory)?, exporter: (any CaptureExport)?,
         drag: (any DragHandoff)?, dragStaging: (any DragCopyStaging)?,
         thumbnailPolicy: ThumbnailStackPolicy, clock: @escaping @Sendable () -> ContinuousClock.Instant,
         codec: (any BitmapCodec)?,
         scrollingFrames: (any ScrollingFrameFeed)?, scrollingPreview: (any ScrollingPreviewSurface)?,
         scrollingBudget: ScrollingCaptureBudget) {
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
        self.dragStaging = dragStaging
        self.codec = codec
        self.scrollingFrames = scrollingFrames
        self.scrollingPreview = scrollingPreview
        self.scrollingBudget = scrollingBudget
    }

    func recoverHistory() async -> Result<HistoryRecoveryReport, HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.recover()
    }

    func maintainHistory(limits: HistoryLimits?) async -> Result<HistoryUsage, HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.maintain(limits: limits)
    }

    func historyStatus(consumeNotice: Bool) async -> Result<HistoryUsage, HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.status(consumeNotice: consumeNotice)
    }

    private func currentRevision(_ id: CaptureID) -> UInt64 { revisions[id] ?? 1 }

    func historyEntries() async -> Result<[HistoryEntry], HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.entries()
    }

    func image(for revision: CaptureRevision) -> CaptureImage? {
        guard revision.number == currentRevision(revision.captureID) else { return nil }
        return images[revision.captureID]
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
            for revision in stack.arrivalOrder() {
                let outcome = await execute(.dismiss(revision))
                outcomes.append(outcome)
                guard case .finalized(_, .committed) = outcome else { break }
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

    func thumbnails() -> [ThumbnailCard] {
        stack.cards(at: clock()).map { card in
            let suppressed = automaticExitSuppressed.contains(card.revision.captureID)
            let pauseTimeout = (stackFocused || screenLocked) && card.dueExit == .timeout
            return ThumbnailCard(revision: card.revision, expiresAt: card.expiresAt,
                                 dueExit: (suppressed || pauseTimeout) ? nil : card.dueExit,
                                 automaticExitSuppressed: suppressed,
                                 displayID: card.displayID)
        }
    }

    func execute(_ command: CaptureCommand) async -> CaptureCommandOutcome {
        switch command {
        case let .dismiss(revision):
            let id = revision.captureID
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] != nil || finalized.contains(id) else { return .rejected(.unknownCapture) }
            guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
            guard !unfinishedRedactions.contains(id) else { return .rejected(.editingUnavailable) }
            guard !finalized.contains(id) || images[id] != nil else { return .rejected(.alreadyFinalized) }
            guard let image = images[id] else { return .rejected(.unknownCapture) }
            inProgress.insert(id)
            let outcome: CommitOutcome
            if finalized.contains(id) { outcome = .committed }
            else {
                outcome = await history?.finalize(AuthorizedFinalization(revision: revision, pngData: image.pngData))
                    ?? .notCommitted(.historyUnavailable)
            }
            if outcome == .notCommitted(.recoveryRequired) { recoveryRequired.insert(id) }
            if outcome == .committed {
                finalized.insert(id)
                pendingBytes -= image.pngData.count
                images.removeValue(forKey: id)
                stack.remove(id)
                failedDeliveries.removeValue(forKey: id)
                automaticExitSuppressed.remove(id)
                copyReceipts.removeValue(forKey: id)
            } else {
                automaticExitSuppressed.insert(id)
            }
            inProgress.remove(id)
            return .finalized(revision, outcome)
        case let .done(revision, edits):
            let id = revision.captureID
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] != nil || finalized.contains(id) || delivered.contains(id) else { return .rejected(.unknownCapture) }
            guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
            guard !finalized.contains(id) else { return .rejected(.alreadyFinalized) }
            guard !recoveryRequired.contains(id) else { return .rejected(.editingUnavailable) }
            guard let image = images[id] else { return .rejected(.alreadyDelivered) }
            // Once redaction is submitted, a rejected render must not expose the
            // original to delivery or History. Only an accepted Done or Delete resolves it.
            if !edits.redactions.isEmpty { unfinishedRedactions.insert(id) }
            guard let codec, let base = codec.decode(image.pngData),
                  let pngData = codec.encode(DocumentRenderer.render(EditorDocument(base: base, edits: edits))),
                  !pngData.isEmpty else { return .rejected(.editingUnavailable) }
            guard pngData.count <= pendingByteLimit - (pendingBytes - image.pngData.count) else {
                return .rejected(.pendingByteBudgetExceeded)
            }
            let next = CaptureRevision(captureID: id, number: revision.number + 1)
            // The rendered revision replaces the original before any suspension, so no
            // later command, retry or History commit can reach the unredacted pixels.
            pendingBytes += pngData.count - image.pngData.count
            images[id] = CaptureImage(pngData: pngData)
            revisions[id] = next.number
            stack.replace(next)
            unfinishedRedactions.remove(id)
            // Retry state belonged to the previous revision's Copy.
            failedDeliveries.removeValue(forKey: id)
            deliveryCommits.removeValue(forKey: id)
            delivered.remove(id)
            inProgress.insert(id)
            var clipboardFailure: ClipboardFailure?
            if !edits.redactions.isEmpty, let receipt = copyReceipts[id] {
                // Do this even if History is unavailable; clipboard privacy is independent
                // of persistence. The adapter checks and writes without a suspension.
                switch await clipboard.write(ClipboardImage(pngData: pngData, replacing: receipt)) {
                case let .success(replacement):
                    copyReceipts[id] = replacement
                case .failure(.changed):
                    copyReceipts.removeValue(forKey: id)
                case .failure(.unavailable):
                    clipboardFailure = .unavailable
                }
            }
            let commit = await history?.finalize(AuthorizedFinalization(revision: next, pngData: pngData))
                ?? .notCommitted(.historyUnavailable)
            if commit == .committed { finalized.insert(id) }
            if commit == .notCommitted(.recoveryRequired) { recoveryRequired.insert(id) }
            if finalized.contains(id) || recoveryRequired.contains(id) { copyReceipts.removeValue(forKey: id) }
            if commit != .committed { automaticExitSuppressed.insert(id) }
            inProgress.remove(id)
            return .edited(next, commit, clipboardFailure: clipboardFailure)
        case let .discard(id):
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard !finalized.contains(id) else { return .rejected(.alreadyFinalized) }
            guard images[id] != nil else {
                return .rejected(delivered.contains(id) ? .alreadyDelivered : .unknownCapture)
            }
            pendingBytes -= images[id]?.pngData.count ?? 0
            images.removeValue(forKey: id)
            stack.remove(id)
            failedDeliveries.removeValue(forKey: id)
            automaticExitSuppressed.remove(id)
            copyReceipts.removeValue(forKey: id)
            discarded.insert(id)
            unfinishedRedactions.remove(id)
            return .discarded(id)
        case let .captureScrolling(id, maximumBytes):
            return await runScrollingCapture(id: id, maximumBytes: maximumBytes)
        case let .capture(id, maximumBytes), let .captureFullScreen(id, maximumBytes), let .captureWindow(id, maximumBytes):
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] == nil, !delivered.contains(id), !finalized.contains(id) else { return .rejected(.duplicateCapture) }
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
                images[id] = image
                revisions[id] = 1
                stack.insert(CaptureRevision(captureID: id, number: 1), at: clock())
                return .pending(CaptureRevision(captureID: id, number: 1))
            case let .failure(.permissionRequired(state)):
                return .permissionRequired(state)
            case let .failure(error):
                return .captureFailed(error)
            }
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
                    return .copy(CopyOutcome(revision: revision, commit: commit, delivery: delivery))
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
                    return .save(SaveOutcome(revision: revision, commit: commit, delivery: delivery))
                })
        case let .exitThumbnail(revision, exit):
            let id = revision.captureID
            if images[id] != nil, !inProgress.contains(id) {
                guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
                guard !unfinishedRedactions.contains(id) else { return .rejected(.editingUnavailable) }
                if exit == .timeout || exit == .overflow {
                    guard !automaticExitSuppressed.contains(id) else { return .rejected(.thumbnailExitNotDue) }
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
            let id = revision.captureID
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] != nil || delivered.contains(id) else { return .rejected(.unknownCapture) }
            guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
            guard !unfinishedRedactions.contains(id) else { return .rejected(.editingUnavailable) }
            guard !delivered.contains(id) else { return .rejected(.alreadyDelivered) }
            guard let image = images[id] else { return .rejected(.unknownCapture) }
            inProgress.insert(id)
            let request = AuthorizedFinalization(revision: revision, pngData: image.pngData)
            let commit: CommitOutcome
            if let prior = deliveryCommits[id] {
                commit = prior
            } else if finalized.contains(id) {
                commit = .committed
                deliveryCommits[id] = commit
            } else {
                commit = await history?.finalize(request) ?? .notCommitted(.historyUnavailable)
                deliveryCommits[id] = commit
                if commit == .committed { finalized.insert(id) }
            }
            if commit == .notCommitted(.recoveryRequired) { recoveryRequired.insert(id) }
            var delivery: DragDelivery = .failed
            if let dragStaging, let drag {
                do {
                    let stagedID = try await dragStaging.stage(request)
                    delivery = try await drag.deliver(.copy, image: DragImage(pngData: image.pngData),
                        events: DragCopyEventBridge(staging: dragStaging, id: stagedID))
                } catch {
                    delivery = .failed
                }
            }
            if delivery == .copied {
                delivered.insert(id)
                failedDeliveries.removeValue(forKey: id)
                automaticExitSuppressed.remove(id)
                pendingBytes -= image.pngData.count
                images.removeValue(forKey: id)
                stack.remove(id)
                copyReceipts.removeValue(forKey: id)
            } else {
                automaticExitSuppressed.insert(id)
            }
            inProgress.remove(id)
            return .drag(DragOutcome(revision: revision, commit: commit, delivery: delivery))
        }
    }

    /// Every delivery shares authorization, commit caching, retry gating and byte ownership.
    private func deliver<Receipt: Sendable, Failure: Error & Sendable>(
        _ revision: CaptureRevision, kind: DeliveryKind, retrying: Bool,
        using operation: @Sendable (AuthorizedFinalization) async -> Result<Receipt, Failure>,
        outcome: (CommitOutcome, Result<Receipt, Failure>) -> CaptureCommandOutcome
    ) async -> CaptureCommandOutcome {
        let id = revision.captureID
        guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
        guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
        guard images[id] != nil || delivered.contains(id) else { return .rejected(.unknownCapture) }
        guard revision.number == currentRevision(id) else { return .rejected(.staleRevision) }
        guard !unfinishedRedactions.contains(id) else { return .rejected(.editingUnavailable) }
        guard !delivered.contains(id) else { return .rejected(.alreadyDelivered) }
        guard let image = images[id] else { return .rejected(.unknownCapture) }
        let previouslyFailed = failedDeliveries[id]?.contains(kind) == true
        if retrying {
            guard previouslyFailed else { return .rejected(.retryNotAvailable) }
        } else if previouslyFailed {
            return .rejected(.retryRequired)
        }
        inProgress.insert(id)
        defer { inProgress.remove(id) }
        let request = AuthorizedFinalization(revision: revision, pngData: image.pngData)
        // Retrying delivery never repeats a commit, including a failed one.
        let commit: CommitOutcome
        if let prior = deliveryCommits[id] { commit = prior }
        else if finalized.contains(id) {
            commit = .committed
            deliveryCommits[id] = commit
        } else {
            commit = await history?.finalize(request) ?? .notCommitted(.historyUnavailable)
            deliveryCommits[id] = commit
            if commit == .committed { finalized.insert(id) }
        }
        if commit == .notCommitted(.recoveryRequired) { recoveryRequired.insert(id) }
        let result = await operation(request)
        switch result {
        case let .success(receipt):
            delivered.insert(id)
            failedDeliveries.removeValue(forKey: id)
            // A failed History commit leaves an editable Pending capture when a codec
            // can replace the earlier copy. Keep its byte charge and receipt.
            if kind == .copy, commit != .committed, !recoveryRequired.contains(id), codec != nil,
               let copyReceipt = receipt as? ClipboardReceipt {
                copyReceipts[id] = copyReceipt
                automaticExitSuppressed.insert(id)
            } else {
                automaticExitSuppressed.remove(id)
                pendingBytes -= image.pngData.count
                images.removeValue(forKey: id)
                stack.remove(id)
                copyReceipts.removeValue(forKey: id)
            }
        case .failure:
            failedDeliveries[id, default: []].insert(kind)
            automaticExitSuppressed.insert(id)
        }
        return outcome(commit, result)
    }

    private func runScrollingCapture(id: CaptureID, maximumBytes: Int) async -> CaptureCommandOutcome {
        guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
        guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
        guard images[id] == nil, !delivered.contains(id), !finalized.contains(id) else { return .rejected(.duplicateCapture) }
        guard maximumBytes > 0 else { return .rejected(.invalidByteAllowance) }
        guard let scrollingFrames else { return .captureFailed(.unavailable) }
        guard maximumBytes <= pendingByteLimit - pendingBytes else { return .rejected(.pendingByteBudgetExceeded) }
        // Reserve before the first suspension, just like area/full-screen capture.
        pendingBytes += maximumBytes
        inProgress.insert(id)
        let access = await permission.capturePermission()
        guard access == .granted else {
            pendingBytes -= maximumBytes
            inProgress.remove(id)
            return .permissionRequired(access)
        }
        let sessionBudget = ScrollingCaptureBudget(pixelCap: scrollingBudget.pixelCap,
                                                   memoryBudgetBytes: min(scrollingBudget.memoryBudgetBytes, maximumBytes))
        let session = ScrollingCaptureSession(budget: sessionBudget)
        while true {
            switch await scrollingFrames.nextFrame() {
            case .cancel:
                session.cancel()
                pendingBytes -= maximumBytes
                inProgress.remove(id)
                return .captureFailed(.cancelled)
            case let .failed(failure):
                session.cancel()
                pendingBytes -= maximumBytes
                inProgress.remove(id)
                if case let .permissionRequired(state) = failure { return .permissionRequired(state) }
                return .captureFailed(failure)
            case .done:
                return await acceptScrollingResult(id: id, maximumBytes: maximumBytes, session: session, limit: nil)
            case let .viewport(viewport):
                switch session.ingest(viewport) {
                case let .preview(preview):
                    await scrollingPreview?.update(preview)
                case let .rejectedAlignment(evidence):
                    session.cancel()
                    pendingBytes -= maximumBytes
                    inProgress.remove(id)
                    return .captureFailed(.rejectedAlignment(evidence))
                case .unchanged:
                    break
                case let .stopped(reason, preview):
                    await scrollingPreview?.update(preview)
                    return await acceptScrollingResult(id: id, maximumBytes: maximumBytes, session: session, limit: reason)
                case let .refused(reason):
                    session.cancel()
                    pendingBytes -= maximumBytes
                    inProgress.remove(id)
                    return .scrollingRefused(reason)
                case .failed:
                    session.cancel()
                    pendingBytes -= maximumBytes
                    inProgress.remove(id)
                    return .captureFailed(.unavailable)
                }
            }
        }
    }

    private func acceptScrollingResult(id: CaptureID, maximumBytes: Int, session: ScrollingCaptureSession,
                                       limit: ScrollingCaptureNotice?) async -> CaptureCommandOutcome {
        guard let image = session.finish(), !image.pngData.isEmpty, image.pngData.count <= maximumBytes else {
            session.cancel()
            pendingBytes -= maximumBytes
            inProgress.remove(id)
            if let limit { return .scrollingRefused(limit) }
            return imageCountFailure(sessionHadImage: false)
        }
        pendingBytes -= maximumBytes
        pendingBytes += image.pngData.count
        images[id] = image
        revisions[id] = 1
        let revision = CaptureRevision(captureID: id, number: 1)
        stack.insert(revision, at: clock())
        inProgress.remove(id)
        if let limit { return .scrollingLimited(revision, limit) }
        return .pending(revision)
    }

    private func imageCountFailure(sessionHadImage: Bool) -> CaptureCommandOutcome {
        .captureFailed(sessionHadImage ? .unavailable : .emptyImage)
    }
}

private struct DragCopyEventBridge: DragCopyEvents {
    let staging: any DragCopyStaging
    let id: DragStagingID
    func promiseWriteReturned() async throws { try await staging.promiseWriteReturned(id) }
    func dragSessionEnded() async { await staging.dragSessionEnded(id) }
}
