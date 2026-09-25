import Accelerate
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
/// Blur (vImage) and Magnify (CoreGraphics) run in `EditPainter.paint` over the redacted composite;
/// annotations are drawn by `AnnotationPainter` with CoreGraphics and CoreText. The editor preview,
/// `CapturePreview.render`, paints with the same function, so at full size it equals the delivered image.
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
        let size = EditPainter.outputSize(width: width, height: height, edits: edits)
        guard size.height <= maximumOutputHeight else { return .failure(.outputTooTall(height: size.height)) }
        guard size.width > 0, size.height > 0, size.width <= Int.max / 4 / size.height else {
            return .failure(.unreadableCapture)
        }
        let origin = EditPainter.cropOrigin(width: width, height: height, edits: edits)
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
        guard drawn, var output = RGBABuffer(width: size.width, height: size.height, bytes: bytes) else {
            return .failure(.encodingFailed)
        }
        bytes = []   // `output` now owns the only copy, so painting mutates it in place.
        EditPainter.paint(&output, edits: edits, output: size, grid: .identity(output: size, origin: origin))
        return encode(output, space: space)
    }

    /// PNG in memory, with no properties: no text, time, EXIF or resolution chunks.
    private static func encode(_ buffer: RGBABuffer, space: CGColorSpace) -> Result<Data, RenderFailure> {
        let data = NSMutableData()
        guard let image = buffer.image(space: space),
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

extension CaptureRenderer {
    /// The editor preview's default size limit: its longer edge is at most this many pixels.
    public static let previewMaxEdge = 2048

    /// Decodes a pending capture once for the editor preview, downscaled so neither edge exceeds
    /// `maxEdge`. Run it off the main actor: it decodes the whole capture. Nothing touches the disk.
    ///
    /// Downscaling is leak-free by construction. Preview pixel `j` averages only capture pixels that
    /// overlap its own block `[j·W/w, (j+1)·W/w)` (a vImage box average centred in the block and no
    /// wider than it), and `render` fills every preview pixel whose block touches a redacted pixel.
    /// So no preview pixel mixes in content from under a Solid redaction.
    public func preview(_ capture: Data, maxEdge: Int = CaptureRenderer.previewMaxEdge) throws(RenderFailure) -> CapturePreview {
        try autoreleasepool { Self.makePreview(capture, maxEdge: maxEdge) }.get()
    }

    private static func makePreview(_ capture: Data, maxEdge: Int) -> Result<CapturePreview, RenderFailure> {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(capture as CFData, options),
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return .failure(.unreadableCapture) }
        guard height <= maximumOutputHeight else { return .failure(.outputTooTall(height: height)) }
        guard width <= Int.max / 4 / height else { return .failure(.unreadableCapture) }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == width, image.height == height else { return .failure(.unreadableCapture) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return .failure(.encodingFailed) }
        // Decoded exactly as `flatten` decodes: one sRGB bitmap, copy blend, no interpolation.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let whole = RGBABuffer(width: width, height: height, bytes: bytes) else { return .failure(.encodingFailed) }
        bytes = []
        let edge = max(1, maxEdge)
        guard max(width, height) > edge else { return .success(CapturePreview(base: whole, captureWidth: width, captureHeight: height)) }
        let fraction = Double(edge) / Double(max(width, height))
        let size = (width: min(width, max(1, Int((Double(width) * fraction).rounded()))),
                    height: min(height, max(1, Int((Double(height) * fraction).rounded()))))
        guard let reduced = downscale(whole, to: size) else { return .failure(.encodingFailed) }
        return .success(CapturePreview(base: reduced, captureWidth: width, captureHeight: height))
    }

    /// Preview pixel `(i, j)` is a box average of capture pixels centred at column `⌊(2i+1)·W/2w⌋` and
    /// row `⌊(2j+1)·H/2h⌋`, `2r+1` wide with `r = ⌊(W−w)/2w⌋` (and the same for rows). That box lies
    /// inside the pixel's own block, so each preview pixel reads only pixels that overlap its block.
    private static func downscale(_ whole: RGBABuffer, to size: (width: Int, height: Int)) -> RGBABuffer? {
        let W = whole.width, H = whole.height, w = size.width, h = size.height
        let radiusX = (W - w) / (2 * w), radiusY = (H - h) / (2 * h)
        var row = [UInt8](repeating: 0, count: W * 4)
        var output = [UInt8](repeating: 0, count: w * h * 4)
        let failed = whole.bytes.withUnsafeBytes { wholeRaw -> Bool in
            row.withUnsafeMutableBytes { rowRaw -> Bool in
                output.withUnsafeMutableBytes { outputRaw -> Bool in
                    var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: wholeRaw.baseAddress),
                                               height: vImagePixelCount(H), width: vImagePixelCount(W), rowBytes: W * 4)
                    var line = vImage_Buffer(data: rowRaw.baseAddress, height: 1, width: vImagePixelCount(W), rowBytes: W * 4)
                    let rowPixels = rowRaw.baseAddress!.assumingMemoryBound(to: UInt32.self)
                    let outputPixels = outputRaw.baseAddress!.assumingMemoryBound(to: UInt32.self)
                    for j in 0..<h {
                        let centre = (2 * j + 1) * H / (2 * h)
                        // The kernel reads real rows above and below the one-row region; only the
                        // image's own edges are extended.
                        let error = vImageBoxConvolve_ARGB8888(&source, &line, nil, 0, vImagePixelCount(centre),
                                                               UInt32(2 * radiusY + 1), UInt32(2 * radiusX + 1), nil,
                                                               vImage_Flags(kvImageEdgeExtend))
                        guard error == kvImageNoError else { return true }
                        for i in 0..<w {
                            outputPixels[j * w + i] = rowPixels[(2 * i + 1) * W / (2 * w)]
                        }
                    }
                    return false
                }
            }
        }
        return failed ? nil : RGBABuffer(width: w, height: h, bytes: output)
    }
}

/// The editor preview of one pending capture, decoded once. `render(edits)` takes the same edits as
/// Done. When `isDownscaled` is false it equals the decoded output of `flatten(capture, edits:)` exactly.
/// When downscaled, every preview pixel whose block touches a Solid redaction is exactly that
/// redaction's colour at alpha 255, and every other mark keeps its full-size geometry, scaled (D23).
/// It holds only memory; release it to release the decoded pixels.
public struct CapturePreview: Sendable {
    let base: RGBABuffer
    /// The capture's size in pixels.
    public let captureWidth: Int
    public let captureHeight: Int

    /// The whole capture's size in preview pixels.
    public var width: Int { base.width }
    public var height: Int { base.height }
    public var isDownscaled: Bool { base.width != captureWidth || base.height != captureHeight }

    /// The preview of the output these edits produce. Pure: the same edits give the same pixels.
    public func render(_ edits: DocumentEdits) throws(RenderFailure) -> CGImage {
        let output = EditPainter.outputSize(width: captureWidth, height: captureHeight, edits: edits)
        let origin = EditPainter.cropOrigin(width: captureWidth, height: captureHeight, edits: edits)
        let grid: PixelGrid = isDownscaled
            ? .preview(captureWidth: captureWidth, captureHeight: captureHeight, width: width, height: height,
                       origin: origin, output: output)
            : .identity(output: output, origin: origin)
        guard var buffer = base.copy(x: grid.target.x, y: grid.target.y, width: grid.size.width, height: grid.size.height)
        else { throw .encodingFailed }
        EditPainter.paint(&buffer, edits: edits, output: output, grid: grid)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let image = buffer.image(space: space) else {
            throw .encodingFailed
        }
        return image
    }
}

extension RGBABuffer {
    /// The pixels of a rectangle inside this buffer.
    func copy(x: Int, y: Int, width: Int, height: Int) -> RGBABuffer? {
        guard x >= 0, y >= 0, width > 0, height > 0, x + width <= self.width, y + height <= self.height else { return nil }
        if x == 0, y == 0, width == self.width, height == self.height { return self }
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for row in y..<(y + height) {
            let start = (row * self.width + x) * 4
            bytes.append(contentsOf: self.bytes[start..<(start + width * 4)])
        }
        return RGBABuffer(width: width, height: height, bytes: bytes)
    }

    /// An sRGB image over a copy of these bytes.
    func image(space: CGColorSpace) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Annotations drawn natively (ticket 66): CoreGraphics strokes and CoreText labels, antialiased,
/// with font smoothing off. The editor preview (`CapturePreview.render`) and `flatten` both
/// call this, so what the user sees is what is delivered.
enum AnnotationPainter {
    /// Labels use this pinned font, 18 pt per document point (decision 67).
    static let labelFontName = "HelveticaNeue-Bold"
    static let labelPointSize = 18.0

    enum Layer { case plate, ink }

    /// Draws one layer of every annotation over `buffer`, an `output`-sized crop mapped through `grid`.
    /// A downscaled grid scales the whole drawing, so strokes, arrow heads and labels keep their
    /// full-size geometry and are never drawn larger than in the delivered image (D23).
    static func draw(_ annotations: [DocumentAnnotation], layer: Layer, on buffer: inout RGBABuffer, scale: Double,
                     output: (width: Int, height: Int), grid: PixelGrid) {
        guard !annotations.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let width = buffer.width, height = buffer.height
        let origin = grid.origin, fullWidth = output.width, fullHeight = output.height
        buffer.bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // CoreGraphics' device space is bottom-up. The rows are reversed while drawing, so device y
            // is the output row and user space is the output, top-down.
            reverseRows(raw, width: width, height: height)
            defer { reverseRows(raw, width: width, height: height) }
            if !grid.isIdentity {
                context.translateBy(x: CGFloat(-grid.target.x), y: CGFloat(-grid.target.y))
                context.scaleBy(x: CGFloat(grid.width) / CGFloat(grid.captureWidth),
                                y: CGFloat(grid.height) / CGFloat(grid.captureHeight))
                context.translateBy(x: CGFloat(origin.x), y: CGFloat(origin.y))
                // Glyphs keep their exact scaled position: CoreGraphics would otherwise snap the
                // label to the preview's pixel grid, moving it up to a preview pixel (D23).
                context.setAllowsFontSubpixelQuantization(false)
                context.setShouldSubpixelQuantizeFonts(false)
                context.setAllowsFontSubpixelPositioning(true)
                context.setShouldSubpixelPositionFonts(true)
            }
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
            // Straight caps and joins only (decision 68).
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
    private static let plateColour = CGColor(srgbRed: CGFloat(EditPainter.plate.red) / 255,
                                             green: CGFloat(EditPainter.plate.green) / 255,
                                             blue: CGFloat(EditPainter.plate.blue) / 255, alpha: 1)

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
