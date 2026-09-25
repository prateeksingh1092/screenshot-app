import CoreGraphics
import Foundation
import ImageIO

/// Why an edited capture could not be flattened. Nothing is delivered in any of these cases.
public enum RenderFailure: Error, Equatable, Sendable {
    /// The edited output would be taller than `CaptureRenderer.maximumOutputHeight` (DA-6).
    case outputTooTall(height: Int)
    /// The capture is not a PNG this renderer can read.
    case unreadableCapture
    /// Drawing or PNG encoding failed.
    case encodingFailed
}

/// The only output path for an edited capture: Done, Copy, Save, drag, History and OCR input
/// all use the bytes `flatten` returns.
public protocol CaptureFlattening: Sendable {
    func flatten(_ capture: Data, edits: DocumentEdits) throws(RenderFailure) -> Data
}

/// Production flattener. The crop is copied as whole source pixels into one sRGB bitmap
/// (`.copy` blend, no interpolation, so nothing is resampled), Solid redactions are stamped
/// in each redaction's colour, and the result is encoded as PNG in memory with no metadata.
/// Nothing touches the disk.
///
/// Effects and annotations are still painted by `DocumentRenderer`'s pixel code over the whole
/// output (tickets 66 and 67 replace them), with the same snapping the editor preview uses,
/// so the delivered image equals the preview's render at full size.
public struct CaptureRenderer: CaptureFlattening {
    /// DA-6: edited output is capped at this many pixels tall.
    public static let maximumOutputHeight = 32_768

    public init() {}

    public func flatten(_ capture: Data, edits: DocumentEdits) throws(RenderFailure) -> Data {
        // Release ImageIO's temporaries, and with them any reference to the original, on return.
        try autoreleasepool { Self.render(capture, edits: edits) }.get()
    }

    private static func render(_ capture: Data, edits: DocumentEdits) -> Result<Data, RenderFailure> {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(capture as CFData, options),
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return .failure(.unreadableCapture) }
        // The header alone decides the cap: nothing is decoded or allocated for a refused output.
        let size = DocumentRenderer.outputSize(width: width, height: height, edits: edits)
        guard size.height <= maximumOutputHeight else { return .failure(.outputTooTall(height: size.height)) }
        guard size.width > 0, size.height > 0, size.width <= Int.max / 4 / size.height else {
            return .failure(.unreadableCapture)
        }
        let origin = DocumentRenderer.cropOrigin(width: width, height: height, edits: edits)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == width, image.height == height,
              let cropped = image.cropping(to: CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)),
              cropped.width == size.width, cropped.height == size.height else { return .failure(.unreadableCapture) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return .failure(.encodingFailed) }

        var bytes = [UInt8](repeating: 0, count: size.width * size.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size.width, height: size.height,
                                          bitsPerComponent: 8, bytesPerRow: size.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        guard drawn, var output = Bitmap(width: size.width, height: size.height, bytes: bytes) else {
            return .failure(.encodingFailed)
        }
        bytes = []   // `output` now owns the only copy, so painting mutates it in place.
        DocumentRenderer.paintEdits(&output, edits: edits, origin: origin)
        return encode(output, space: space)
    }

    /// PNG in memory, with no properties: no text, time, EXIF or resolution chunks.
    private static func encode(_ bitmap: Bitmap, space: CGColorSpace) -> Result<Data, RenderFailure> {
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(bitmap.bytes) as CFData),
              let image = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bitmap.width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return .failure(.encodingFailed) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
              let stripped = imageChunksOnly(data as Data) else { return .failure(.encodingFailed) }
        return .success(stripped)
    }

    /// ImageIO adds an eXIf chunk even with no properties. Keep only the chunks that define the
    /// pixels and their colour; each kept chunk is copied whole, with its CRC.
    private static let keptChunks: Set<String> = ["IHDR", "PLTE", "tRNS", "sRGB", "iCCP", "gAMA", "cHRM", "IDAT", "IEND"]

    private static func imageChunksOnly(_ png: Data) -> Data? {
        let bytes = [UInt8](png)
        guard bytes.count >= 8, bytes[0..<8].elementsEqual([137, 80, 78, 71, 13, 10, 26, 10]) else { return nil }
        var output = Data(bytes[0..<8])
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let end = offset + 12 + length
            guard length >= 0, end <= bytes.count else { return nil }
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if keptChunks.contains(type) { output.append(contentsOf: bytes[offset..<end]) }
            offset = end
            if type == "IEND" { return output }
        }
        return nil
    }
}
