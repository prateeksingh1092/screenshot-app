import Foundation

/// What the History window reads. `HistoryStore` is the production source.
public protocol HistoryRowSource: Sendable {
    /// Every row, newest first, in one query. No file names or paths.
    func rows() async -> Result<[HistoryItem], HistoryFailure>
    /// One row's cached thumbnail, looked up by ID.
    func thumbnailPNG(_ id: CaptureID) async -> Data?
    /// One row's finalized image, looked up by ID.
    func finalizedImage(_ id: CaptureID) async -> Result<(revision: UInt64, pngData: Data), HistoryFailure>
}

/// The History window's read model (ticket 74). A reload is one `rows()` query and nothing else:
/// pictures are looked up by ID only when a row comes into view, then cached by revision. A reload
/// that finds the same rows reports no change, so the window does not redraw.
@MainActor public final class HistoryList<Picture> {
    public private(set) var rows: [HistoryItem] = []
    private let source: any HistoryRowSource
    private let decode: (Data) -> Picture?
    private let pictureLimit: Int
    private var pictures: [CaptureRevision: Picture] = [:]
    /// Oldest cached first, so the cache drops the picture used least recently.
    private var pictureOrder: [CaptureRevision] = []

    /// `decode` turns a thumbnail, or the finalized image when no thumbnail is cached, into a picture.
    public init(source: any HistoryRowSource, pictureLimit: Int = 300, decode: @escaping (Data) -> Picture?) {
        self.source = source
        self.pictureLimit = max(1, pictureLimit)
        self.decode = decode
    }

    /// Reads every row in one query. Returns whether the rows changed; on failure the rows empty.
    public func reload() async -> Result<Bool, HistoryFailure> {
        switch await source.rows() {
        case let .success(next):
            guard next != rows else { return .success(false) }
            rows = next
            let kept = Set(next.map(Self.revision))
            pictures = pictures.filter { kept.contains($0.key) }
            pictureOrder.removeAll { !kept.contains($0) }
            return .success(true)
        case let .failure(failure):
            rows = []
            pictures = [:]
            pictureOrder = []
            return .failure(failure)
        }
    }

    /// The row to select after a reload (D30). Opening History selects the newest row, so Copy, Save,
    /// Restore and Delete act on the capture just made; a reload while the window is open keeps the
    /// user's row while it still exists.
    public func selection(keeping current: CaptureID?, opening: Bool) -> CaptureID? {
        guard !opening, let current, rows.contains(where: { $0.captureID == current }) else { return rows.first?.captureID }
        return current
    }

    public func cachedPicture(_ item: HistoryItem) -> Picture? {
        pictures[Self.revision(item)]
    }

    /// The row's picture: from the cache, else looked up by ID and cached.
    public func picture(for item: HistoryItem) async -> Picture? {
        let key = Self.revision(item)
        if let cached = pictures[key] {
            pictureOrder.removeAll { $0 == key }
            pictureOrder.append(key)
            return cached
        }
        let data: Data?
        if let thumbnail = await source.thumbnailPNG(item.captureID) {
            data = thumbnail
        } else if case let .success((_, pngData)) = await source.finalizedImage(item.captureID) {
            data = pngData
        } else {
            data = nil
        }
        guard let data, let picture = decode(data) else { return nil }
        if pictures[key] == nil { pictureOrder.append(key) }
        pictures[key] = picture
        while pictureOrder.count > pictureLimit { pictures[pictureOrder.removeFirst()] = nil }
        return picture
    }

    private static func revision(_ item: HistoryItem) -> CaptureRevision {
        CaptureRevision(captureID: item.captureID, number: item.revision)
    }
}
