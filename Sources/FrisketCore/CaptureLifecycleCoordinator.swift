import Foundation

actor CaptureLifecycleCoordinator {
    private let permission: any CapturePermissionSource
    private let pendingByteLimit: Int
    private var pendingBytes = 0
    private let source: any CapturePixelSource
    private let fullScreenSource: (any CapturePixelSource)?
    private let clipboard: any ImageClipboard
    private var inProgress: Set<CaptureID> = []
    private var discarded: Set<CaptureID> = []
    private var failedDelivery: Set<CaptureID> = []
    private var delivered: Set<CaptureID> = []
    private var images: [CaptureID: CaptureImage] = [:]

    init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)?,
         clipboard: any ImageClipboard, pendingByteLimit: Int) {
        self.pendingByteLimit = max(0, pendingByteLimit)
        self.permission = permission
        self.source = source
        self.fullScreenSource = fullScreenSource
        self.clipboard = clipboard
    }

    func image(for revision: CaptureRevision) -> CaptureImage? {
        guard revision.number == 1 else { return nil }
        return images[revision.captureID]
    }

    func execute(_ command: CaptureCommand) async -> CaptureCommandOutcome {
        switch command {
        case let .discard(id):
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] != nil else {
                return .rejected(delivered.contains(id) ? .alreadyDelivered : .unknownCapture)
            }
            pendingBytes -= images[id]?.pngData.count ?? 0
            images.removeValue(forKey: id)
            failedDelivery.remove(id)
            discarded.insert(id)
            return .discarded(id)
        case let .capture(id, maximumBytes), let .captureFullScreen(id, maximumBytes):
            guard !inProgress.contains(id) else { return .rejected(.commandInProgress) }
            guard !discarded.contains(id) else { return .rejected(.discardedCapture) }
            guard images[id] == nil, !delivered.contains(id) else { return .rejected(.duplicateCapture) }
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
            return .copy(CopyOutcome(revision: revision, commit: .notCommitted(.historyUnavailable),
                                     delivery: delivery))
        }
    }
}
