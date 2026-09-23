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
    private let evictionPoint: @Sendable (HistoryEvictionPoint) throws -> Void
    private let commitPoint: @Sendable (HistoryCommitPoint) throws -> Void
    private var database: DatabaseQueue?
    private var measurementFailed = false
    private var limits: HistoryLimits

    public init(root: URL, limits: HistoryLimits = HistoryLimits(), clock: @escaping @Sendable () -> Date = { Date() },
                commitPoint: @escaping @Sendable (HistoryCommitPoint) throws -> Void = { _ in },
                evictionPoint: @escaping @Sendable (HistoryEvictionPoint) throws -> Void = { _ in }) {
        self.limits = limits
        self.root = root
        self.clock = clock
        self.commitPoint = commitPoint
        self.evictionPoint = evictionPoint
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
        do {
            guard !measurementFailed else { throw HistoryFailure.unavailable }
            guard let source = CGImageSourceCreateWithData(request.pngData as CFData, nil),
                  CGImageSourceGetType(source) as String? == "public.png",
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw HistoryFailure.invalidImage
            }
            let identifier = request.revision.captureID.rawValue.uuidString
            let imageLocation = "images/\(identifier).png"
            let recordLocation = "images/\(identifier).finalization.json"
            let finalizedAt = clock()
            let record = FinalizationRecord(marker: "frisket.finalized.v1", captureIdentifier: identifier,
                revision: request.revision.number, width: image.width, height: image.height,
                imageBytes: Int64(request.pngData.count), finalizedAt: finalizedAt)
            let recordData = try JSONEncoder().encode(record)
            let thumbnailData = try makeThumbnail(source: source)
            guard Int64(request.pngData.count) + Int64(recordData.count) + Int64(thumbnailData.count) <= limits.maximumBytes else {
                return .notCommitted(.captureExceedsHistoryLimit)
            }
            let database = try writableDatabase()
            _ = try usageBytes(database) // Every required size read must succeed before committing.
            let stagingImage = root.appendingPathComponent("staging/\(identifier).png")
            let stagingRecord = root.appendingPathComponent("staging/\(identifier).finalization.json")
            try recordAuxiliary(identifier: identifier, location: "staging/\(identifier).png", bytes: Int64(request.pngData.count), database: database)
            try durableWrite(request.pngData, to: stagingImage, staged: .pngStaged, synced: .pngSynced)
            try recordAuxiliary(identifier: identifier, location: "staging/\(identifier).finalization.json", bytes: Int64(recordData.count), database: database)
            try durableWrite(recordData, to: stagingRecord, staged: .recordStaged, synced: .recordSynced)
            try renameExclusively(stagingImage, to: root.appendingPathComponent(imageLocation))
            try relocateAuxiliary(from: "staging/\(identifier).png", to: imageLocation, database: database)
            try commitPoint(.imageRenamed)
            try renameExclusively(stagingRecord, to: root.appendingPathComponent(recordLocation))
            try relocateAuxiliary(from: "staging/\(identifier).finalization.json", to: recordLocation, database: database)
            try commitPoint(.recordRenamed)
            try syncDirectory(root.appendingPathComponent("images"))
            try syncDirectory(root.appendingPathComponent("staging"))
            try syncDirectory(root)
            try commitPoint(.directorySynced)
            // A failed size read must not turn into a committed row.
            let imageBytes = try logicalSize(root.appendingPathComponent(imageLocation))
            let recordBytes = try logicalSize(root.appendingPathComponent(recordLocation))
            _ = try usageBytes(database)
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO history (capture_identifier, revision, image_location, record_location,
                        width, height, image_bytes, record_bytes, finalized_at, state)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'finalized')
                    """, arguments: [identifier, Int64(request.revision.number), imageLocation, recordLocation,
                                      image.width, image.height, imageBytes, recordBytes, finalizedAt.timeIntervalSince1970])
                try db.execute(sql: "DELETE FROM history_auxiliary_files WHERE capture_identifier = ?", arguments: [identifier])
            }
            committed = true
            try commitPoint(.rowCommitted)
            try? cacheThumbnail(data: thumbnailData, identifier: identifier, database: database)
            try commitPoint(.thumbnailCached)
            try enforce(database, protecting: identifier)
            return .committed
        } catch {
            // A post-commit cache or injected failure cannot undo durable History.
            if committed { return .committed }
            switch error {
            case HistoryFailure.unknownMigrations: return .notCommitted(.unknownMigrations)
            case HistoryFailure.invalidImage: return .notCommitted(.invalidImage)
            case HistoryFailure.recoveryRequired: return .notCommitted(.recoveryRequired)
            default: return .notCommitted(.historyUnavailable)
            }
        }
    }

    /// Explicit launch/settings maintenance; an unused History root stays absent.
    public func maintain(limits: HistoryLimits?) -> Result<HistoryUsage, HistoryFailure> {
        if let limits { self.limits = limits }
        do {
            guard database != nil || FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) else {
                return .success(HistoryUsage(limits: self.limits, usageBytes: 0))
            }
            let database = try writableDatabase()
            measurementFailed = true
            for entry in try readEntries(database, includeDeleting: true) where entry.state == .deleting {
                try evict(entry, database: database)
            }
            try remeasure(database)
            measurementFailed = false
            try enforce(database, protecting: nil)
            return status(consumeNotice: false)
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    public func status(consumeNotice: Bool) -> Result<HistoryUsage, HistoryFailure> {
        do {
            guard !measurementFailed else { throw HistoryFailure.unavailable }
            guard let database else {
                if FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) {
                    return .failure(.recoveryRequired)
                }
                return .success(HistoryUsage(limits: limits, usageBytes: 0))
            }
            try checkpoint(database)
            let usage = try usageBytes(database)
            let row = try database.read { try Row.fetchOne($0, sql: "SELECT * FROM history_retention WHERE id = 1")! }
            let last: Double? = row["last_quota_eviction"]
            let pending: Bool = row["quota_notice_pending"]
            if consumeNotice && pending {
                try database.write { try $0.execute(sql: "UPDATE history_retention SET quota_notice_pending = 0 WHERE id = 1") }
                try checkpoint(database)
            }
            return .success(HistoryUsage(limits: limits, usageBytes: usage,
                lastQuotaEviction: last.map(Date.init(timeIntervalSince1970:)), quotaNoticePending: pending,
                ageEvictionDeferred: row["age_deferred"]))
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    private func checkpoint(_ database: DatabaseQueue) throws {
        _ = try database.writeWithoutTransaction { try $0.checkpoint(.truncate) }
    }

    private func ownedLocations(_ entry: HistoryEntry) throws -> [URL] {
        let id = entry.captureID.rawValue.uuidString
        guard entry.imageLocation == "images/\(id).png",
              entry.recordLocation == "images/\(id).finalization.json",
              entry.thumbnailLocation == nil || entry.thumbnailLocation == "thumbnails/\(id).png" else {
            throw HistoryFailure.unavailable
        }
        return try [entry.imageLocation, entry.recordLocation, entry.thumbnailLocation].compactMap { location in
            guard let location else { return nil }
            let url = root.appendingPathComponent(location)
            guard url.deletingLastPathComponent().resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
                throw HistoryFailure.unavailable
            }
            return url
        }
    }

    private func recordAuxiliary(identifier: String, location: String, bytes: Int64, database: DatabaseQueue) throws {
        try database.write { db in
            try db.execute(sql: "INSERT INTO history_auxiliary_files (capture_identifier, location, logical_bytes) VALUES (?, ?, ?)",
                arguments: [identifier, location, bytes])
        }
    }

    private func relocateAuxiliary(from: String, to: String, database: DatabaseQueue) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE history_auxiliary_files SET location = ? WHERE location = ?", arguments: [to, from])
        }
    }

    private func remeasureAuxiliary(_ database: DatabaseQueue) throws {
        let rows = try database.read { try Row.fetchAll($0, sql: "SELECT * FROM history_auxiliary_files") }
        for row in rows {
            let id: String = row["capture_identifier"]
            let location: String = row["location"]
            guard UUID(uuidString: id)?.uuidString == id,
                  ["staging/\(id).png", "staging/\(id).finalization.json", "images/\(id).png",
                   "images/\(id).finalization.json"].contains(location) else { throw HistoryFailure.unavailable }
            var measuredLocation = location
            // A process may die between a rename and updating the ownership ledger.
            if location.hasPrefix("staging/"), !FileManager.default.fileExists(atPath: root.appendingPathComponent(location).path) {
                measuredLocation = "images/" + root.appendingPathComponent(location).lastPathComponent
            }
            let url = root.appendingPathComponent(measuredLocation)
            guard url.deletingLastPathComponent().resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
                throw HistoryFailure.unavailable
            }
            // Missing intended files can precede the first write, or have been removed by recovery.
            var info = stat()
            if lstat(url.path, &info) != 0 {
                guard errno == ENOENT else { throw HistoryFailure.unavailable }
                try database.write { try $0.execute(sql: "DELETE FROM history_auxiliary_files WHERE location = ?", arguments: [location]) }
            } else {
                let bytes = try logicalSize(url)
                try database.write { try $0.execute(sql: "UPDATE history_auxiliary_files SET location = ?, logical_bytes = ? WHERE location = ?",
                    arguments: [measuredLocation, bytes, location]) }
            }
        }
    }

    private func remeasure(_ database: DatabaseQueue) throws {
        let measurements = try readEntries(database).map { entry -> (Int64, [Int64]) in
            (entry.key, try ownedLocations(entry).map { try logicalSize($0) })
        }
        try remeasureAuxiliary(database)
        // Validate SQLite sidecars too, before publishing any measured sizes.
        _ = try usageBytes(database)
        try database.write { db in
            for (key, sizes) in measurements {
                try db.execute(sql: "UPDATE history SET image_bytes = ?, record_bytes = ?, thumbnail_bytes = ? WHERE id = ?",
                    arguments: [sizes[0], sizes[1], sizes.count == 3 ? sizes[2] : 0, key])
            }
        }
    }

    private func usageBytes(_ database: DatabaseQueue) throws -> Int64 {
        var total = try database.read { try Int64.fetchOne($0,
            sql: "SELECT (SELECT COALESCE(SUM(image_bytes + record_bytes + thumbnail_bytes), 0) FROM history) + (SELECT COALESCE(SUM(logical_bytes), 0) FROM history_auxiliary_files)")! }
        for suffix in ["", "-wal", "-shm"] {
            let file = root.appendingPathComponent("history.sqlite" + suffix)
            if suffix.isEmpty || FileManager.default.fileExists(atPath: file.path) {
                total += try logicalSize(file)
            }
        }
        return total
    }

    private func enforce(_ database: DatabaseQueue, protecting identifier: String?) throws {
        let now = clock().timeIntervalSince1970
        let window = Double(limits.retentionDays) * 86_400
        let deferred = try database.write { db -> Bool in
            let newest = try Double.fetchOne(db, sql: "SELECT MAX(finalized_at) FROM history")
            let last = try Double.fetchOne(db, sql: "SELECT last_sweep FROM history_retention WHERE id = 1")
            let anomalous = newest.map { now < $0 } == true || (last ?? newest).map { now - $0 > window } == true
            // Persist the normalization flag so repeated rollbacks cannot keep rewriting dates.
            try db.execute(sql: "UPDATE history SET finalized_at = ?, date_normalized = 1 WHERE finalized_at > ? AND date_normalized = 0",
                arguments: [now, now])
            try db.execute(sql: "UPDATE history_retention SET last_sweep = ?, age_deferred = ? WHERE id = 1",
                arguments: [now, anomalous])
            return anomalous
        }
        if !deferred {
            let cutoff = Date(timeIntervalSince1970: now - window)
            for entry in try readEntries(database) where entry.finalizedAt < cutoff && entry.captureID.rawValue.uuidString != identifier {
                try evict(entry, database: database)
            }
        }
        try checkpoint(database)
        for entry in try readEntries(database) where entry.captureID.rawValue.uuidString != identifier {
            guard try usageBytes(database) > limits.maximumBytes else { break }
            try evict(entry, database: database, quota: true)
            try checkpoint(database)
        }
    }

    private func evict(_ entry: HistoryEntry, database: DatabaseQueue, quota: Bool = false) throws {
        let locations = try ownedLocations(entry)
        try database.write { db in
            try db.execute(sql: "UPDATE history SET state = 'deleting' WHERE id = ?", arguments: [entry.key])
            if quota {
                try db.execute(sql: "UPDATE history_retention SET last_quota_eviction = ?, quota_notice_pending = 1 WHERE id = 1",
                    arguments: [clock().timeIntervalSince1970])
            }
        }
        try checkpoint(database)
        try evictionPoint(.markedDeleting)
        let points: [HistoryEvictionPoint] = [.imageUnlinked, .recordUnlinked, .thumbnailUnlinked]
        for index in 0..<3 {
            if index < locations.count {
                if unlink(locations[index].path) != 0 && errno != ENOENT { throw HistoryFailure.unavailable }
            }
            try evictionPoint(points[index])
        }
        try syncDirectory(root.appendingPathComponent("images"))
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("thumbnails").path) {
            try syncDirectory(root.appendingPathComponent("thumbnails"))
        }
        try evictionPoint(.directoriesSynced)
        try database.write { db in
            try db.execute(sql: "DELETE FROM history WHERE id = ?", arguments: [entry.key])
        }
        try checkpoint(database)
        try evictionPoint(.rowRemoved)
    }

    private func makeThumbnail(source: CGImageSource) throws -> Data {
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
        return data as Data
    }

    private func cacheThumbnail(data: Data, identifier: String, database: DatabaseQueue) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("thumbnails"), withIntermediateDirectories: true)
        let location = "thumbnails/\(identifier).png"
        let url = root.appendingPathComponent(location)
        try data.write(to: url, options: .atomic)
        let size = Int64(data.count)
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
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
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
        migrator.registerMigration("history-retention-v1") { db in
            try db.execute(sql: """
                CREATE TABLE history_retention (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    last_quota_eviction REAL,
                    quota_notice_pending INTEGER NOT NULL DEFAULT 0,
                    last_sweep REAL,
                    age_deferred INTEGER NOT NULL DEFAULT 0
                );
                INSERT INTO history_retention (id) VALUES (1);
                ALTER TABLE history ADD COLUMN date_normalized INTEGER NOT NULL DEFAULT 0;
                CREATE TABLE history_auxiliary_files (
                    capture_identifier TEXT NOT NULL,
                    location TEXT PRIMARY KEY,
                    logical_bytes INTEGER NOT NULL CHECK (logical_bytes >= 0)
                );
                """)
        }
        return migrator
    }

    private func readEntries(_ database: DatabaseQueue, includeDeleting: Bool = false) throws -> [HistoryEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM history WHERE state = 'finalized' OR ? ORDER BY finalized_at, id", arguments: [includeDeleting]).map { row in
                guard let uuid = UUID(uuidString: row["capture_identifier"]) else { throw HistoryFailure.unavailable }
                return HistoryEntry(key: row["id"], captureID: CaptureID(uuid), revision: UInt64(row["revision"] as Int64),
                    imageLocation: row["image_location"], recordLocation: row["record_location"],
                    thumbnailLocation: row["thumbnail_location"], width: row["width"], height: row["height"],
                    imageBytes: row["image_bytes"], recordBytes: row["record_bytes"], thumbnailBytes: row["thumbnail_bytes"],
                    finalizedAt: Date(timeIntervalSince1970: row["finalized_at"]), state: HistoryState(rawValue: row["state"])!)
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
        var info = stat()
        guard lstat(location.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            throw HistoryFailure.unavailable
        }
        return Int64(info.st_size)
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
