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
    private var commands: CaptureCommandLayer?
    private var statusItem: NSStatusItem?
    private var panels: [CaptureID: ThumbnailPanel] = [:]
    private var screens: [CaptureID: NSScreen] = [:]
    private var editors: [CaptureID: EditorWindow] = [:]
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
        commands = CaptureCommandLayer(permission: permission, source: AreaCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier),
            fullScreenSource: FullScreenCaptureSource(platform: platform, bundleIdentifier: identity.bundleIdentifier),
            clipboard: PasteboardAdapter(destination: GeneralPasteboardDestination()), pendingByteLimit: 256 * 1024 * 1024,
            history: HistoryStore(root: identity.historyRoot), codec: PNGBitmapCodec())
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Frisket"
        item.button?.setAccessibilityLabel("Frisket capture menu")
        let menu = NSMenu()
        menu.delegate = self
        add("Capture Area (⌃⌥⌘4)", action: #selector(captureArea), to: menu)
        add("Capture Full Screen", action: #selector(captureFullScreen), to: menu)
        add("Focus Latest Thumbnail", action: #selector(focusThumbnail), to: menu)
        menu.addItem(.separator())
        let history = NSMenuItem(title: "Dismiss captures to keep in History", action: nil, keyEquivalent: "")
        history.isEnabled = false
        menu.addItem(history)
        menu.addItem(.separator())
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
        guard !capturing, !terminating, !requestingPermission, let commands else { return }
        if recoveryPanel?.window?.isVisible == true { recoveryPanel?.present(); return }
        capturing = true
        Task {
            defer { capturing = false; refreshPermissionIndicator() }
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
                screens[id] = screen
                panels[id] = makePanel(id, revision: revision, preview: preview, screen: screen, offset: panels.count)
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

    private func makePanel(_ id: CaptureID, revision: CaptureRevision, preview: CGImage, screen: NSScreen, offset: Int) -> ThumbnailPanel {
        ThumbnailPanel(revision: revision, preview: preview, screen: screen, offset: offset,
            copy: { [weak self] in self?.copy(id) }, discard: { [weak self] in self?.discard(id) },
            dismiss: { [weak self] in self?.dismiss(id) }, edit: { [weak self] in self?.edit(id) })
    }

    private func edit(_ id: CaptureID) {
        guard !terminating, editors[id] == nil, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            let screen = screens[id]
            guard let image = await commands.image(for: panel.revision),
                  let base = PNGBitmapCodec().decode(image.pngData),
                  let editor = EditorWindow(base: base, scale: Double(screen?.backingScaleFactor ?? 1), screen: screen,
                                            finish: { [weak self] edits in self?.finishEditing(id, edits) }) else {
                panel.model.busy = false
                notice("Editor unavailable", "This capture can't be edited. Copy, dismiss, or delete it instead.")
                return
            }
            editors[id] = editor
            editor.show()
        }
    }

    private func finishEditing(_ id: CaptureID, _ edits: DocumentEdits?) {
        editors.removeValue(forKey: id)
        guard let panel = panels[id], let commands else { return }
        guard let edits else { panel.model.busy = false; return }
        Task {
            guard case let .edited(revision, commit, clipboardFailure) = await commands.execute(.done(panel.revision, edits)) else {
                panel.model.busy = false
                notice("Could not finish editing", "The capture is unchanged. Edit it again, or dismiss it to keep it in History.")
                return
            }
            // The unedited preview must not stay on screen once the rendered revision exists.
            let screen = screens[id] ?? NSScreen.main
            guard let image = await commands.image(for: revision),
                  let preview = ThumbnailImage.make(from: image.pngData, maximumPixelSize: 480), let screen else {
                remove(id)
                if case .finalized(_, .committed) = await commands.execute(.dismiss(revision)) { return }
                notice("Preview unavailable", "The redacted capture couldn't be shown or kept in History.")
                return
            }
            panel.close()
            let refreshed = makePanel(id, revision: revision, preview: preview, screen: screen,
                                      offset: arrivalOrder.firstIndex(of: id) ?? 0)
            refreshed.model.historyCommitted = commit == .committed
            refreshed.model.editingUnavailable = commit == .notCommitted(.recoveryRequired)
            refreshed.model.dismissFailed = commit != .committed
            panels[id] = refreshed
            if clipboardFailure != nil {
                notice("Could not replace the earlier copy", "The clipboard may still contain the original capture. Use Copy on the redacted thumbnail to replace it.")
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
            panel.model.editingUnavailable = outcome.commit == .notCommitted(.recoveryRequired)
            if case .copied = outcome.delivery {
                if outcome.commit == .notCommitted(.recoveryRequired) {
                    notice("History needs recovery", "The capture was copied, but History could not finish keeping it. This capture cannot be edited.")
                    remove(id)
                } else if case .notCommitted = outcome.commit {
                    panel.model.copiedWhilePending = true
                    panel.model.copyFailed = false
                    panel.model.dismissFailed = true
                    notice("Could not keep in History", "The capture was copied. You can still edit it, retry Dismiss, or delete it.")
                } else {
                    remove(id)
                }
            } else {
                panel.model.copyFailed = true
                panel.model.dismissFailed = !panel.model.historyCommitted
            }
        }
    }

    private func dismiss(_ id: CaptureID) {
        guard !terminating, let panel = panels[id], !panel.model.busy, let commands else { return }
        panel.model.busy = true
        Task {
            let result = await commands.execute(.dismiss(panel.revision))
            if case .finalized(_, .committed) = result {
                panel.showKeptInHistory()
                try? await Task.sleep(for: .seconds(1.2))
                remove(id)
            } else {
                if case .finalized(_, .notCommitted(.recoveryRequired)) = result { panel.model.editingUnavailable = true }
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
        screens.removeValue(forKey: id)
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
        guard editors.isEmpty else {
            reopenAfterQuit = false
            notice("Finish editing first", "Press Done, or close the editor without changes, then quit again.")
            return .terminateCancel
        }
        guard !capturing, !requestingPermission, !panels.values.contains(where: { $0.model.busy }) else {
            reopenAfterQuit = false
            notice("Finish the current action", "Cancel selection with Escape or wait for Copy, then quit again.")
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
