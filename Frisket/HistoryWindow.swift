import AppKit
import SwiftUI
import FrisketCore

@MainActor final class HistoryWindowModel: ObservableObject {
    struct Row: Identifiable {
        var id: CaptureID { item.captureID }
        let item: HistoryItem
        let preview: NSImage?
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
    private var commands: CaptureCommandLayer?
    var onRevealHistory: (() -> Void)?

    func connect(_ commands: CaptureCommandLayer) { self.commands = commands }

    func reload(clearingMessage: Bool = true) async {
        guard let commands else { return }
        switch await commands.historyItems() {
        case let .success(items):
            var next: [Row] = []
            rows = next
            for item in items {
                let preview: NSImage?
                if let thumbnail = await commands.historyThumbnail(item.captureID) {
                    preview = NSImage(data: thumbnail)
                } else {
                    preview = await commands.historyImage(item.captureID).flatMap {
                        ThumbnailImage.make(from: $0.pngData, maximumPixelSize: 160)
                    }.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
                }
                next.append(Row(item: item, preview: preview))
                rows = next
            }
            if selected == nil { selected = rows.first?.id }
            else if !rows.contains(where: { $0.id == selected }) { selected = rows.first?.id }
            if clearingMessage { message = nil }
            disabled = false
        case let .failure(failure):
            rows = []
            selected = nil
            disabled = true
            message = HistoryFailureNotice.text(failure)
        }
    }

    func retry() {
        guard !busy, let commands else { return }
        busy = true
        Task {
            _ = await commands.recoverHistory()
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

    func delete() {
        guard !busy, let commands, let row = selectedRow else { return }
        busy = true
        Task {
            let result = await commands.execute(.deleteHistory(row.item.captureID))
            busy = false
            if case .historyDeleted = result {
                await reload()
            } else {
                await reload(clearingMessage: false)
                message = "Delete failed. Try again."
            }
        }
    }
}

private struct HistoryWindowView: View {
    @ObservedObject var model: HistoryWindowModel
    var startDrag: (HistoryWindowModel.Row, NSView, NSEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Finished captures. Copy, save, drag, or delete. There is no editor.")
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
                HistoryRowView(row: row, startDrag: startDrag)
                    .tag(row.id)
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
    var startDrag: (HistoryWindowModel.Row, NSView, NSEvent) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HistoryDragWell(row: row, startDrag: startDrag)
            VStack(alignment: .leading) {
                Text("\(row.item.width) × \(row.item.height)")
                Text(row.item.finalizedAt, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDragWell: NSViewRepresentable {
    let row: HistoryWindowModel.Row
    var startDrag: (HistoryWindowModel.Row, NSView, NSEvent) -> Void

    func makeNSView(context: Context) -> HistoryDragView {
        let view = HistoryDragView()
        view.image = row.preview
        view.onDrag = { view, event in startDrag(row, view, event) }
        view.setAccessibilityLabel(row.label)
        return view
    }

    func updateNSView(_ view: HistoryDragView, context: Context) {
        view.image = row.preview
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
