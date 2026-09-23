import Foundation

actor CaptureLifecycleCoordinator {
    private let permission: any CapturePermissionSource
    private let pendingByteLimit: Int
    private var pendingBytes = 0
    private let source: any CapturePixelSource
    private let fullScreenSource: (any CapturePixelSource)?
    private let clipboard: any ImageClipboard
    private let history: (any CaptureHistory)?
    private var finalized: Set<CaptureID> = []
    private var copyCommits: [CaptureID: CommitOutcome] = [:]
    private var inProgress: Set<CaptureID> = []
    private var discarded: Set<CaptureID> = []
    private var failedDelivery: Set<CaptureID> = []
    private var delivered: Set<CaptureID> = []
    private var images: [CaptureID: CaptureImage] = [:]
    private let codec: (any BitmapCodec)?
    private var revisions: [CaptureID: UInt64] = [:]
    private var copyReceipts: [CaptureID: ClipboardReceipt] = [:]
    private var recoveryRequired: Set<CaptureID> = []
    private var unfinishedRedactions: Set<CaptureID> = []

    init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)?,
         clipboard: any ImageClipboard, pendingByteLimit: Int, history: (any CaptureHistory)?, codec: (any BitmapCodec)?) {
        self.pendingByteLimit = max(0, pendingByteLimit)
        self.permission = permission
        self.source = source
        self.fullScreenSource = fullScreenSource
        self.clipboard = clipboard
        self.history = history
        self.codec = codec
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
                failedDelivery.remove(id)
                copyReceipts.removeValue(forKey: id)
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
            unfinishedRedactions.remove(id)
            // Retry state belonged to the previous revision's Copy.
            failedDelivery.remove(id)
            copyCommits.removeValue(forKey: id)
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
            failedDelivery.remove(id)
            copyReceipts.removeValue(forKey: id)
            discarded.insert(id)
            unfinishedRedactions.remove(id)
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
                return .pending(CaptureRevision(captureID: id, number: 1))
            case let .failure(.permissionRequired(state)):
                return .permissionRequired(state)
            case let .failure(error):
                return .captureFailed(error)
            }
        case let .copy(revision), let .retryCopy(revision):
            guard !inProgress.contains(revision.captureID) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(revision.captureID) else { return .rejected(.discardedCapture) }
            guard images[revision.captureID] != nil || delivered.contains(revision.captureID) else {
                return .rejected(.unknownCapture)
            }
            guard revision.number == currentRevision(revision.captureID) else { return .rejected(.staleRevision) }
            guard !unfinishedRedactions.contains(revision.captureID) else { return .rejected(.editingUnavailable) }
            guard !delivered.contains(revision.captureID) else { return .rejected(.alreadyDelivered) }
            guard let image = images[revision.captureID] else { return .rejected(.unknownCapture) }
            if case .retryCopy = command {
                guard failedDelivery.contains(revision.captureID) else { return .rejected(.retryNotAvailable) }
            } else if failedDelivery.contains(revision.captureID) {
                return .rejected(.retryRequired)
            }
            let delivery: DeliveryOutcome
            inProgress.insert(revision.captureID)
            // Retrying delivery never repeats a commit, including a failed one.
            let commit: CommitOutcome
            if let prior = copyCommits[revision.captureID] { commit = prior }
            else if finalized.contains(revision.captureID) { commit = .committed }
            else {
                commit = await history?.finalize(AuthorizedFinalization(revision: revision, pngData: image.pngData))
                    ?? .notCommitted(.historyUnavailable)
                copyCommits[revision.captureID] = commit
                if commit == .committed { finalized.insert(revision.captureID) }
            }
            if commit == .notCommitted(.recoveryRequired) { recoveryRequired.insert(revision.captureID) }
            switch await clipboard.write(ClipboardImage(pngData: image.pngData)) {
            case let .success(receipt):
                delivery = .copied(receipt)
                delivered.insert(revision.captureID)
                failedDelivery.remove(revision.captureID)
                if commit != .committed, !recoveryRequired.contains(revision.captureID), codec != nil {
                    // A failed History commit leaves an editable Pending capture. Keep its
                    // byte charge and receipt until Done, Dismiss or Delete resolves it.
                    copyReceipts[revision.captureID] = receipt
                } else {
                    pendingBytes -= image.pngData.count
                    images.removeValue(forKey: revision.captureID)
                    copyReceipts.removeValue(forKey: revision.captureID)
                }
            case let .failure(error):
                delivery = .failed(error)
                failedDelivery.insert(revision.captureID)
            }
            inProgress.remove(revision.captureID)
            return .copy(CopyOutcome(revision: revision, commit: commit,
                                     delivery: delivery))
        }
    }
}
