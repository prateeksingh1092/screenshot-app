import AppKit
import FrisketAdapters
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
    private var commands: CaptureLifecycleCoordinator?
    private var dragAdapter: FilePromiseDragAdapter?
    private var statusItem: NSStatusItem?
    private var historySettings: HistorySettings?
    private var thumbnailSettings: ThumbnailSettings?
    private var settingsWindow: ExportSettingsWindow?
    private var historyWindow: HistoryWindow?
    private var historyRoot: URL?
    private var captures: CaptureSurfaces?
    private var terminating: Bool {
        get { captures?.isTerminating ?? false }
        set { captures?.isTerminating = newValue }
    }
    private var requestingPermission = false
    private let notices = NoticeCenter()
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
            self?.notices.show(.historyQuotaReached)
        }
        historySettings.onRevealHistory = { [weak self] in self?.revealHistoryFolder() }
        settingsWindow = ExportSettingsWindow(settings: exportSettings, history: historySettings, thumbnails: thumbnailSettings,
                                              exclusions: exclusions, shortcuts: shortcutSettings)
        let budgets = CaptureBudgets.v1
        let windowPlatform = WindowScreenCapturePlatform(permission: permission, bundleIdentifier: identity.bundleIdentifier,
            exclusions: { [exclusions] in exclusions.bundleIdentifiers })
        windowPlatform.decodedByteCeiling = budgets.stillDecodedBytes
        self.windowPlatform = windowPlatform
        let dragAdapter = FilePromiseDragAdapter(writer: DragPromiseWriter())
        self.dragAdapter = dragAdapter
        let pasteboard = PasteboardAdapter(destination: GeneralPasteboardDestination())
        let diagnostics = SystemDiagnosticLog(subsystem: identity.bundleIdentifier)
        let historyStore = HistoryStore.launch(root: identity.historyRoot, limits: historySettings.limits, diagnostics: diagnostics)
        commands = CaptureLifecycleCoordinator(permission: permission, source: AreaCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier, exclusions: { [exclusions] in exclusions.bundleIdentifiers }, latency: latency, decodedByteCeiling: budgets.stillDecodedBytes),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier, exclusions: { [exclusions] in exclusions.bundleIdentifiers }, latency: latency, decodedByteCeiling: budgets.stillDecodedBytes),
            windowSource: WindowCaptureSource(platform: windowPlatform, ownProcessID: ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: identity.bundleIdentifier, exclusions: { [exclusions] in exclusions.bundleIdentifiers }),
            clipboard: pasteboard, pendingByteLimit: budgets.pendingSessionEncodedBytes,
            diagnostics: diagnostics, history: historyStore,
            exporter: PNGFileExporter(folder: { await exportSettings.folder }, historyRoot: identity.historyRoot),
            drag: dragAdapter, thumbnailPolicy: thumbnailSettings.policy,
            flattener: CaptureRenderer(),
            textRecognizer: VisionTextRecognizer(), textClipboard: pasteboard)
        if let commands {
            historySettings.connect(historyStore)
            thumbnailSettings.connect(commands)
            let historyWindow = HistoryWindow()
            historyWindow.model.connect(historyStore, commands: commands)
            historyWindow.model.onRevealHistory = { [weak self] in self?.revealHistoryFolder() }
            historyWindow.model.onNotice = { [weak self] notice in self?.notices.show(notice) }
            historyWindow.startDrag = { [weak self] row, view, event in
                self?.startHistoryDrag(row, from: view, event: event)
            }
            self.historyWindow = historyWindow
            Task {
                if let failure = await historyStore.availability() {
                    self.notices.show(.historyOff(HistoryFailureNotice.text(failure)))
                }
            }
            let presentation = CaptureSurfaces(commands: commands, drag: dragAdapter, latency: latency,
                notify: { [weak self] notice in self?.notices.show(notice) },
                refreshHistory: { [weak self] in
                    if let self { await self.refreshHistorySurfaces() }
                })
            presentation.permissionRequired = { [weak self] state in self?.showPermissionRecovery(state) }
            presentation.cancelSelection = { [weak self] in
                self?.platform.hideSelection()
                self?.windowPlatform?.hideSelection()
            }
            presentation.onCaptureFinished = { [weak self] in self?.refreshPermissionIndicator() }
            presentation.canStart = { [weak self] in
                guard let self else { return false }
                if self.recoveryPanel?.window?.isVisible == true { self.recoveryPanel?.present(); return false }
                if self.surfaces.focusOnboardingIfVisible() { return false }
                return !self.requestingPermission
            }
            captures = presentation
            historyWindow.model.onHistoryDeleted = { [weak presentation] id in presentation?.historyDeleted(id) }
            historyWindow.model.onRestore = { [weak presentation] id in
                await presentation?.restoreFromHistory(id) {
                    if case let .success((_, pngData)) = await historyStore.finalizedImage(id) { pngData } else { nil }
                } ?? false
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
        menu.addItem(.separator())
        add("Focus Latest Thumbnail", action: #selector(focusThumbnail), to: menu)
        add("Copy Latest Capture", action: #selector(copyLatest), to: menu)
        add("Delete Latest Capture", action: #selector(deleteLatest), to: menu)
        add("History", action: #selector(showHistory), to: menu)
        menu.addItem(.separator())
        let history = NSMenuItem(title: "Dismiss captures to add them to History", action: nil, keyEquivalent: "")
        history.isEnabled = false
        menu.addItem(history)
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())
        installMainMenu()
        add("About Frisket", action: #selector(showAbout), to: menu)
        add("What Frisket Stores…", action: #selector(showOnboarding), to: menu)
        add("Quit Frisket", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        refreshPermissionIndicator()
        shortcutSettings.changed = { [weak self] in self?.refreshShortcutTitles() }
        shortcutSettings.onCheckSystemScreenshots = { [weak self] in self?.startShortcuts() }
        shortcutSettings.onRestoreSystemScreenshots = { [weak self] in
            do {
                try SystemScreenshotHotkeyStore.restore()
                self?.shortcutSettings.canRestoreSystemScreenshots = false
            } catch {
                self?.notices.show(.systemShortcutsNotRestored)
            }
            self?.startShortcuts()
        }
        // After the user changes macOS shortcuts in System Settings, register Frisket's on return.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startShortcuts() }
        }
        hotKey.action = { [weak self] action in
            guard let self, self.shortcutSettings.permits(action) else { return }
            switch action {
            case .captureArea: self.captureArea()
            case .captureWindow: self.captureWindow()
            case .captureFullScreen: self.captureFullScreen()
            case .focusThumbnails: self.focusThumbnail()
            case .showHistory: self.showHistory()
            }
        }
        startShortcuts()
        resumeLaunchSurfaces()
    }

    /// Registers Frisket's shortcuts. macOS settings are only read (DA-2): a shortcut macOS still owns
    /// stays inactive, and Settings says which ones to turn off in System Settings.
    private func startShortcuts() {
        let desired = Array(ShortcutCommands.resolved(saved: hotKey.load()).values)
        let enabled = (try? hotKey.enabledShortcuts()) ?? []
        shortcutSettings.systemCollisions = SystemScreenshotHotkeys.collisions(desired: desired, systemEnabled: enabled)
        shortcutSettings.canRestoreSystemScreenshots = !SystemScreenshotHotkeyStore.turnedOffIdentifiers().isEmpty
        shortcutSettings.start()
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
        // The editor answers Save (⌘S) and Copy (⌘C) through the responder chain (D5).
        command("Save", #selector(EditorKeyWindow.saveEditedCapture(_:)), "s", in: file)
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
        guard dragAdapter.beginSession(from: view, event: event, image: historyWindow?.model.cachedPreview(row)) else { return }
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
        captures?.start(.capture(CaptureID(), maximumBytes: CaptureBudgets.v1.stillEncodedBytes))
    }

    @objc private func captureFullScreen() {
        captures?.start(.captureFullScreen(CaptureID(), maximumBytes: CaptureBudgets.v1.stillEncodedBytes))
    }

    @objc private func captureWindow() {
        captures?.start(.captureWindow(CaptureID(), maximumBytes: CaptureBudgets.v1.stillEncodedBytes))
    }

    @objc private func focusThumbnail() { captures?.focusThumbnail() }
    @objc private func copyLatest() { captures?.copyLatest() }
    @objc private func deleteLatest() { captures?.deleteLatest() }
    @objc private func showAbout() { surfaces.presentAbout() }
    /// Reopens onboarding on request (ticket 101). Continue hands off to permission recovery as on first launch.
    @objc private func showOnboarding() {
        surfaces.presentOnboardingIfNeeded(
            systemAlertPending: { [weak self] in self?.requestingPermission ?? false },
            permission: { [weak self] in self?.permission.capturePermission() ?? .notAsked },
            recover: { [weak self] state in self?.showPermissionRecovery(state) },
            requested: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func screensChanged() { captures?.screensChanged() }
    @objc private func screenLocked() { captures?.screenLocked() }
    @objc private func screenUnlocked() { captures?.screenUnlocked() }

    @objc private func workspaceWillPowerOff() { captures?.interruptForPowerOff() }


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
            let symbol = missing ? "exclamationmark.triangle" : "camera.viewfinder"
            let image = NSImage(systemSymbolName: symbol,
                accessibilityDescription: missing ? "Screen Recording permission required" : "Screen Recording available")
            image?.isTemplate = true
            statusItem?.button?.image = image
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
                guard let self, self.captures?.isCapturing != true, !self.terminating else { return }
                self.requestingPermission = true
                _ = self.permission.requestPermission()
                self.requestingPermission = false
                self.refreshPermissionIndicator()
                self.resumeLaunchSurfaces()
                // Never automatically resume capture after a system request.
            }, privacy: { [weak self] in
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                if !NSWorkspace.shared.open(url) {
                    self?.notices.show(.openScreenRecordingSettings)
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
            notices.show(.cannotReopen)
            return false
        }
    }

    /// Termination in one place (story 99, ticket 76). `QuitPlan` decides; Quit never refuses with a notice.
    /// A capture flag left set by an interrupted selection used to hold Quit behind a modal; now Quit
    /// closes the selection, waits a bounded time, and goes on.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let captures else { return prepareAcceptedQuit() ? .terminateNow : .terminateCancel }
        let steps = QuitPlan.steps(for: QuitState(editorOpen: captures.hasEditor, captureInFlight: captures.isCapturing,
                                                  thumbnailCommandInFlight: captures.hasBusyThumbnail,
                                                  thumbnailsShown: captures.hasThumbnail))
        if steps == [.quit] { return prepareAcceptedQuit() ? .terminateNow : .terminateCancel }
        if steps == [.offerEditorsToLeave] {
            reopenAfterQuit = false
            captures.offerEditorsToLeave()
            return .terminateCancel
        }
        Task {
            let finished = await captures.quit(steps)
            if !finished {
                reopenAfterQuit = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            // Only prepare relaunch after every pending capture is safely in History.
            let accepted = prepareAcceptedQuit()
            if !accepted { captures.isTerminating = false }
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
            notices.show(.cannotReopenWhileQuitting)
        }
    }
}

/// Copy Latest and Delete Latest are disabled when there is nothing to act on (D17, ticket 81).
extension AppController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyLatest): captures?.canCopyLatest ?? false
        case #selector(deleteLatest): captures?.canDeleteLatest ?? false
        default: true
        }
    }
}
