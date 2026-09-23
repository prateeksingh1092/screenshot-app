import Darwin
import Foundation

/// One rendered copy under `staging/drag`. The file is removed only after the promise
/// write completion has returned and the drag session has ended, in either order.
/// Launch recovery empties `staging/` recursively, so a leftover here is swept.
public actor DragStagingLifetime: DragCopyStaging {
    private struct StagedCopy {
        let url: URL
        var writeReturned = false
        var sessionEnded = false
    }

    private let directory: URL
    private let commitPoint: @Sendable (HistoryCommitPoint) throws -> Void
    private var staged: [UUID: StagedCopy] = [:]

    public init(directory: URL, commitPoint: @escaping @Sendable (HistoryCommitPoint) throws -> Void = { _ in }) {
        self.directory = directory
        self.commitPoint = commitPoint
    }

    public func stage(_ request: AuthorizedFinalization) async throws -> DragStagingID {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        try writeExclusive(request.pngData, to: url)
        try syncDirectory(directory)
        staged[id] = StagedCopy(url: url)
        try commitPoint(.dragStaged)
        return DragStagingID(rawValue: id)
    }

    public func promiseWriteReturned(_ id: DragStagingID) async throws {
        guard var copy = staged[id.rawValue], !copy.writeReturned else { return }
        copy.writeReturned = true
        staged[id.rawValue] = copy
        try commitPoint(.dragPromiseWritten)
        removeIfFinished(id.rawValue)
    }

    public func dragSessionEnded(_ id: DragStagingID) async {
        guard var copy = staged[id.rawValue], !copy.sessionEnded else { return }
        copy.sessionEnded = true
        staged[id.rawValue] = copy
        removeIfFinished(id.rawValue)
    }

    /// Copies the rendered bytes to the destination the promise receiver provides.
    public func writePromiseCopy(_ pngData: Data, to destination: URL) async throws {
        try pngData.write(to: destination, options: .atomic)
    }

    private func removeIfFinished(_ id: UUID) {
        guard let copy = staged[id], copy.writeReturned, copy.sessionEnded else { return }
        try? FileManager.default.removeItem(at: copy.url)
        staged[id] = nil
    }

    private func writeExclusive(_ data: Data, to location: URL) throws {
        let descriptor = Darwin.open(location.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw DragStagingError.unavailable }
        defer { Darwin.close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw DragStagingError.unavailable }
                offset += count
            }
        }
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else { throw DragStagingError.unavailable }
    }

    private func syncDirectory(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DragStagingError.unavailable }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw DragStagingError.unavailable }
    }
}

private enum DragStagingError: Error { case unavailable }
