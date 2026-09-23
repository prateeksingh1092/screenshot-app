import AppKit
import SwiftUI
import FrisketCore

/// This target does not enable App Sandbox. A bundle-scoped plain path avoids
/// security-scoped permissions it does not need. Revisit if sandboxing is enabled.
@MainActor final class ExportSettings: ObservableObject {
    @Published private(set) var folder: URL
    @Published private(set) var message: String?
    private let historyRoot: URL
    private let defaults: UserDefaults
    private let key = "exportFolderPath"

    init(historyRoot: URL, defaults: UserDefaults = .standard) {
        self.historyRoot = historyRoot
        self.defaults = defaults
        folder = defaults.string(forKey: key).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Frisket", isDirectory: true)
    }

    var assessment: ExportFolderAssessment {
        PNGFileExporter.assess(folder: folder, historyRoot: historyRoot)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        switch PNGFileExporter.assess(folder: selected, historyRoot: historyRoot) {
        case .refused(.insideHistory):
            message = "Choose a folder outside Frisket’s History folder."
            return
        case .refused:
            message = "Frisket cannot write to that folder. Choose another folder."
            return
        case .allowed(warnsAboutICloud: true):
            let alert = NSAlert()
            alert.messageText = "This folder uses iCloud"
            alert.informativeText = "Saved captures may sync to iCloud and other devices."
            alert.addButton(withTitle: "Use Folder")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        case .allowed: break
        }
        folder = selected
        defaults.set(selected.path, forKey: key)
        message = nil
    }
}

private struct ExportSettingsView: View {
    @ObservedObject var settings: ExportSettings
    @ObservedObject var history: HistorySettings
    @ObservedObject var thumbnails: ThumbnailSettings
    let exclusions: CaptureExclusionList
    @ObservedObject var shortcuts: ShortcutSettings

    var body: some View {
        Form {
            ShortcutSettingsView(settings: shortcuts)
            ThumbnailSettingsSection(settings: thumbnails)
            HistorySettingsSection(settings: history)
            Section("Export folder") {
                Text(settings.folder.path)
                    .textSelection(.enabled)
                    .accessibilityLabel("Export folder: \(settings.folder.path)")
                Button("Choose…", action: settings.chooseFolder)
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityLabel("Choose export folder")
                Text("Save keeps a permanent PNG copy. History retention and deletion do not remove saved copies.")
                if let message = settings.message {
                    Text(message).foregroundStyle(.red).accessibilityLabel(message)
                }
                switch settings.assessment {
                case .allowed(warnsAboutICloud: true):
                    Text("This folder uses iCloud. Saved captures may sync to other devices.")
                        .foregroundStyle(.orange)
                case .refused:
                    Text("The export folder is unavailable or is inside History. Choose another folder before saving.")
                        .foregroundStyle(.red)
                case .allowed: EmptyView()
                }
            }
            CaptureExclusionSettingsView(exclusions: exclusions)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 680, height: 680)
    }
}

@MainActor final class ExportSettingsWindow {
    private let window: NSWindow

    init(settings: ExportSettings, history: HistorySettings, thumbnails: ThumbnailSettings,
         exclusions: CaptureExclusionList, shortcuts: ShortcutSettings) {
        window = NSWindow(contentViewController: NSHostingController(rootView: ExportSettingsView(
            settings: settings, history: history, thumbnails: thumbnails, exclusions: exclusions, shortcuts: shortcuts)))
        window.title = "Frisket Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setAccessibilityLabel("Frisket Settings")
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
