import Foundation
import Darwin

/// Writes a separate export from frozen bytes; never opens or moves a History image.
public actor PNGFileExporter: CaptureExport {
    private let folder: @Sendable () async -> URL
    private let historyRoot: URL
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(folder: @escaping @Sendable () async -> URL, historyRoot: URL,
                now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.folder = folder
        self.historyRoot = historyRoot
        self.now = now
        self.timeZone = timeZone
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
            // Publish only complete PNGs. The temporary file is exclusively
            // created in this folder so the exclusive rename stays on one volume.
            let temporary = destination.appendingPathComponent(".Frisket-\(UUID().uuidString).tmp")
            let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                         S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            guard descriptor >= 0 else { return .failure(.unavailable) }
            var temporaryExists = true
            defer { if temporaryExists { _ = Darwin.unlink(temporary.path) } }
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
            guard succeeded else { return .failure(.unavailable) }
            let savedAt = now()
            for collision in UInt(0)..<10_000 {
                let filename = ExportFilenamePolicy.filename(at: savedAt, in: timeZone, collisionIndex: collision)
                let file = destination.appendingPathComponent(filename)
                if renamex_np(temporary.path, file.path, UInt32(RENAME_EXCL)) == 0 {
                    temporaryExists = false
                    return .success(ExportReceipt(filename: filename))
                }
                if errno != EEXIST { return .failure(.unavailable) }
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

    /// Match existing ancestors by volume and file identity, then compare any
    /// missing suffix. This also protects roots that have not been created yet.
    private nonisolated static func isInside(_ destination: URL, root: URL, caseSensitive: Bool) -> Bool {
        let manager = FileManager.default
        var rootAncestor = root
        var rootSuffix: [String] = []
        while !manager.fileExists(atPath: rootAncestor.path), rootAncestor.path != "/" {
            rootSuffix.insert(rootAncestor.lastPathComponent, at: 0)
            rootAncestor = rootAncestor.deletingLastPathComponent()
        }
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey, .fileResourceIdentifierKey]
        guard let rootValues = try? rootAncestor.resourceValues(forKeys: keys),
              let rootVolume = rootValues.volumeIdentifier as? NSObject,
              let rootFile = rootValues.fileResourceIdentifier as? NSObject else { return false }
        func normalized(_ parts: [String]) -> [String] {
            caseSensitive ? parts : parts.map { $0.lowercased() }
        }
        var probe = destination
        var suffix: [String] = []
        while true {
            if let values = try? probe.resourceValues(forKeys: keys),
               let volume = values.volumeIdentifier as? NSObject,
               let file = values.fileResourceIdentifier as? NSObject,
               rootVolume.isEqual(volume), rootFile.isEqual(file),
               normalized(suffix).starts(with: normalized(rootSuffix)) {
                return true
            }
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path || probe.path == "/" { return false }
            suffix.insert(probe.lastPathComponent, at: 0)
            probe = parent
        }
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
        let roots = [root] + ExportFolderPolicy.historyRootPaths(homePath: home.path).map {
            resolvedDestination(URL(fileURLWithPath: $0, isDirectory: true))
        }
        if roots.contains(where: { isInside(destination, root: $0, caseSensitive: caseSensitive) }) {
            return .refused(.insideHistory)
        }
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
