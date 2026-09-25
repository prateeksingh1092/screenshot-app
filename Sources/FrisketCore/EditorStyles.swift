import Foundation

/// The style bar's choices for new marks (ticket 100, decision 93): the Solid redaction colour, the
/// ink, the Arrow tool's style, each drawing tool's line width, and the Text tool's label size and
/// style. A new editor opens with the last choices, stored through `PreferenceKey`.
///
/// Only what the editor offers loads: a stored value outside a palette or menu, or of the wrong
/// type, falls back to its own default and leaves the others as stored. So a remembered redaction
/// colour is always an opaque palette colour, and Solid redaction's guarantees are unchanged.
public struct EditorStyles: Equatable, Sendable {
    public var redactionColour: RGBAPixel
    public var ink: RGBAPixel
    /// The Arrow tool's style: Standard, Curved or Double (the Line tool's style is fixed).
    public var arrowStyle: ArrowStyle
    /// Line widths of the Arrow, Line and Shape tools, each its own, as in the editor.
    public var arrowWidth: Double
    public var lineWidth: Double
    public var shapeWidth: Double
    /// The Text tool's size and style for new labels; a wrap width belongs to one label and is not kept.
    public var labelFormat: LabelFormat

    public static let defaults = EditorStyles(
        redactionColour: SolidRedaction.fill, ink: DocumentAnnotation.stroke, arrowStyle: .standard,
        arrowWidth: DocumentAnnotation.defaultWidth, lineWidth: DocumentAnnotation.defaultWidth,
        shapeWidth: DocumentAnnotation.defaultWidth, labelFormat: .standard)

    /// The keys `store` writes and `load` reads.
    public static let preferenceKeys: [PreferenceKey] = [
        .editorRedactionColour, .editorInkColour, .editorArrowStyle, .editorArrowWidth, .editorLineWidth,
        .editorShapeWidth, .editorLabelSize, .editorLabelStyle,
    ]

    public init(redactionColour: RGBAPixel, ink: RGBAPixel, arrowStyle: ArrowStyle, arrowWidth: Double,
                lineWidth: Double, shapeWidth: Double, labelFormat: LabelFormat) {
        self.redactionColour = redactionColour
        self.ink = ink
        self.arrowStyle = arrowStyle
        self.arrowWidth = arrowWidth
        self.lineWidth = lineWidth
        self.shapeWidth = shapeWidth
        self.labelFormat = labelFormat
    }

    /// The styles stored under `PreferenceKey`, each checked against what the editor offers.
    public static func load(_ stored: (PreferenceKey) -> Any?) -> EditorStyles {
        let d = defaults
        func colour(_ key: PreferenceKey, in palette: [RGBAPixel], or fallback: RGBAPixel) -> RGBAPixel {
            guard let raw = stored(key) as? String, let pixel = pixel(hex: raw), palette.contains(pixel) else { return fallback }
            return pixel
        }
        func width(_ key: PreferenceKey, or fallback: Double) -> Double {
            guard let value = number(stored(key)), DocumentAnnotation.lineWidths.contains(value) else { return fallback }
            return value
        }
        let arrowStyle = (stored(.editorArrowStyle) as? String).flatMap(ArrowStyle.init(rawValue:))
            .flatMap { ArrowStyle.arrowStyles.contains($0) ? $0 : nil } ?? d.arrowStyle
        let size = number(stored(.editorLabelSize)).flatMap { LabelFormat.sizes.contains($0) ? $0 : nil }
            ?? d.labelFormat.size
        let labelStyle = (stored(.editorLabelStyle) as? String).flatMap(LabelStyle.init(rawValue:)) ?? d.labelFormat.style
        return EditorStyles(
            redactionColour: colour(.editorRedactionColour, in: SolidRedaction.palette.map(\.pixel), or: d.redactionColour),
            ink: colour(.editorInkColour, in: DocumentAnnotation.palette.map(\.pixel), or: d.ink),
            arrowStyle: arrowStyle,
            arrowWidth: width(.editorArrowWidth, or: d.arrowWidth),
            lineWidth: width(.editorLineWidth, or: d.lineWidth),
            shapeWidth: width(.editorShapeWidth, or: d.shapeWidth),
            labelFormat: LabelFormat(style: labelStyle, size: size) ?? d.labelFormat)
    }

    /// Writes every style: colours as `RRGGBB`, styles by name, widths and sizes in points.
    public func store(_ write: (PreferenceKey, Any) -> Void) {
        write(.editorRedactionColour, Self.hex(redactionColour))
        write(.editorInkColour, Self.hex(ink))
        write(.editorArrowStyle, arrowStyle.rawValue)
        write(.editorArrowWidth, arrowWidth)
        write(.editorLineWidth, lineWidth)
        write(.editorShapeWidth, shapeWidth)
        write(.editorLabelSize, labelFormat.size)
        write(.editorLabelStyle, labelFormat.style.rawValue)
    }

    private static func hex(_ pixel: RGBAPixel) -> String {
        String(format: "%02X%02X%02X", Int(pixel.red), Int(pixel.green), Int(pixel.blue))
    }

    /// Six hex digits, opaque; anything else is nil.
    private static func pixel(hex: String) -> RGBAPixel? {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
        return RGBAPixel(red: UInt8(value >> 16 & 0xff), green: UInt8(value >> 8 & 0xff), blue: UInt8(value & 0xff), alpha: 255)
    }

    /// A finite number stored as any numeric type (UserDefaults returns an NSNumber).
    private static func number(_ value: Any?) -> Double? {
        let number: Double? = switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        default: nil
        }
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
}
