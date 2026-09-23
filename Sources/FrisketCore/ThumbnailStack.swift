import Foundation

/// Every way a card leaves the thumbnail stack. Decision 44 fixes each outcome.
public enum ThumbnailExit: Sendable, CaseIterable {
    case timeout, swipe, close, overflow, escape, delete

    public var outcome: ThumbnailExitOutcome { self == .delete ? .discard : .finalizeToHistory }
}

public enum ThumbnailExitOutcome: Sendable { case finalizeToHistory, discard }

public struct ThumbnailStackPolicy: Sendable {
    public let maximumCount: Int
    public let autoDismissDelay: Duration
    public init(maximumCount: Int = 4, autoDismissDelay: Duration = .seconds(10)) {
        self.maximumCount = max(1, maximumCount)
        self.autoDismissDelay = max(.zero, autoDismissDelay)
    }
}

public struct ThumbnailCard: Equatable, Sendable {
    public let revision: CaptureRevision
    /// On the command layer's injected clock.
    public let expiresAt: ContinuousClock.Instant
    /// The exit the policy requires now; nil while the card may stay.
    public let dueExit: ThumbnailExit?
    public init(revision: CaptureRevision, expiresAt: ContinuousClock.Instant, dueExit: ThumbnailExit?) {
        self.revision = revision
        self.expiresAt = expiresAt
        self.dueExit = dueExit
    }
}

/// Pure ordering and exit policy for the cards of Pending captures.
struct ThumbnailStack: Sendable {
    private let policy: ThumbnailStackPolicy
    private var newestFirst: [(revision: CaptureRevision, expiresAt: ContinuousClock.Instant)] = []

    init(policy: ThumbnailStackPolicy) { self.policy = policy }

    mutating func insert(_ revision: CaptureRevision, at now: ContinuousClock.Instant) {
        newestFirst.insert((revision, now + policy.autoDismissDelay), at: 0)
    }

    mutating func remove(_ id: CaptureID) { newestFirst.removeAll { $0.revision.captureID == id } }

    func cards(at now: ContinuousClock.Instant) -> [ThumbnailCard] {
        newestFirst.enumerated().map { index, card in
            let overflowing = index >= policy.maximumCount
            let expired = now >= card.expiresAt
            return ThumbnailCard(revision: card.revision, expiresAt: card.expiresAt,
                                 dueExit: overflowing ? .overflow : expired ? .timeout : nil)
        }
    }

    /// Pointer and keyboard exits are always admitted; policy exits only when due.
    func admits(_ exit: ThumbnailExit, for id: CaptureID, at now: ContinuousClock.Instant) -> Bool {
        guard let index = newestFirst.firstIndex(where: { $0.revision.captureID == id }) else { return false }
        switch exit {
        case .overflow: return index >= policy.maximumCount
        case .timeout: return now >= newestFirst[index].expiresAt
        case .swipe, .close, .escape, .delete: return true
        }
    }
}
