import Foundation
import FrisketCore
import Testing

/// Ticket 92 (D29): the editor's style controls live in the style bar under the toolbar, which
/// shows only the controls for the selected mark, or else for the active tool, so none of them
/// lands in the toolbar's overflow menu.
@Suite struct StyleBarTests {
    private static func marked() throws -> DocumentEdits {
        let redaction = try #require(SolidRedaction(x: 4, y: 4, width: 10, height: 8))
        let shape = try #require(DocumentAnnotation(.rectangle(x: 30, y: 4, width: 20, height: 16)))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 4, y0: 40, x1: 40, y1: 40), style: .curved))
        let line = try #require(DocumentAnnotation(.arrow(x0: 4, y0: 60, x1: 40, y1: 60), style: .line))
        let label = try #require(DocumentAnnotation(.text(x: 4, y: 50, characters: "Hi")))
        let blur = try #require(DocumentEffect(.blur(x: 20, y: 30, width: 8, height: 6)))
        return try #require(DocumentEdits(scale: 2, redactions: [redaction], annotations: [shape, arrow, line, label],
                                          effects: [blur]))
    }

    @Test func eachToolShowsOnlyItsOwnControls() throws {
        let edits = try Self.marked()
        let expected: [(EditorToolKind, [StyleControl])] = [
            (.select, []),
            (.solidRedaction, [.redactionColour]),
            (.crop, []),
            (.arrow, [.inkColour, .arrowStyle, .lineWidth]),
            (.line, [.inkColour, .lineWidth]),
            (.shape, [.inkColour, .lineWidth]),
            (.text, [.inkColour, .labelSize, .labelStyle]),
            (.blur, []),
            (.magnify, []),
        ]
        #expect(Set(expected.map(\.0)) == Set(EditorToolKind.allCases))
        for (tool, controls) in expected {
            #expect(StyleBar.controls(tool: tool, selection: nil, in: edits) == controls, "\(tool)")
        }
    }

    @Test func aSelectedMarkShowsItsControlsWhateverTheTool() throws {
        let edits = try Self.marked()
        let expected: [(MarkReference, [StyleControl])] = [
            (.redaction(0), [.redactionColour]),
            (.annotation(0), [.inkColour, .lineWidth]),
            (.annotation(1), [.inkColour, .arrowStyle, .lineWidth]),
            (.annotation(2), [.inkColour, .lineWidth]),
            (.annotation(3), [.inkColour, .labelSize, .labelStyle]),
        ]
        for tool in EditorToolKind.allCases {
            for (mark, controls) in expected {
                #expect(StyleBar.controls(tool: tool, selection: mark, in: edits) == controls, "\(mark) with \(tool)")
            }
        }
    }

    @Test func aSelectedMarkWithNoStyleLeavesTheToolsControls() throws {
        let edits = try Self.marked()
        #expect(StyleBar.controls(tool: .solidRedaction, selection: .effect(0), in: edits) == [.redactionColour])
        #expect(StyleBar.controls(tool: .select, selection: .effect(0), in: edits) == [])
        #expect(StyleBar.controls(tool: .text, selection: .annotation(9), in: edits) == [.inkColour, .labelSize, .labelStyle],
                "a stale reference falls back to the tool")
    }

    /// Ticket 99: the ink swatches never show for Solid redaction, Crop, Blur or Magnify, nor for a
    /// selected redaction or effect.
    @Test func inkIsOfferedOnlyForArrowsLinesShapesAndLabels() throws {
        let edits = try Self.marked()
        for tool in [EditorToolKind.select, .solidRedaction, .crop, .blur, .magnify] {
            #expect(!StyleBar.controls(tool: tool, selection: nil, in: edits).contains(.inkColour), "\(tool)")
        }
        for mark in [MarkReference.redaction(0), .effect(0)] {
            #expect(!StyleBar.controls(tool: .select, selection: mark, in: edits).contains(.inkColour), "\(mark)")
        }
    }
}
