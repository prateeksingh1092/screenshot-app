import Foundation

actor CaptureLifecycleCoordinator {
    private let pendingByteLimit: Int
    private var pendingBytes = 0
    private let source: any CapturePixelSource
    private let fullScreenSource: (any CapturePixelSource)?
    private let clipboard: any ImageClipboard
    private let history: (any CaptureHistory)?
    private let exporter: (any CaptureExport)?
    private var finalized: Set<CaptureID> = []
    private var deliveryCommits: [CaptureID: CommitOutcome] = [:]
    private var inProgress: Set<CaptureID> = []
    private var discarded: Set<CaptureID> = []
    private enum DeliveryKind { case copy, save }
    private var failedDeliveries: [CaptureID: Set<DeliveryKind>] = [:]
    private var delivered: Set<CaptureID> = []
    private var images: [CaptureID: CaptureImage] = [:]

    init(source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)?,
         clipboard: any ImageClipboard, pendingByteLimit: Int, history: (any CaptureHistory)?, exporter: (any CaptureExport)?) {
        self.pendingByteLimit = max(0, pendingByteLimit)
        self.source = source
        self.fullScreenSource = fullScreenSource
        self.clipboard = clipboard
        self.history = history
        self.exporter = exporter
    }

    func historyEntries() async -> Result<[HistoryEntry], HistoryFailure> {
        guard let history else { return .failure(.unavailable) }
        return await history.entries()
    }

    func image(for revision: CaptureRevision) -> CaptureImage? {
        guard revision.number == 1 else { return nil }
        return images[revision.captureID]
    }

    func execute(_ command: CaptureCommand) async -> CaptureCommandOutcome {
        switch command {
        case let .dismiss(revision):
            let id = revision.captureID
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] != nil || finalized.contains(id) else { return .rejected(.unknownCapture) }
            guard revision.number == 1 else { return .rejected(.staleRevision) }
            guard !finalized.contains(id) || images[id] != nil else { return .rejected(.alreadyFinalized) }
            guard let image = images[id] else { return .rejected(.unknownCapture) }
            inProgress.insert(id)
            let outcome: CommitOutcome
            if finalized.contains(id) { outcome = .committed }
            else {
                outcome = await history?.finalize(AuthorizedFinalization(revision: revision, pngData: image.pngData))
                    ?? .notCommitted(.historyUnavailable)
            }
            if outcome == .committed {
                finalized.insert(id)
                pendingBytes -= image.pngData.count
                images.removeValue(forKey: id)
                failedDeliveries.removeValue(forKey: id)
            }
            inProgress.remove(id)
            return .finalized(revision, outcome)
        case let .discard(id):
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard !finalized.contains(id) else { return .rejected(.alreadyFinalized) }
            guard images[id] != nil else {
                return .rejected(delivered.contains(id) ? .alreadyDelivered : .unknownCapture)
            }
            pendingBytes -= images[id]?.pngData.count ?? 0
            images.removeValue(forKey: id)
            failedDeliveries.removeValue(forKey: id)
            discarded.insert(id)
            return .discarded(id)
        case let .capture(id, maximumBytes), let .captureFullScreen(id, maximumBytes):
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
            } else {
                captureSource = source
            }
            pendingBytes += maximumBytes
            inProgress.insert(id)
            let result = await captureSource.capture(maximumBytes: maximumBytes)
            pendingBytes -= maximumBytes
            inProgress.remove(id)
            switch result {
            case let .success(image):
                guard !image.pngData.isEmpty else { return .captureFailed(.emptyImage) }
                guard image.pngData.count <= maximumBytes else { return .rejected(.pendingByteBudgetExceeded) }
                pendingBytes += image.pngData.count
                images[id] = image
                return .pending(CaptureRevision(captureID: id, number: 1))
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
        guard revision.number == 1 else { return .rejected(.staleRevision) }
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
        else {
            commit = await history?.finalize(request) ?? .notCommitted(.historyUnavailable)
            deliveryCommits[id] = commit
            if commit == .committed { finalized.insert(id) }
        }
        let result = await operation(request)
        switch result {
        case .success:
            delivered.insert(id)
            failedDeliveries.removeValue(forKey: id)
            pendingBytes -= image.pngData.count
            images.removeValue(forKey: id)
        case .failure:
            failedDeliveries[id, default: []].insert(kind)
        }
        return outcome(commit, result)
    }
}
