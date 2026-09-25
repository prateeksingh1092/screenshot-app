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

/// Export names follow macOS screenshots: `Frisket 2026-09-25 at 14.03.07.png`, in local time at the
/// moment of the save, with ` (2)`, ` (3)` … on collisions (ticket 81). Dots, not colons: Finder shows a colon as a slash.
public enum ExportFilenamePolicy {
    public static func filename(at date: Date, in timeZone: TimeZone, collisionIndex: UInt = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { value.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "00" }
        let suffix = collisionIndex == 0 ? "" : " (\(collisionIndex + 1))"
        return "Frisket \(c.year ?? 0)-\(two(c.month))-\(two(c.day)) at \(two(c.hour)).\(two(c.minute)).\(two(c.second))\(suffix).png"
    }
}
