import CoreGraphics
import Foundation
import FrisketCore
import ImageIO

/// PNG bytes to and from the renderer's premultiplied sRGB RGBA8 bitmap, entirely in memory.
/// No decoded-image cache is kept.
struct PNGBitmapCodec: BitmapCodec {
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
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
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
        guard let encoder = StripPNGEncoder(width: size.width, height: size.height) else { return nil }
        var ok = true
        DocumentRenderer.forEachStrip(document) { strip in
            if ok { ok = encoder.append(strip) }
        }
        return ok ? encoder.finish() : nil
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
        var bytes = [UInt8](repeating: 0, count: bounds.width * rowCount * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: bounds.width, height: rowCount,
                                          bitsPerComponent: 8, bytesPerRow: bounds.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: -minX, y: -(minY + startRow),
                                           width: image.width, height: image.height))
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
