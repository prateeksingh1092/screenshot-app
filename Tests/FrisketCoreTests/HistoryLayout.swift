import FrisketCore

/// History's on-disk layout, as the tests check it (`HistoryStore` keeps its own paths).
extension HistoryEntry {
    var imageLocation: String { "images/\(captureID.rawValue.uuidString).png" }
    var thumbnailLocation: String? { thumbnailBytes > 0 ? "thumbnails/\(captureID.rawValue.uuidString).png" : nil }
}
