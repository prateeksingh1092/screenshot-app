import AppKit
import FrisketAdapters
import FrisketCore

/// Thumbnail cards, the editor, and capture dispatch. Policy stays in `CaptureLifecycleCoordinator`.
@MainActor final class CaptureSurfaces {
    private let commands: CaptureLifecycleCoordinator
    private let dragAdapter: FilePromiseDragAdapter
    private let latency: CaptureLatencyLog
    /// The notice line (DA-5): never a modal. A failure the Thumbnail shows on its status line is not repeated here.
    private let notify: (Notice) -> Void
    private let refreshHistory: () async -> Void
    /// Recovery, onboarding, and an in-flight permission prompt. Return false to skip the capture.
    var canStart: () -> Bool = { true }
    var onCaptureFinished: () -> Void = {}

    private(set) var isCapturing = false
    var isTerminating = false
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    /// Cards showing "Capture kept in History" before they close; Restore waits for them (ticket 95).
    private var exiting: [CaptureID: Task<Void, Never>] = [:]
    private var editors: [CaptureID: EditorWindow] = [:]
    /// Wakes the stack at the core's next due time; the core owns order, displays and status (ticket 73).
    private var nextDue: Task<Void, Never>?

    var hasEditor: Bool { !editors.isEmpty }
    var hasBusyThumbnail: Bool { panels.values.contains { $0.model.busy } }
    var hasThumbnail: Bool { !panels.isEmpty }

    init(commands: CaptureLifecycleCoordinator, drag: FilePromiseDragAdapter, latency: CaptureLatencyLog,
         notify: @escaping (Notice) -> Void,
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
            case let .permissionRequired(state):
                permissionRequired?(state)
            default:
                notice(Notice.after(command, result))
            }
        }
    }

    /// Permission recovery stays with the application delegate.
    var permissionRequired: ((CapturePermissionState) -> Void)?

    /// The overlay a capture command is waiting on. Quit closes it instead of refusing (ticket 76).
    var cancelSelection: () -> Void = {}

    /// Quit, decided by `QuitPlan` (story 99). It never refuses with a notice: only an open editor
    /// holds it, through its own prompt. Returns false when a capture could not be added to History.
    func quit(_ steps: [QuitStep]) async -> Bool {
        isTerminating = true   // blocks new captures and Thumbnail actions
        for step in steps {
            switch step {
            case .offerEditorsToLeave:
                isTerminating = false
                offerEditorsToLeave()
                return false
            case .cancelCapture:
                cancelSelection()
                // A capture that already has its pixels may still arrive; a stuck one must not hold Quit.
                await waitUntil(seconds: 2) { !self.isCapturing }
            case .waitForThumbnailCommands:
                await waitUntil(seconds: 10) { !self.hasBusyThumbnail }
            case .finalizeThumbnails:
                markThumbnailsBusy()
                guard await applyQuit(await commands.handleSystemEvent(.quit)) else { return false }
            case .quit:
                return true
            }
        }
        return true
    }

    private func waitUntil(seconds: Double, _ done: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Quit finalization. Returns false when a commit failed and quit should cancel.
    private func applyQuit(_ results: [CaptureCommandOutcome]) async -> Bool {
        await refreshHistory()
        for result in results {
            if case .finalized(let revision, _) = result { notice(Notice.after(.dismiss(revision), result)) }
            if case .finalized(let revision, .committed) = result {
                remove(revision.captureID)
                continue
            }
            if case .finalized(let revision, _) = result, let panel = panels[revision.captureID] {
                panel.model.dismissFailed = true
            }
            for panel in panels.values { panel.model.busy = false }
            isTerminating = false
            notice(.quitNotFinished)
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
        Task {
            guard let id = await commands.thumbnails().latestToCopy?.revision.captureID, panels[id] != nil else { return }
            copy(id)
        }
    }

    func deleteLatest() {
        Task {
            guard let id = await commands.thumbnails().latestToDelete?.revision.captureID, panels[id] != nil else { return }
            discard(id)
        }
    }

    /// Menu enablement (D17): the panels mirror the core's `Thumbnails`, so these answer synchronously.
    var canCopyLatest: Bool { !panels.isEmpty }
    var canDeleteLatest: Bool { panels.values.contains { $0.model.status == .pending } }

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

    private func notice(_ notice: Notice?) { if let notice { notify(notice) } }

    private func showThumbnail(_ revision: CaptureRevision) async {
        // The capture names its display (ticket 75); an unknown or unplugged one falls back to the main screen.
        guard let image = await commands.image(for: revision),
              let preview = await ThumbnailImage.decode(image.pngData, maximumPixelSize: 480),
              let screen = screen(for: image.displayID) ?? NSScreen.main else {
            _ = await commands.execute(.discard(revision.captureID))
            notice(.previewUnavailable)
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
            guard let image = await commands.image(for: panel.revision),
                  let previews = await Self.editorPreview(image.pngData),
                  let editor = EditorWindow(preview: previews.shown, livePreview: previews.live,
                                            scale: Double(screen?.backingScaleFactor ?? 1), screen: screen,
                                            finish: { [weak self] leave in await self?.finishEditing(id, leave) ?? false }) else {
                panel.model.busy = false
                notice(.editorUnavailable)
                return
            }
            editor.onFileDrag = { [weak self] view, event in self?.startEditorDrag(id, from: view, event: event) }
            storeEditor(editor, for: id)
            await commands.setEditorOpen(true, for: id)   // ticket 91: the Thumbnail's timeout waits for the editor
            editor.show()
        }
    }

    /// Decodes the capture once for the editor, off the main actor (ticket 68), with the reduced
    /// preview a live drag renders through (ticket 102).
    @concurrent private nonisolated static func editorPreview(_ png: Data) async -> (shown: CapturePreview, live: CapturePreview)? {
        guard let preview = try? CaptureRenderer().preview(png) else { return nil }
        return (preview, preview.reduced())
    }

    private func finishEditing(_ id: CaptureID, _ leave: EditorLeave) async -> Bool {
        guard let panel = panels[id] else { return false }
        switch leave {
        case .finalize(nil):
            let outcome = await commands.execute(.dismiss(panel.revision))
            notice(Notice.after(.dismiss(panel.revision), outcome))
            if case .finalized(_, let commit) = outcome {
                storeEditor(nil, for: id)
                await commands.setEditorOpen(false, for: id)   // the timeout restarts in full
                if commit == .committed { panel.model.busy = false; await closeUnlessKept(id); return true }
                panel.model.busy = false
                panel.model.dismissFailed = true
                return true
            }
            panel.model.busy = false
            if case .rejected = outcome {} else { notice(.captureNotKept) }
            return false
        case .delete:
            _ = await commands.execute(.discard(id))
            storeEditor(nil, for: id)
            await commands.setEditorOpen(false, for: id)
            remove(id)
            return true
        case .finalize(.some), .deliver:
            let delivery: EditorDelivery? = if case let .deliver(_, kind) = leave { kind } else { nil }
            // An editor drag renders the edits but commits nothing; only an accepted drop finalizes it (DA-3).
            let revision: CaptureRevision, commit: CommitOutcome?
            let command = leave.command(for: panel.revision)
            let finished = await commands.execute(command)
            switch finished {
            case let .edited(edited, committed, _): (revision, commit) = (edited, committed)
            case let .rendered(rendered, _): (revision, commit) = (rendered, nil)
            default:
                notice(Notice.after(command, finished) ?? .editNotFinished)
                return false
            }
            storeEditor(nil, for: id)
            await commands.setEditorOpen(false, for: id)   // the timeout restarts in full
            guard let image = await commands.image(for: revision),
                  let preview = await ThumbnailImage.decode(image.pngData, maximumPixelSize: 480) else {
                remove(id)
                if case .finalized(_, .committed) = await commands.execute(.dismiss(revision)) { return true }
                notice(.editedPreviewUnavailable)
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
                if case .drag(let outcome) = delivered, outcome.delivery != .copied { refreshed.model.dragFailed = true }
                notice(Notice.after(delivery.command(for: revision), delivered))
                if case .rejected = delivered, delivery == .drag { refreshed.model.dragFailed = true }
            }
            panels[id] = refreshed
            await settleThumbnails()   // applies the core's status to the new card
            notice(Notice.after(command, finished))   // an edited capture over the History limit, or an earlier copy left in place
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
            let command: CaptureCommand = panel.model.copyFailed ? .retryCopy(panel.revision) : .copy(panel.revision)
            let result = await commands.execute(command)
            defer { panel.model.busy = false }
            guard case .copy(let outcome) = result else {
                panel.model.copyFailed = true
                return
            }
            await refreshHistory()
            notice(Notice.after(command, result))
            await settleThumbnails()
            if case .copied = outcome.delivery {
                if outcome.commit == .notCommitted(.recoveryRequired) {
                    remove(id)
                } else if outcome.commit == .notCommitted(.captureExceedsHistoryLimit) {
                    remove(id)
                } else if case .notCommitted = outcome.commit {
                    panel.model.copiedWhilePending = true
                    panel.model.copyFailed = false
                    panel.model.dismissFailed = true   // the status line says it (DA-5)
                } else {
                    panel.model.copyFailed = false
                    await closeUnlessKept(id)
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
                notice(Notice.after(.drag(panel.revision, .copy), result))
                panel.model.dragFailed = false
                await closeUnlessKept(id)
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
            let command: CaptureCommand = panel.model.saveFailed ? .retrySave(panel.revision) : .save(panel.revision)
            let result = await commands.execute(command)
            guard case .save(let outcome) = result else {
                panel.model.saveFailed = true
                return
            }
            await refreshHistory()
            notice(Notice.after(command, result))
            if case .saved = outcome.delivery {
                panel.model.saveFailed = false
                await closeUnlessKept(id)
            } else {
                await settleThumbnails()
                panel.model.saveFailed = true   // the status line says what failed and offers Retry Save (DA-5)
            }
        }
    }

    /// Timeout, swipe, close, overflow and Escape all finalize into History.
    private func leave(_ id: CaptureID, by exit: ThumbnailExit) {
        guard !isTerminating, let panel = panels[id], !panel.model.busy else { return }
        panel.model.busy = true
        Task {
            let command = CaptureCommand.exitThumbnail(panel.revision, exit)
            let result = await commands.execute(command)
            switch result {
            case .finalized(_, let commit):
                await refreshHistory()
                notice(Notice.after(command, result))
                if commit == .committed {
                    panel.showKeptInHistory()
                    let exit = Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        exiting[id] = nil
                        remove(id)
                    }
                    exiting[id] = exit
                    await exit.value
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

    /// Ticket 79 (DA-10): a History item comes back as a finalized Thumbnail on the pointer's display.
    /// The core lists it; its preview is decoded from History's image, which `image` reads.
    /// A card still animating out is let go first, so Restore brings it back rather than failing.
    func restoreFromHistory(_ id: CaptureID, image: () async -> Data?) async -> Bool {
        if let exit = exiting[id] { await exit.value }
        guard !isTerminating, panels[id]?.model.busy != true else { return false }
        guard case let .restored(revision) = await commands.execute(.restoreFromHistory(id)) else { return false }
        if panels[id] == nil {
            guard let png = await image(), let preview = await ThumbnailImage.decode(png, maximumPixelSize: 480) else {
                _ = await commands.execute(.exitThumbnail(revision, .close))   // unlist it; History keeps the item
                return false
            }
            let panel = makePanel(id, revision: revision, preview: preview)
            panel.model.status = .finalized
            panel.model.editable = false
            panels[id] = panel
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let display = screen.flatMap(displayID(of:)) { await commands.assignThumbnailDisplay(id, displayID: display) }
        }
        await settleThumbnails()
        return true
    }

    /// History deleted this capture, and the core already released its Thumbnail (D10).
    func historyDeleted(_ id: CaptureID) {
        guard panels[id] != nil else { return }
        remove(id)
    }

    /// A finalized Thumbnail stays until its timeout, a Close or overflow (ticket 91). A capture the
    /// core released without keeping its card (not committed to History) closes.
    private func closeUnlessKept(_ id: CaptureID) async {
        await settleThumbnails()
        if await !commands.thumbnails().contains(where: { $0.revision.captureID == id }) { remove(id) }
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
}
