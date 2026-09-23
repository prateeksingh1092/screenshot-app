import Foundation
import Darwin
import GRDB
import ImageIO

/// Disk access is lazy: initialization and an empty query create nothing.
/// The directory lock is held until this store is released, including while
/// History queries and authorized commits run.
public actor HistoryStore: CaptureHistory {
    private let root: URL
    private let clock: @Sendable () -> Date
    private let commitPoint: @Sendable (HistoryCommitPoint) throws -> Void
    private let diagnostics: any DiagnosticSink
    private var recoveryFailure: HistoryFailure?
    private var launchRecoveryPending = false
    private var closed = false
    private var database: DatabaseQueue?
    private var rootLock: HistoryRootLock?

    deinit { try? database?.close() }

    public init(root: URL, clock: @escaping @Sendable () -> Date = { Date() },
                diagnostics: any DiagnosticSink = LocalDiagnosticLog(),
                commitPoint: @escaping @Sendable (HistoryCommitPoint) throws -> Void = { _ in }) {
        self.diagnostics = diagnostics
        self.root = root
        self.clock = clock
        self.commitPoint = commitPoint
    }

    /// Starts one launch sweep. Queries and finalizations also join the startup
    /// gate, so scheduling the task cannot expose unrecovered History.
    public static func launch(root: URL, diagnostics: any DiagnosticSink = LocalDiagnosticLog()) -> HistoryStore {
        let store = HistoryStore(launchRoot: root, diagnostics: diagnostics)
        Task { await store.ensureLaunchRecovery() }
        return store
    }

    private init(launchRoot: URL, diagnostics: any DiagnosticSink) {
        root = launchRoot
        clock = { Date() }
        commitPoint = { _ in }
        self.diagnostics = diagnostics
        launchRecoveryPending = true
    }

    private func ensureLaunchRecovery() async {
        guard launchRecoveryPending else { return }
        _ = await recover()
    }

    /// Deterministic shutdown for owners rebuilding over the same root. A closed
    /// instance never reopens; construct a new store for the next session.
    public func close() -> Result<Void, HistoryFailure> {
        closed = true
        launchRecoveryPending = false
        do {
            try database?.close()
            database = nil
            rootLock = nil
            return .success(())
        } catch { return .failure(.unavailable) }
    }

    public func recover() async -> Result<HistoryRecoveryReport, HistoryFailure> {
        launchRecoveryPending = false
        let result = performRecovery()
        switch result {
        case let .success(report):
            recoveryFailure = nil
            if report.removedMissingImages > 0 {
                await diagnostics.record(DiagnosticEvent(name: .historyImageMissing, operation: .launchRecovery,
                    error: DiagnosticError(domain: .history, code: .missingHistoryImage)))
            }
            await diagnostics.record(DiagnosticEvent(name: .historyRecovered, operation: .launchRecovery))
        case let .failure(failure):
            recoveryFailure = failure
            let code: DiagnosticErrorCode
            switch failure {
            case .unavailable: code = .unavailable
            case .unknownMigrations: code = .unknownMigrations
            case .invalidImage: code = .invalidImage
            case .recoveryRequired: code = .recoveryRequired
            case .rootLocked: code = .rootLocked
            }
            await diagnostics.record(DiagnosticEvent(name: .historyRecoveryFailed, operation: .launchRecovery,
                error: DiagnosticError(domain: .history, code: code)))
        }
        return result
    }

    private func performRecovery() -> Result<HistoryRecoveryReport, HistoryFailure> {
        do {
            guard !closed else { throw HistoryFailure.unavailable }
            guard FileManager.default.fileExists(atPath: root.path) else {
                return .success(HistoryRecoveryReport(logicalBytes: 0, removedMissingImages: 0))
            }
            try acquireRootLock()
            try validateRootLayout()
            if try isReconciled() {
                return .success(HistoryRecoveryReport(logicalBytes: try totalLogicalBytes(), removedMissingImages: 0))
            }
            let database = try writableDatabase(recovering: true)
            let removedMissingImages = try reconcileRows(database)
            for file in try children("staging") { try FileManager.default.removeItem(at: file) }
            let known = Set(try readEntries(database).map { $0.captureID.rawValue.uuidString })
            for file in try children("images")
                where file.pathExtension == "png" {
                let identifier = file.deletingPathExtension().lastPathComponent
                guard !known.contains(identifier) else { continue }
                guard UUID(uuidString: identifier)?.uuidString == identifier else {
                    try FileManager.default.removeItem(at: file)
                    continue
                }
                let recordLocation = "images/\(identifier).finalization.json"
                let recordURL = root.appendingPathComponent(recordLocation)
                guard let record = try validRecord(identifier: identifier, imageURL: file, recordURL: recordURL) else {
                    try FileManager.default.removeItem(at: file)
                    try removeIfPresent(recordURL)
                    continue
                }
                let imageBytes = try logicalSize(file)
                let recordBytes = try logicalSize(recordURL)
                try database.write { db in
                    try db.execute(sql: """
                        INSERT INTO history (capture_identifier, revision, image_location, record_location,
                            width, height, image_bytes, record_bytes, finalized_at, state)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'finalized')
                        """, arguments: [identifier, Int64(record.revision), "images/\(identifier).png", recordLocation,
                                          record.width, record.height, imageBytes, recordBytes, record.finalizedAt.timeIntervalSince1970])
                }
            }
            let entries = try readEntries(database)
            let records = Set(entries.map(\.recordLocation))
            for file in try children("images") where file.lastPathComponent.hasSuffix(".finalization.json") {
                if !records.contains("images/" + file.lastPathComponent) { try FileManager.default.removeItem(at: file) }
            }
            let thumbnails = Set(entries.compactMap(\.thumbnailLocation))
            for file in try children("thumbnails") {
                if !thumbnails.contains("thumbnails/" + file.lastPathComponent) { try FileManager.default.removeItem(at: file) }
            }
            for directory in ["images", "staging", "thumbnails"] {
                let url = root.appendingPathComponent(directory)
                if FileManager.default.fileExists(atPath: url.path) { try syncDirectory(url) }
            }
            _ = try database.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
            try database.close()
            self.database = nil
            return .success(HistoryRecoveryReport(logicalBytes: try totalLogicalBytes(), removedMissingImages: removedMissingImages))
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    private func reconcileRows(_ database: DatabaseQueue) throws -> Int {
        let rows = try database.read { db in try Row.fetchAll(db, sql: "SELECT * FROM history ORDER BY id") }
        var missingImages = 0
        for row in rows {
            let identifier: String = row["capture_identifier"]
            let imageLocation: String = row["image_location"]
            let recordLocation: String = row["record_location"]
            let thumbnailLocation: String? = row["thumbnail_location"]
            try validateLocations(identifier: identifier, image: imageLocation, record: recordLocation, thumbnail: thumbnailLocation)
            let imageURL = root.appendingPathComponent(imageLocation)
            let missing = !FileManager.default.fileExists(atPath: imageURL.path)
            if row["state"] as String == "deleting" || missing {
                for location in [imageLocation, recordLocation, thumbnailLocation].compactMap({ $0 }) {
                    try removeIfPresent(root.appendingPathComponent(location))
                }
                // Unlink before row removal so a second sweep can finish this deletion.
                for directory in ["images", "thumbnails"] {
                    let url = root.appendingPathComponent(directory)
                    if FileManager.default.fileExists(atPath: url.path) { try syncDirectory(url) }
                }
                try database.write { db in try db.execute(sql: "DELETE FROM history WHERE capture_identifier = ?", arguments: [identifier]) }
                if missing && row["state"] as String == "finalized" { missingImages += 1 }
                continue
            }
            let imageBytes = try logicalSize(imageURL)
            let recordURL = root.appendingPathComponent(recordLocation)
            let recordBytes = FileManager.default.fileExists(atPath: recordURL.path) ? try logicalSize(recordURL) : 0
            let thumbnail = thumbnailLocation.flatMap { location in
                FileManager.default.fileExists(atPath: root.appendingPathComponent(location).path) ? location : nil
            }
            let thumbnailBytes = try thumbnail.map { try logicalSize(root.appendingPathComponent($0)) } ?? 0
            if imageBytes != row["image_bytes"] || recordBytes != row["record_bytes"] || thumbnailBytes != row["thumbnail_bytes"] || thumbnail != thumbnailLocation {
                try database.write { db in
                    try db.execute(sql: "UPDATE history SET image_bytes = ?, record_bytes = ?, thumbnail_location = ?, thumbnail_bytes = ? WHERE capture_identifier = ?",
                        arguments: [imageBytes, recordBytes, thumbnail, thumbnailBytes, identifier])
                }
            }
        }
        return missingImages
    }

    private func validateLocations(identifier: String, image: String, record: String, thumbnail: String?) throws {
        guard let uuid = UUID(uuidString: identifier), uuid.uuidString == identifier,
              image == "images/\(identifier).png", record == "images/\(identifier).finalization.json",
              thumbnail == nil || thumbnail == "thumbnails/\(identifier).png" else { throw HistoryFailure.unavailable }
    }

    // A no-op sweep must not even open a writer: SQLite can alter its header
    // or shared-memory bookkeeping without changing any History rows.
    private func isReconciled() throws -> Bool {
        guard database == nil, FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) else { return false }
        let reader: DatabaseQueue
        do { reader = try readOnlyDatabase() }
        catch HistoryFailure.recoveryRequired { return false }
        defer { try? reader.close() }
        try validateMigrations(reader)
        let entries = try readEntries(reader)
        let count = try reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history") }
        guard count == entries.count, try children("staging").isEmpty else { return false }
        var expectedImages = Set<String>()
        var expectedThumbnails = Set<String>()
        for entry in entries {
            try validateLocations(identifier: entry.captureID.rawValue.uuidString, image: entry.imageLocation,
                                  record: entry.recordLocation, thumbnail: entry.thumbnailLocation)
            expectedImages.insert(entry.imageLocation)
            for (location, bytes) in [(entry.imageLocation, entry.imageBytes), (entry.recordLocation, entry.recordBytes)] {
                let file = root.appendingPathComponent(location)
                if FileManager.default.fileExists(atPath: file.path) {
                    expectedImages.insert(location)
                    guard try logicalSize(file) == bytes else { return false }
                } else if location == entry.imageLocation || bytes != 0 { return false }
            }
            if let location = entry.thumbnailLocation {
                expectedThumbnails.insert(location)
                let file = root.appendingPathComponent(location)
                guard FileManager.default.fileExists(atPath: file.path), try logicalSize(file) == entry.thumbnailBytes else { return false }
            } else if entry.thumbnailBytes != 0 { return false }
        }
        return try Set(children("images").map { "images/" + $0.lastPathComponent }) == expectedImages
            && Set(try children("thumbnails").map { "thumbnails/" + $0.lastPathComponent }) == expectedThumbnails
    }

    private func acquireRootLockIfPresent() throws {
        if FileManager.default.fileExists(atPath: root.path) { try acquireRootLock() }
    }

    private func acquireRootLock() throws {
        guard rootLock == nil else { return }
        guard root.lastPathComponent.hasSuffix(".noindex") else { throw HistoryFailure.unavailable }
        rootLock = try HistoryRootLock.acquire(root)
    }

    private func children(_ directory: String) throws -> [URL] {
        let url = root.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard try fileKind(url) == S_IFDIR else { throw HistoryFailure.unavailable }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func validRecord(identifier: String, imageURL: URL, recordURL: URL) throws -> FinalizationRecord? {
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        let data = try Data(contentsOf: recordURL)
        let imageData = try Data(contentsOf: imageURL)
        guard let record = try? JSONDecoder().decode(FinalizationRecord.self, from: data),
              record.marker == "frisket.finalized.v1", record.captureIdentifier == identifier,
              record.revision > 0, record.revision <= UInt64(Int64.max),
              record.finalizedAt.timeIntervalSince1970.isFinite,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              image.width == record.width, image.height == record.height,
              let pixels = image.dataProvider?.data, CFDataGetLength(pixels) > 0 else { return nil }
        guard record.imageBytes == (try logicalSize(imageURL)) else { return nil }
        return record
    }

    private func totalLogicalBytes() throws -> Int64 {
        var total: Int64 = 0
        func count(_ directory: URL) throws {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
                if try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try count(file) }
                else { total += try logicalSize(file) }
            }
        }
        try count(root)
        return total
    }

    public func entries() async -> Result<[HistoryEntry], HistoryFailure> {
        await ensureLaunchRecovery()
        do {
            guard !closed else { throw HistoryFailure.unavailable }
            if let recoveryFailure { throw recoveryFailure }
            try acquireRootLockIfPresent()
            if let database { return .success(try readEntries(database)) }
            let path = root.appendingPathComponent("history.sqlite")
            guard FileManager.default.fileExists(atPath: path.path) else { return .success([]) }
            let reader = try readOnlyDatabase()
            defer { try? reader.close() }
            try validateMigrations(reader)
            return .success(try readEntries(reader))
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    public func finalize(_ request: AuthorizedFinalization) async -> CommitOutcome {
        await ensureLaunchRecovery()
        return finalizeAfterRecovery(request)
    }

    private func finalizeAfterRecovery(_ request: AuthorizedFinalization) -> CommitOutcome {
        var committed = false
        var imageWriteAttempted = false
        do {
            guard let source = CGImageSourceCreateWithData(request.pngData as CFData, nil),
                  CGImageSourceGetType(source) as String? == "public.png",
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw HistoryFailure.invalidImage
            }
            let database = try writableDatabase()
            let identifier = request.revision.captureID.rawValue.uuidString
            let imageLocation = "images/\(identifier).png"
            let recordLocation = "images/\(identifier).finalization.json"
            let finalizedAt = clock()
            let record = FinalizationRecord(marker: "frisket.finalized.v1", captureIdentifier: identifier,
                revision: request.revision.number, width: image.width, height: image.height,
                imageBytes: Int64(request.pngData.count), finalizedAt: finalizedAt)
            let recordData = try JSONEncoder().encode(record)
            let stagingImage = root.appendingPathComponent("staging/\(identifier).png")
            let stagingRecord = root.appendingPathComponent("staging/\(identifier).finalization.json")
            imageWriteAttempted = true
            try durableWrite(request.pngData, to: stagingImage, staged: .pngStaged, synced: .pngSynced)
            try durableWrite(recordData, to: stagingRecord, staged: .recordStaged, synced: .recordSynced)
            try renameExclusively(stagingImage, to: root.appendingPathComponent(imageLocation))
            try commitPoint(.imageRenamed)
            try renameExclusively(stagingRecord, to: root.appendingPathComponent(recordLocation))
            try commitPoint(.recordRenamed)
            try syncDirectory(root.appendingPathComponent("images"))
            try syncDirectory(root.appendingPathComponent("staging"))
            try syncDirectory(root)
            try commitPoint(.directorySynced)
            // A failed size read must not turn into a committed row.
            let imageBytes = try logicalSize(root.appendingPathComponent(imageLocation))
            let recordBytes = try logicalSize(root.appendingPathComponent(recordLocation))
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO history (capture_identifier, revision, image_location, record_location,
                        width, height, image_bytes, record_bytes, finalized_at, state)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'finalized')
                    """, arguments: [identifier, Int64(request.revision.number), imageLocation, recordLocation,
                                      image.width, image.height, imageBytes, recordBytes, finalizedAt.timeIntervalSince1970])
            }
            committed = true
            try commitPoint(.rowCommitted)
            try cacheThumbnail(source: source, identifier: identifier, database: database)
            try commitPoint(.thumbnailCached)
            return .committed
        } catch {
            // A post-commit cache or injected failure cannot undo durable History.
            if committed { return .committed }
            // Failed writes can leave authorized pixels for recovery. Do not describe
            // that revision as safely editable: a later redaction cannot erase them.
            if imageWriteAttempted { return .notCommitted(.recoveryRequired) }
            switch error {
            case HistoryFailure.unknownMigrations: return .notCommitted(.unknownMigrations)
            case HistoryFailure.invalidImage: return .notCommitted(.invalidImage)
            case HistoryFailure.recoveryRequired: return .notCommitted(.recoveryRequired)
            default: return .notCommitted(.historyUnavailable)
            }
        }
    }

    private func cacheThumbnail(source: CGImageSource, identifier: String, database: DatabaseQueue) throws {
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw HistoryFailure.invalidImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw HistoryFailure.unavailable
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw HistoryFailure.unavailable }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("thumbnails"), withIntermediateDirectories: true)
        let location = "thumbnails/\(identifier).png"
        let url = root.appendingPathComponent(location)
        try (data as Data).write(to: url, options: .atomic)
        let size = try logicalSize(url)
        try database.write { db in
            try db.execute(sql: "UPDATE history SET thumbnail_location = ?, thumbnail_bytes = ? WHERE capture_identifier = ?",
                           arguments: [location, size, identifier])
        }
    }

    private func readOnlyDatabase() throws -> DatabaseQueue {
        // SQLite READONLY alone may create/change -shm. An immutable read
        // creates no sidecars, but ignores WAL: refuse outstanding WAL first.
        // Launch recovery reconciles it under the exclusive root lock.
        for suffix in ["-wal", "-journal"] {
            let journal = root.appendingPathComponent("history.sqlite" + suffix)
            if FileManager.default.fileExists(atPath: journal.path), try logicalSize(journal) > 0 {
                throw HistoryFailure.recoveryRequired
            }
        }
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: root.appendingPathComponent("history.sqlite").absoluteString + "?immutable=1",
                                 configuration: configuration)
    }

    private func validateMigrations(_ database: DatabaseQueue) throws {
        try database.read { db in
            if try Self.migrator().hasBeenSuperseded(db) { throw HistoryFailure.unknownMigrations }
        }
    }

    // A crashed WAL/rollback journal must be applied to see migration state.
    // Do that to a disposable metadata-only copy first: refusing a future
    // schema must not create SHM or recover a journal in the original root.
    private func validateRecoverySnapshot() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for suffix in ["", "-wal", "-journal"] {
            let name = "history.sqlite" + suffix
            let source = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: temporary.appendingPathComponent(name))
            }
        }
        let reader = try DatabaseQueue(path: temporary.appendingPathComponent("history.sqlite").path)
        defer { try? reader.close() }
        try validateMigrations(reader)
    }

    private func writableDatabase(recovering: Bool = false) throws -> DatabaseQueue {
        guard !closed else { throw HistoryFailure.unavailable }
        if !recovering, let recoveryFailure { throw recoveryFailure }
        try acquireRootLockIfPresent()
        if let database { return database }
        guard root.lastPathComponent.hasSuffix(".noindex") else { throw HistoryFailure.unavailable }
        // Refuse future schemas before setting attributes, PRAGMAs, or creating files.
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) {
            if recovering { try validateRecoverySnapshot() }
            else {
                let reader = try readOnlyDatabase()
                defer { try? reader.close() }
                try validateMigrations(reader)
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try acquireRootLock()
        var excludedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedRoot.setResourceValues(values)
        for directory in ["staging", "images"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        let isNewDatabase = !FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Must precede creation of the first table. secure_delete is per connection.
            if isNewDatabase { try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL") }
            try db.execute(sql: "PRAGMA secure_delete = ON; PRAGMA synchronous = FULL; PRAGMA fullfsync = ON; PRAGMA checkpoint_fullfsync = ON")
        }
        let opened = try DatabaseQueue(path: root.appendingPathComponent("history.sqlite").path, configuration: configuration)
        do {
            try opened.writeWithoutTransaction { db in
                guard try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL") == "wal" else { throw HistoryFailure.unavailable }
            }
            try Self.migrator().migrate(opened)
            try syncDirectory(root)
            try syncDirectory(root.deletingLastPathComponent())
            database = opened
            return opened
        } catch {
            try? opened.close()
            throw error
        }
    }

    // Append migrations; never edit a shipped migration or enable erase-on-change.
    private static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("history-v1") { db in
            try db.execute(sql: """
                CREATE TABLE history (
                    id INTEGER PRIMARY KEY,
                    capture_identifier TEXT NOT NULL UNIQUE,
                    revision INTEGER NOT NULL CHECK (revision > 0),
                    image_location TEXT NOT NULL UNIQUE,
                    record_location TEXT NOT NULL UNIQUE,
                    thumbnail_location TEXT,
                    width INTEGER NOT NULL CHECK (width > 0),
                    height INTEGER NOT NULL CHECK (height > 0),
                    image_bytes INTEGER NOT NULL CHECK (image_bytes >= 0),
                    record_bytes INTEGER NOT NULL CHECK (record_bytes >= 0),
                    thumbnail_bytes INTEGER NOT NULL DEFAULT 0 CHECK (thumbnail_bytes >= 0),
                    finalized_at REAL NOT NULL,
                    state TEXT NOT NULL CHECK (state IN ('finalized', 'deleting'))
                );
                CREATE INDEX history_age ON history(finalized_at, id);
                """)
        }
        return migrator
    }

    private func readEntries(_ database: DatabaseQueue) throws -> [HistoryEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM history WHERE state = 'finalized' ORDER BY finalized_at, id").map { row in
                guard let uuid = UUID(uuidString: row["capture_identifier"]) else { throw HistoryFailure.unavailable }
                return HistoryEntry(key: row["id"], captureID: CaptureID(uuid), revision: UInt64(row["revision"] as Int64),
                    imageLocation: row["image_location"], recordLocation: row["record_location"],
                    thumbnailLocation: row["thumbnail_location"], width: row["width"], height: row["height"],
                    imageBytes: row["image_bytes"], recordBytes: row["record_bytes"], thumbnailBytes: row["thumbnail_bytes"],
                    finalizedAt: Date(timeIntervalSince1970: row["finalized_at"]), state: .finalized)
            }
        }
    }

    private func durableWrite(_ data: Data, to location: URL, staged: HistoryCommitPoint, synced: HistoryCommitPoint) throws {
        let descriptor = Darwin.open(location.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw HistoryFailure.unavailable }
        defer { Darwin.close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw HistoryFailure.unavailable }
                offset += count
            }
        }
        try commitPoint(staged)
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else { throw HistoryFailure.unavailable }
        try commitPoint(synced)
    }

    private func renameExclusively(_ source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw HistoryFailure.unavailable }
    }

    private func syncDirectory(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw HistoryFailure.unavailable }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw HistoryFailure.unavailable }
    }

    private func logicalSize(_ location: URL) throws -> Int64 {
        var metadata = stat()
        guard lstat(location.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG else { throw HistoryFailure.unavailable }
        return Int64(metadata.st_size)
    }

    private func fileKind(_ location: URL) throws -> mode_t {
        var metadata = stat()
        guard lstat(location.path, &metadata) == 0 else { throw HistoryFailure.unavailable }
        return metadata.st_mode & S_IFMT
    }

    private func validateRootLayout() throws {
        // Reject links before opening SQLite or reading/removing any owned file.
        // Recurse through archives as well so size accounting cannot escape root.
        func validate(_ directory: URL) throws {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                switch try fileKind(file) {
                case S_IFDIR: try validate(file)
                case S_IFREG: break
                default: throw HistoryFailure.unavailable
                }
            }
        }
        try validate(root)
        for name in ["images", "staging", "thumbnails"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), try fileKind(url) != S_IFDIR { throw HistoryFailure.unavailable }
        }
    }
}

/// Alongside the PNG, durable before the row. Recovery also has to decode the
/// image and compare dimensions; this marker alone never proves validity.
private struct FinalizationRecord: Codable {
    let marker: String
    let captureIdentifier: String
    let revision: UInt64
    let width: Int
    let height: Int
    let imageBytes: Int64
    let finalizedAt: Date
}

// A directory descriptor avoids creating a lock file on an unused root. Each
// open file description gets its own nonblocking flock, even in one process.
private final class HistoryRootLock: Sendable {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    static func acquire(_ root: URL) throws -> HistoryRootLock {
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw HistoryFailure.unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw code == EWOULDBLOCK ? HistoryFailure.rootLocked : HistoryFailure.unavailable
        }
        return HistoryRootLock(descriptor: descriptor)
    }
    deinit { Darwin.close(descriptor) }
}
