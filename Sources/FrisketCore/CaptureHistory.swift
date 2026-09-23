import Foundation

public enum HistoryFailure: Error, Equatable, Sendable {
    case unavailable, unknownMigrations, invalidImage, recoveryRequired, rootLocked
}

public enum HistoryState: String, Codable, Sendable { case finalized, deleting }

public struct HistoryEntry: Equatable, Sendable {
    public let key: Int64
    public let captureID: CaptureID
    public let revision: UInt64
    public let imageLocation: String
    public let recordLocation: String
    public let thumbnailLocation: String?
    public let width: Int
    public let height: Int
    public let imageBytes: Int64
    public let recordBytes: Int64
    public let thumbnailBytes: Int64
    public let finalizedAt: Date
    public let state: HistoryState
}

/// History window row. No file names or paths.
public struct HistoryItem: Equatable, Sendable {
    public let captureID: CaptureID
    public let revision: UInt64
    public let width: Int
    public let height: Int
    public let finalizedAt: Date
    public init(captureID: CaptureID, revision: UInt64, width: Int, height: Int, finalizedAt: Date) {
        self.captureID = captureID
        self.revision = revision
        self.width = width
        self.height = height
        self.finalizedAt = finalizedAt
    }
}

/// Only the lifecycle coordinator constructs this capability, after an explicit
/// finalization command. It contains the frozen output, never an editor original.
public struct AuthorizedFinalization: Sendable {
    public let revision: CaptureRevision
    public let pngData: Data
    internal init(revision: CaptureRevision, pngData: Data) {
        self.revision = revision
        self.pngData = pngData
    }
}

public protocol CaptureHistory: Sendable {
    func recover() async -> Result<HistoryRecoveryReport, HistoryFailure>
    func finalize(_ request: AuthorizedFinalization) async -> CommitOutcome
    func maintain(limits: HistoryLimits?) async -> Result<HistoryUsage, HistoryFailure>
    func status(consumeNotice: Bool) async -> Result<HistoryUsage, HistoryFailure>
    func entries() async -> Result<[HistoryEntry], HistoryFailure>
    func delete(_ id: CaptureID) async -> Result<Void, HistoryFailure>
    func finalizedImage(_ id: CaptureID) async -> Result<(revision: UInt64, pngData: Data), HistoryFailure>
}

/// Recovery/fault-injection contract. Each point means the named operation has
/// completed. Both crash-recovery tiers must cover every case, including the cache.
public enum HistoryCommitPoint: String, CaseIterable, Codable, Sendable {
    case pngStaged, pngSynced, recordStaged, recordSynced
    case imageRenamed, recordRenamed, directorySynced, rowCommitted, thumbnailCached
    case dragStaged, dragPromiseWritten
}

public struct HistoryRecoveryReport: Equatable, Sendable {
    public let logicalBytes: Int64
    public let removedMissingImages: Int
}

public struct HistoryLimits: Equatable, Sendable {
    public let retentionDays: Int
    public let maximumBytes: Int64
    public init(retentionDays: Int = 30, maximumBytes: Int64 = 1_000_000_000) {
        self.retentionDays = min(36_500, max(1, retentionDays))
        self.maximumBytes = max(1, maximumBytes)
    }
}

public struct HistoryUsage: Equatable, Sendable {
    public let limits: HistoryLimits
    public let usageBytes: Int64
    public let lastQuotaEviction: Date?
    public let quotaNoticePending: Bool
    public let ageEvictionDeferred: Bool
    public init(limits: HistoryLimits, usageBytes: Int64, lastQuotaEviction: Date? = nil,
                quotaNoticePending: Bool = false, ageEvictionDeferred: Bool = false) {
        self.limits = limits
        self.usageBytes = usageBytes
        self.lastQuotaEviction = lastQuotaEviction
        self.quotaNoticePending = quotaNoticePending
        self.ageEvictionDeferred = ageEvictionDeferred
    }
}

public extension CaptureHistory {
    func maintain(limits: HistoryLimits?) async -> Result<HistoryUsage, HistoryFailure> { .failure(.unavailable) }
    func status(consumeNotice: Bool) async -> Result<HistoryUsage, HistoryFailure> { .failure(.unavailable) }
    func delete(_ id: CaptureID) async -> Result<Void, HistoryFailure> { .failure(.unavailable) }
    func finalizedImage(_ id: CaptureID) async -> Result<(revision: UInt64, pngData: Data), HistoryFailure> {
        .failure(.unavailable)
    }
}

/// Each callback occurs after the named durable step. Resume deleting rows at launch.
public enum HistoryEvictionPoint: String, CaseIterable, Sendable {
    case markedDeleting, imageUnlinked, recordUnlinked, thumbnailUnlinked, directoriesSynced, rowRemoved
}
