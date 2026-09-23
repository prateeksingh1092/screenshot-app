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
    private let permission = ScreenCapturePermissionAdapter(access: SystemScreenRecordingAccess())
    private lazy var platform = ScreenCapturePlatform(permission: permission)
    private var windowPlatform: WindowScreenCapturePlatform?
    private var commands: CaptureCommandLayer?
    private var statusItem: NSStatusItem?
    private var settingsWindow: ExportSettingsWindow?
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    private var arrivalOrder: [CaptureID] = []
    private var capturing = false
    private var terminating = false
    private var requestingPermission = false
    private var recoveryPanel: PermissionRecoveryPanel?
    private var permissionTimer: Timer?
    private var reopenAfterQuit = false
    private var preparedRelaunch: InstalledAppRelaunch?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let identifier = Bundle.main.bundleIdentifier else { NSApp.terminate(nil); return }
        let identity = AppIdentity(bundleIdentifier: identifier)
        let exportSettings = ExportSettings(historyRoot: identity.historyRoot)
        settingsWindow = ExportSettingsWindow(settings: exportSettings)
        let windowPlatform = WindowScreenCapturePlatform(permission: permission, bundleIdentifier: identity.bundleIdentifier)
        self.windowPlatform = windowPlatform
        commands = CaptureCommandLayer(permission: permission, source: AreaCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier),
            windowSource: WindowCaptureSource(platform: windowPlatform, ownProcessID: ProcessInfo.processInfo.processIdentifier,
                bundleIdentifier: identity.bundleIdentifier),
            clipboard: PasteboardAdapter(destination: GeneralPasteboardDestination()), pendingByteLimit: 256 * 1024 * 1024,
            history: HistoryStore.launch(root: identity.historyRoot),
            exporter: PNGFileExporter(folder: { await exportSettings.folder }, historyRoot: identity.historyRoot))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Frisket"
        item.button?.setAccessibilityLabel("Frisket capture menu")
        let menu = NSMenu()
        menu.delegate = self
        add("Capture Area (⌃⌥⌘4)", action: #selector(captureArea), to: menu)
        add("Capture Window", action: #selector(captureWindow), to: menu)
        add("Capture Full Screen", action: #selector(captureFullScreen), to: menu)
        add("Focus Latest Thumbnail", action: #selector(focusThumbnail), to: menu)
        menu.addItem(.separator())
        let history = NSMenuItem(title: "Dismiss captures to keep in History", action: nil, keyEquivalent: "")
        history.isEnabled = false
        menu.addItem(history)
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())
        installMainMenu()
        add("Quit Frisket", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        refreshPermissionIndicator()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermissionIndicator() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
        if !hotKey.register(action: { [weak self] in self?.captureArea() }) {
            notice("Shortcut unavailable", "Another app may be using Control–Option–Command–4. Capture Area is still available in the Frisket menu.")
        }
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

    @objc private func showSettings() { settingsWindow?.show() }

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

    private func capture(_ command: CaptureCommand) {
        guard !capturing, !terminating, !requestingPermission, let commands else { return }
        if recoveryPanel?.window?.isVisible == true { recoveryPanel?.present(); return }
        capturing = true
        Task {
            defer { capturing = false; refreshPermissionIndicator() }
            let result = await commands.execute(command)
            switch result {
            case let .pending(revision):
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
                let panel = ThumbnailPanel(revision: revision, preview: preview, screen: screen, offset: panels.count,
                    copy: { [weak self] in self?.copy(id) }, save: { [weak self] in self?.save(id) }, discard: { [weak self] in self?.discard(id) },
                    dismiss: { [weak self] in self?.dismiss(id) })
                panels[id] = panel
                arrivalOrder.append(id)
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
            panel.model.historyCommitted = outcome.commit == .committed
            if case .copied = outcome.delivery {
                if case .notCommitted = outcome.commit {
                    // Keep the failure visible until acknowledged, even though delivery succeeded.
                    notice("Could not keep in History", "The capture was copied to the clipboard, but could not be kept in History.")
                }
                remove(id)
            } else {
                panel.model.copyFailed = true
                panel.model.dismissFailed = !panel.model.historyCommitted
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
            panel.model.historyCommitted = outcome.commit == .committed
            if case .saved = outcome.delivery {
                if case .notCommitted = outcome.commit {
                    notice("Could not keep in History", "The PNG was saved to the export folder, but could not be kept in History.")
                }
                remove(id)
            } else {
                panel.model.saveFailed = true
                notice("Save failed", panel.model.historyCommitted
                    ? "The capture is kept in History. Check the export folder in Settings, then Retry Save or Dismiss."
                    : "The capture could not be saved or kept in History. Check the export folder in Settings, then Retry Save or Dismiss.")
            }
        }
    }

    private func dismiss(_ id: CaptureID) {
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            if case .finalized(_, .committed) = await commands.execute(.dismiss(panel.revision)) {
                panel.showKeptInHistory()
                try? await Task.sleep(for: .seconds(1.2))
                remove(id)
            } else {
                panel.model.dismissFailed = true
                panel.model.busy = false
            }
        }
    }

    private func discard(_ id: CaptureID) {
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            if case .discarded = await commands.execute(.discard(id)) { remove(id) }
            else { panel.model.busy = false }
        }
    }
    private func remove(_ id: CaptureID) {
        panels.removeValue(forKey: id)?.close()
        arrivalOrder.removeAll { $0 == id }
    }
    @objc private func focusThumbnail() {
        if let id = arrivalOrder.last { panels[id]?.focus() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func menuWillOpen(_ menu: NSMenu) { refreshPermissionIndicator() }
    func applicationDidBecomeActive(_ notification: Notification) { refreshPermissionIndicator() }

    private func refreshPermissionIndicator() {
        let missing = permission.refresh() != .granted
        statusItem?.button?.image = NSImage(systemSymbolName: missing ? "exclamationmark.triangle.fill" : "camera",
            accessibilityDescription: missing ? "Screen Recording permission required" : "Screen Recording available")
        statusItem?.button?.imagePosition = .imageLeading
        statusItem?.button?.setAccessibilityLabel(missing ? "Frisket capture menu, Screen Recording permission required" : "Frisket capture menu")
        statusItem?.button?.toolTip = missing ? "Screen Recording permission required" : "Capture with Frisket"
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
                // Never automatically resume capture or reopen UI after a system request.
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
        guard !capturing, !requestingPermission, !panels.values.contains(where: { $0.model.busy }) else {
            reopenAfterQuit = false
            notice("Finish the current action", "Cancel selection with Escape or wait for Copy or Save, then quit again.")
            return .terminateCancel
        }
        guard !panels.isEmpty, let commands else { return prepareAcceptedQuit() ? .terminateNow : .terminateCancel }
        terminating = true
        Task {
            for id in arrivalOrder {
                guard let panel = panels[id] else { continue }
                panel.model.busy = true
                guard case .finalized(_, .committed) = await commands.execute(.dismiss(panel.revision)) else {
                    panel.model.dismissFailed = true
                    panel.model.busy = false
                    terminating = false
                    reopenAfterQuit = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                remove(id)
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
        hotKey.stop()
        do {
            try preparedRelaunch?.openDuringTermination()
        } catch {
            notice("Could not reopen Frisket", "Frisket is quitting. Launch it from ~/Applications/Frisket.app to reopen it.")
        }
    }
    private func notice(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
