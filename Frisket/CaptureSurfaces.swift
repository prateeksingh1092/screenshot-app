import AppKit
import FrisketCore

/// Thumbnail cards, the editor, and capture dispatch. Policy stays in `CaptureCommandLayer`.
@MainActor final class CaptureSurfaces {
    private let commands: CaptureCommandLayer
    private let dragAdapter: FilePromiseDragAdapter
    private let latency: CaptureLatencyLog
    private let notify: (String, String) -> Void
    private let refreshHistory: () async -> Void
    /// Recovery, onboarding, and an in-flight permission prompt. Return false to skip the capture.
    var canStart: () -> Bool = { true }
    var onCaptureFinished: () -> Void = {}

    private(set) var isCapturing = false
    var isTerminating = false
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    private var editors: [CaptureID: EditorWindow] = [:]
    /// Wakes the stack at the core's next due time; the core owns order, displays and status (ticket 73).
    private var nextDue: Task<Void, Never>?

    var hasEditor: Bool { !editors.isEmpty }
    var hasBusyThumbnail: Bool { panels.values.contains { $0.model.busy } }
    var hasThumbnail: Bool { !panels.isEmpty }

    init(commands: CaptureCommandLayer, drag: FilePromiseDragAdapter, latency: CaptureLatencyLog,
         notify: @escaping (String, String) -> Void,
         refreshHistory: @escaping () async -> Void) {
        self.commands = commands
        self.dragAdapter = drag
        self.latency = latency
        self.notify = notify
        self.refreshHistory = refreshHistory
    }

    func offerEditorsToLeave() {
        for editor in editors.values { editor.offerToLeave() }
    }

    func interruptForPowerOff() {
        for editor in editors.values { editor.interruptUnansweredPrompt(.logout) }
    }

    func markThumbnailsBusy() {
        for panel in panels.values { panel.model.busy = true }
    }

    func start(_ command: CaptureCommand) {
        guard !isCapturing, !isTerminating, canStart() else { return }
        isCapturing = true
        Task {
            defer { latency.cancel(); isCapturing = false; onCaptureFinished() }
            let result = await commands.execute(command)
            switch result {
            case let .pending(revision):
                await showThumbnail(revision)
            case .captureFailed(.cancelled): break
            case let .permissionRequired(state):
                permissionRequired?(state)
            case let .captureFailed(.window(failure)):
                notice(failure.title, failure.message)
            case .captureFailed:
                notice("Capture unavailable", "A disconnected display or an oversized capture can prevent capture. Try again with a smaller area.")
            default:
                notice("Capture unavailable", "Copy or delete pending captures, then try again.")
            }
        }
    }

    /// Permission recovery stays with the application delegate.
    var permissionRequired: ((CapturePermissionState) -> Void)?

    /// Blocks new captures and thumbnail actions before the quit task suspends.
    func beginQuit() {
        isTerminating = true
        markThumbnailsBusy()
    }

    /// Finalizes pending thumbnails for quit. Returns false when a commit failed.
    func finishQuit() async -> Bool {
        await applyQuit(await commands.handleSystemEvent(.quit))
    }

    /// Quit finalization. Returns false when a commit failed and quit should cancel.
    private func applyQuit(_ results: [CaptureCommandOutcome]) async -> Bool {
        await refreshHistory()
        for result in results {
            if case .finalized(_, let commit) = result { showOversizedNotice(commit) }
            if case .finalized(let revision, .committed) = result {
                remove(revision.captureID)
                continue
            }
            if case .finalized(let revision, _) = result, let panel = panels[revision.captureID] {
                panel.model.dismissFailed = true
            }
            for panel in panels.values { panel.model.busy = false }
            isTerminating = false
            return false
        }
        return true
    }

    func focusThumbnail() {
        Task {
            await commands.setThumbnailStackFocus(true)
            if let revision = await commands.focusedThumbnail() {
                panels[revision.captureID]?.focus()
            }
        }
    }

    func copyLatest() {
        Task { if let id = await latestThumbnail() { copy(id) } }
    }

    func deleteLatest() {
        Task { if let id = await latestThumbnail() { discard(id) } }
    }

    private func latestThumbnail() async -> CaptureID? {
        await commands.thumbnails().first { panels[$0.revision.captureID] != nil }?.revision.captureID
    }

    func screenLocked() {
        Task {
            _ = await commands.handleSystemEvent(.screenLocked)
            await settleThumbnails()
        }
    }

    func screenUnlocked() {
        Task {
            _ = await commands.handleSystemEvent(.screenUnlocked)
            await settleThumbnails()
        }
    }

    func screensChanged() {
        Task { await rehomeThumbnails() }
    }

    private func notice(_ title: String, _ message: String) { notify(title, message) }

    private func showThumbnail(_ revision: CaptureRevision) async {
        // The capture names its display (ticket 75); an unknown or unplugged one falls back to the main screen.
        guard let image = await commands.image(for: revision),
              let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480),
              let screen = screen(for: image.displayID) ?? NSScreen.main else {
            _ = await commands.execute(.discard(revision.captureID))
            notice("Preview unavailable", "The capture could not be displayed and was deleted.")
            return
        }
        let id = revision.captureID
        panels[id] = makePanel(id, revision: revision, preview: preview)
        if let assignedDisplay = displayID(of: screen) { await commands.assignThumbnailDisplay(id, displayID: assignedDisplay) }
        await settleThumbnails()
        // Downsampling and orderFrontRegardless have completed. This is
        // presentation submission, not a physical-display timestamp.
        latency.thumbnailSubmitted()
    }

    private func makePanel(_ id: CaptureID, revision: CaptureRevision, preview: CGImage) -> ThumbnailPanel {
        let panel = ThumbnailPanel(revision: revision, preview: preview,
            actions: ThumbnailCardActions(copy: { [weak self] in self?.copy(id) },
                                          save: { [weak self] in self?.save(id) },
                                          delete: { [weak self] in self?.discard(id) },
                                          close: { [weak self] in self?.leave(id, by: .close) },
                                          escape: { [weak self] in self?.leave(id, by: .escape) },
                                          swipe: { [weak self] in self?.leave(id, by: .swipe) },
                                          edit: { [weak self] in self?.edit(id) },
                                          copyText: { [weak self] in self?.copyRecognizedText(id) }),
            startDrag: { [weak self] view, event in self?.startDrag(id, from: view, event: event) })
        panel.moveFocus = { [weak self] move in self?.moveStackFocus(move) }
        panel.onBecomeKey = { [weak self] in
            Task { await self?.commands.setThumbnailStackFocus(true) }
        }
        panel.onResignKey = { [weak self] in
            Task { await self?.releaseStackFocusIfIdle() }
        }
        return panel
    }

    private func moveStackFocus(_ move: ThumbnailFocusMove) {
        Task {
            guard let revision = await commands.moveThumbnailFocus(move) else { return }
            panels[revision.captureID]?.focus()
        }
    }

    private func releaseStackFocusIfIdle() async {
        try? await Task.sleep(for: .milliseconds(50))
        if panels.values.contains(where: \.isKey) { return }
        await commands.setThumbnailStackFocus(false)
        await settleThumbnails()   // a paused timeout may be due now
    }

    private func edit(_ id: CaptureID) {
        guard !isTerminating, editors[id] == nil, let panel = panels[id], !panel.model.busy, panel.model.editable else { return }
        panel.model.busy = true
        Task {
            let screen = await thumbnailScreen(id)
            let codec = PNGBitmapCodec()
            guard let image = await commands.image(for: panel.revision),
                  let pixels = codec.pixelSize(image.pngData),
                  let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: EditorProxy.maxEdge),
                  let base = codec.bitmap(from: preview),
                  let editor = EditorWindow(base: base,
                                            pixelSize: CGSize(width: pixels.width, height: pixels.height),
                                            scale: Double(screen?.backingScaleFactor ?? 1), screen: screen,
                                            finish: { [weak self] leave in await self?.finishEditing(id, leave) ?? false }) else {
                panel.model.busy = false
                notice("Editor unavailable", "This capture can't be edited. Copy, dismiss, or delete it instead.")
                return
            }
            editor.onFileDrag = { [weak self] view, event in self?.startEditorDrag(id, from: view, event: event) }
            storeEditor(editor, for: id)
            editor.show()
        }
    }

    private func finishEditing(_ id: CaptureID, _ leave: EditorLeave) async -> Bool {
        guard let panel = panels[id] else { return false }
        switch leave {
        case .finalize(nil):
            let outcome = await commands.execute(.dismiss(panel.revision))
            if case .finalized(_, let commit) = outcome {
                storeEditor(nil, for: id)
                showOversizedNotice(commit)
                if commit == .committed { remove(id); return true }
                panel.model.busy = false
                panel.model.dismissFailed = true
                return true
            }
            panel.model.busy = false
            notice("Could not keep the capture", "History did not accept this capture. Copy or Save it, then try again.")
            return false
        case .delete:
            _ = await commands.execute(.discard(id))
            storeEditor(nil, for: id)
            remove(id)
            return true
        case .finalize(.some), .deliver:
            let delivery: EditorDelivery? = if case let .deliver(_, kind) = leave { kind } else { nil }
            // An editor drag renders the edits but commits nothing; only an accepted drop finalizes it (DA-3).
            let revision: CaptureRevision, commit: CommitOutcome?, clipboardFailure: ClipboardFailure?
            switch await commands.execute(leave.command(for: panel.revision)) {
            case let .edited(edited, committed, failure): (revision, commit, clipboardFailure) = (edited, committed, failure)
            case let .rendered(rendered, failure): (revision, commit, clipboardFailure) = (rendered, nil, failure)
            default:
                notice("Could not finish editing", "Your edits are still open. Done could not prepare the redacted result. Press Done again to finish editing.")
                return false
            }
            storeEditor(nil, for: id)
            guard let image = await commands.image(for: revision),
                  let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480) else {
                remove(id)
                if case .finalized(_, .committed) = await commands.execute(.dismiss(revision)) { return true }
                notice("Preview unavailable", "The redacted capture couldn't be shown or kept in History.")
                return true
            }
            panel.close()
            let refreshed = makePanel(id, revision: revision, preview: preview)
            refreshed.model.dismissFailed = commit.map { $0 != .committed } ?? false
            if let delivery {
                let delivered = await commands.execute(delivery.command(for: revision))
                if case .copy(let outcome) = delivered, case .failed = outcome.delivery { refreshed.model.copyFailed = true }
                if case .save(let outcome) = delivered, case .failed = outcome.delivery { refreshed.model.saveFailed = true }
                if case .rejected = delivered, delivery == .copy { refreshed.model.copyFailed = true }
                if case .rejected = delivered, delivery == .save { refreshed.model.saveFailed = true }
                if case .drag(let outcome) = delivered {
                    if outcome.delivery != .copied { refreshed.model.dragFailed = true }
                    else if case .notCommitted = outcome.commit {
                        notice("Could not add to History", "The capture was dragged out, but could not be added to History.")
                    }
                }
                if case .rejected = delivered, delivery == .drag { refreshed.model.dragFailed = true }
            }
            panels[id] = refreshed
            await settleThumbnails()   // applies the core's status to the new card
            if clipboardFailure != nil {
                notice("Could not replace the earlier copy", "The clipboard may still contain the original capture. Use Copy on the redacted thumbnail to replace it.")
            }
            return true
        }
    }

    private func copyRecognizedText(_ id: CaptureID) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            let result = await commands.execute(.copyRecognizedText(panel.revision))
            panel.model.busy = false
            // Non-modal (DA-5): the Thumbnail's status line shows the result and VoiceOver announces it.
            switch result {
            case let .recognizedText(outcome):
                if case .copied = outcome.delivery {
                    panel.model.textNotice = "Copied \(outcome.characterCount) characters"
                } else {
                    panel.model.textNotice = "Could not copy text. Try again."
                }
            case .noTextFound:
                panel.model.textNotice = "No text found"
            default:
                panel.model.textNotice = "Could not copy text. The capture changed."
            }
            let shown = panel.model.textNotice
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if panel.model.textNotice == shown { panel.model.textNotice = "" }
            }
        }
    }

    private func copy(_ id: CaptureID) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            let result = await commands.execute(panel.model.copyFailed ? .retryCopy(panel.revision) : .copy(panel.revision))
            defer { panel.model.busy = false }
            guard case .copy(let outcome) = result else {
                panel.model.copyFailed = true
                return
            }
            await refreshHistory()
            showOversizedNotice(outcome.commit)
            await settleThumbnails()
            if case .copied = outcome.delivery {
                if outcome.commit == .notCommitted(.recoveryRequired) {
                    notice("History needs recovery", "The capture was copied, but History could not finish keeping it. This capture cannot be edited.")
                    remove(id)
                } else if outcome.commit == .notCommitted(.captureExceedsHistoryLimit) {
                    remove(id)
                } else if case .notCommitted = outcome.commit {
                    panel.model.copiedWhilePending = true
                    panel.model.copyFailed = false
                    panel.model.dismissFailed = true
                    notice("Could not add to History", "The capture was copied. You can still edit it, retry Close, or delete it.")
                } else {
                    remove(id)
                }
            } else {
                panel.model.copyFailed = true
                panel.model.dismissFailed = !panel.model.historyCommitted
            }
        }
    }

    private func startEditorDrag(_ id: CaptureID, from view: NSView, event: NSEvent) {
        guard !isTerminating, let editor = editors[id] else { return }
        guard dragAdapter.beginSession(from: view, event: event, image: editor.dragPreview) else { return }
        Task {
            _ = await finishEditing(id, .deliver(editor.currentEdits, .drag))
            dragAdapter.endHandoff()
        }
    }

    private func startDrag(_ id: CaptureID, from view: NSView, event: NSEvent) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        let ghost = (view as? ThumbnailDragWellView)?.image
        guard dragAdapter.beginSession(from: view, event: event, image: ghost) else { return }
        panel.model.busy = true
        Task {
            let result = await commands.execute(.drag(panel.revision, .copy))
            dragAdapter.endHandoff()
            guard let panel = panels[id] else { return }
            panel.model.busy = false
            guard case .drag(let outcome) = result else {
                panel.model.dragFailed = true
                return
            }
            if case .copied = outcome.delivery {
                if case .notCommitted = outcome.commit {
                    notice("Could not add to History", "The capture was dragged out, but could not be added to History.")
                }
                remove(id)
            } else {
                await settleThumbnails()
                panel.model.dragFailed = true
            }
        }
    }

    private func save(_ id: CaptureID) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            defer { panel.model.busy = false }
            let result = await commands.execute(panel.model.saveFailed ? .retrySave(panel.revision) : .save(panel.revision))
            guard case .save(let outcome) = result else {
                panel.model.saveFailed = true
                return
            }
            await refreshHistory()
            showOversizedNotice(outcome.commit)
            if case .saved = outcome.delivery {
                if case .notCommitted(let reason) = outcome.commit, reason != .captureExceedsHistoryLimit {
                    notice("Could not add to History", "The PNG was saved to the export folder, but could not be added to History.")
                }
                remove(id)
            } else {
                await settleThumbnails()
                panel.model.saveFailed = true
                notice("Save failed", panel.model.historyCommitted
                    ? "The capture is kept in History. Check the export folder in Settings, then Retry Save or Close."
                    : "The capture could not be saved or kept in History. Check the export folder in Settings, then Retry Save or Close.")
            }
        }
    }

    /// Timeout, swipe, close, overflow and Escape all finalize into History.
    private func leave(_ id: CaptureID, by exit: ThumbnailExit) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            switch await commands.execute(.exitThumbnail(panel.revision, exit)) {
            case .finalized(_, let commit):
                await refreshHistory()
                showOversizedNotice(commit)
                if commit == .committed {
                    panel.showKeptInHistory()
                    try? await Task.sleep(for: .seconds(1.2))
                    remove(id)
                } else {
                    await settleThumbnails()
                    panel.model.dismissFailed = true
                    panel.model.busy = false
                }
            case .rejected(.thumbnailExitNotDue):
                panel.model.busy = false
            default:
                panel.model.dismissFailed = true
                panel.model.busy = false
            }
        }
    }

    private func discard(_ id: CaptureID) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            if case .discarded = await commands.execute(.exitThumbnail(panel.revision, .delete)) { remove(id) }
            else { panel.model.busy = false; settleSoon() }
        }
    }

    /// History deleted this capture, and the core already released its Thumbnail (D10).
    func historyDeleted(_ id: CaptureID) {
        guard panels[id] != nil else { return }
        remove(id)
    }

    private func remove(_ id: CaptureID) {
        panels.removeValue(forKey: id)?.close()
        storeEditor(nil, for: id)
        if panels.isEmpty { Task { await commands.setThumbnailStackFocus(false) } }
        settleSoon()
    }

    private func settleSoon() { Task { await settleThumbnails() } }

    /// Applies the core's Thumbnail status, lays cards out in its order on its displays,
    /// performs the exits it reports as due, and wakes at its next due time.
    private func settleThumbnails() async {
        guard !isTerminating else { return }
        let thumbnails = await commands.thumbnails()
        guard !isTerminating else { return }
        layoutThumbnails(thumbnails.cards)
        for card in thumbnails {
            guard let panel = panels[card.revision.captureID] else { continue }
            if panel.model.status != card.status { panel.model.status = card.status }
            if panel.model.editable != card.editable { panel.model.editable = card.editable }
            if let exit = card.dueExit { leave(card.revision.captureID, by: exit) }
        }
        nextDue?.cancel()
        nextDue = thumbnails.nextDueAt.map { due in
            Task { [weak self] in
                try? await Task.sleep(until: due, clock: .continuous)
                guard !Task.isCancelled else { return }
                await self?.settleThumbnails()
            }
        }
    }

    /// Newest card nearest the corner of its capture display; older cards stack upward.
    private func layoutThumbnails(_ newestFirst: [ThumbnailCard]) {
        var stacks: [UInt32?: [ThumbnailPanel]] = [:]
        for card in newestFirst {
            if let panel = panels[card.revision.captureID] { stacks[card.displayID, default: []].append(panel) }
        }
        for (displayID, stack) in stacks {
            guard let screen = screen(for: displayID) ?? NSScreen.main else { continue }
            // Fixed-size Thumbnails (D9): the core computes non-overlapping slots.
            let origins = ThumbnailStackLayout.origins(count: stack.count, in: screen.visibleFrame)
            for (panel, origin) in zip(stack, origins) { panel.place(at: origin) }
        }
    }

    /// The display the core assigned to this capture's Thumbnail.
    private func thumbnailScreen(_ id: CaptureID) async -> NSScreen? {
        screen(for: await commands.thumbnails().first { $0.revision.captureID == id }?.displayID)
    }

    private func displayID(of screen: NSScreen) -> UInt32? { screen.selectionDisplay?.id }

    private func screen(for displayID: UInt32?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }

    private func storeEditor(_ editor: EditorWindow?, for id: CaptureID) {
        if let editor { editors[id] = editor } else { editors.removeValue(forKey: id) }
        if editors.isEmpty {
            ProcessInfo.processInfo.enableSuddenTermination()
        } else {
            ProcessInfo.processInfo.disableSuddenTermination()
        }
    }

    private func connectedDisplayIDs() -> [UInt32] {
        let ids = NSScreen.screens.compactMap(displayID(of:))
        guard let main = NSScreen.main.flatMap(displayID(of:)) else { return ids }
        return [main] + ids.filter { $0 != main }
    }

    private func rehomeThumbnails() async {
        _ = await commands.handleSystemEvent(.displaysChanged(remaining: connectedDisplayIDs()))
        await settleThumbnails()
    }

    private func showOversizedNotice(_ commit: CommitOutcome) {
        if commit == .notCommitted(.captureExceedsHistoryLimit) {
            notice("Capture exceeds History size limit", "This capture could not be kept in History. Copy and Save remain available. Increase the size limit in Settings to keep larger captures.")
        }
    }
}
