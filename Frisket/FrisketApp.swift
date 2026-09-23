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

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    private let hotKey = CarbonHotKey()
    private let platform = ScreenCapturePlatform()
    private var commands: CaptureCommandLayer?
    private var statusItem: NSStatusItem?
    private var settingsWindow: ExportSettingsWindow?
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    private var arrivalOrder: [CaptureID] = []
    private var capturing = false
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let identifier = Bundle.main.bundleIdentifier else { NSApp.terminate(nil); return }
        let identity = AppIdentity(bundleIdentifier: identifier)
        let exportSettings = ExportSettings(historyRoot: identity.historyRoot)
        settingsWindow = ExportSettingsWindow(settings: exportSettings)
        commands = CaptureCommandLayer(source: AreaCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier),
            clipboard: PasteboardAdapter(destination: GeneralPasteboardDestination()), pendingByteLimit: 256 * 1024 * 1024,
            history: HistoryStore(root: identity.historyRoot),
            exporter: PNGFileExporter(folder: { await exportSettings.folder }, historyRoot: identity.historyRoot))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Frisket"
        item.button?.setAccessibilityLabel("Frisket capture menu")
        let menu = NSMenu()
        add("Capture Area (⌃⌥⌘4)", action: #selector(captureArea), to: menu)
        add("Capture Full Screen", action: #selector(captureFullScreen), to: menu)
        add("Focus Latest Thumbnail", action: #selector(focusThumbnail), to: menu)
        menu.addItem(.separator())
        let history = NSMenuItem(title: "Dismiss captures to keep in History", action: nil, keyEquivalent: "")
        history.isEnabled = false
        menu.addItem(history)
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        addSettings(to: appMenu)
        NSApp.mainMenu = mainMenu
        add("Quit Frisket", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        if !hotKey.register(action: { [weak self] in self?.captureArea() }) {
            notice("Shortcut unavailable", "Another app may be using Control–Option–Command–4. Capture Area is still available in the Frisket menu.")
        }
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

    private func capture(_ command: CaptureCommand) {
        guard !capturing, !terminating, let commands else { return }
        capturing = true
        Task {
            defer { capturing = false }
            let result = await commands.execute(command)
            switch result {
            case let .pending(revision):
                guard let image = await commands.image(for: revision),
                      let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480),
                      let screen = NSScreen.screens.first(where: {
                          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == platform.captureDisplayID
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
            case .captureFailed:
                notice("Capture unavailable", "Check Frisket’s Screen Recording permission in System Settings → Privacy & Security → Screen & System Audio Recording. If macOS requests it, quit and reopen Frisket. A disconnected display or an oversized capture can also prevent capture.")
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
            guard case .save(let outcome) = result else { return }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !capturing, !panels.values.contains(where: { $0.model.busy }) else {
            notice("Finish the current action", "Cancel selection with Escape or wait for Copy or Save, then quit again.")
            return .terminateCancel
        }
        guard !panels.isEmpty, let commands else { return .terminateNow }
        terminating = true
        Task {
            for id in arrivalOrder {
                guard let panel = panels[id] else { continue }
                panel.model.busy = true
                guard case .finalized(_, .committed) = await commands.execute(.dismiss(panel.revision)) else {
                    panel.model.dismissFailed = true
                    panel.model.busy = false
                    terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                remove(id)
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { hotKey.stop() }
    private func notice(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
