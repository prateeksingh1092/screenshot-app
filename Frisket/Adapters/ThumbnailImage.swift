import Foundation
import ImageIO

/// Decodes only a downsampled, in-memory presentation image. No file cache.
enum ThumbnailImage {
    static func make(from pngData: Data, maximumPixelSize: Int) -> CGImage? {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(pngData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    /// The same decode, run off the caller's actor, so a Thumbnail never decodes on the main thread (ticket 68).
    @concurrent static func decode(_ pngData: Data, maximumPixelSize: Int) async -> CGImage? {
        make(from: pngData, maximumPixelSize: maximumPixelSize)
    }
}
