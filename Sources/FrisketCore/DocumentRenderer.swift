import Foundation

/// A pure function from document to bitmap; the same document always renders the same pixels.
///
/// Crop is applied first. Each Solid redaction is then shifted into the cropped document,
/// scaled to output pixels, snapped outward (down on the minimum edges, up on the maximum
/// edges), clipped to the cropped image, and copied as opaque fill with no blending or
/// antialiasing.
public enum DocumentRenderer {
    public static func render(_ document: EditorDocument) -> Bitmap {
        var output = croppedBase(document.base, crop: document.edits.crop, scale: document.edits.scale)
        let fill = SolidRedaction.fill
        let scale = document.edits.scale
        let originX = document.edits.crop?.x ?? 0
        let originY = document.edits.crop?.y ?? 0
        for redaction in document.edits.redactions {
            // Clamp in floating point first: Int conversion traps on out-of-range values.
            func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(output.width))) }
            func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(output.height))) }
            let minX = column(((redaction.x - originX) * scale).rounded(.down))
            let minY = row(((redaction.y - originY) * scale).rounded(.down))
            let maxX = column(((redaction.x - originX + redaction.width) * scale).rounded(.up))
            let maxY = row(((redaction.y - originY + redaction.height) * scale).rounded(.up))
            guard minX < maxX, minY < maxY else { continue }
            for y in minY..<maxY {
                for x in minX..<maxX {
                    let index = (y * output.width + x) * 4
                    output.bytes.replaceSubrange(index..<index + 4, with: [fill.red, fill.green, fill.blue, fill.alpha])
                }
            }
        }
        for annotation in document.edits.annotations {
            draw(annotation, on: &output, scale: scale, originX: originX, originY: originY)
        }
        return output
    }

    private static func draw(_ annotation: DocumentAnnotation, on output: inout Bitmap, scale: Double,
                             originX: Double, originY: Double) {
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(output.width))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(output.height))) }
        func plot(_ x: Int, _ y: Int) {
            guard (0..<output.width).contains(x), (0..<output.height).contains(y) else { return }
            let stroke = DocumentAnnotation.stroke
            let index = (y * output.width + x) * 4
            output.bytes.replaceSubrange(index..<index + 4, with: [stroke.red, stroke.green, stroke.blue, stroke.alpha])
        }
        switch annotation.kind {
        case let .rectangle(x, y, width, height):
            let minX = column(((x - originX) * scale).rounded(.down))
            let minY = row(((y - originY) * scale).rounded(.down))
            let maxX = column(((x - originX + width) * scale).rounded(.up))
            let maxY = row(((y - originY + height) * scale).rounded(.up))
            guard minX < maxX, minY < maxY else { return }
            for x in minX..<maxX {
                plot(x, minY)
                plot(x, maxY - 1)
            }
            for y in minY..<maxY {
                plot(minX, y)
                plot(maxX - 1, y)
            }
        case let .arrow(x0, y0, x1, y1):
            let startX = Int(((x0 - originX) * scale).rounded())
            let startY = Int(((y0 - originY) * scale).rounded())
            let endX = Int(((x1 - originX) * scale).rounded())
            let endY = Int(((y1 - originY) * scale).rounded())
            plotLine(from: (startX, startY), to: (endX, endY), plot: plot)
            plotArrowHead(from: (startX, startY), to: (endX, endY), scale: scale, plot: plot)
        case let .text(x, y, characters):
            let originColumn = Int(((x - originX) * scale).rounded(.down))
            let originRow = Int(((y - originY) * scale).rounded(.down))
            let cell = max(1, Int(scale.rounded(.down)))
            var cursor = 0
            for character in AnnotationFont.glyphs(in: characters) {
                for glyphRow in 0..<AnnotationFont.height {
                    guard let bits = AnnotationFont.row(character, glyphRow) else { continue }
                    for (glyphColumn, bit) in bits.enumerated() where bit == "#" {
                        for dy in 0..<cell {
                            for dx in 0..<cell {
                                plot(originColumn + cursor * cell + glyphColumn * cell + dx,
                                     originRow + glyphRow * cell + dy)
                            }
                        }
                    }
                }
                cursor += AnnotationFont.advance
            }
        }
    }

    private static func plotLine(from start: (Int, Int), to end: (Int, Int), plot: (Int, Int) -> Void) {
        var x = start.0, y = start.1
        let dx = abs(end.0 - start.0), dy = -abs(end.1 - start.1)
        let stepX = start.0 < end.0 ? 1 : -1, stepY = start.1 < end.1 ? 1 : -1
        var error = dx + dy
        while true {
            plot(x, y)
            if x == end.0 && y == end.1 { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += stepX }
            if doubled <= dx { error += dx; y += stepY }
        }
    }

    private static func plotArrowHead(from start: (Int, Int), to end: (Int, Int), scale: Double,
                                      plot: (Int, Int) -> Void) {
        let vx = Double(end.0 - start.0), vy = Double(end.1 - start.1)
        let length = (vx * vx + vy * vy).squareRoot()
        guard length > 0 else { return }
        let size = max(1, scale.rounded(.down))
        let ux = vx / length, uy = vy / length
        let backX = Double(end.0) - ux * size, backY = Double(end.1) - uy * size
        plot(Int((backX - uy * size).rounded()), Int((backY + ux * size).rounded()))
        plot(Int((backX + uy * size).rounded()), Int((backY - ux * size).rounded()))
    }

    private static func croppedBase(_ base: Bitmap, crop: DocumentCrop?, scale: Double) -> Bitmap {
        guard let crop else { return base }
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(base.width))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(base.height))) }
        let minX = column((crop.x * scale).rounded(.down))
        let minY = row((crop.y * scale).rounded(.down))
        let maxX = column(((crop.x + crop.width) * scale).rounded(.up))
        let maxY = row(((crop.y + crop.height) * scale).rounded(.up))
        guard minX < maxX, minY < maxY else { return base }
        var bytes: [UInt8] = []
        bytes.reserveCapacity((maxX - minX) * (maxY - minY) * 4)
        for y in minY..<maxY {
            let start = (y * base.width + minX) * 4
            bytes.append(contentsOf: base.bytes[start..<(start + (maxX - minX) * 4)])
        }
        return Bitmap(width: maxX - minX, height: maxY - minY, bytes: bytes) ?? base
    }
}
