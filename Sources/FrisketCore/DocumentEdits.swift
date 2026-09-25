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

/// The renderer's working pixels: 8-bit sRGB RGBA with premultiplied alpha, rows top to bottom,
/// tightly packed. Internal to the core; callers see PNG bytes (`flatten`) or a `CGImage` (`CapturePreview`).
struct RGBABuffer: Sendable {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, width <= Int.max / 4 / height, bytes.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }
}

/// An opaque replacement of a region, in document points from the top-left corner.
/// Its fill colour is data, always at alpha 255 (decision 61); it has no opacity, corner
/// radius or stroke to configure.
public struct SolidRedaction: Equatable, Sendable {
    /// The default fill colour.
    public static let fill = RGBAPixel(red: 0, green: 0, blue: 0, alpha: 255)
    /// The colours the editor offers (decision 61): a small set of opaque neutrals, black first as
    /// the default. There is no free colour picker.
    public static let palette = [
        RedactionColour(name: "Black", pixel: fill),
        RedactionColour(name: "Dark Grey", pixel: RGBAPixel(red: 0x40, green: 0x40, blue: 0x40, alpha: 255)),
        RedactionColour(name: "Grey", pixel: RGBAPixel(red: 0x80, green: 0x80, blue: 0x80, alpha: 255)),
        RedactionColour(name: "Light Grey", pixel: RGBAPixel(red: 0xc0, green: 0xc0, blue: 0xc0, alpha: 255)),
        RedactionColour(name: "White", pixel: RGBAPixel(red: 0xff, green: 0xff, blue: 0xff, alpha: 255))
    ]
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    /// Every pixel this redaction covers is exactly this colour in every output.
    public let colour: RGBAPixel

    /// Refuses a colour that is not fully opaque.
    public init?(x: Double, y: Double, width: Double, height: Double, colour: RGBAPixel = SolidRedaction.fill) {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0, colour.alpha == 255 else { return nil }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colour = colour
    }
}

/// One Solid redaction colour the editor offers, with the name the palette shows and VoiceOver reads.
public struct RedactionColour: Equatable, Sendable {
    public let name: String
    public let pixel: RGBAPixel
    public init(name: String, pixel: RGBAPixel) {
        self.name = name
        self.pixel = pixel
    }
}

/// One annotation ink the editor offers (ticket 99), with the name the palette shows and VoiceOver reads.
public struct InkColour: Equatable, Sendable {
    public let name: String
    public let pixel: RGBAPixel
    public init(name: String, pixel: RGBAPixel) {
        self.name = name
        self.pixel = pixel
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

/// An annotation drawn above redactions. Its ink is one opaque colour and its line a width in
/// document points (ticket 84: both can be changed after drawing). A Box-style label fills its box
/// in the ink colour (decision 88); it is a label, not a redaction, and carries none of Solid redaction's guarantees.
public struct DocumentAnnotation: Equatable, Sendable {
    /// The default ink.
    public static let stroke = RGBAPixel(red: 0xff, green: 0x3b, blue: 0x30, alpha: 0xff)
    /// The default line width, in document points.
    public static let defaultWidth = 2.0
    /// The line widths the editor offers: thin (the default), medium and thick.
    public static let lineWidths = [2.0, 4.0, 8.0]
    /// The inks the editor offers (decision 92): six opaque colours, Red (the default) first. The
    /// hues are Apple's system colours, so Red is the existing default ink and every golden holds.
    public static let palette = [
        InkColour(name: "Red", pixel: stroke),
        InkColour(name: "Yellow", pixel: RGBAPixel(red: 0xff, green: 0xcc, blue: 0x00, alpha: 255)),
        InkColour(name: "Blue", pixel: RGBAPixel(red: 0x00, green: 0x7a, blue: 0xff, alpha: 255)),
        InkColour(name: "Green", pixel: RGBAPixel(red: 0x34, green: 0xc7, blue: 0x59, alpha: 255)),
        InkColour(name: "Black", pixel: RGBAPixel(red: 0x00, green: 0x00, blue: 0x00, alpha: 255)),
        InkColour(name: "White", pixel: RGBAPixel(red: 0xff, green: 0xff, blue: 0xff, alpha: 255))
    ]

    /// The palette name of `ink`, or nil when it is not a palette colour.
    public static func inkName(_ ink: RGBAPixel) -> String? {
        palette.first { $0.pixel == ink }?.name
    }

    public enum Kind: Equatable, Sendable {
        case rectangle(x: Double, y: Double, width: Double, height: Double)
        case arrow(x0: Double, y0: Double, x1: Double, y1: Double)
        case text(x: Double, y: Double, characters: String)
    }

    public let kind: Kind
    /// The ink, always fully opaque.
    public let colour: RGBAPixel
    /// The line width in document points. A label's glyphs ignore it; its size is `label.size`.
    public let width: Double
    /// How an arrow-kind mark is drawn (ticket 85); always `.standard` for other kinds.
    public let style: ArrowStyle
    /// Where a Curved arrow's middle handle sits; always `.straight` for other kinds and styles.
    public let bend: ArrowBend
    /// A label's style, size and wrap width (ticket 86); always `.standard` for other kinds.
    public let label: LabelFormat

    /// Refuses an empty mark, a colour that is not fully opaque, or a width outside (0, 64] points.
    /// A new Curved arrow given no bend bows by `ArrowBend.newCurve`.
    public init?(_ kind: Kind, colour: RGBAPixel = DocumentAnnotation.stroke, width: Double = DocumentAnnotation.defaultWidth,
                 style: ArrowStyle = .standard, bend: ArrowBend? = nil, label: LabelFormat = .standard) {
        switch kind {
        case let .rectangle(x, y, width, height):
            guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        case let .arrow(x0, y0, x1, y1):
            guard [x0, y0, x1, y1].allSatisfy(\.isFinite), !(x0 == x1 && y0 == y1) else { return nil }
        case let .text(x, y, characters):
            guard x.isFinite, y.isFinite, !characters.allSatisfy(\.isWhitespace) else { return nil }
        }
        guard colour.alpha == 255, width.isFinite, width > 0, width <= 64 else { return nil }
        self.kind = kind
        self.colour = colour
        self.width = width
        if case .text = kind { self.label = label } else { self.label = .standard }
        if case .arrow = kind {
            self.style = style
            self.bend = style == .curved ? bend ?? .newCurve : .straight
        } else {
            self.style = .standard
            self.bend = .straight
        }
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
