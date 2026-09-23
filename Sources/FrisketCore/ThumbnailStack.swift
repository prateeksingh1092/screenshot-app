import Foundation

/// Every way a card leaves the thumbnail stack. Decision 44 fixes each outcome.
public enum ThumbnailExit: Sendable, CaseIterable {
    case timeout, swipe, close, overflow, escape, delete

    public var outcome: ThumbnailExitOutcome { self == .delete ? .discard : .finalizeToHistory }
}

public enum ThumbnailExitOutcome: Sendable { case finalizeToHistory, discard }

/// Newest-first stack order. Arrow-down is newer; arrow-up is older.
public enum ThumbnailFocusMove: Sendable { case newer, older }

public enum ThumbnailKeyCommand: Equatable, Sendable {
    case copy, save, edit, deleteCapture, dismiss, newer, older
}

/// Single keys and arrows for a focused thumbnail. Modifier chords are ignored.
public enum ThumbnailKeys {
    public static func command(characters: String, keyCode: UInt16,
                               command: Bool = false, option: Bool = false,
                               control: Bool = false, shift: Bool = false) -> ThumbnailKeyCommand? {
        guard !command, !option, !control, !shift else { return nil }
        switch keyCode {
        case 125: return .newer
        case 126: return .older
        case 51, 117: return .deleteCapture
        case 53: return .dismiss
        default: break
        }
        switch characters.lowercased() {
        case "c": return .copy
        case "s": return .save
        case "e": return .edit
        case "\u{1b}": return .dismiss
        case "\u{7f}": return .deleteCapture
        default: return nil
        }
    }
}

public struct ThumbnailStackPolicy: Sendable {
    public let maximumCount: Int
    public let autoDismissDelay: Duration
    // Decision 54: 4 cards / 10 seconds are working defaults, configurable through Settings later.
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
    /// A failed action requires an explicit user retry; do not schedule automatic exits.
    public let automaticExitSuppressed: Bool
    public init(revision: CaptureRevision, expiresAt: ContinuousClock.Instant, dueExit: ThumbnailExit?,
                automaticExitSuppressed: Bool = false) {
        self.revision = revision
        self.expiresAt = expiresAt
        self.dueExit = dueExit
        self.automaticExitSuppressed = automaticExitSuppressed
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

    /// Keeps arrival order and expiry; only the current revision changes after Done.
    mutating func replace(_ revision: CaptureRevision) {
        guard let index = newestFirst.firstIndex(where: { $0.revision.captureID == revision.captureID }) else { return }
        newestFirst[index].revision = revision
    }

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
