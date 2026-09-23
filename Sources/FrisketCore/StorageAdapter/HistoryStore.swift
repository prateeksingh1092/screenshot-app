import Foundation
import Darwin
import GRDB
import ImageIO

/// Disk access is lazy: initialization and an empty query create nothing.
/// A single instance owns the root during this process; launch locking and
/// reconciliation belong to ticket 10.
public actor HistoryStore: CaptureHistory {
    private let root: URL
    private let clock: @Sendable () -> Date
    private let commitPoint: @Sendable (HistoryCommitPoint) throws -> Void
    private var database: DatabaseQueue?

    public init(root: URL, clock: @escaping @Sendable () -> Date = { Date() },
                commitPoint: @escaping @Sendable (HistoryCommitPoint) throws -> Void = { _ in }) {
        self.root = root
        self.clock = clock
        self.commitPoint = commitPoint
    }

    public func entries() -> Result<[HistoryEntry], HistoryFailure> {
        do {
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

    public func finalize(_ request: AuthorizedFinalization) -> CommitOutcome {
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
        // Ticket 10 must reconcile it under its exclusive recovery lock.
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

    private func writableDatabase() throws -> DatabaseQueue {
        if let database { return database }
        guard root.lastPathComponent.hasSuffix(".noindex") else { throw HistoryFailure.unavailable }
        // Refuse future schemas before setting attributes, PRAGMAs, or creating files.
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) {
            let reader = try readOnlyDatabase()
            defer { try? reader.close() }
            try validateMigrations(reader)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excludedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedRoot.setResourceValues(values)
        for directory in ["staging", "images"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: false)
        }
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Must precede creation of the first table. secure_delete is per connection.
            try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL; PRAGMA secure_delete = ON; PRAGMA synchronous = FULL; PRAGMA fullfsync = ON; PRAGMA checkpoint_fullfsync = ON")
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
        let values = try location.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else { throw HistoryFailure.unavailable }
        return Int64(size)
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
