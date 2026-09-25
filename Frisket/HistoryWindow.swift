import AppKit
import SwiftUI
import FrisketCore

@MainActor final class HistoryWindowModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        var id: CaptureID { item.captureID }
        let item: HistoryItem
        var revision: CaptureRevision { CaptureRevision(captureID: item.captureID, number: item.revision) }
        var label: String {
            "History capture, \(item.width) by \(item.height) pixels, \(item.finalizedAt.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    @Published private(set) var rows: [Row] = []
    @Published var selected: CaptureID?
    @Published private(set) var message: String?
    @Published private(set) var disabled = false
    @Published private(set) var busy = false
    private var history: HistoryStore?
    private var list: HistoryList<NSImage>?
    private var commands: CaptureLifecycleCoordinator?
    var onRevealHistory: (() -> Void)?

    func connect(_ history: HistoryStore, commands: CaptureLifecycleCoordinator) {
        self.history = history
        self.commands = commands
        list = HistoryList(source: history) { data in
            ThumbnailImage.make(from: data, maximumPixelSize: 160).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }

    /// One query; the rows are published only when they changed, and pictures load per visible row.
    func reload(clearingMessage: Bool = true) async {
        guard let list else { return }
        switch await list.reload() {
        case let .success(changed):
            if changed || disabled { rows = list.rows.map(Row.init(item:)) }
            if selected == nil { selected = rows.first?.id }
            else if !rows.contains(where: { $0.id == selected }) { selected = rows.first?.id }
            if clearingMessage, message != nil { message = nil }
            if disabled { disabled = false }
        case let .failure(failure):
            rows = []
            selected = nil
            disabled = true
            message = HistoryFailureNotice.text(failure)
        }
    }

    func cachedPreview(_ row: Row) -> NSImage? { list?.cachedPicture(row.item) }

    /// The row's History thumbnail, looked up by ID when the row comes into view, then cached.
    func preview(for row: Row) async -> NSImage? { await list?.picture(for: row.item) }

    func retry() {
        guard !busy, let history else { return }
        busy = true
        Task {
            _ = await history.recover()
            busy = false
            await reload()
        }
    }

    var selectedRow: Row? { rows.first { $0.id == selected } }

    func moveSelection(_ delta: Int) {
        guard let index = rows.firstIndex(where: { $0.id == selected }) else {
            selected = rows.first?.id
            return
        }
        selected = rows[min(rows.count - 1, max(0, index + delta))].id
    }

    func copy() {
        guard !busy, let commands, let row = selectedRow else { return }
        busy = true
        Task {
            let result = await commands.execute(.copy(row.revision))
            busy = false
            if case .copy(let outcome) = result, case .copied = outcome.delivery { message = nil }
            else { message = "Copy failed. Try again." }
        }
    }

    func save() {
        guard !busy, let commands, let row = selectedRow else { return }
        busy = true
        Task {
            let result = await commands.execute(.save(row.revision))
            busy = false
            if case .save(let outcome) = result, case .saved = outcome.delivery { message = nil }
            else { message = "Save failed. Try again." }
        }
    }

    /// Called after a History item is deleted, so its open Thumbnail closes on screen too (D10).
    var onHistoryDeleted: ((CaptureID) -> Void)?

    func delete() {
        guard !busy, let commands, let row = selectedRow, confirmDelete(row) else { return }
        busy = true
        Task {
            let result = await commands.execute(.deleteHistory(row.item.captureID))
            busy = false
            switch result {
            case .historyDeleted(let id):
                onHistoryDeleted?(id)
                await reload()
            case .rejected(.commandInProgress):
                await reload(clearingMessage: false)
                message = "This capture is busy with another action. Delete again in a moment."
            default:
                await reload(clearingMessage: false)
                message = "Could not delete. History is unavailable."
            }
        }
    }

    /// Delete is destructive, so it is the one History action that asks first (DA-4, DA-5).
    private func confirmDelete(_ row: Row) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete this capture from History?"
        alert.informativeText = "\(row.label). It is removed at once and can't be restored. "
            + "Copies you already saved, pasted or dragged elsewhere are not affected."
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct HistoryWindowView: View {
    @ObservedObject var model: HistoryWindowModel
    var startDrag: (HistoryWindowModel.Row, NSView, NSEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = model.message {
                Text(message).foregroundStyle(.red).accessibilityLabel(message)
            }
            if model.disabled {
                HStack {
                    Button("Try Again", action: model.retry).disabled(model.busy)
                        .accessibilityLabel("Try opening History again")
                    Button("Show History Folder") { model.onRevealHistory?() }
                        .accessibilityLabel("Show History folder")
                }
            }
            List(model.rows, selection: $model.selected) { row in
                HistoryRowView(row: row, preview: model.preview(for:), startDrag: startDrag)
                    .tag(row.id)
                    // One element per row, so VoiceOver speaks the label once (part of D16).
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.label)
                    .accessibilityAddTraits(model.selected == row.id ? .isSelected : [])
            }
            .listStyle(.inset)
            .accessibilityLabel("History captures, newest first")
            HStack {
                Button("Copy", action: model.copy)
                    .keyboardShortcut("c", modifiers: [])
                    .disabled(model.busy || model.selected == nil)
                    .accessibilityLabel("Copy selected History capture")
                Button("Save", action: model.save)
                    .keyboardShortcut("s", modifiers: [])
                    .disabled(model.busy || model.selected == nil)
                    .accessibilityLabel("Save selected History capture")
                Button("Delete", action: model.delete)
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(model.busy || model.selected == nil)
                    .accessibilityLabel("Delete selected History capture")
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
        .onMoveCommand { direction in
            switch direction {
            case .up: model.moveSelection(-1)
            case .down: model.moveSelection(1)
            default: break
            }
        }
    }
}

private struct HistoryRowView: View {
    let row: HistoryWindowModel.Row
    let preview: (HistoryWindowModel.Row) async -> NSImage?
    var startDrag: (HistoryWindowModel.Row, NSView, NSEvent) -> Void
    @State private var image: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HistoryDragWell(row: row, image: image, startDrag: startDrag)
            VStack(alignment: .leading) {
                Text("\(row.item.width) × \(row.item.height)")
                Text(row.item.finalizedAt, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        // The list is lazy: a row asks for its picture only when it comes into view.
        .task(id: row.revision) { image = await preview(row) }
    }
}

private struct HistoryDragWell: NSViewRepresentable {
    let row: HistoryWindowModel.Row
    let image: NSImage?
    var startDrag: (HistoryWindowModel.Row, NSView, NSEvent) -> Void

    func makeNSView(context: Context) -> HistoryDragView {
        let view = HistoryDragView()
        view.image = image
        view.onDrag = { view, event in startDrag(row, view, event) }
        // The row is the accessibility element; the picture adds no second label.
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: HistoryDragView, context: Context) {
        view.image = image
        view.onDrag = { view, event in startDrag(row, view, event) }
    }
}

final class HistoryDragView: NSImageView {
    var onDrag: ((NSView, NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        setFrameSize(NSSize(width: 96, height: 60))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        DragStart.track(from: self, event: event) { [weak self] drag in
            guard let self else { return }
            self.onDrag?(self, drag)
        }
    }
}

@MainActor final class HistoryWindow {
    private let window: NSWindow
    let model = HistoryWindowModel()
    var startDrag: ((HistoryWindowModel.Row, NSView, NSEvent) -> Void)?

    init() {
        window = NSWindow(contentViewController: NSHostingController(rootView: Color.clear))
        window.title = "Frisket History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 640))
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setAccessibilityLabel("Frisket History")
        window.center()
        window.orderOut(nil)
        installRoot()
    }

    private func installRoot() {
        window.contentViewController = NSHostingController(rootView: HistoryWindowView(model: model) { [weak self] row, view, event in
            self?.startDrag?(row, view, event)
        })
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await model.reload() }
    }

    func reloadIfVisible() async {
        guard window.isVisible else { return }
        await model.reload()
    }
}
