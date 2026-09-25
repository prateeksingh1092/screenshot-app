import AppKit
import FrisketAdapters
import SwiftUI
import UniformTypeIdentifiers

struct CaptureExclusionSettingsView: View {
    @ObservedObject var exclusions: CaptureExclusionList
    @State private var message: String?

    var body: some View {
        Section("Capture exclusion list") {
            Text("Windows belonging to these apps are left out of captures. Frisket always excludes itself.")
            if exclusions.bundleIdentifiers.isEmpty {
                Text("No apps added.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(exclusions.bundleIdentifiers.sorted(), id: \.self) { identifier in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(appName(identifier))
                                    Text(identifier).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove") { exclusions.remove(identifier) }
                                    .accessibilityLabel("Remove \(appName(identifier)) from capture exclusion list")
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(exclusions.bundleIdentifiers.count) * 52, 156))
            }
            Button("Add App…", action: chooseApp)
                .accessibilityLabel("Add app to capture exclusion list")
            if let message { Text(message).foregroundStyle(.red) }
        }
    }

    private func appName(_ identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return identifier }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Exclude App from Captures"
        panel.prompt = "Exclude App"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else {
            message = "Choose an application with a bundle identifier."
            return
        }
        exclusions.add(identifier)
        message = nil
    }
}
