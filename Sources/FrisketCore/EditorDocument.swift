import Foundation

/// One 8-bit sRGB pixel with premultiplied alpha.
public struct RGBAPixel: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// An in-memory 8-bit RGBA bitmap in sRGB with premultiplied alpha, rows top to bottom, tightly packed.
public struct Bitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public internal(set) var bytes: [UInt8]

    public init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, width <= Int.max / 4 / height, bytes.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public init?(width: Int, height: Int, pixels: [RGBAPixel]) {
        self.init(width: width, height: height, bytes: pixels.flatMap { [$0.red, $0.green, $0.blue, $0.alpha] })
    }

    public func pixel(x: Int, y: Int) -> RGBAPixel? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        let index = (y * width + x) * 4
        return RGBAPixel(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
    }
}

/// An opaque replacement of a region, in document points from the top-left corner.
/// It has no colour, opacity, corner radius or stroke to configure.
public struct SolidRedaction: Equatable, Sendable {
    public static let fill = RGBAPixel(red: 0, green: 0, blue: 0, alpha: 255)
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A crop rectangle in document points from the top-left of the original capture.
public struct DocumentCrop: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// An annotation drawn above redactions. Stroke is a fixed opaque colour; there is
/// no opacity, corner radius, or fill that could be mistaken for Solid redaction.
public struct DocumentAnnotation: Equatable, Sendable {
    public static let stroke = RGBAPixel(red: 0xff, green: 0x3b, blue: 0x30, alpha: 0xff)

    public enum Kind: Equatable, Sendable {
        case rectangle(x: Double, y: Double, width: Double, height: Double)
        case arrow(x0: Double, y0: Double, x1: Double, y1: Double)
        case text(x: Double, y: Double, characters: String)
    }

    public let kind: Kind

    public init?(_ kind: Kind) {
        switch kind {
        case let .rectangle(x, y, width, height):
            guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        case let .arrow(x0, y0, x1, y1):
            guard [x0, y0, x1, y1].allSatisfy(\.isFinite), !(x0 == x1 && y0 == y1) else { return nil }
        case let .text(x, y, characters):
            guard x.isFinite, y.isFinite, !AnnotationFont.glyphs(in: characters).isEmpty else { return nil }
        }
        self.kind = kind
    }
}

/// A pixel-sampling annotation effect. It is never a redaction: it has no fill,
/// opacity, or radius, and it reads only the already-redacted composite.
public struct DocumentEffect: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case blur(x: Double, y: Double, width: Double, height: Double)
        case magnify(x: Double, y: Double, width: Double, height: Double)
    }

    public let kind: Kind

    public init?(_ kind: Kind) {
        switch kind {
        case let .blur(x, y, width, height), let .magnify(x, y, width, height):
            guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        }
        self.kind = kind
    }
}

/// Everything the editor changes, without the base image. `scale` is output pixels per document point.
public struct DocumentEdits: Equatable, Sendable {
    public let scale: Double
    public var crop: DocumentCrop?
    public var redactions: [SolidRedaction]
    public var annotations: [DocumentAnnotation]
    public var effects: [DocumentEffect]

    public init?(scale: Double, crop: DocumentCrop? = nil, redactions: [SolidRedaction] = [],
                 annotations: [DocumentAnnotation] = [], effects: [DocumentEffect] = []) {
        guard scale.isFinite, scale > 0 else { return nil }
        self.scale = scale
        self.crop = crop
        self.redactions = redactions
        self.annotations = annotations
        self.effects = effects
    }
}

/// Converts encoded capture bytes to and from the renderer's sRGB bitmap, in memory only.
public protocol BitmapCodec: Sendable {
    func decode(_ pngData: Data) -> Bitmap?
    func encode(_ bitmap: Bitmap) -> Data?
}

/// The editor's document: a base image plus its edits. Rendering is `DocumentRenderer.render`.
public struct EditorDocument: Equatable, Sendable {
    public let base: Bitmap
    public let edits: DocumentEdits

    public init(base: Bitmap, edits: DocumentEdits) {
        self.base = base
        self.edits = edits
    }
}
