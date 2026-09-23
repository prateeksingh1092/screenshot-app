import Foundation

actor CaptureLifecycleCoordinator {
    private let permission: any CapturePermissionSource
    private let pendingByteLimit: Int
    private var pendingBytes = 0
    private let source: any CapturePixelSource
    private let fullScreenSource: (any CapturePixelSource)?
    private let clipboard: any ImageClipboard
    private let history: (any CaptureHistory)?
    private let scrollingFrames: (any ScrollingFrameFeed)?
    private let scrollingPreview: (any ScrollingPreviewSurface)?
    private let scrollingBudget: ScrollingCaptureBudget
    private var finalized: Set<CaptureID> = []
    private var copyCommits: [CaptureID: CommitOutcome] = [:]
    private var inProgress: Set<CaptureID> = []
    private var discarded: Set<CaptureID> = []
    private var failedDelivery: Set<CaptureID> = []
    private var delivered: Set<CaptureID> = []
    private var images: [CaptureID: CaptureImage] = [:]

    init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)?,
         clipboard: any ImageClipboard, pendingByteLimit: Int, history: (any CaptureHistory)?,
         scrollingFrames: (any ScrollingFrameFeed)?, scrollingPreview: (any ScrollingPreviewSurface)?,
         scrollingBudget: ScrollingCaptureBudget) {
        self.pendingByteLimit = max(0, pendingByteLimit)
        self.permission = permission
        self.source = source
        self.fullScreenSource = fullScreenSource
        self.clipboard = clipboard
        self.history = history
        self.scrollingFrames = scrollingFrames
        self.scrollingPreview = scrollingPreview
        self.scrollingBudget = scrollingBudget
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
                failedDelivery.remove(id)
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
            failedDelivery.remove(id)
            discarded.insert(id)
            return .discarded(id)
        case let .captureScrolling(id, maximumBytes):
            return await runScrollingCapture(id: id, maximumBytes: maximumBytes)
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
            guard revision.number == 1 else { return .rejected(.staleRevision) }
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
            else {
                commit = await history?.finalize(AuthorizedFinalization(revision: revision, pngData: image.pngData))
                    ?? .notCommitted(.historyUnavailable)
                copyCommits[revision.captureID] = commit
                if commit == .committed { finalized.insert(revision.captureID) }
            }
            switch await clipboard.write(ClipboardImage(pngData: image.pngData)) {
            case let .success(receipt):
                delivery = .copied(receipt)
                delivered.insert(revision.captureID)
                failedDelivery.remove(revision.captureID)
                pendingBytes -= image.pngData.count
                images.removeValue(forKey: revision.captureID)
            case let .failure(error):
                delivery = .failed(error)
                failedDelivery.insert(revision.captureID)
            }
            inProgress.remove(revision.captureID)
            return .copy(CopyOutcome(revision: revision, commit: commit,
                                     delivery: delivery))
        }
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
        inProgress.remove(id)
        let revision = CaptureRevision(captureID: id, number: 1)
        if let limit { return .scrollingLimited(revision, limit) }
        return .pending(revision)
    }

    private func imageCountFailure(sessionHadImage: Bool) -> CaptureCommandOutcome {
        .captureFailed(sessionHadImage ? .unavailable : .emptyImage)
    }
}
