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
    func entries() async -> Result<[HistoryEntry], HistoryFailure>
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
