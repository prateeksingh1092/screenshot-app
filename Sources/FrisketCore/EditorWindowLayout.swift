import Foundation

/// Sizes the editor so the capture is shown at natural size when it fits, and
/// scaled down uniformly when chrome plus the image would overflow the display.
public struct EditorWindowLayout: Sendable {
    public struct Chrome: Equatable, Sendable {
        public var toolbarHeight: CGFloat
        public var titlebarHeight: CGFloat
        public init(toolbarHeight: CGFloat, titlebarHeight: CGFloat) {
            self.toolbarHeight = toolbarHeight
            self.titlebarHeight = titlebarHeight
        }
    }

    /// Window content size, excluding the titlebar.
    public static func contentSize(document: CGSize, visible: CGSize, chrome: Chrome) -> CGSize {
        guard document.width > 0, document.height > 0, visible.width > 0, visible.height > 0 else {
            return CGSize(width: 1, height: max(chrome.toolbarHeight + 1, 1))
        }
        let maxCanvasHeight = max(visible.height - chrome.titlebarHeight - chrome.toolbarHeight, 1)
        let scale = min(visible.width / document.width, maxCanvasHeight / document.height, 1)
        return CGSize(width: document.width * scale,
                      height: document.height * scale + chrome.toolbarHeight)
    }
}

extension EditorWindowLayout {
    /// The narrowest and the opening width of the editor's content area, in points.
    public static let minimumContentWidth: CGFloat = 560
    public static let defaultContentWidth: CGFloat = 760
    /// The action bar along the bottom of the content area (D5).
    public static let actionBarHeight: CGFloat = 52
    public static let actionBarMargin: CGFloat = 12
    static let actionSpacing: CGFloat = 8
    static let actionButtonSize = CGSize(width: 76, height: 28)
    static let dragHandleSize = CGSize(width: 56, height: 36)

    /// Frames inside the action bar, in its own coordinates (origin at the bottom left).
    public struct ActionBar: Equatable, Sendable {
        public var dragHandle: CGRect
        public var copy: CGRect
        public var save: CGRect
        public var done: CGRect
    }

    /// The drag handle sits at the leading edge; Copy, Save and Done are right-aligned, Done last.
    /// The bar lives in the content area rather than the toolbar, so nothing here can overflow.
    public static func actionBar(width: CGFloat) -> ActionBar {
        let button = actionButtonSize
        let buttonY = ((actionBarHeight - button.height) / 2).rounded()
        let done = CGRect(x: width - actionBarMargin - button.width, y: buttonY,
                          width: button.width, height: button.height)
        let save = done.offsetBy(dx: -(button.width + actionSpacing), dy: 0)
        let copy = save.offsetBy(dx: -(button.width + actionSpacing), dy: 0)
        let drag = CGRect(x: actionBarMargin, y: ((actionBarHeight - dragHandleSize.height) / 2).rounded(),
                          width: dragHandleSize.width, height: dragHandleSize.height)
        return ActionBar(dragHandle: drag, copy: copy, save: save, done: done)
    }
}

/// What a key the editor window receives means. Command keys belong to the main menu (⌘C, ⌘S,
/// ⌘W, ⌘Z); Return and keypad Enter mean Done; a letter selects a tool. While the label field
/// is editing, every key is typing, so Return there never means Done (D5).
public enum EditorKey: Equatable, Sendable {
    case done
    case tool(Character)

    public static func action(characters: String?, commandLike: Bool, editingText: Bool) -> EditorKey? {
        guard !commandLike, !editingText, let key = characters?.first else { return nil }
        if key == "\r" || key == "\u{3}" { return .done }
        guard key.isLetter else { return nil }
        return .tool(Character(key.lowercased()))
    }
}
