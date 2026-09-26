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
    case copy, save, edit, copyText, deleteCapture, dismiss, newer, older
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
        case "t": return .copyText
        case "\u{1b}": return .dismiss
        case "\u{7f}": return .deleteCapture
        default: return nil
        }
    }
}

/// Timeout policy. Zero seconds expire immediately; only `.never` disables timeout.
public enum ThumbnailAutoDismiss: Equatable, Sendable {
    case after(Duration)
    case never
}

/// Persisted Settings mapping. `never` is an explicit flag so stored zero stays immediate timeout.
public struct ThumbnailAutoDismissPreference: Equatable, Sendable {
    public static let defaultSeconds = 10

    public var never: Bool
    public var seconds: Int

    public var autoDismiss: ThumbnailAutoDismiss {
        never ? .never : .after(.seconds(Int64(max(0, seconds))))
    }

    public init(never: Bool = false, seconds: Int = defaultSeconds) {
        self.never = never
        self.seconds = max(0, seconds)
    }

    public static func load(never: Bool, seconds: Any?) -> ThumbnailAutoDismissPreference {
        let parsed = (seconds as? Int).map { max(0, $0) } ?? defaultSeconds
        return ThumbnailAutoDismissPreference(never: never, seconds: parsed)
    }
}

public enum ThumbnailSystemEvent: Equatable, Sendable {
    case quit
    case screenLocked
    case screenUnlocked
    case displaysChanged(remaining: [UInt32])
}

public struct ThumbnailStackPolicy: Sendable {
    public let maximumCount: Int
    public let autoDismiss: ThumbnailAutoDismiss
    /// Delay used by callers that still read the ticket-13 field. Never reports the working default.
    public var autoDismissDelay: Duration {
        switch autoDismiss {
        case .after(let delay): return delay
        case .never: return .seconds(Int64(ThumbnailAutoDismissPreference.defaultSeconds))
        }
    }

    // Decision 54: 4 cards / 10 seconds are working defaults, configurable through Settings.
    public init(maximumCount: Int = 4, autoDismiss: ThumbnailAutoDismiss = .after(.seconds(10))) {
        self.maximumCount = max(1, maximumCount)
        switch autoDismiss {
        case .after(let delay): self.autoDismiss = .after(max(.zero, delay))
        case .never: self.autoDismiss = .never
        }
    }

    public init(maximumCount: Int = 4, autoDismissDelay: Duration) {
        self.init(maximumCount: maximumCount, autoDismiss: .after(autoDismissDelay))
    }
}

/// What a Thumbnail says about its capture. There is no editing or delivering status:
/// the core never sees editing, and a delivery is a transient lock.
public enum ThumbnailStatus: Equatable, Sendable {
    /// In memory only. Delete is available, and Edit when the card is `editable`.
    case pending
    /// Kept in History. The Thumbnail stays until its timeout, a Close or overflow; Edit and Delete are gone.
    case finalized
}

public struct ThumbnailCard: Equatable, Sendable {
    public let revision: CaptureRevision
    /// Arrival plus the delay on the injected clock; nil when auto-dismiss is never.
    public let expiresAt: ContinuousClock.Instant?
    /// The exit the policy requires now; nil while the card may stay.
    public let dueExit: ThumbnailExit?
    /// A failed action requires an explicit user retry; do not schedule automatic exits.
    public let automaticExitSuppressed: Bool
    public let displayID: UInt32?
    public let status: ThumbnailStatus
    /// Done can still render this capture: it is pending and History does not need recovery.
    public let editable: Bool
    public init(revision: CaptureRevision, expiresAt: ContinuousClock.Instant?, dueExit: ThumbnailExit?,
                automaticExitSuppressed: Bool = false, displayID: UInt32? = nil,
                status: ThumbnailStatus = .pending, editable: Bool = true) {
        self.revision = revision
        self.expiresAt = expiresAt
        self.dueExit = dueExit
        self.automaticExitSuppressed = automaticExitSuppressed
        self.displayID = displayID
        self.status = status
        self.editable = editable
    }
}

/// The Thumbnail stack, newest first, and the next time a card's exit becomes due.
public struct Thumbnails: RandomAccessCollection, Equatable, Sendable {
    public let cards: [ThumbnailCard]
    /// The earliest timeout still to come; nil when no card can time out (never, paused, or awaiting a retry).
    /// A card whose exit is already due reports it in `dueExit` instead.
    public let nextDueAt: ContinuousClock.Instant?
    public init(cards: [ThumbnailCard], nextDueAt: ContinuousClock.Instant?) {
        self.cards = cards
        self.nextDueAt = nextDueAt
    }
    public var startIndex: Int { cards.startIndex }
    public var endIndex: Int { cards.endIndex }
    public subscript(position: Int) -> ThumbnailCard { cards[position] }
    /// What Focus Latest Thumbnail acts on: the newest card, by Copy Latest's rule. Nil disables it (D33).
    public var latestToFocus: ThumbnailCard? { cards.first }
    /// What Copy Latest acts on: the newest card, pending or kept in History. Nil disables it (D17).
    public var latestToCopy: ThumbnailCard? { cards.first }
    /// What Delete Latest acts on: the newest pending card; a kept card is already in History. Nil disables it (D17).
    public var latestToDelete: ThumbnailCard? { cards.first { $0.status == .pending } }
}

/// Pure ordering and exit policy for the cards of Pending captures and of finalized ones still shown.
struct ThumbnailStack: Sendable {
    private var policy: ThumbnailStackPolicy
    private var newestFirst: [(revision: CaptureRevision, arrivedAt: ContinuousClock.Instant)] = []
    private var displays: [CaptureID: UInt32] = [:]

    init(policy: ThumbnailStackPolicy) { self.policy = policy }

    mutating func setPolicy(_ policy: ThumbnailStackPolicy) { self.policy = policy }

    mutating func insert(_ revision: CaptureRevision, at now: ContinuousClock.Instant) {
        newestFirst.insert((revision, now), at: 0)
    }

    mutating func remove(_ id: CaptureID) {
        newestFirst.removeAll { $0.revision.captureID == id }
        displays.removeValue(forKey: id)
    }

    func contains(_ id: CaptureID) -> Bool { newestFirst.contains { $0.revision.captureID == id } }

    /// The editor left: the timeout runs again in full from `now` (ticket 91). Order is unchanged.
    mutating func restartTimeout(_ id: CaptureID, at now: ContinuousClock.Instant) {
        guard let index = newestFirst.firstIndex(where: { $0.revision.captureID == id }) else { return }
        newestFirst[index].arrivedAt = now
    }

    /// Keeps arrival order and expiry; only the current revision changes after Done.
    mutating func replace(_ revision: CaptureRevision) {
        guard let index = newestFirst.firstIndex(where: { $0.revision.captureID == revision.captureID }) else { return }
        newestFirst[index].revision = revision
    }

    mutating func assignDisplay(_ id: CaptureID, displayID: UInt32) {
        guard newestFirst.contains(where: { $0.revision.captureID == id }) else { return }
        displays[id] = displayID
    }

    mutating func rehome(remaining: [UInt32]) {
        guard let fallback = remaining.first else { return }
        let connected = Set(remaining)
        for (id, display) in displays where !connected.contains(display) {
            displays[id] = fallback
        }
    }

    /// Oldest first, matching quit finalization order.
    func arrivalOrder() -> [CaptureRevision] { newestFirst.reversed().map(\.revision) }

    /// The oldest cards beyond the maximum, skipping `spared` (the captures being edited, ticket 95).
    private func overflowing(sparing spared: Set<CaptureID>) -> Set<CaptureID> {
        var excess = newestFirst.count - policy.maximumCount
        var result: Set<CaptureID> = []
        for card in newestFirst.reversed() where excess > 0 && !spared.contains(card.revision.captureID) {
            result.insert(card.revision.captureID)
            excess -= 1
        }
        return result
    }

    func cards(at now: ContinuousClock.Instant, sparing spared: Set<CaptureID> = []) -> [ThumbnailCard] {
        let overflow = overflowing(sparing: spared)
        return newestFirst.map { card in
            let overflowing = overflow.contains(card.revision.captureID)
            let expiresAt: ContinuousClock.Instant?
            let expired: Bool
            switch policy.autoDismiss {
            case .after(let delay):
                expiresAt = card.arrivedAt + delay
                expired = now >= card.arrivedAt + delay
            case .never:
                expiresAt = nil
                expired = false
            }
            return ThumbnailCard(revision: card.revision, expiresAt: expiresAt,
                                 dueExit: overflowing ? .overflow : expired ? .timeout : nil,
                                 displayID: displays[card.revision.captureID])
        }
    }

    /// Pointer and keyboard exits are always admitted; policy exits only when due.
    func admits(_ exit: ThumbnailExit, for id: CaptureID, at now: ContinuousClock.Instant,
                sparing spared: Set<CaptureID> = []) -> Bool {
        guard let index = newestFirst.firstIndex(where: { $0.revision.captureID == id }) else { return false }
        switch exit {
        case .overflow: return overflowing(sparing: spared).contains(id)
        case .timeout:
            guard case .after(let delay) = policy.autoDismiss else { return false }
            return now >= newestFirst[index].arrivedAt + delay
        case .swipe, .close, .escape, .delete: return true
        }
    }
}
