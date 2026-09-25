import Foundation
@testable import FrisketCore
import Testing

/// Ticket 74: the History window reads `HistoryStore.rows()` in one query and looks each
/// row's picture up by ID, so reloading costs time in proportion to the rows.
@Suite struct HistoryRowsTests {
    // A synthetic 2 x 1 opaque red PNG; no screen content.
    static let pixels = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!

    /// Commits `count` synthetic captures through the store's authorized finalization, oldest first.
    private static func seed(_ store: HistoryStore, count: Int) async throws -> [CaptureID] {
        var ids: [CaptureID] = []
        for _ in 0..<count {
            let revision = CaptureRevision(captureID: CaptureID(), number: 1)
            try #require(await store.finalize(AuthorizedFinalization(revision: revision, pngData: pixels)) == .committed)
            ids.append(revision.captureID)
        }
        return ids
    }

    private static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
    }

    @Test func rowsListNewestFirstAndEachPictureIsFoundByID() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = LockedClock()
        let store = HistoryStore(root: root, clock: { clock.next() })
        let ids = try await Self.seed(store, count: 3)
        let rows = try await store.rows().get()
        #expect(rows.map(\.captureID) == ids.reversed())
        #expect(rows.allSatisfy { $0.revision == 1 && $0.width == 2 && $0.height == 1 })
        for id in ids {
            let thumbnail = try #require(await store.thumbnailPNG(id))
            #expect(!thumbnail.isEmpty)
            #expect(try await store.finalizedImage(id).get().pngData == Self.pixels)
        }
        #expect(await store.thumbnailPNG(CaptureID()) == nil)
        #expect(await store.finalizedImage(CaptureID()).map(\.pngData) == .failure(.unavailable))
    }

    @Test func rowsOfAnEmptyRootCreateNothing() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        #expect(try await store.rows().get().isEmpty)
        #expect(await store.thumbnailPNG(CaptureID()) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func rowsAfterRelaunchReadWithoutOpeningTheWriter() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = HistoryStore(root: root)
        let ids = try await Self.seed(first, count: 2)
        try await first.close().get()
        let relaunched = HistoryStore.launch(root: root)
        #expect(try await relaunched.rows().get().map(\.captureID) == ids.reversed())
        #expect(await relaunched.thumbnailPNG(ids[0]) != nil)
    }

    /// A History reload is one `rows()` query plus one lookup by ID per visible row. The criterion
    /// is time in proportion to the rows, so ten times the rows must cost well under a hundred
    /// times as much (quadratic). Set `FRISKET_HISTORY_ROWS` to measure more rows, such as 1000.
    @Test func reloadTimeGrowsInProportionToTheRows() async throws {
        let large = ProcessInfo.processInfo.environment["FRISKET_HISTORY_ROWS"].flatMap(Int.init) ?? 200
        let small = max(1, large / 10)
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        _ = try await Self.seed(store, count: small)
        let smallTime = try await Self.reload(store, expecting: small)
        _ = try await Self.seed(store, count: large - small)
        let largeTime = try await Self.reload(store, expecting: large)
        print("history-reload rows=\(small) seconds=\(smallTime) rows=\(large) seconds=\(largeTime) ratio=\(largeTime / smallTime)")
        #expect(largeTime < smallTime * 40, "reloading \(large) rows took \(largeTime)s against \(smallTime)s for \(small)")
    }

    /// Best of three reloads: every row, then every row's picture by ID.
    private static func reload(_ store: HistoryStore, expecting count: Int) async throws -> Double {
        var best = Double.infinity
        for _ in 0..<3 {
            let start = ContinuousClock.now
            let rows = try await store.rows().get()
            for row in rows { _ = try #require(await store.thumbnailPNG(row.captureID)) }
            let elapsed = start.duration(to: .now)
            try #require(rows.count == count)
            best = min(best, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        return best
    }
}

/// Counts every read the History window makes, so a test can tell one query from per-row lookups.
private actor CountingRows: HistoryRowSource {
    private(set) var items: [HistoryItem]
    private(set) var rowQueries = 0
    private(set) var pictureLookups = 0
    init(count: Int) {
        items = (0..<count).map { index in
            HistoryItem(captureID: CaptureID(), revision: 1, width: 2, height: 1,
                        finalizedAt: Date(timeIntervalSince1970: Double(10_000 - index)))
        }
    }
    func add(_ item: HistoryItem) { items.insert(item, at: 0) }
    func rows() async -> Result<[HistoryItem], HistoryFailure> {
        rowQueries += 1
        return .success(items)
    }
    func thumbnailPNG(_ id: CaptureID) async -> Data? {
        pictureLookups += 1
        return Data(id.rawValue.uuidString.utf8)
    }
    func finalizedImage(_ id: CaptureID) async -> Result<(revision: UInt64, pngData: Data), HistoryFailure> {
        pictureLookups += 1
        return .failure(.unavailable)
    }
}

@MainActor @Suite struct HistoryListTests {
    /// Live, with ~240 History items and the window open, every Copy, Save or Close reloaded History
    /// with 240 thumbnail lookups and a redraw per row: Done took 48 s instead of 0.5 s.
    @Test func reloadingTwoHundredFortyRowsIsOneQueryWithNoPictureLookups() async throws {
        let source = CountingRows(count: 240)
        let list = HistoryList<Data>(source: source) { $0 }
        #expect(try await list.reload().get() == true)
        #expect(list.rows.count == 240)
        #expect(await source.rowQueries == 1)
        #expect(await source.pictureLookups == 0, "a reload looked pictures up row by row")
    }

    @Test func aReloadThatFindsTheSameRowsReportsNoChange() async throws {
        let source = CountingRows(count: 240)
        let list = HistoryList<Data>(source: source) { $0 }
        _ = await list.reload()
        #expect(try await list.reload().get() == false, "an unchanged History would redraw")
        let added = HistoryItem(captureID: CaptureID(), revision: 1, width: 2, height: 1, finalizedAt: Date(timeIntervalSince1970: 20_000))
        await source.add(added)
        #expect(try await list.reload().get() == true)
        #expect(list.rows.first == added)
    }

    /// D30: live, ⌘⇧1 kept an older row selected, so History Copy copied an older capture.
    @Test func openingHistorySelectsTheNewestRow() async throws {
        let source = CountingRows(count: 3)
        let list = HistoryList<Data>(source: source) { $0 }
        _ = await list.reload()
        let older = list.rows[2].captureID
        let added = HistoryItem(captureID: CaptureID(), revision: 1, width: 4, height: 3, finalizedAt: Date(timeIntervalSince1970: 20_000))
        await source.add(added)
        _ = await list.reload()
        #expect(list.selection(keeping: older, opening: true) == added.captureID, "opening History kept an older row")
        #expect(list.selection(keeping: nil, opening: true) == added.captureID)
    }

    @Test func aReloadWhileOpenKeepsTheUsersRow() async throws {
        let source = CountingRows(count: 3)
        let list = HistoryList<Data>(source: source) { $0 }
        _ = await list.reload()
        let chosen = list.rows[2].captureID
        await source.add(HistoryItem(captureID: CaptureID(), revision: 1, width: 4, height: 3, finalizedAt: Date(timeIntervalSince1970: 20_000)))
        _ = await list.reload()
        #expect(list.selection(keeping: chosen, opening: false) == chosen, "a commit took the user's selection away")
        #expect(list.selection(keeping: CaptureID(), opening: false) == list.rows.first?.captureID, "a vanished row should fall back to the newest")
        #expect(list.selection(keeping: nil, opening: false) == list.rows.first?.captureID)
    }

    @Test func aRowPictureIsLookedUpOnceByIDAndThenCached() async throws {
        let source = CountingRows(count: 240)
        let list = HistoryList<Data>(source: source) { $0 }
        _ = await list.reload()
        let row = list.rows[7]
        #expect(list.cachedPicture(row) == nil)
        #expect(await list.picture(for: row) == Data(row.captureID.rawValue.uuidString.utf8))
        #expect(await list.picture(for: row) != nil)
        _ = await list.reload()
        #expect(list.cachedPicture(row) != nil)
        #expect(await source.pictureLookups == 1)
    }

    @Test func thePictureCacheKeepsOnlyItsLimit() async throws {
        let source = CountingRows(count: 5)
        let list = HistoryList<Data>(source: source, pictureLimit: 2) { $0 }
        _ = await list.reload()
        for row in list.rows { _ = await list.picture(for: row) }
        #expect(list.rows.filter { list.cachedPicture($0) != nil } == Array(list.rows.suffix(2)))
    }

    /// The real store: a reload of 240 rows is one query. The budget is 100 ms, a tenth of the 1 s
    /// that editor open and Done may take live; this Intel Mac measures it at a few milliseconds.
    @Test func reloadingTwoHundredFortyStoredRowsStaysWithinBudget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".noindex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        for _ in 0..<240 {
            let revision = CaptureRevision(captureID: CaptureID(), number: 1)
            try #require(await store.finalize(AuthorizedFinalization(revision: revision, pngData: HistoryRowsTests.pixels)) == .committed)
        }
        var best = Duration.seconds(60)
        for _ in 0..<3 {
            let list = HistoryList<Data>(source: store) { $0 }
            let start = ContinuousClock.now
            #expect(try await list.reload().get() == true)
            best = min(best, start.duration(to: .now))
            #expect(list.rows.count == 240)
        }
        print("history-list-reload rows=240 best=\(best)")
        #expect(best < .milliseconds(100), "reloading 240 History rows took \(best)")
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 1_000.0
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return Date(timeIntervalSince1970: value)
    }
}
