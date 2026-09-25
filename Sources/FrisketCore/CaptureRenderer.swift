import CoreGraphics
import Foundation
import CoreText
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
/// Effects are still painted by `DocumentRenderer`'s pixel code (ticket 67 replaces them);
/// annotations are drawn by `AnnotationPainter` with CoreGraphics and CoreText. Both use the same
/// snapping as the editor preview, so the delivered image equals the preview's render at full size.
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

/// Annotations drawn natively (ticket 66): CoreGraphics strokes and CoreText labels, antialiased,
/// with font smoothing off. The editor preview (`DocumentRenderer.render`) and `flatten` both
/// call this, so what the user sees is what is delivered.
enum AnnotationPainter {
    /// Labels use this pinned font, 18 pt per document point (decision 67).
    static let labelFontName = "HelveticaNeue-Bold"
    static let labelPointSize = 18.0

    enum Layer { case plate, ink }

    /// Draws one layer of every annotation over `output`, whose first row is row `rowShift` of the
    /// full output. `origin` is the crop's snapped top-left in output pixels of the uncropped image.
    static func draw(_ annotations: [DocumentAnnotation], layer: Layer, on output: inout Bitmap, scale: Double,
                     origin: (x: Int, y: Int), rowShift: Int, fullWidth: Int, fullHeight: Int) {
        guard !annotations.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let width = output.width, height = output.height
        output.bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // CoreGraphics' device space is bottom-up, and its antialiasing is not exactly invariant
            // under a large translation. So the rows are reversed while drawing: device y is then the
            // output row, and user space is the full output, top-down, shifted by the strip's first row.
            reverseRows(raw, width: width, height: height)
            defer { reverseRows(raw, width: width, height: height) }
            context.translateBy(x: 0, y: CGFloat(-rowShift))
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
            // Straight caps and joins only: CoreGraphics flattens curves relative to the device, so a
            // round cap would rasterize differently in a strip than in the whole image.
            context.setLineCap(.square)
            context.setLineJoin(.miter)
            let pen = CGFloat(max(2, (2 * scale).rounded()))
            let colour = layer == .ink ? inkColour : plateColour
            context.setStrokeColor(colour)
            context.setFillColor(colour)
            context.setLineWidth(layer == .ink ? pen : pen + 2)
            for annotation in annotations {
                draw(annotation, layer: layer, in: context, scale: scale, origin: origin, pen: pen,
                     fullWidth: fullWidth, fullHeight: fullHeight)
            }
            context.flush()
        }
    }

    private static func reverseRows(_ raw: UnsafeMutableRawBufferPointer, width: Int, height: Int) {
        guard let base = raw.baseAddress, height > 1 else { return }
        let rowBytes = width * 4
        let spare = UnsafeMutableRawPointer.allocate(byteCount: rowBytes, alignment: 4)
        defer { spare.deallocate() }
        for top in 0..<(height / 2) {
            let a = base + top * rowBytes, b = base + (height - 1 - top) * rowBytes
            spare.copyMemory(from: a, byteCount: rowBytes)
            a.copyMemory(from: b, byteCount: rowBytes)
            b.copyMemory(from: spare, byteCount: rowBytes)
        }
    }

    private static let inkColour = CGColor(srgbRed: CGFloat(DocumentAnnotation.stroke.red) / 255,
                                           green: CGFloat(DocumentAnnotation.stroke.green) / 255,
                                           blue: CGFloat(DocumentAnnotation.stroke.blue) / 255, alpha: 1)
    private static let plateColour = CGColor(srgbRed: CGFloat(DocumentRenderer.plate.red) / 255,
                                             green: CGFloat(DocumentRenderer.plate.green) / 255,
                                             blue: CGFloat(DocumentRenderer.plate.blue) / 255, alpha: 1)

    private static func draw(_ annotation: DocumentAnnotation, layer: Layer, in context: CGContext, scale: Double,
                             origin: (x: Int, y: Int), pen: CGFloat, fullWidth: Int, fullHeight: Int) {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * scale - Double(origin.x), y: y * scale - Double(origin.y))
        }
        switch annotation.kind {
        case let .rectangle(x, y, width, height):
            // Snapped outward like a redaction; the stroke lies inside the snapped box.
            func column(_ value: Double) -> Double { min(max(value, 0), Double(fullWidth)) }
            func row(_ value: Double) -> Double { min(max(value, 0), Double(fullHeight)) }
            let minX = column((x * scale).rounded(.down) - Double(origin.x))
            let minY = row((y * scale).rounded(.down) - Double(origin.y))
            let maxX = column(((x + width) * scale).rounded(.up) - Double(origin.x))
            let maxY = row(((y + height) * scale).rounded(.up) - Double(origin.y))
            guard minX < maxX, minY < maxY else { return }
            let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            context.stroke(box.insetBy(dx: min(pen / 2, box.width / 2), dy: min(pen / 2, box.height / 2)))
        case let .arrow(x0, y0, x1, y1):
            let tail = point(x0, y0), tip = point(x1, y1)
            let vx = tip.x - tail.x, vy = tip.y - tail.y
            let length = (vx * vx + vy * vy).squareRoot()
            guard length > 0 else { return }
            let size = CGFloat(max(8, 10 * scale))
            let ux = vx / length, uy = vy / length
            let back = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
            context.move(to: tail)
            context.addLine(to: tip)
            context.move(to: CGPoint(x: back.x - uy * size, y: back.y + ux * size))
            context.addLine(to: tip)
            context.addLine(to: CGPoint(x: back.x + uy * size, y: back.y - ux * size))
            context.strokePath()
        case let .text(x, y, characters):
            let font = CTFontCreateWithName(labelFontName as CFString, CGFloat(labelPointSize * scale), nil)
            let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
            guard let string = CFAttributedStringCreate(nil, characters as CFString, attributes as CFDictionary) else { return }
            let line = CTLineCreateWithAttributedString(string)
            let top = point(x, y)
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: top.x, y: top.y + CTFontGetAscent(font))
            context.setTextDrawingMode(layer == .ink ? .fill : .stroke)
            context.setLineWidth(2)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }
}
