import CoreGraphics
import Foundation
import FrisketCore
import ImageIO

/// PNG bytes to and from the renderer's premultiplied sRGB RGBA8 bitmap, entirely in memory.
/// No decoded-image cache is kept.
struct PNGBitmapCodec: BitmapCodec {
    /// Edited outputs up to this many rows tall are rendered in one pass by `DocumentRenderer.render`,
    /// the function the editor preview uses, so what is delivered matches what the user saw (D1).
    /// Only taller outputs keep the strip path. Interim (decision 58); ticket 65 removes the strip path.
    static let wholeRenderMaxHeight = 32_768

    func decode(_ pngData: Data) -> Bitmap? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(pngData as CFData, options),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= Int.max / 4 / height else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Bitmap(width: width, height: height, bytes: bytes) : nil
    }

    func encode(_ bitmap: Bitmap) -> Data? {
        guard let image = Self.image(bitmap) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    func encode(_ pngData: Data, edits: DocumentEdits) -> Data? {
        guard let full = pixelSize(pngData) else { return nil }
        if DocumentRenderer.outputSize(width: full.width, height: full.height, edits: edits).height
            <= Self.wholeRenderMaxHeight {
            guard let base = decodeInStrips(pngData) else { return nil }
            return encodeWhole(EditorDocument(base: base, edits: edits))
        }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(pngData as CFData, options),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        let size = DocumentRenderer.outputSize(width: image.width, height: image.height, edits: edits)
        guard let encoder = StripPNGEncoder(width: size.width, height: size.height) else { return nil }
        var ok = true
        DocumentRenderer.forEachStrip(width: image.width, height: image.height, edits: edits) { start, count in
            rows(from: image, crop: edits.crop, scale: edits.scale, startRow: start, rowCount: count)
        } body: { strip in
            if ok { ok = encoder.append(strip) }
        }
        return ok ? encoder.finish() : nil
    }

    func encode(_ document: EditorDocument) -> Data? {
        let size = DocumentRenderer.outputSize(document)
        if size.height <= Self.wholeRenderMaxHeight { return encodeWhole(document) }
        guard let encoder = StripPNGEncoder(width: size.width, height: size.height) else { return nil }
        var ok = true
        DocumentRenderer.forEachStrip(document) { strip in
            if ok { ok = encoder.append(strip) }
        }
        return ok ? encoder.finish() : nil
    }

    /// Same pixels as `decode`, copied a strip at a time from one cached decode. `decode` draws the
    /// whole image at once, and ImageIO's buffers then triple the peak (2.05 GB at 5,120 × 32,768).
    /// The cached image is released on return, before the render allocates its output.
    private func decodeInStrips(_ pngData: Data) -> Bitmap? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(pngData as CFData, options),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= Int.max / 4 / height else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        var row = 0
        while row < height {
            let count = min(DocumentRenderer.stripHeight, height - row)
            guard let strip = rows(from: image, crop: nil, scale: 1, startRow: row, rowCount: count) else { return nil }
            bytes.append(contentsOf: strip.bytes)
            row += count
        }
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    /// The editor preview's render of the whole document, written through the same PNG encoder
    /// as the strip path.
    private func encodeWhole(_ document: EditorDocument) -> Data? {
        let rendered = DocumentRenderer.render(document)
        guard let encoder = StripPNGEncoder(width: rendered.width, height: rendered.height),
              encoder.append(rendered) else { return nil }
        return encoder.finish()
    }

    func pixelSize(_ pngData: Data) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(pngData as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
                ?? properties[kCGImagePropertyPixelWidth] as? Int,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
                ?? properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private func rows(from image: CGImage, crop: DocumentCrop?, scale: Double,
                      startRow: Int, rowCount: Int) -> Bitmap? {
        guard let edits = DocumentEdits(scale: scale, crop: crop) else { return nil }
        let bounds = DocumentRenderer.outputSize(width: image.width, height: image.height, edits: edits)
        guard startRow >= 0, rowCount > 0, startRow + rowCount <= bounds.height,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var minX = 0, minY = 0
        if let crop {
            func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(image.width))) }
            func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(image.height))) }
            minX = column((crop.x * scale).rounded(.down))
            minY = row((crop.y * scale).rounded(.down))
        }
        let strip = CGRect(x: minX, y: minY + startRow, width: bounds.width, height: rowCount)
        guard let cropped = image.cropping(to: strip),
              cropped.width == bounds.width, cropped.height == rowCount else { return nil }
        var bytes = [UInt8](repeating: 0, count: bounds.width * rowCount * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: bounds.width, height: rowCount,
                                          bitsPerComponent: 8, bytesPerRow: bounds.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: bounds.width, height: rowCount))
            return true
        }
        return drawn ? Bitmap(width: bounds.width, height: rowCount, bytes: bytes) : nil
    }

    func bitmap(from image: CGImage) -> Bitmap? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= Int.max / 4 / height,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Bitmap(width: width, height: height, bytes: bytes) : nil
    }

    /// An sRGB image over the bitmap's bytes, for encoding and on-screen display.
    static func image(_ bitmap: Bitmap) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bitmap.bytes) as CFData) else { return nil }
        return CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bitmap.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
