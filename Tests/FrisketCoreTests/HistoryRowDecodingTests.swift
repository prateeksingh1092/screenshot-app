import Foundation
import FrisketCore
import Testing

/// Ticket 77: a History row that cannot be read is a typed `HistoryFailure`, never a trap.
private let pixels = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!

private struct RowPixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> { .success(CaptureImage(pngData: pixels)) }
}

private struct RowClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> { .success(ClipboardReceipt(changeCount: 1)) }
}

private func sqlite(_ root: URL, _ sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [root.appendingPathComponent("history.sqlite").path, sql]
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
}

private enum UnreadableColumn: String, CaseIterable {
    case finalizedAt = "UPDATE history SET finalized_at = 'yesterday';"
    case width = "UPDATE history SET width = 'wide';"
    case imageBytes = "UPDATE history SET image_bytes = 'many';"
}

@Suite struct HistoryRowDecodingTests {
    @Test(arguments: UnreadableColumn.allCases)
    fileprivate func anUnreadableRowIsAHistoryFailure(column: UnreadableColumn) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = HistoryStore(root: root, limits: HistoryLimits(retentionDays: 40_000))
        let commands = CaptureLifecycleCoordinator(permission: GrantedTestPermission(), source: RowPixels(),
            clipboard: RowClipboard(), pendingByteLimit: 1024, history: history)
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        _ = await commands.execute(.capture(revision.captureID, maximumBytes: 1024))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        try await history.close().get()
        try sqlite(root, column.rawValue)

        let reopened = HistoryStore(root: root, limits: HistoryLimits(retentionDays: 40_000))
        #expect(await reopened.entries() == .failure(.unavailable))
        if column != .imageBytes {   // The History window's rows don't read sizes.
            #expect(await reopened.rows() == .failure(.unavailable))
        }
    }
}
