import AppKit
import FrisketCore

@main @MainActor enum FrisketApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotKey = CarbonHotKey()
    private lazy var shortcutSettings = ShortcutSettings(system: hotKey)
    private let latency = CaptureLatencyLog.standardOutput()
    private let permission = ScreenCapturePermissionAdapter(access: SystemScreenRecordingAccess())
    private let exclusions = CaptureExclusionList(defaults: .standard)
    private lazy var platform = ScreenCapturePlatform(permission: permission, exclusions: { [exclusions] in exclusions.bundleIdentifiers })
    private var windowPlatform: WindowScreenCapturePlatform?
    private var commands: CaptureCommandLayer?
    private var dragAdapter: FilePromiseDragAdapter?
    private var scrolling: ManualScrollingCapture?
    private var statusItem: NSStatusItem?
    private var historySettings: HistorySettings?
    private var thumbnailSettings: ThumbnailSettings?
    private var settingsWindow: ExportSettingsWindow?
    private var historyWindow: HistoryWindow?
    private var historyRoot: URL?
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    private var screens: [CaptureID: NSScreen] = [:]
    private var editors: [CaptureID: EditorWindow] = [:]
    private var arrivalOrder: [CaptureID] = []
    private var timeouts: [CaptureID: Task<Void, Never>] = [:]
    private var capturing = false
    private var terminating = false
    private var requestingPermission = false
    private var recoveryPanel: PermissionRecoveryPanel?
    private let surfaces = LaunchSurfaces()
    private var permissionTimer: Timer?
    private var reopenAfterQuit = false
    private var preparedRelaunch: InstalledAppRelaunch?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let identifier = Bundle.main.bundleIdentifier else { NSApp.terminate(nil); return }
        let identity = AppIdentity(bundleIdentifier: identifier)
        historyRoot = identity.historyRoot
        let exportSettings = ExportSettings(historyRoot: identity.historyRoot)
        let historySettings = HistorySettings()
        let thumbnailSettings = ThumbnailSettings()
        self.historySettings = historySettings
        self.thumbnailSettings = thumbnailSettings
        historySettings.onQuotaEviction = { [weak self] in
            self?.notice("History size limit reached", "Older captures were removed from History to meet its size limit. Saved exports are unchanged. You can adjust the limit in Settings.")
        }
        historySettings.onRevealHistory = { [weak self] in self?.revealHistoryFolder() }
        settingsWindow = ExportSettingsWindow(settings: exportSettings, history: historySettings, thumbnails: thumbnailSettings,
                                              exclusions: exclusions, shortcuts: shortcutSettings)
        let windowPlatform = WindowScreenCapturePlatform(permission: permission, bundleIdentifier: identity.bundleIdentifier,
            exclusions: { [exclusions] in exclusions.bundleIdentifiers })
        self.windowPlatform = windowPlatform
        let dragStaging = DragStagingLifetime(directory: identity.historyRoot.appendingPathComponent("staging/drag"))
        let dragAdapter = FilePromiseDragAdapter(staging: dragStaging)
        self.dragAdapter = dragAdapter
        let scrolling = ManualScrollingCapture(platform: platform, bundleIdentifier: identity.bundleIdentifier)
        self.scrolling = scrolling
        let pasteboard = PasteboardAdapter(destination: GeneralPasteboardDestination())
        commands = CaptureCommandLayer(permission: permission, source: AreaCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier, exclusions: { [exclusions] in exclusions.bundleIdentifiers }, latency: latency),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier, exclusions: { [exclusions] in exclusions.bundleIdentifiers }, latency: latency),
            windowSource: WindowCaptureSource(platform: windowPlatform, ownProcessID: ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: identity.bundleIdentifier),
            clipboard: pasteboard, pendingByteLimit: 256 * 1024 * 1024,
            history: HistoryStore.launch(root: identity.historyRoot, limits: historySettings.limits),
            exporter: PNGFileExporter(folder: { await exportSettings.folder }, historyRoot: identity.historyRoot),
            drag: dragAdapter, dragStaging: dragStaging, thumbnailPolicy: thumbnailSettings.policy,
            codec: PNGBitmapCodec(),
            scrollingFrames: scrolling, scrollingPreview: scrolling,
            textRecognizer: VisionTextRecognizer(), textClipboard: pasteboard)
        if let commands {
            historySettings.connect(commands)
            thumbnailSettings.connect(commands)
            let historyWindow = HistoryWindow()
            historyWindow.model.connect(commands)
            historyWindow.model.onRevealHistory = { [weak self] in self?.revealHistoryFolder() }
            historyWindow.startDrag = { [weak self] row, view, event in
                self?.startHistoryDrag(row, from: view, event: event)
            }
            self.historyWindow = historyWindow
            Task {
                if let failure = await commands.historyAvailability() {
                    self.notice("History is off", HistoryFailureNotice.text(failure))
                }
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let lockCenter = DistributedNotificationCenter.default()
        lockCenter.addObserver(self, selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        lockCenter.addObserver(self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceWillPowerOff),
            name: NSWorkspace.willPowerOffNotification, object: nil)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Frisket") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "Frisket"
        }
        item.button?.setAccessibilityLabel("Frisket capture menu")
        let menu = NSMenu()
        menu.delegate = self
        add("Capture Area", action: #selector(captureArea), to: menu)
        add("Capture Window", action: #selector(captureWindow), to: menu)
        add("Capture Full Screen", action: #selector(captureFullScreen), to: menu)
        add("Capture Scrolling Page", action: #selector(captureScrolling), to: menu)
        menu.addItem(.separator())
        add("Focus Latest Thumbnail", action: #selector(focusThumbnail), to: menu)
        add("Copy Latest Capture", action: #selector(copyLatest), to: menu)
        add("Delete Latest Capture", action: #selector(deleteLatest), to: menu)
        add("History", action: #selector(showHistory), to: menu)
        menu.addItem(.separator())
        let history = NSMenuItem(title: "Dismiss captures to keep in History", action: nil, keyEquivalent: "")
        history.isEnabled = false
        menu.addItem(history)
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())
        installMainMenu()
        add("About Frisket", action: #selector(showAbout), to: menu)
        add("Quit Frisket", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        refreshPermissionIndicator()
        shortcutSettings.changed = { [weak self] in self?.refreshShortcutTitles() }
        shortcutSettings.onClaimSystemScreenshots = { [weak self] in self?.claimSystemScreenshotShortcuts() }
        shortcutSettings.onRestoreSystemScreenshots = { [weak self] in
            try? SystemScreenshotHotkeyStore.restore()
            self?.shortcutSettings.canRestoreSystemScreenshots = false
            self?.shortcutSettings.start()
        }
        hotKey.action = { [weak self] action in
            guard let self, self.shortcutSettings.permits(action) else { return }
            switch action {
            case .captureArea: self.captureArea()
            case .captureWindow: self.captureWindow()
            case .captureFullScreen: self.captureFullScreen()
            case .captureScrolling: self.captureScrolling()
            case .focusThumbnails: self.focusThumbnail()
            case .showHistory: self.showHistory()
            }
        }
        claimSystemScreenshotShortcuts()
        resumeLaunchSurfaces()
    }

    /// If macOS still owns ⌘⇧3/4/5/6, turn those symbolic hotkeys off and register Frisket's.
    private func claimSystemScreenshotShortcuts() {
        let desired = Array(ShortcutCommands.resolved(saved: hotKey.load()).values)
        let enabled = (try? hotKey.enabledShortcuts()) ?? []
        let hits = SystemScreenshotHotkeys.collisions(desired: desired, systemEnabled: enabled)
        var claim: [ShortcutBinding] = []
        if !hits.isEmpty, (try? SystemScreenshotHotkeyStore.disableFamilyIfNeeded()) != nil {
            claim = hits
        }
        shortcutSettings.canRestoreSystemScreenshots = !SystemScreenshotHotkeyStore.turnedOffIdentifiers().isEmpty
        shortcutSettings.start(claimingSystemShortcuts: claim)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            mainMenu.addItem(item)
            return menu
        }
        func command(_ title: String, _ action: Selector, _ key: String, in menu: NSMenu,
                     modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            // A nil target uses the responder chain, including SwiftUI's selected text.
            menu.addItem(item)
        }
        let app = submenu("Frisket")
        command("About Frisket", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", in: app)
        app.addItem(.separator())
        addSettings(to: app)
        let historyItem = NSMenuItem(title: "History", action: #selector(showHistory), keyEquivalent: "y")
        historyItem.keyEquivalentModifierMask = [.command, .control]
        historyItem.target = self
        app.addItem(historyItem)
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        app.addItem(servicesItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        command("Hide Frisket", #selector(NSApplication.hide(_:)), "h", in: app)
        command("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", in: app,
                modifiers: [.command, .option])
        command("Show All", #selector(NSApplication.unhideAllApplications(_:)), "", in: app)
        app.addItem(.separator())
        command("Quit Frisket", #selector(NSApplication.terminate(_:)), "q", in: app)

        let file = submenu("File")
        command("Close Window", #selector(NSWindow.performClose(_:)), "w", in: file)
        let edit = submenu("Edit")
        command("Undo", Selector(("undo:")), "z", in: edit)
        command("Redo", Selector(("redo:")), "z", in: edit, modifiers: [.command, .shift])
        edit.addItem(.separator())
        command("Cut", #selector(NSText.cut(_:)), "x", in: edit)
        command("Copy", #selector(NSText.copy(_:)), "c", in: edit)
        command("Paste", #selector(NSText.paste(_:)), "v", in: edit)
        command("Delete", #selector(NSText.delete(_:)), "", in: edit)
        command("Select All", #selector(NSText.selectAll(_:)), "a", in: edit)
        NSApp.mainMenu = mainMenu
    }

    private func addSettings(to menu: NSMenu) {
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.keyEquivalentModifierMask = .command
        item.target = self
        menu.addItem(item)
    }

    private func refreshShortcutTitles() {
        let actions: [(ShortcutAction, Selector)] = [
            (.captureArea, #selector(captureArea)),
            (.captureWindow, #selector(captureWindow)),
            (.captureFullScreen, #selector(captureFullScreen)),
            (.captureScrolling, #selector(captureScrolling)),
            (.focusThumbnails, #selector(focusThumbnail)),
            (.showHistory, #selector(showHistory)),
        ]
        for (action, selector) in actions {
            guard let item = statusItem?.menu?.items.first(where: { $0.action == selector }) else { continue }
            if let binding = shortcutSettings.bindings[action], let equivalent = binding.menuKeyEquivalent {
                item.title = action.title
                item.keyEquivalent = equivalent.character
                item.keyEquivalentModifierMask = equivalent.modifiers
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
                let suffix = shortcutSettings.bindings[action].map { " (\($0.displayName))" } ?? " (shortcut inactive)"
                item.title = action.title + suffix
            }
        }
    }

    @objc private func showSettings() {
        settingsWindow?.show()
        Task { await refreshHistorySurfaces() }
    }

    private func refreshHistorySurfaces() async {
        await historySettings?.refresh()
        await historyWindow?.reloadIfVisible()
    }

    private func revealHistoryFolder() {
        guard let root = historyRoot else { return }
        if FileManager.default.fileExists(atPath: root.path) {
            _ = NSWorkspace.shared.open(root)
        } else {
            _ = NSWorkspace.shared.open(root.deletingLastPathComponent())
        }
    }

    @objc private func showHistory() {
        historyWindow?.show()
    }

    private func startHistoryDrag(_ row: HistoryWindowModel.Row, from view: NSView, event: NSEvent) {
        guard !terminating, let commands, let dragAdapter else { return }
        guard dragAdapter.beginSession(from: view, event: event, image: row.preview) else { return }
        Task {
            _ = await commands.execute(.drag(row.revision, .copy))
            dragAdapter.endHandoff()
            await historyWindow?.model.reload()
        }
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func captureArea() {
        capture(.capture(CaptureID(), maximumBytes: 128 * 1024 * 1024))
    }

    @objc private func captureFullScreen() {
        capture(.captureFullScreen(CaptureID(), maximumBytes: 128 * 1024 * 1024))
    }

    @objc private func captureWindow() {
        capture(.captureWindow(CaptureID(), maximumBytes: 128 * 1024 * 1024))
    }

    @objc private func captureScrolling() {
        capture(.captureScrolling(CaptureID(), maximumBytes: 128 * 1024 * 1024))
    }

    private func capture(_ command: CaptureCommand) {
        guard !capturing, !terminating, !requestingPermission, let commands else { return }
        if recoveryPanel?.window?.isVisible == true { recoveryPanel?.present(); return }
        if surfaces.focusOnboardingIfVisible() { return }
        capturing = true
        Task {
            defer { latency.cancel(); capturing = false; scrolling?.hide(); refreshPermissionIndicator() }
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
                showPermissionRecovery(state)
            case .captureFailed:
                notice("Capture unavailable", "A disconnected display or an oversized capture can prevent capture. Try again with a smaller area.")
            default:
                notice("Capture unavailable", "Copy or delete pending captures, then try again.")
            }
        }
    }

    private func showThumbnail(_ revision: CaptureRevision, command: CaptureCommand) async {
        guard let commands else { return }
        let captureDisplayID: UInt32?
        if case .captureWindow = command { captureDisplayID = windowPlatform?.captureDisplayID }
        else { captureDisplayID = platform.captureDisplayID }
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
            Task { await self?.commands?.setThumbnailStackFocus(true) }
        }
        panel.onResignKey = { [weak self] in
            Task { await self?.releaseStackFocusIfIdle() }
        }
        return panel
    }

    private func moveStackFocus(_ move: ThumbnailFocusMove) {
        Task {
            guard let revision = await commands?.moveThumbnailFocus(move) else { return }
            panels[revision.captureID]?.focus()
        }
    }

    private func releaseStackFocusIfIdle() async {
        try? await Task.sleep(for: .milliseconds(50))
        if panels.values.contains(where: \.isKey) { return }
        await commands?.setThumbnailStackFocus(false)
    }

    private func edit(_ id: CaptureID) {
        guard !terminating, editors[id] == nil, let panel = panels[id], !panel.model.busy, let commands else { return }
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
        guard let panel = panels[id], let commands else { return false }
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
        case let .finalize(edits?), let .deliver(edits, _):
        let delivery: EditorDelivery? = if case let .deliver(_, kind) = leave { kind } else { nil }
        guard case let .edited(revision, commit, clipboardFailure) = await commands.execute(.done(panel.revision, edits)) else {
            notice("Could not finish editing", "Your edits are still open. Done could not prepare the redacted result. Retry Done to finish editing.")
            return false
        }
        storeEditor(nil, for: id)
        // The unedited preview must not stay on screen once the rendered revision exists.
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
        refreshed.model.dismissFailed = commit != .committed
        if let delivery {
            let delivered = await commands.execute(delivery.command(for: revision))
            if case .copy(let outcome) = delivered, case .failed = outcome.delivery { refreshed.model.copyFailed = true }
            if case .save(let outcome) = delivered, case .failed = outcome.delivery { refreshed.model.saveFailed = true }
            if case .rejected = delivered, delivery == .copy { refreshed.model.copyFailed = true }
            if case .rejected = delivered, delivery == .save { refreshed.model.saveFailed = true }
            if case .drag(let outcome) = delivered, outcome.delivery != .copied { refreshed.model.dragFailed = true }
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
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            let result = await commands.execute(.copyRecognizedText(panel.revision))
            panel.model.busy = false
            if case let .recognizedText(outcome) = result, case .copied = outcome.delivery {
                notice("Copied \(outcome.characterCount) characters", "")
            } else {
                notice("Could not copy text", "No text was recognized, or the capture is no longer current.")
            }
        }
    }

    private func copy(_ id: CaptureID) {
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            let result = await commands.execute(panel.model.copyFailed ? .retryCopy(panel.revision) : .copy(panel.revision))
            defer { panel.model.busy = false }
            guard case .copy(let outcome) = result else {
                panel.model.copyFailed = true
                return
            }
            await refreshHistorySurfaces()
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
        guard !terminating, let editor = editors[id], let dragAdapter else { return }
        guard dragAdapter.beginSession(from: view, event: event, image: editor.dragPreview) else { return }
        Task {
            _ = await finishEditing(id, .deliver(editor.currentEdits, .drag))
            dragAdapter.endHandoff()
        }
    }

    private func startDrag(_ id: CaptureID, from view: NSView, event: NSEvent) {
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands, let dragAdapter else { return }
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
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            defer { panel.model.busy = false }
            let result = await commands.execute(panel.model.saveFailed ? .retrySave(panel.revision) : .save(panel.revision))
            guard case .save(let outcome) = result else {
                panel.model.saveFailed = true
                return
            }
            await refreshHistorySurfaces()
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

    /// Timeout, swipe, close, overflow and Escape all finalize into History (decision 44).
    private func leave(_ id: CaptureID, by exit: ThumbnailExit) {
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            switch await commands.execute(.exitThumbnail(panel.revision, exit)) {
            case .finalized(_, let commit):
                await refreshHistorySurfaces()
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
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            if case .discarded = await commands.execute(.exitThumbnail(panel.revision, .delete)) { remove(id) }
            else { panel.model.busy = false; settleSoon() }
        }
    }
    private func remove(_ id: CaptureID) {
        panels.removeValue(forKey: id)?.close()
        screens.removeValue(forKey: id)
        storeEditor(nil, for: id)
        arrivalOrder.removeAll { $0 == id }
        timeouts.removeValue(forKey: id)?.cancel()
        if panels.isEmpty { Task { await commands?.setThumbnailStackFocus(false) } }
        settleSoon()
    }

    private func settleSoon() { Task { await settleThumbnails() } }

    /// Lays cards out in the core's order and performs the exits it reports as due.
    private func settleThumbnails() async {
        guard !terminating, let commands else { return }
        let cards = await commands.thumbnails()
        guard !terminating else { return }
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
        let margin: CGFloat = 20, gap: CGFloat = 10
        for (displayID, stack) in stacks {
            guard let screen = NSScreen.screens.first(where: { self.displayID(of: $0) == displayID }),
                  let height = stack.first?.size.height else { continue }
            let frame = screen.visibleFrame
            // Overlap cards rather than leave the display when they don't fit.
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
    @objc private func focusThumbnail() {
        Task {
            await commands?.setThumbnailStackFocus(true)
            if let revision = await commands?.focusedThumbnail() {
                panels[revision.captureID]?.focus()
            }
        }
    }

    @objc private func copyLatest() {
        guard let id = arrivalOrder.last else { return }
        copy(id)
    }

    @objc private func deleteLatest() {
        guard let id = arrivalOrder.last else { return }
        discard(id)
    }
    @objc private func showAbout() { surfaces.presentAbout() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func screensChanged() {
        Task { await rehomeThumbnails() }
    }

    @objc private func screenLocked() {
        Task {
            _ = await commands?.handleSystemEvent(.screenLocked)
            await settleThumbnails()
        }
    }

    @objc private func screenUnlocked() {
        Task {
            _ = await commands?.handleSystemEvent(.screenUnlocked)
            await settleThumbnails()
        }
    }

    @objc private func workspaceWillPowerOff() {
        for editor in editors.values { editor.interruptUnansweredPrompt(.logout) }
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
        guard let commands else { return }
        _ = await commands.handleSystemEvent(.displaysChanged(remaining: connectedDisplayIDs()))
        for card in await commands.thumbnails() {
            let id = card.revision.captureID
            guard let panel = panels[id], let display = card.displayID else { continue }
            panel.displayID = display
            screens[id] = NSScreen.screens.first { displayID(of: $0) == display }
        }
        await settleThumbnails()
    }

    private func resumeLaunchSurfaces() {
        surfaces.systemAlertEnded(
            systemAlertPending: { [weak self] in self?.requestingPermission ?? false },
            permission: { [weak self] in self?.permission.capturePermission() ?? .notAsked },
            recover: { [weak self] state in self?.showPermissionRecovery(state) })
    }

    func menuWillOpen(_ menu: NSMenu) { refreshPermissionIndicator() }
    func applicationDidBecomeActive(_ notification: Notification) { refreshPermissionIndicator() }

    private var permissionMissing: Bool?

    private func refreshPermissionIndicator() {
        let missing = permission.refresh() != .granted
        if permissionMissing != missing || statusItem?.button?.image == nil {
            permissionMissing = missing
            statusItem?.button?.image = NSImage(systemSymbolName: missing ? "exclamationmark.triangle.fill" : "camera",
                accessibilityDescription: missing ? "Screen Recording permission required" : "Screen Recording available")
            statusItem?.button?.imagePosition = .imageLeading
            statusItem?.button?.setAccessibilityLabel(missing ? "Frisket capture menu, Screen Recording permission required" : "Frisket capture menu")
            statusItem?.button?.toolTip = missing ? "Screen Recording permission required" : "Capture with Frisket"
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        guard missing else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermissionIndicator() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func showPermissionRecovery(_ state: CapturePermissionState) {
        recoveryPanel?.close()
        recoveryPanel = PermissionRecoveryPanel(state: state,
            request: { [weak self] in
                guard let self, !self.capturing, !self.terminating else { return }
                self.requestingPermission = true
                _ = self.permission.requestPermission()
                self.requestingPermission = false
                self.refreshPermissionIndicator()
                self.resumeLaunchSurfaces()
                // Never automatically resume capture after a system request.
            }, privacy: { [weak self] in
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                if !NSWorkspace.shared.open(url) {
                    self?.notice("Open System Settings", "Open Privacy & Security → Screen & System Audio Recording and enable Frisket.")
                }
            }, reopen: { [weak self] in
                guard let self else { return }
                self.reopenAfterQuit = true
                NSApp.terminate(nil)
            })
        recoveryPanel?.present()
    }

    private func prepareAcceptedQuit() -> Bool {
        guard reopenAfterQuit else { return true }
        reopenAfterQuit = false
        do {
            preparedRelaunch = try InstalledAppRelaunch()
            return true
        } catch {
            notice("Could not reopen Frisket", "Launch Frisket from ~/Applications/Frisket.app, then try Quit & Reopen again.")
            return false
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard editors.isEmpty else {
            reopenAfterQuit = false
            for editor in editors.values { editor.offerToLeave() }
            return .terminateCancel
        }
        guard !capturing, !requestingPermission, !panels.values.contains(where: { $0.model.busy }) else {
            reopenAfterQuit = false
            notice("Finish the current action", "Cancel selection with Escape or wait for Copy or Save, then quit again.")
            return .terminateCancel
        }
        guard !panels.isEmpty, let commands else { return prepareAcceptedQuit() ? .terminateNow : .terminateCancel }
        terminating = true
        for panel in panels.values { panel.model.busy = true }
        Task {
            let results = await commands.handleSystemEvent(.quit)
            await refreshHistorySurfaces()
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
                terminating = false
                reopenAfterQuit = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            // Only prepare relaunch after every pending capture is safely in History.
            let accepted = prepareAcceptedQuit()
            if !accepted { terminating = false }
            sender.reply(toApplicationShouldTerminate: accepted)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        shortcutSettings.commands.stop()
        hotKey.stop()
        do {
            try preparedRelaunch?.openDuringTermination()
        } catch {
            notice("Could not reopen Frisket", "Frisket is quitting. Launch it from ~/Applications/Frisket.app to reopen it.")
        }
    }
    private func showOversizedNotice(_ commit: CommitOutcome) {
        if commit == .notCommitted(.captureExceedsHistoryLimit) {
            notice("Capture exceeds History size limit", "This capture could not be kept in History. Copy and Save remain available. Increase the size limit in Settings to keep larger captures.")
        }
    }

    private func notice(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
