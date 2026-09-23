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
        return output
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
