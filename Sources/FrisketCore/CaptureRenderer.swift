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
/// in each redaction's colour, and the result is encoded as PNG in memory with no metadata but the
/// capture's density (`capturePNG`).
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
        // The capture's own density when it has one (its display's scale), else the document's.
        let density = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        let scale = density.flatMap { $0.isFinite && $0 > 0 ? $0 / 72 : nil } ?? edits.scale
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
        guard let image = output.image(space: space), let png = capturePNG(image, scale: scale) else {
            return .failure(.encodingFailed)
        }
        return .success(png)
    }

    /// ImageIO adds an eXIf chunk even with no properties. Keep only the chunks that define the
    /// pixels, their colour and their density (pHYs, ticket 102); each kept chunk is copied whole, with its CRC.
    private static let keptChunks: Set<String> = ["IHDR", "PLTE", "tRNS", "sRGB", "iCCP", "gAMA", "cHRM", "pHYs", "IDAT", "IEND"]

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
    /// The one PNG encoder for capture pixels (ticket 102): the capture sources and `flatten` use it.
    /// The PNG holds the pixels as they are, their colour, and a density of 72 dpi × `scale` (the
    /// display's backing scale: 144 dpi at 2×), as `screencapture` writes; no other metadata.
    /// Viewers that honour the density show a Retina capture at its point size, pixel for pixel.
    public static func capturePNG(_ image: CGImage, scale: Double) -> Data? {
        guard scale.isFinite, scale > 0 else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return imageChunksOnly(data as Data)
    }

    /// The editor preview's default size limit: its longer edge is at most this many pixels. It is the
    /// longer edge of the largest Apple display (6,016 px, decision 60), so a capture of one display is
    /// previewed at full resolution and the editor shows its real pixels (ticket 102). Only captures
    /// taller than a display (up to the DA-6 cap) are downscaled.
    public static let previewMaxEdge = 6016

    /// The live-drag preview's size limit (decision 75's 2,048): renders during a drag stay inside the
    /// 60 Hz frame on the largest display (ticket 97). The settled edits render at full size.
    public static let livePreviewMaxEdge = 2048

    /// Decodes a pending capture once for the editor preview, downscaled so neither edge exceeds
    /// `maxEdge`. Run it off the main actor: it decodes the whole capture. Nothing touches the disk.
    ///
    /// Downscaling is leak-free by construction. Preview pixel `j` averages only capture pixels that
    /// overlap its own block `[j·W/w, (j+1)·W/w)` (an area average of the block), and `render` fills
    /// every preview pixel whose block touches a redacted pixel.
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
        guard let preview = reduce(whole, maxEdge: maxEdge) else { return .failure(.encodingFailed) }
        return .success(preview)
    }

    /// The preview of a fully decoded capture, downscaled so neither edge exceeds `maxEdge`.
    static func reduce(_ whole: RGBABuffer, maxEdge: Int) -> CapturePreview? {
        let width = whole.width, height = whole.height
        let edge = max(1, maxEdge)
        guard max(width, height) > edge else { return CapturePreview(base: whole, captureWidth: width, captureHeight: height) }
        let fraction = Double(edge) / Double(max(width, height))
        let size = (width: min(width, max(1, Int((Double(width) * fraction).rounded()))),
                    height: min(height, max(1, Int((Double(height) * fraction).rounded()))))
        guard let reduced = downscale(whole, to: size) else { return nil }
        return CapturePreview(base: reduced, captureWidth: width, captureHeight: height)
    }

    /// Preview pixel `(i, j)` is the area average of its block: the capture rectangle
    /// `[i·W/w, (i+1)·W/w) × [j·H/h, (j+1)·H/h)`, each capture pixel weighted by the part of it
    /// inside the block (ticket 102). Every capture pixel counts, so no column or row is dropped, and
    /// no pixel outside the block is read. The weights are whole numbers (overlaps in units of
    /// 1/w and 1/h of a pixel), so the sums are exact and the result is rounded once.
    private static func downscale(_ whole: RGBABuffer, to size: (width: Int, height: Int)) -> RGBABuffer? {
        let W = whole.width, H = whole.height, w = size.width, h = size.height
        guard w > 0, h > 0, w <= W, h <= H else { return nil }
        // Column spans and weights: output column i reads capture columns first[i]...last[i].
        var first = [Int](repeating: 0, count: w), last = [Int](repeating: 0, count: w), weights = [UInt64]()
        for i in 0..<w {
            first[i] = i * W / w
            last[i] = ((i + 1) * W - 1) / w
            for k in first[i]...last[i] { weights.append(UInt64(min((k + 1) * w, (i + 1) * W) - max(k * w, i * W))) }
        }
        let total = UInt64(W) * UInt64(H)
        var output = [UInt8](repeating: 0, count: w * h * 4)
        var reduced = [UInt64](repeating: 0, count: w * 4), accumulator = [UInt64](repeating: 0, count: w * 4)
        var reducedRow = -1
        whole.bytes.withUnsafeBufferPointer { source in
            reduced.withUnsafeMutableBufferPointer { row in
                accumulator.withUnsafeMutableBufferPointer { sum in
                    // One capture row, reduced across: each output column's weighted sum (weights total W).
                    func reduce(_ r: Int) {
                        guard r != reducedRow else { return }
                        reducedRow = r
                        var weight = 0
                        let base = r * W * 4
                        for i in 0..<w {
                            var red: UInt64 = 0, green: UInt64 = 0, blue: UInt64 = 0, alpha: UInt64 = 0
                            for k in first[i]...last[i] {
                                let factor = weights[weight], p = base + k * 4
                                weight += 1
                                red += factor * UInt64(source[p]); green += factor * UInt64(source[p + 1])
                                blue += factor * UInt64(source[p + 2]); alpha += factor * UInt64(source[p + 3])
                            }
                            row[i * 4] = red; row[i * 4 + 1] = green; row[i * 4 + 2] = blue; row[i * 4 + 3] = alpha
                        }
                    }
                    for j in 0..<h {
                        for c in 0..<(w * 4) { sum[c] = 0 }
                        for r in (j * H / h)...(((j + 1) * H - 1) / h) {
                            let factor = UInt64(min((r + 1) * h, (j + 1) * H) - max(r * h, j * H))
                            reduce(r)
                            for c in 0..<(w * 4) { sum[c] += factor * row[c] }
                        }
                        let start = j * w * 4
                        for c in 0..<(w * 4) { output[start + c] = UInt8((sum[c] + total / 2) / total) }
                    }
                }
            }
        }
        return RGBABuffer(width: w, height: h, bytes: output)
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

    /// A smaller preview of the same capture for renders during a live drag (ticket 102): this one
    /// downscaled so neither edge exceeds `maxEdge`, with the same leak-free blocks. A preview that is
    /// already downscaled is returned as it is, because its blocks must come from the capture's pixels.
    public func reduced(maxEdge: Int = CaptureRenderer.livePreviewMaxEdge) -> CapturePreview {
        guard !isDownscaled else { return self }
        return CaptureRenderer.reduce(base, maxEdge: maxEdge) ?? self
    }

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
    /// Draws every annotation over `buffer`, an `output`-sized crop mapped through `grid`.
    /// A downscaled grid scales the whole drawing, so strokes, arrow heads and labels keep their
    /// full-size geometry and are never drawn larger than in the delivered image (D23).
    static func draw(_ annotations: [DocumentAnnotation], on buffer: inout RGBABuffer, scale: Double,
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
            for annotation in annotations {
                // Each mark's own ink and width (ticket 84); the default 2 pt keeps decision 68's pen.
                let pen = CGFloat(max(2, (annotation.width * scale).rounded()))
                let colour = inkColour(annotation.colour)
                context.setStrokeColor(colour)
                context.setFillColor(colour)
                context.setLineWidth(pen)
                draw(annotation, in: context, scale: scale, origin: origin, pen: pen,
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

    private static func inkColour(_ ink: RGBAPixel) -> CGColor {
        CGColor(srgbRed: CGFloat(ink.red) / 255, green: CGFloat(ink.green) / 255, blue: CGFloat(ink.blue) / 255, alpha: 1)
    }
    /// The letters of an Outlined or Box label in a dark or mid ink.
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private static func draw(_ annotation: DocumentAnnotation, in context: CGContext, scale: Double,
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
            // Filled polygons from the core's geometry (ticket 85), filled with the ink.
            let head = max(8, ArrowGeometry.headLength(width: annotation.width) * scale)
            let polygons = ArrowGeometry.polygons(style: annotation.style, tail: point(x0, y0), tip: point(x1, y1),
                                                  bend: annotation.bend, width: Double(pen), head: head)
            for polygon in polygons {
                context.beginPath()
                context.addLines(between: polygon)
                context.closePath()
                context.fillPath()
            }
        case let .text(x, y, characters):
            // Layout, wrapping and styles are the core's (ticket 86, `Labels.swift`).
            drawLabel(characters, format: annotation.label, colour: annotation.colour, top: point(x, y), scale: scale,
                      in: context)
        }
    }
}
