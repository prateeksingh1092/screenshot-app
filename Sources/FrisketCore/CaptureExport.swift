import Foundation

public struct ExportReceipt: Equatable, Sendable {
    public let filename: String
    public init(filename: String) { self.filename = filename }
}

public enum ExportFailure: Error, Equatable, Sendable { case unavailable, insideHistory, unwritable }

/// Only an authorized frozen revision can reach the file export adapter.
public protocol CaptureExport: Sendable {
    func export(_ request: AuthorizedFinalization) async -> Result<ExportReceipt, ExportFailure>
}

public enum SaveDeliveryOutcome: Equatable, Sendable {
    case saved(ExportReceipt)
    case failed(ExportFailure)
}

public struct SaveOutcome: Equatable, Sendable {
    public let revision: CaptureRevision
    public let commit: CommitOutcome
    public let delivery: SaveDeliveryOutcome
    public init(revision: CaptureRevision, commit: CommitOutcome, delivery: SaveDeliveryOutcome) {
        self.revision = revision
        self.commit = commit
        self.delivery = delivery
    }
}

public enum ExportFilenamePolicy {
    /// Stable base per rendered revision; suffixes begin at 2 on collisions.
    public static func filename(for revision: CaptureRevision, collisionIndex: UInt = 0) -> String {
        let suffix = collisionIndex == 0 ? "" : "-\(collisionIndex + 1)"
        return "Frisket-\(revision.captureID.rawValue.uuidString)-r\(revision.number)\(suffix).png"
    }
}
