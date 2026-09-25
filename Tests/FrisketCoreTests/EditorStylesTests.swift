import FrisketCore
import Testing

/// Ticket 100 (decision 93): the style bar's choices for new marks are remembered through
/// `PreferenceKey`, and a new editor opens with them. A stored value the editor does not offer is
/// ignored, so a remembered redaction colour is always one of the opaque palette colours.
@Suite struct EditorStylesTests {
    @Test func nothingStoredLoadsTheDefaults() {
        let styles = EditorStyles.load { _ in nil }
        #expect(styles == .defaults)
        #expect(styles.redactionColour == SolidRedaction.fill)
        #expect(styles.ink == DocumentAnnotation.stroke)
        #expect(styles.arrowStyle == .standard)
        #expect([styles.arrowWidth, styles.lineWidth, styles.shapeWidth] == Array(repeating: DocumentAnnotation.defaultWidth, count: 3))
        #expect(styles.labelFormat == .standard)
    }

    @Test func everyValueRoundTrips() throws {
        let chosen = EditorStyles(redactionColour: SolidRedaction.palette[2].pixel, ink: DocumentAnnotation.palette[2].pixel,
                                  arrowStyle: .curved, arrowWidth: 8, lineWidth: 4, shapeWidth: 8,
                                  labelFormat: try #require(LabelFormat(style: .box, size: 36)))
        var stored: [PreferenceKey: Any] = [:]
        chosen.store { stored[$0] = $1 }
        #expect(Set(stored.keys) == Set(EditorStyles.preferenceKeys))
        #expect(EditorStyles.load { stored[$0] } == chosen)

        // Every palette entry and menu item survives the trip.
        for colour in SolidRedaction.palette {
            var styles = EditorStyles.defaults
            styles.redactionColour = colour.pixel
            styles.store { stored[$0] = $1 }
            #expect(EditorStyles.load { stored[$0] }.redactionColour == colour.pixel, "\(colour.name)")
        }
        for ink in DocumentAnnotation.palette {
            var styles = EditorStyles.defaults
            styles.ink = ink.pixel
            styles.store { stored[$0] = $1 }
            #expect(EditorStyles.load { stored[$0] }.ink == ink.pixel, "\(ink.name)")
        }
        for style in ArrowStyle.arrowStyles {
            var styles = EditorStyles.defaults
            styles.arrowStyle = style
            styles.store { stored[$0] = $1 }
            #expect(EditorStyles.load { stored[$0] }.arrowStyle == style)
        }
        for size in LabelFormat.sizes {
            for style in LabelStyle.allCases {
                var styles = EditorStyles.defaults
                styles.labelFormat = try #require(LabelFormat(style: style, size: size))
                styles.store { stored[$0] = $1 }
                #expect(EditorStyles.load { stored[$0] }.labelFormat == styles.labelFormat)
            }
        }
    }

    @Test func anInvalidStoredValueFallsBackToItsDefaultAlone() {
        let invalid: [PreferenceKey: Any] = [
            .editorRedactionColour: "FF0000",   // red is not a redaction colour
            .editorInkColour: "123456",         // not a palette ink
            .editorArrowStyle: "line",          // the Line tool's style, not an Arrow style
            .editorArrowWidth: 3.0,             // not an offered width
            .editorLineWidth: "wide",           // the wrong type
            .editorShapeWidth: Double.nan,
            .editorLabelSize: 20.0,             // not an offered size
            .editorLabelStyle: "shadow",
        ]
        #expect(EditorStyles.load { invalid[$0] } == .defaults)

        for key in EditorStyles.preferenceKeys {
            // One bad value leaves the others as stored.
            var stored: [PreferenceKey: Any] = [:]
            let chosen = EditorStyles(redactionColour: SolidRedaction.palette[4].pixel, ink: DocumentAnnotation.palette[3].pixel,
                                      arrowStyle: .double, arrowWidth: 4, lineWidth: 8, shapeWidth: 4,
                                      labelFormat: LabelFormat(style: .outlined, size: 48)!)
            chosen.store { stored[$0] = $1 }
            stored[key] = invalid[key]
            let loaded = EditorStyles.load { stored[$0] }
            var expected = chosen
            switch key {
            case .editorRedactionColour: expected.redactionColour = EditorStyles.defaults.redactionColour
            case .editorInkColour: expected.ink = EditorStyles.defaults.ink
            case .editorArrowStyle: expected.arrowStyle = EditorStyles.defaults.arrowStyle
            case .editorArrowWidth: expected.arrowWidth = EditorStyles.defaults.arrowWidth
            case .editorLineWidth: expected.lineWidth = EditorStyles.defaults.lineWidth
            case .editorShapeWidth: expected.shapeWidth = EditorStyles.defaults.shapeWidth
            case .editorLabelSize: expected.labelFormat = LabelFormat(style: .outlined, size: LabelFormat.defaultSize)!
            case .editorLabelStyle: expected.labelFormat = LabelFormat(style: .standard, size: 48)!
            default: Issue.record("\(key) is not an editor style key")
            }
            #expect(loaded == expected, "\(key)")
        }
    }

    @Test func aRememberedRedactionColourIsAlwaysOpaque() {
        // Decision 93: Solid redaction's guarantees are unchanged. Only palette colours load.
        for raw in ["000000", "404040", "808080", "C0C0C0", "FFFFFF", "00000000", "zzzzzz", "", "#808080"] {
            let colour = EditorStyles.load { $0 == .editorRedactionColour ? raw : nil }.redactionColour
            #expect(colour.alpha == 255)
            #expect(SolidRedaction.palette.contains { $0.pixel == colour }, "\(raw)")
        }
    }
}
