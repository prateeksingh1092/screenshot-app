import Foundation
import FrisketCore
import Testing

/// Ticket 69 (O11): the editor's edits undo and redo through an `UndoManager`, the one the
/// editor window returns, so ⌘Z, ⌘⇧Z and Edit › Undo/Redo treat every edit kind alike.
@MainActor @Suite struct UndoableEditsTests {
    /// Ends the current event. The undo manager groups by event: the run loop closes the group
    /// after the canvas mouse-up returns. A run loop with nothing scheduled returns at once, so a
    /// timer keeps it running for one pass.
    private static func endEvent(_ undoManager: UndoManager) {
        #expect(undoManager.groupingLevel == 1, "each edit opens exactly one event group")
        RunLoop.main.add(Timer(timeInterval: 0.001, repeats: false) { _ in }, forMode: .default)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        #expect(undoManager.groupingLevel == 0, "the event's undo group is closed")
    }

    private static func base() throws -> DocumentEdits { try #require(DocumentEdits(scale: 2)) }

    /// Each edit kind, as the editor's tool would add it, with the name the Undo menu item shows.
    private static func editKinds() throws -> [(name: String, edit: (inout DocumentEdits) -> Void)] {
        let redaction = try #require(SolidRedaction(x: 1, y: 2, width: 3, height: 4))
        let crop = try #require(DocumentCrop(x: 5, y: 5, width: 20, height: 10))
        let shape = try #require(DocumentAnnotation(.rectangle(x: 1, y: 1, width: 6, height: 6)))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 0, y0: 0, x1: 9, y1: 9)))
        let label = try #require(DocumentAnnotation(.text(x: 3, y: 3, characters: "A1")))
        let blur = try #require(DocumentEffect(.blur(x: 2, y: 2, width: 5, height: 5)))
        let magnify = try #require(DocumentEffect(.magnify(x: 2, y: 2, width: 5, height: 5)))
        return [
            ("Solid Redaction", { $0.redactions.append(redaction) }),
            ("Crop", { $0.crop = crop }),
            ("Shape", { $0.annotations.append(shape) }),
            ("Arrow", { $0.annotations.append(arrow) }),
            ("Label", { $0.annotations.append(label) }),
            ("Blur", { $0.effects.append(blur) }),
            ("Magnify", { $0.effects.append(magnify) })
        ]
    }

    @Test func everyEditKindUndoesAndRedoesAndNamesTheEdit() throws {
        for kind in try Self.editKinds() {
            let undoManager = UndoManager()
            let document = UndoableEdits(try Self.base(), undoManager: undoManager)
            var next = document.edits
            kind.edit(&next)

            document.apply(next)
            Self.endEvent(undoManager)
            #expect(document.edits == next, "\(kind.name) applies")
            #expect(undoManager.canUndo, "\(kind.name) is undoable")
            #expect(undoManager.undoActionName == kind.name)
            #expect(!document.isUnchanged)

            undoManager.undo()
            #expect(document.edits == (try Self.base()), "\(kind.name) undoes")
            #expect(document.isUnchanged, "undoing \(kind.name) leaves nothing to ask about on close")
            #expect(!undoManager.canUndo)
            #expect(undoManager.canRedo, "\(kind.name) is redoable")
            #expect(undoManager.redoActionName == kind.name)

            undoManager.redo()
            #expect(document.edits == next, "\(kind.name) redoes")
            #expect(undoManager.undoActionName == kind.name)
        }
    }

    @Test func editsUndoOneAtATimeInReverseOrderAndRedoForward() throws {
        let undoManager = UndoManager()
        let document = UndoableEdits(try Self.base(), undoManager: undoManager)
        var states = [document.edits]
        for kind in try Self.editKinds() {
            var next = document.edits
            kind.edit(&next)
            document.apply(next)
            Self.endEvent(undoManager)
            states.append(next)
        }
        let names = try Self.editKinds().map(\.name)
        for index in names.indices.reversed() {
            #expect(undoManager.undoActionName == names[index])
            undoManager.undo()
            #expect(document.edits == states[index])
        }
        #expect(!undoManager.canUndo)
        for index in names.indices {
            #expect(undoManager.redoActionName == names[index])
            undoManager.redo()
            #expect(document.edits == states[index + 1])
        }
    }

    /// Ticket 95: the name is the mark that changed, not the newest mark of its family.
    @Test func anEditNamesTheMarkItChangedNotTheNewestMark() throws {
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 0, y0: 0, x1: 9, y1: 9)))
        let movedArrow = try #require(DocumentAnnotation(.arrow(x0: 1, y0: 1, x1: 10, y1: 10)))
        let label = try #require(DocumentAnnotation(.text(x: 3, y: 3, characters: "A1")))
        let blur = try #require(DocumentEffect(.blur(x: 2, y: 2, width: 5, height: 5)))
        let movedBlur = try #require(DocumentEffect(.blur(x: 3, y: 3, width: 5, height: 5)))
        let magnify = try #require(DocumentEffect(.magnify(x: 2, y: 2, width: 5, height: 5)))
        var start = try Self.base()
        start.annotations = [arrow, label]
        start.effects = [blur, magnify]
        let changes: [(name: String, edit: (inout DocumentEdits) -> Void)] = [
            ("Arrow", { $0.annotations[0] = movedArrow }),
            ("Arrow", { $0.annotations.remove(at: 0) }),
            ("Label", { $0.annotations.remove(at: 1) }),
            ("Blur", { $0.effects[0] = movedBlur }),
            ("Blur", { $0.effects.remove(at: 0) }),
            ("Magnify", { $0.effects.append(magnify) })
        ]
        for change in changes {
            let undoManager = UndoManager()
            let document = UndoableEdits(start, undoManager: undoManager)
            var next = document.edits
            change.edit(&next)
            document.apply(next)
            Self.endEvent(undoManager)
            #expect(undoManager.undoActionName == change.name)
        }
    }

    @Test func aNewEditAfterUndoClearsRedo() throws {
        let undoManager = UndoManager()
        let document = UndoableEdits(try Self.base(), undoManager: undoManager)
        let kinds = try Self.editKinds()
        var first = document.edits
        kinds[0].edit(&first)
        document.apply(first)
        Self.endEvent(undoManager)
        undoManager.undo()
        var second = document.edits
        kinds[1].edit(&second)
        document.apply(second)
        Self.endEvent(undoManager)
        #expect(!undoManager.canRedo)
        #expect(undoManager.undoActionName == kinds[1].name)
    }

    @Test func anEditThatChangesNothingRegistersNoUndo() throws {
        let undoManager = UndoManager()
        let document = UndoableEdits(try Self.base(), undoManager: undoManager)
        var changes = 0
        document.onChange = { changes += 1 }
        document.apply(document.edits)
        #expect(!undoManager.canUndo)
        #expect(changes == 0)
    }

    @Test func undoAndRedoTellTheEditorToRefresh() throws {
        let undoManager = UndoManager()
        let document = UndoableEdits(try Self.base(), undoManager: undoManager)
        var seen: [DocumentEdits] = []
        document.onChange = { seen.append(document.edits) }
        var next = document.edits
        try Self.editKinds()[1].edit(&next)
        document.apply(next)
        Self.endEvent(undoManager)
        undoManager.undo()
        undoManager.redo()
        #expect(seen == [next, try Self.base(), next])
    }
}
