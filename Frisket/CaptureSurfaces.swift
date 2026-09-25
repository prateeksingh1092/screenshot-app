import AppKit
import FrisketCore

/// Thumbnail cards, the editor, and capture dispatch. Policy stays in `CaptureCommandLayer`.
@MainActor final class CaptureSurfaces {
    private let commands: CaptureCommandLayer
    private let dragAdapter: FilePromiseDragAdapter
    private let latency: CaptureLatencyLog
    private let scrolling: ManualScrollingCapture
    private let areaDisplayID: () -> UInt32?
    private let windowDisplayID: () -> UInt32?
    private let notify: (String, String) -> Void
    private let refreshHistory: () async -> Void
    /// Recovery, onboarding, and an in-flight permission prompt. Return false to skip the capture.
    var canStart: () -> Bool = { true }
    var onCaptureFinished: () -> Void = {}

    private(set) var isCapturing = false
    var isTerminating = false
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    private var screens: [CaptureID: NSScreen] = [:]
    private var editors: [CaptureID: EditorWindow] = [:]
    private var arrivalOrder: [CaptureID] = []
    private var timeouts: [CaptureID: Task<Void, Never>] = [:]

    var hasEditor: Bool { !editors.isEmpty }
    var hasBusyThumbnail: Bool { panels.values.contains { $0.model.busy } }
    var hasThumbnail: Bool { !panels.isEmpty }

    init(commands: CaptureCommandLayer, drag: FilePromiseDragAdapter, latency: CaptureLatencyLog,
         scrolling: ManualScrollingCapture, areaDisplayID: @escaping () -> UInt32?,
         windowDisplayID: @escaping () -> UInt32?, notify: @escaping (String, String) -> Void,
         refreshHistory: @escaping () async -> Void) {
        self.commands = commands
        self.dragAdapter = drag
        self.latency = latency
        self.scrolling = scrolling
        self.areaDisplayID = areaDisplayID
        self.windowDisplayID = windowDisplayID
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
            defer { latency.cancel(); isCapturing = false; scrolling.hide(); onCaptureFinished() }
            let result = await commands.execute(command)
            switch result {
            case let .scrollingLimited(revision, notice):
                self.notice("Scrolling capture stopped", notice.message)
                await showThumbnail(revision, command: command)
            case let .scrollingRefused(notice):
                self.notice("Scrolling capture stopped", notice.message)
            case let .pending(revision):
                await showThumbnail(revision, command: command)
            case .captureFailed(.cancelled): break
            case let .permissionRequired(state):
                permissionRequired?(state)
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
        guard let id = arrivalOrder.last else { return }
        copy(id)
    }

    func deleteLatest() {
        guard let id = arrivalOrder.last else { return }
        discard(id)
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

    private func showThumbnail(_ revision: CaptureRevision, command: CaptureCommand) async {
        let captureDisplayID: UInt32? = if case .captureWindow = command { windowDisplayID() } else { areaDisplayID() }
        guard let image = await commands.image(for: revision),
              let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480),
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == captureDisplayID
              }) ?? NSScreen.main else {
            _ = await commands.execute(.discard(revision.captureID))
            notice("Preview unavailable", "The capture could not be displayed and was deleted.")
            return
        }
        let id = revision.captureID
        screens[id] = screen
        let assignedDisplay = displayID(of: screen)
        panels[id] = makePanel(id, revision: revision, preview: preview, displayID: assignedDisplay)
        arrivalOrder.append(id)
        if let assignedDisplay { await commands.assignThumbnailDisplay(id, displayID: assignedDisplay) }
        await settleThumbnails()
        // Downsampling and orderFrontRegardless have completed. This is
        // presentation submission, not a physical-display timestamp.
        latency.thumbnailSubmitted()
    }

    private func makePanel(_ id: CaptureID, revision: CaptureRevision, preview: CGImage, displayID: UInt32?) -> ThumbnailPanel {
        let panel = ThumbnailPanel(revision: revision, preview: preview, displayID: displayID,
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
    }

    private func edit(_ id: CaptureID) {
        guard !isTerminating, editors[id] == nil, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            let screen = screens[id]
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
                notice("Could not finish editing", "Your edits are still open. Keep in History could not prepare the redacted result. Retry Keep in History to finish editing.")
                return false
            }
            storeEditor(nil, for: id)
            let screen = screens[id] ?? NSScreen.main
            guard let image = await commands.image(for: revision),
                  let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480), let screen else {
                remove(id)
                if case .finalized(_, .committed) = await commands.execute(.dismiss(revision)) { return true }
                notice("Preview unavailable", "The redacted capture couldn't be shown or kept in History.")
                return true
            }
            panel.close()
            let refreshed = makePanel(id, revision: revision, preview: preview, displayID: displayID(of: screen))
            refreshed.model.historyCommitted = commit == .committed
            refreshed.model.editingUnavailable = commit == .notCommitted(.recoveryRequired)
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
                        notice("Could not keep in History", "The capture was dragged out, but could not be kept in History.")
                    }
                }
                if case .rejected = delivered, delivery == .drag { refreshed.model.dragFailed = true }
            }
            panels[id] = refreshed
            await settleThumbnails()
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
            panel.model.historyCommitted = outcome.commit == .committed
            panel.model.editingUnavailable = outcome.commit == .notCommitted(.recoveryRequired)
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
                    notice("Could not keep in History", "The capture was copied. You can still edit it, retry Close, or delete it.")
                    settleSoon()
                } else {
                    remove(id)
                }
            } else {
                panel.model.copyFailed = true
                panel.model.dismissFailed = !panel.model.historyCommitted
                settleSoon()
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
            panel.model.historyCommitted = outcome.commit == .committed
            if case .copied = outcome.delivery {
                if case .notCommitted = outcome.commit {
                    notice("Could not keep in History", "The capture was dragged out, but could not be kept in History.")
                }
                remove(id)
            } else {
                panel.model.dragFailed = true
                settleSoon()
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
            panel.model.historyCommitted = outcome.commit == .committed
            if case .saved = outcome.delivery {
                if case .notCommitted(let reason) = outcome.commit, reason != .captureExceedsHistoryLimit {
                    notice("Could not keep in History", "The PNG was saved to the export folder, but could not be kept in History.")
                }
                remove(id)
            } else {
                panel.model.saveFailed = true
                settleSoon()
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
                    timeouts.removeValue(forKey: id)?.cancel()
                    panel.showKeptInHistory()
                    try? await Task.sleep(for: .seconds(1.2))
                    remove(id)
                } else if commit == .notCommitted(.recoveryRequired) {
                    panel.model.editingUnavailable = true
                    panel.model.dismissFailed = true
                    panel.model.busy = false
                } else {
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
        screens.removeValue(forKey: id)
        storeEditor(nil, for: id)
        arrivalOrder.removeAll { $0 == id }
        timeouts.removeValue(forKey: id)?.cancel()
        if panels.isEmpty { Task { await commands.setThumbnailStackFocus(false) } }
        settleSoon()
    }

    private func settleSoon() { Task { await settleThumbnails() } }

    /// Lays cards out in the core's order and performs the exits it reports as due.
    private func settleThumbnails() async {
        guard !isTerminating else { return }
        let cards = await commands.thumbnails()
        guard !isTerminating else { return }
        layoutThumbnails(cards.map(\.revision.captureID))
        for card in cards {
            let id = card.revision.captureID
            guard panels[id] != nil else { continue }
            if card.automaticExitSuppressed {
                timeouts.removeValue(forKey: id)?.cancel()
                continue
            }
            if let exit = card.dueExit {
                leave(id, by: exit)
            } else if let expiresAt = card.expiresAt, expiresAt > .now, timeouts[id] == nil {
                timeouts[id] = Task { [weak self] in
                    try? await Task.sleep(until: expiresAt, clock: .continuous)
                    guard !Task.isCancelled else { return }
                    self?.timeouts[id] = nil
                    await self?.settleThumbnails()
                }
            } else {
                timeouts.removeValue(forKey: id)?.cancel()
            }
        }
    }

    /// Newest card nearest the corner of its capture display; older cards stack upward.
    private func layoutThumbnails(_ newestFirst: [CaptureID]) {
        var stacks: [UInt32?: [ThumbnailPanel]] = [:]
        for id in newestFirst {
            if let panel = panels[id] { stacks[panel.displayID, default: []].append(panel) }
        }
        let margin: CGFloat = 20, gap: CGFloat = 8
        for (displayID, stack) in stacks {
            guard let screen = NSScreen.screens.first(where: { self.displayID(of: $0) == displayID }),
                  let height = stack.first?.size.height else { continue }
            let frame = screen.visibleFrame
            let room = max(0, frame.height - 2 * margin - height)
            let step = stack.count > 1 ? min(height + gap, room / CGFloat(stack.count - 1)) : 0
            for (slot, panel) in stack.enumerated() {
                panel.place(at: CGPoint(x: frame.maxX - margin - panel.size.width,
                                        y: frame.minY + margin + CGFloat(slot) * step))
            }
        }
    }

    private func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
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
        for card in await commands.thumbnails() {
            let id = card.revision.captureID
            guard let panel = panels[id], let display = card.displayID else { continue }
            panel.displayID = display
            screens[id] = NSScreen.screens.first { displayID(of: $0) == display }
        }
        await settleThumbnails()
    }

    private func showOversizedNotice(_ commit: CommitOutcome) {
        if commit == .notCommitted(.captureExceedsHistoryLimit) {
            notice("Capture exceeds History size limit", "This capture could not be kept in History. Copy and Save remain available. Increase the size limit in Settings to keep larger captures.")
        }
    }
}
