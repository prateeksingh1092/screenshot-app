import Foundation
import Darwin
import GRDB
import ImageIO

/// History storage (DA-4 and DA-11; ticket 78). A finalized capture is one atomic PNG write,
/// `images/<UUID>.png`, plus one GRDB row at SQLite's default durability. `thumbnails/<UUID>.png`
/// is a disposable cache. The launch sweep adopts a row-less UUID-named PNG (a crash between the
/// write and the row), drops a row whose image is gone, and removes files it does not own.
/// There is no lock, no staging directory, no sidecar and no ownership ledger.
///
/// Disk access is lazy: initialization and an empty query create nothing.
public actor HistoryStore: CaptureHistory, HistoryRowSource {
    private let root: URL
    private let clock: @Sendable () -> Date
    private let evictionPoint: @Sendable (HistoryEvictionPoint) throws -> Void
    private let commitPoint: @Sendable (HistoryCommitPoint) throws -> Void
    private let diagnostics: any DiagnosticSink
    private var recoveryFailure: HistoryFailure?
    private var launchRecoveryPending = false
    private var recoveredOnce = false
    private var closed = false
    private var database: DatabaseQueue?
    private var measurementFailed = false
    private var limits: HistoryLimits

    deinit { try? database?.close() }

    public init(root: URL, limits: HistoryLimits = HistoryLimits(), clock: @escaping @Sendable () -> Date = { Date() },
                diagnostics: any DiagnosticSink = DroppedDiagnostics(),
                commitPoint: @escaping @Sendable (HistoryCommitPoint) throws -> Void = { _ in },
                evictionPoint: @escaping @Sendable (HistoryEvictionPoint) throws -> Void = { _ in }) {
        self.diagnostics = diagnostics
        self.limits = limits
        self.root = root
        self.clock = clock
        self.commitPoint = commitPoint
        self.evictionPoint = evictionPoint
    }

    /// Starts one launch sweep. Queries, finalizations and maintenance also join the startup
    /// gate, so scheduling the task cannot expose unrecovered History.
    public static func launch(root: URL, limits: HistoryLimits = HistoryLimits(),
                              diagnostics: any DiagnosticSink = DroppedDiagnostics()) -> HistoryStore {
        let store = HistoryStore(launchRoot: root, limits: limits, diagnostics: diagnostics)
        Task { await store.ensureLaunchRecovery() }
        return store
    }

    private init(launchRoot: URL, limits: HistoryLimits, diagnostics: any DiagnosticSink) {
        root = launchRoot
        clock = { Date() }
        commitPoint = { _ in }
        evictionPoint = { _ in }
        self.limits = limits
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
            return .success(())
        } catch { return .failure(.unavailable) }
    }

    public func availability() async -> HistoryFailure? {
        if !recoveredOnce { _ = await recover() }
        if closed { return .unavailable }
        return recoveryFailure
    }

    public func recover() async -> Result<HistoryRecoveryReport, HistoryFailure> {
        recoveredOnce = true
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
            try validateRootLayout()
            if try isReconciled() {
                return .success(HistoryRecoveryReport(logicalBytes: try totalLogicalBytes(), removedMissingImages: 0))
            }
            let database = try writableDatabase(recovering: true)
            let removedMissingImages = try sweep(database)
            try checkpoint(database)
            // Closing lets a clean second sweep use an immutable read; row actions reopen on demand (D19).
            try database.close()
            self.database = nil
            return .success(HistoryRecoveryReport(logicalBytes: try totalLogicalBytes(), removedMissingImages: removedMissingImages))
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    /// Rows first: a row whose image is gone is dropped, and sizes follow the files. Then files:
    /// a row-less `images/<UUID>.png` that decodes is adopted; anything else the store does not
    /// own in `images/` and `thumbnails/` is removed, as is any `staging/` an earlier build left.
    private func sweep(_ database: DatabaseQueue) throws -> Int {
        try removeIfPresent(root.appendingPathComponent("staging"))
        try removeIfPresent(backupDirectory)
        var missingImages = 0
        for entry in try readEntries(database) {
            let id = entry.captureID.rawValue.uuidString
            let image = imageURL(id)
            let thumbnail = thumbnailURL(id)
            guard try exists(image) else {
                try removeIfPresent(thumbnail)
                try database.write { try $0.execute(sql: "DELETE FROM history WHERE id = ?", arguments: [entry.key]) }
                missingImages += 1
                continue
            }
            let imageBytes = try logicalSize(image)
            let thumbnailBytes = try exists(thumbnail) ? try logicalSize(thumbnail) : 0
            if imageBytes != entry.imageBytes || thumbnailBytes != entry.thumbnailBytes {
                try database.write { db in
                    try db.execute(sql: "UPDATE history SET image_bytes = ?, thumbnail_bytes = ? WHERE id = ?",
                                   arguments: [imageBytes, thumbnailBytes, entry.key])
                }
            }
        }
        var known = Set(try readEntries(database).map { $0.captureID.rawValue.uuidString })
        for file in try children("images") {
            guard let id = Self.identifier(of: file) else {
                try FileManager.default.removeItem(at: file) // a `.partial`, a sidecar, or a foreign name
                continue
            }
            if known.contains(id) { continue }
            if try adopt(file, identifier: id, database: database) { known.insert(id) }
            else { try FileManager.default.removeItem(at: file) } // not a whole PNG: not a capture
        }
        for file in try children("thumbnails") {
            if let id = Self.identifier(of: file), known.contains(id) { continue }
            try FileManager.default.removeItem(at: file)
        }
        return missingImages
    }

    /// A crash between the atomic PNG write and the row leaves only the PNG. It was authorized
    /// (the write happens only inside `finalize`), so it is adopted, never deleted. The file has
    /// no revision or date of its own: the row takes revision 1 and the file's modification date.
    private func adopt(_ file: URL, identifier: String, database: DatabaseQueue) throws -> Bool {
        let data = try Data(contentsOf: file)
        guard let size = Self.decodedSize(data) else { return false }
        let bytes = try logicalSize(file)
        let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? clock()
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO history (capture_identifier, revision, width, height, image_bytes, thumbnail_bytes, finalized_at)
                VALUES (?, 1, ?, ?, ?, 0, ?)
                """, arguments: [identifier, size.width, size.height, bytes, modified.timeIntervalSince1970])
        }
        return true
    }

    /// Forces the pixels to decode: ImageIO can return a header-valid image whose compressed pixels are corrupt.
    private static func decodedSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let pixels = image.dataProvider?.data, CFDataGetLength(pixels) > 0 else { return nil }
        return (image.width, image.height)
    }

    /// The canonical capture identifier of `<UUID>.png`, or nil for any other name.
    private static func identifier(of file: URL) -> String? {
        guard file.pathExtension == "png" else { return nil }
        let name = file.deletingPathExtension().lastPathComponent
        return UUID(uuidString: name)?.uuidString == name ? name : nil
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
        guard try isCurrentSchema(reader) else { return false }
        guard try !exists(root.appendingPathComponent("staging")), try !exists(backupDirectory) else { return false }
        var expectedImages = Set<String>()
        var expectedThumbnails = Set<String>()
        for entry in try readEntries(reader) {
            let id = entry.captureID.rawValue.uuidString
            expectedImages.insert("\(id).png")
            guard try exists(imageURL(id)), try logicalSize(imageURL(id)) == entry.imageBytes else { return false }
            if entry.thumbnailBytes > 0 {
                expectedThumbnails.insert("\(id).png")
                guard try exists(thumbnailURL(id)), try logicalSize(thumbnailURL(id)) == entry.thumbnailBytes else { return false }
            }
        }
        return try Set(children("images").map(\.lastPathComponent)) == expectedImages
            && Set(try children("thumbnails").map(\.lastPathComponent)) == expectedThumbnails
    }

    private func imageURL(_ id: String) -> URL { root.appendingPathComponent("images/\(id).png") }
    private func thumbnailURL(_ id: String) -> URL { root.appendingPathComponent("thumbnails/\(id).png") }
    private var backupDirectory: URL { root.appendingPathComponent("migration-backup") }

    private func children(_ directory: String) throws -> [URL] {
        let url = root.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard try fileKind(url) == S_IFDIR else { throw HistoryFailure.unavailable }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Does not follow links: a dangling link still exists.
    private func exists(_ url: URL) throws -> Bool {
        var metadata = stat()
        if lstat(url.path, &metadata) == 0 { return true }
        guard errno == ENOENT else { throw HistoryFailure.unavailable }
        return false
    }

    private func removeIfPresent(_ url: URL) throws {
        if try exists(url) { try FileManager.default.removeItem(at: url) }
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
            let entries = try readExisting { db in
                try Row.fetchAll(db, sql: "SELECT * FROM history ORDER BY finalized_at, id").map(Self.entry(from:))
            }
            return .success(entries ?? [])
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    public func finalize(_ request: AuthorizedFinalization) async -> CommitOutcome {
        await ensureLaunchRecovery()
        return finalizeAfterRecovery(request)
    }

    public func delete(_ id: CaptureID) async -> Result<Void, HistoryFailure> {
        await ensureLaunchRecovery()
        do {
            guard !closed else { throw HistoryFailure.unavailable }
            if let recoveryFailure { throw recoveryFailure }
            let database = try writerForExistingHistory()
            guard let entry = try readEntry(id, database) else { throw HistoryFailure.unavailable }
            try evict([entry], database: database)
            return .success(())
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    private func writerForExistingHistory() throws -> DatabaseQueue {
        if let database { return database }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) else {
            throw HistoryFailure.unavailable
        }
        return try writableDatabase()
    }

    /// History window rows, newest first, from one query. Rows carry no file names or paths.
    public func rows() async -> Result<[HistoryItem], HistoryFailure> {
        await ensureLaunchRecovery()
        do {
            let rows = try readExisting { db in
                try Row.fetchAll(db, sql: """
                    SELECT capture_identifier, revision, width, height, finalized_at FROM history
                    ORDER BY finalized_at DESC, id DESC
                    """).map { row in
                    guard let uuid = UUID(uuidString: try row.decode(forColumn: "capture_identifier")) else {
                        throw HistoryFailure.unavailable
                    }
                    return HistoryItem(captureID: CaptureID(uuid), revision: try Self.revision(of: row),
                                       width: try row.decode(forColumn: "width"), height: try row.decode(forColumn: "height"),
                                       finalizedAt: Date(timeIntervalSince1970: try row.decode(forColumn: "finalized_at")))
                }
            }
            return .success(rows ?? [])
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    /// The cached thumbnail of one History item, looked up by ID.
    public func thumbnailPNG(_ id: CaptureID) async -> Data? {
        await ensureLaunchRecovery()
        guard let entry = try? readExisting({ try Self.entry(id, in: $0) }) ?? nil, entry.thumbnailBytes > 0,
              let thumbnail = try? ownedURL(thumbnailURL(entry.captureID.rawValue.uuidString)) else { return nil }
        return try? Data(contentsOf: thumbnail)
    }

    public func finalizedImage(_ id: CaptureID) async -> Result<(revision: UInt64, pngData: Data), HistoryFailure> {
        await ensureLaunchRecovery()
        do {
            guard let entry = try readExisting({ try Self.entry(id, in: $0) }) ?? nil else { throw HistoryFailure.unavailable }
            let data = try Data(contentsOf: try ownedURL(imageURL(entry.captureID.rawValue.uuidString)))
            guard !data.isEmpty else { throw HistoryFailure.invalidImage }
            return .success((entry.revision, data))
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    // D19: recovery closes the writer after its checkpoint, and a relaunch never opens it, so row
    // actions open what they need on demand. A root with no History database has no rows, and
    // nothing is created for it: this returns nil. A database from before this schema needs the
    // launch sweep to migrate it; a query never writes, so it reports `recoveryRequired`.
    private func readExisting<T>(_ body: (Database) throws -> T) throws -> T? {
        guard !closed else { throw HistoryFailure.unavailable }
        if let recoveryFailure { throw recoveryFailure }
        if let database { return try database.read(body) }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) else { return nil }
        let reader = try readOnlyDatabase()
        defer { try? reader.close() }
        try validateMigrations(reader)
        guard try isCurrentSchema(reader) else { throw HistoryFailure.recoveryRequired }
        return try reader.read(body)
    }

    private func finalizeAfterRecovery(_ request: AuthorizedFinalization) -> CommitOutcome {
        var committed = false
        var imageWriteAttempted = false
        let identifier = request.revision.captureID.rawValue.uuidString
        let partial = root.appendingPathComponent("images/\(identifier).partial")
        do {
            guard !measurementFailed else { throw HistoryFailure.unavailable }
            guard let source = CGImageSourceCreateWithData(request.pngData as CFData, nil),
                  CGImageSourceGetType(source) as String? == "public.png",
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw HistoryFailure.invalidImage
            }
            let finalizedAt = clock()
            let thumbnailData = try makeThumbnail(source: source)
            guard Int64(request.pngData.count) + Int64(thumbnailData.count) <= limits.maximumBytes else {
                return .notCommitted(.captureExceedsHistoryLimit)
            }
            let database = try writableDatabase()
            _ = try usageBytes(database) // Every required size read must succeed before committing.
            // Never replace the image of a committed row.
            guard try readEntry(request.revision.captureID, database) == nil else {
                throw HistoryFailure.unavailable
            }
            imageWriteAttempted = true
            // The atomic write: whole bytes under a name the sweep never adopts, then one rename.
            try removeIfPresent(partial)
            try request.pngData.write(to: partial, options: .withoutOverwriting)
            try commitPoint(.imageStaged)
            guard Darwin.rename(partial.path, imageURL(identifier).path) == 0 else { throw HistoryFailure.unavailable }
            try commitPoint(.imageWritten)
            // A failed size read must not turn into a committed row.
            let imageBytes = try logicalSize(imageURL(identifier))
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO history (capture_identifier, revision, width, height, image_bytes, thumbnail_bytes, finalized_at)
                    VALUES (?, ?, ?, ?, ?, 0, ?)
                    """, arguments: [identifier, Int64(request.revision.number), image.width, image.height,
                                      imageBytes, finalizedAt.timeIntervalSince1970])
            }
            committed = true
            try commitPoint(.rowCommitted)
            try? cacheThumbnail(data: thumbnailData, identifier: identifier, database: database)
            try commitPoint(.thumbnailCached)
            try enforce(database, protecting: identifier)
            return .committed
        } catch {
            // A post-commit cache or injected failure cannot undo History.
            if committed { return .committed }
            // Failed writes can leave authorized pixels that the next sweep adopts. Do not describe
            // that revision as safely editable: a later redaction cannot erase them.
            if imageWriteAttempted {
                try? removeIfPresent(partial)
                return .notCommitted(.recoveryRequired)
            }
            switch error {
            case HistoryFailure.unknownMigrations: return .notCommitted(.unknownMigrations)
            case HistoryFailure.invalidImage: return .notCommitted(.invalidImage)
            case HistoryFailure.recoveryRequired: return .notCommitted(.recoveryRequired)
            default: return .notCommitted(.historyUnavailable)
            }
        }
    }

    /// Explicit launch/settings maintenance; an unused History root stays absent.
    /// `maintain` and `status` are `async` like their `CaptureHistory` requirements: a synchronous
    /// actor method loses overload resolution to the protocol extension's `.unavailable` default
    /// when the app awaits it on a `HistoryStore` directly.
    public func maintain(limits: HistoryLimits?) async -> Result<HistoryUsage, HistoryFailure> {
        await ensureLaunchRecovery()
        return maintainNow(limits: limits)
    }

    public func status(consumeNotice: Bool) async -> Result<HistoryUsage, HistoryFailure> {
        await ensureLaunchRecovery()
        return statusNow(consumeNotice: consumeNotice)
    }

    private func maintainNow(limits: HistoryLimits?) -> Result<HistoryUsage, HistoryFailure> {
        if let limits { self.limits = limits }
        do {
            guard database != nil || FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) else {
                return .success(HistoryUsage(limits: self.limits, usageBytes: 0))
            }
            let database = try writableDatabase()
            measurementFailed = true
            try remeasure(database)
            measurementFailed = false
            try enforce(database, protecting: nil)
            return statusNow(consumeNotice: false)
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    private func statusNow(consumeNotice: Bool) -> Result<HistoryUsage, HistoryFailure> {
        do {
            guard !measurementFailed else { throw HistoryFailure.unavailable }
            guard database != nil || FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path) else {
                return .success(HistoryUsage(limits: limits, usageBytes: 0))
            }
            let database = try writableDatabase()
            try checkpoint(database)
            let usage = try usageBytes(database)
            let row = try database.read { try Row.fetchOne($0, sql: "SELECT * FROM history_retention WHERE id = 1") }
            guard let row else { throw HistoryFailure.unavailable }
            let last: Double? = try row.decode(forColumn: "last_quota_eviction")
            let pending: Bool = try row.decode(forColumn: "quota_notice_pending")
            if consumeNotice && pending {
                try database.write { try $0.execute(sql: "UPDATE history_retention SET quota_notice_pending = 0 WHERE id = 1") }
                try checkpoint(database)
            }
            return .success(HistoryUsage(limits: limits, usageBytes: usage,
                lastQuotaEviction: last.map(Date.init(timeIntervalSince1970:)), quotaNoticePending: pending,
                ageEvictionDeferred: try row.decode(forColumn: "age_deferred")))
        } catch let failure as HistoryFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }

    private func checkpoint(_ database: DatabaseQueue) throws {
        _ = try database.writeWithoutTransaction { try $0.checkpoint(.truncate) }
    }

    /// Refuses a location whose directory resolves outside the root (a linked `images/`).
    private func ownedURL(_ url: URL) throws -> URL {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
            throw HistoryFailure.unavailable
        }
        return url
    }

    /// Row sizes follow the files. A missing image fails maintenance and blocks commits until
    /// a sweep drops the row; a missing thumbnail is only an empty cache.
    private func remeasure(_ database: DatabaseQueue) throws {
        let measurements = try readEntries(database).map { entry -> (Int64, Int64, Int64) in
            let id = entry.captureID.rawValue.uuidString
            let image = try logicalSize(try ownedURL(imageURL(id)))
            let thumbnail = try ownedURL(thumbnailURL(id))
            return (entry.key, image, try exists(thumbnail) ? try logicalSize(thumbnail) : 0)
        }
        _ = try usageBytes(database)
        try database.write { db in
            for (key, image, thumbnail) in measurements {
                try db.execute(sql: "UPDATE history SET image_bytes = ?, thumbnail_bytes = ? WHERE id = ?",
                               arguments: [image, thumbnail, key])
            }
        }
    }

    private func usageBytes(_ database: DatabaseQueue) throws -> Int64 {
        let rows = try database.read { try Int64.fetchOne($0,
            sql: "SELECT COALESCE(SUM(image_bytes + thumbnail_bytes), 0) FROM history") }
        guard var total = rows else { throw HistoryFailure.unavailable }
        for suffix in ["", "-wal", "-shm"] {
            let file = root.appendingPathComponent("history.sqlite" + suffix)
            if suffix.isEmpty || FileManager.default.fileExists(atPath: file.path) {
                total += try logicalSize(file)
            }
        }
        return total
    }

    /// One batch: age first, then oldest-first until the quota holds, never the capture just committed.
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
        let candidates = try readEntries(database).filter { $0.captureID.rawValue.uuidString != identifier }
        let cutoff = Date(timeIntervalSince1970: now - window)
        let aged = deferred ? [] : candidates.filter { $0.finalizedAt < cutoff }
        // Measure once, with the WAL folded in, then subtract what the batch removes.
        try checkpoint(database)
        var usage = try usageBytes(database) - aged.reduce(0) { $0 + $1.imageBytes + $1.thumbnailBytes }
        let agedKeys = Set(aged.map(\.key))
        var overQuota: [HistoryEntry] = []
        for entry in candidates where !agedKeys.contains(entry.key) {
            guard usage > limits.maximumBytes else { break }
            overQuota.append(entry)
            usage -= entry.imageBytes + entry.thumbnailBytes
        }
        try evict(aged + overQuota, database: database, quota: !overQuota.isEmpty)
    }

    /// Files first, then every row in one transaction and one checkpoint for the whole batch.
    private func evict(_ batch: [HistoryEntry], database: DatabaseQueue, quota: Bool = false) throws {
        guard !batch.isEmpty else { return }
        if quota {
            try database.write { db in
                try db.execute(sql: "UPDATE history_retention SET last_quota_eviction = ?, quota_notice_pending = 1 WHERE id = 1",
                    arguments: [clock().timeIntervalSince1970])
            }
        }
        for entry in batch {
            let id = entry.captureID.rawValue.uuidString
            for url in [imageURL(id), thumbnailURL(id)] {
                if unlink(try ownedURL(url).path) != 0 && errno != ENOENT { throw HistoryFailure.unavailable }
            }
        }
        try evictionPoint(.filesUnlinked)
        try database.write { db in
            for entry in batch { try db.execute(sql: "DELETE FROM history WHERE id = ?", arguments: [entry.key]) }
        }
        try checkpoint(database)
        try evictionPoint(.rowsRemoved)
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
        try data.write(to: thumbnailURL(identifier), options: .atomic)
        let size = Int64(data.count)
        try database.write { db in
            try db.execute(sql: "UPDATE history SET thumbnail_bytes = ? WHERE capture_identifier = ?", arguments: [size, identifier])
        }
    }

    private func readOnlyDatabase() throws -> DatabaseQueue {
        // SQLite READONLY alone may create/change -shm. An immutable read
        // creates no sidecars, but ignores WAL: refuse outstanding WAL first.
        // The launch sweep reconciles it.
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

    private func isCurrentSchema(_ database: DatabaseQueue) throws -> Bool {
        try database.read { try Self.migrator().hasCompletedMigrations($0) }
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
        var excludedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedRoot.setResourceValues(values)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        let isNewDatabase = !FileManager.default.fileExists(atPath: root.appendingPathComponent("history.sqlite").path)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Must precede creation of the first table. secure_delete is per connection.
            // Durability is SQLite's default (DA-11): no synchronous or fullfsync overrides.
            if isNewDatabase { try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL") }
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let opened = try DatabaseQueue(path: root.appendingPathComponent("history.sqlite").path, configuration: configuration)
        do {
            try opened.writeWithoutTransaction { db in
                guard try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL") == "wal" else { throw HistoryFailure.unavailable }
            }
            try migrate(opened)
            database = opened
            return opened
        } catch {
            try? opened.close()
            throw error
        }
    }

    /// Existing History (the sidecar schema) migrates behind a backup of its database. The backup
    /// sits in the Time Machine-excluded root and is excluded itself; it is deleted once the
    /// migration's own check (every finalized row survives) and SQLite's integrity check pass.
    /// A failed migration rolls back and leaves the backup in place.
    private func migrate(_ database: DatabaseQueue) throws {
        let migrator = Self.migrator()
        let applied = try database.read { try migrator.appliedIdentifiers($0) }
        let upgrading = applied.contains("history-v1") && !applied.contains(Self.rowsOnlyMigration)
        if upgrading {
            try removeIfPresent(backupDirectory)
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
            var excluded = backupDirectory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            let backup = try DatabaseQueue(path: backupDirectory.appendingPathComponent("history.sqlite").path)
            try database.backup(to: backup)
            try backup.close()
            // A row the old store was deleting has no place in the new table; finish its unlinks
            // first, or the sweep would adopt its image back into History.
            let deleting = try database.read { db in
                try String.fetchAll(db, sql: "SELECT capture_identifier FROM history WHERE state = 'deleting'")
            }
            for id in deleting where UUID(uuidString: id)?.uuidString == id {
                for url in [imageURL(id), thumbnailURL(id), root.appendingPathComponent("images/\(id).finalization.json")] {
                    try removeIfPresent(url)
                }
            }
        }
        try migrator.migrate(database)
        guard upgrading else { return }
        let integrity = try database.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
        guard integrity == "ok" else { throw HistoryFailure.unavailable }
        try removeIfPresent(root.appendingPathComponent("staging"))
        for file in try children("images") where file.lastPathComponent.hasSuffix(".finalization.json") {
            try FileManager.default.removeItem(at: file)
        }
        try removeIfPresent(backupDirectory)
    }

    private static let rowsOnlyMigration = "history-rows-v1"

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
        // Ticket 78: one row per finalized capture, locations derived from the identifier. The
        // sidecar columns, the `deleting` state and the auxiliary ledger go. The check inside the
        // migration rolls it back unless every finalized row survives with a canonical identifier.
        migrator.registerMigration(rowsOnlyMigration) { db in
            let finalized = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history WHERE state = 'finalized'") ?? 0
            try db.execute(sql: """
                CREATE TABLE history_rows (
                    id INTEGER PRIMARY KEY,
                    capture_identifier TEXT NOT NULL UNIQUE,
                    revision INTEGER NOT NULL CHECK (revision > 0),
                    width INTEGER NOT NULL CHECK (width > 0),
                    height INTEGER NOT NULL CHECK (height > 0),
                    image_bytes INTEGER NOT NULL CHECK (image_bytes >= 0),
                    thumbnail_bytes INTEGER NOT NULL DEFAULT 0 CHECK (thumbnail_bytes >= 0),
                    finalized_at REAL NOT NULL,
                    date_normalized INTEGER NOT NULL DEFAULT 0
                );
                INSERT INTO history_rows (id, capture_identifier, revision, width, height, image_bytes,
                        thumbnail_bytes, finalized_at, date_normalized)
                    SELECT id, capture_identifier, revision, width, height, image_bytes,
                        CASE WHEN thumbnail_location IS NULL THEN 0 ELSE thumbnail_bytes END, finalized_at, date_normalized
                    FROM history WHERE state = 'finalized';
                DROP TABLE history;
                ALTER TABLE history_rows RENAME TO history;
                CREATE INDEX history_age ON history(finalized_at, id);
                DROP TABLE history_auxiliary_files;
                """)
            let identifiers = try String.fetchAll(db, sql: "SELECT capture_identifier FROM history")
            guard identifiers.count == finalized,
                  identifiers.allSatisfy({ UUID(uuidString: $0)?.uuidString == $0 }) else { throw HistoryFailure.unavailable }
        }
        return migrator
    }

    private func readEntries(_ database: DatabaseQueue) throws -> [HistoryEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM history ORDER BY finalized_at, id").map(Self.entry(from:))
        }
    }

    private func readEntry(_ id: CaptureID, _ database: DatabaseQueue) throws -> HistoryEntry? {
        try database.read { try Self.entry(id, in: $0) }
    }

    /// One History item by ID; the capture identifier is unique and indexed.
    private static func entry(_ id: CaptureID, in db: Database) throws -> HistoryEntry? {
        try Row.fetchOne(db, sql: "SELECT * FROM history WHERE capture_identifier = ?",
                         arguments: [id.rawValue.uuidString]).map(entry(from:))
    }

    /// Every column is decoded with GRDB's throwing `decode`: an unreadable value is a
    /// `HistoryFailure`, never a trap in GRDB's non-optional subscript.
    private static func entry(from row: Row) throws -> HistoryEntry {
        let identifier: String = try row.decode(forColumn: "capture_identifier")
        guard let uuid = UUID(uuidString: identifier), uuid.uuidString == identifier else { throw HistoryFailure.unavailable }
        return HistoryEntry(key: try row.decode(forColumn: "id"), captureID: CaptureID(uuid), revision: try revision(of: row),
            width: try row.decode(forColumn: "width"), height: try row.decode(forColumn: "height"),
            imageBytes: try row.decode(forColumn: "image_bytes"), thumbnailBytes: try row.decode(forColumn: "thumbnail_bytes"),
            finalizedAt: Date(timeIntervalSince1970: try row.decode(forColumn: "finalized_at")))
    }

    private static func revision(of row: Row) throws -> UInt64 {
        guard let revision = UInt64(exactly: try row.decode(Int64.self, forColumn: "revision")) else { throw HistoryFailure.unavailable }
        return revision
    }

    private func logicalSize(_ location: URL) throws -> Int64 {
        var metadata = stat()
        guard lstat(location.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size >= 0 else { throw HistoryFailure.unavailable }
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
        for name in ["images", "thumbnails"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), try fileKind(url) != S_IFDIR { throw HistoryFailure.unavailable }
        }
    }
}
