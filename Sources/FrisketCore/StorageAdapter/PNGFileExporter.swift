import Foundation
import Darwin

/// Writes a separate export from frozen bytes; never opens or moves a History image.
public actor PNGFileExporter: CaptureExport {
    private let folder: @Sendable () async -> URL
    private let historyRoot: URL

    public init(folder: @escaping @Sendable () async -> URL, historyRoot: URL) {
        self.folder = folder
        self.historyRoot = historyRoot
    }

    public func export(_ request: AuthorizedFinalization) async -> Result<ExportReceipt, ExportFailure> {
        let destination = Self.resolvedDestination(await folder())
        if case let .refused(reason) = Self.assess(folder: destination, historyRoot: historyRoot) {
            return .failure(reason)
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            if case let .refused(reason) = Self.assess(folder: destination, historyRoot: historyRoot) {
                return .failure(reason)
            }
            // Exclusive creation also handles another writer winning the name race.
            for collision in UInt(0)..<10_000 {
                let filename = ExportFilenamePolicy.filename(for: request.revision, collisionIndex: collision)
                let file = destination.appendingPathComponent(filename)
                let descriptor = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
                if descriptor < 0 {
                    if errno == EEXIST { continue }
                    return .failure(.unavailable)
                }
                var succeeded = request.pngData.withUnsafeBytes { bytes -> Bool in
                    var offset = 0
                    while offset < bytes.count {
                        let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                        if count < 0 && errno == EINTR { continue }
                        guard count > 0 else { return false }
                        offset += count
                    }
                    return fsync(descriptor) == 0
                }
                if Darwin.close(descriptor) != 0 { succeeded = false }
                guard succeeded else {
                    // Only remove the file this attempt exclusively created.
                    _ = Darwin.unlink(file.path)
                    return .failure(.unavailable)
                }
                return .success(ExportReceipt(filename: filename))
            }
            return .failure(.unavailable)
        } catch {
            return .failure(.unavailable)
        }
    }

    /// Foundation may leave symlinks unresolved when the final child is absent.
    /// Resolve the existing ancestor first, then append only missing components.
    private nonisolated static func resolvedDestination(_ folder: URL) -> URL {
        var ancestor = folder.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/", !ancestor.path.isEmpty {
            missing.append(ancestor.lastPathComponent)
            ancestor = ancestor.deletingLastPathComponent()
        }
        return missing.reversed().reduce(ancestor.resolvingSymlinksInPath()) {
            $0.appendingPathComponent($1, isDirectory: true)
        }.standardizedFileURL
    }

    /// Read-only filesystem facts, shared by Settings and every delivery attempt.
    public nonisolated static func assess(folder: URL, historyRoot: URL,
                                         home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ExportFolderAssessment {
        guard folder.isFileURL else { return .refused(.unwritable) }
        let destination = resolvedDestination(folder)
        let root = resolvedDestination(historyRoot)
        let manager = FileManager.default
        var ancestor = destination
        var directory: ObjCBool = false
        while !manager.fileExists(atPath: ancestor.path, isDirectory: &directory) {
            guard ancestor.path != "/", !ancestor.path.isEmpty else { return .refused(.unwritable) }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return .refused(.unwritable) }
            ancestor = parent
        }
        let writable = directory.boolValue && manager.isWritableFile(atPath: ancestor.path)
            && manager.isExecutableFile(atPath: ancestor.path)
        let caseSensitive = (try? ancestor.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
        var ubiquitous = false
        var probe = ancestor
        while true {
            if (try? probe.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
                ubiquitous = true
                break
            }
            if probe.path == "/" || probe.path.isEmpty { break }
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path { break }
            probe = parent
        }
        return ExportFolderPolicy.assess(folderPath: destination.path, historyRootPath: root.path,
            homePath: home.resolvingSymlinksInPath().path, isWritable: writable, isUbiquitous: ubiquitous,
            isCaseSensitive: caseSensitive)
    }

}
