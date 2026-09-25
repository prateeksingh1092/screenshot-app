import Foundation

/// The editor's `DocumentEdits` with their undo history (ticket 69). Every change registers on
/// `undoManager`, named for the edit it made. The manager groups by event, as AppKit's do, so each
/// canvas drag (one mouse-up) is one undo step and label typing coalesces as usual. The editor window
/// returns this manager, so ⌘Z, ⌘⇧Z and Edit › Undo/Redo treat every edit kind, crop included, alike.
@MainActor public final class UndoableEdits {
    public let undoManager: UndoManager
    public private(set) var edits: DocumentEdits
    /// Called after every change: an applied edit, an undo or a redo.
    public var onChange: (() -> Void)?

    public init(_ edits: DocumentEdits, undoManager: UndoManager = UndoManager()) {
        self.edits = edits
        self.undoManager = undoManager
    }

    /// True when there is nothing to keep: no crop, redaction, annotation or effect.
    public var isUnchanged: Bool {
        edits.crop == nil && edits.redactions.isEmpty && edits.annotations.isEmpty && edits.effects.isEmpty
    }

    /// Applies `next` as an undoable edit in the current event's undo group.
    /// An edit that changes nothing registers nothing.
    public func apply(_ next: DocumentEdits) {
        guard next != edits else { return }
        let name = Self.actionName(from: edits, to: next)
        replace(with: next)
        undoManager.setActionName(name)
    }

    /// Applies `next` as one undoable edit named `name`, such as "Move Arrow" (ticket 84).
    public func apply(_ next: DocumentEdits, named name: String) {
        guard next != edits else { return }
        replace(with: next)
        undoManager.setActionName(name)
    }

    /// Applies `next` named `name`, folded into the previous step when that step was applied with the
    /// same `key` and nothing has been undone, redone or applied since. Typing one label (ticket 86)
    /// is therefore one undo step however many events it spans, as typing is in any Mac text view.
    public func apply(_ next: DocumentEdits, named name: String, coalescing key: AnyHashable) {
        guard next != edits else { return }
        if coalescing == key, undoManager.canUndo, !undoManager.canRedo, undoManager.undoActionName == name {
            edits = next
            onChange?()
            return
        }
        replace(with: next)
        undoManager.setActionName(name)
        coalescing = key
    }

    /// The key of the last step `apply(_:named:coalescing:)` registered, until anything else changes the edits.
    private var coalescing: AnyHashable?

    /// Registers the inverse before changing, so undo registers redo and redo registers undo.
    private func replace(with next: DocumentEdits) {
        coalescing = nil
        let previous = edits
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.replace(with: previous) }
        }
        edits = next
        onChange?()
    }

    /// The name the Undo and Redo menu items show for the change from `old` to `new`: the noun of the
    /// mark that changed (ticket 95), from `DocumentEdits.noun(for:)` like the mark-editing names.
    static func actionName(from old: DocumentEdits, to new: DocumentEdits) -> String {
        if old.crop != new.crop { return "Crop" }
        if old.redactions != new.redactions { return "Solid Redaction" }
        if let (edits, index) = changed(old.annotations, new.annotations, in: old, new) {
            return edits.noun(for: .annotation(index))
        }
        if let (edits, index) = changed(old.effects, new.effects, in: old, new) {
            return edits.noun(for: .effect(index))
        }
        return "Edit"
    }

    /// The first mark that differs, read from `new`, or from `old` when a mark was removed.
    private static func changed<Mark: Equatable>(_ before: [Mark], _ after: [Mark], in old: DocumentEdits,
                                                 _ new: DocumentEdits) -> (DocumentEdits, Int)? {
        guard before != after else { return nil }
        let shared = min(before.count, after.count)
        let index = (0..<shared).first { before[$0] != after[$0] } ?? shared
        return after.count < before.count ? (old, index) : (new, index)
    }
}
