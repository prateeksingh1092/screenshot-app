import AppKit
import FrisketCore

/// Write-only system seam. Tests receive the actual AppKit items and options.
@MainActor public protocol PasteboardDestination: AnyObject {
    var changeCount: Int { get }
    func replace(with items: [NSPasteboardItem], options: NSPasteboard.ContentsOptions) -> Int?
}

@MainActor public final class GeneralPasteboardDestination: PasteboardDestination {
    public init() {}
    public var changeCount: Int { NSPasteboard.general.changeCount }
    public func replace(with items: [NSPasteboardItem], options: NSPasteboard.ContentsOptions) -> Int? {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: options)
        guard board.writeObjects(items) else { return nil }
        return board.changeCount // Metadata only; never inspect clipboard contents.
    }
}

@MainActor public final class PasteboardAdapter: ImageClipboard, TextClipboard {
    private let destination: any PasteboardDestination
    public init(destination: any PasteboardDestination) { self.destination = destination }

    public func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        // This method has no suspension between the metadata check and replacement.
        // Never read types, items or contents from the general pasteboard.
        if let receipt = image.replacing, destination.changeCount != receipt.changeCount {
            return .failure(.changed)
        }
        let item = NSPasteboardItem()
        guard item.setData(image.pngData, forType: .png),
              item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
              let count = destination.replace(with: [item], options: [.currentHostOnly]) else {
            return .failure(.unavailable)
        }
        return .success(ClipboardReceipt(changeCount: count))
    }

    public func writeText(_ text: String) async -> Result<ClipboardReceipt, ClipboardFailure> {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
              let count = destination.replace(with: [item], options: [.currentHostOnly]) else {
            return .failure(.unavailable)
        }
        return .success(ClipboardReceipt(changeCount: count))
    }
}
