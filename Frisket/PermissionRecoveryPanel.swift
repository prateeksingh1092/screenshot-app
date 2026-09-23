import AppKit
import FrisketCore
import SwiftUI

@MainActor final class PermissionRecoveryPanel: NSWindowController {
    init(state: CapturePermissionState, request: @escaping () -> Void,
         privacy: @escaping () -> Void, reopen: @escaping () -> Void) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Screen Recording permission"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        super.init(window: panel)
        let content = NSHostingView(rootView: PermissionRecoveryView(state: state,
            request: { [weak self] in self?.close(); request() },
            privacy: { [weak self] in self?.close(); privacy() },
            reopen: { [weak self] in self?.close(); reopen() },
            cancel: { [weak self] in self?.close() }))
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        panel.center()
    }
    required init?(coder: NSCoder) { nil }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct PermissionRecoveryView: View {
    let state: CapturePermissionState
    let request: () -> Void
    let privacy: () -> Void
    let reopen: () -> Void
    let cancel: () -> Void

    private var explanation: String {
        switch state {
        case .notAsked: "Allow Frisket to capture your screen before selecting an area."
        case .denied: "Screen Recording is off for Frisket. Enable it in Privacy & Security, then try again. If it is already enabled, quit and reopen Frisket."
        case .revokedWhileRunning: "Frisket lost Screen Recording access while running. Enable it in Privacy & Security; quit and reopen if macOS asks."
        case .needsRelaunch: "Screen Recording access has changed, but this process cannot use it. Quit and reopen Frisket to continue."
        case .granted: "Screen Recording is available. Close this panel and try capture again."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Recording permission").font(.headline)
            Text(explanation).fixedSize(horizontal: false, vertical: true)
            if state == .notAsked || state == .denied || state == .revokedWhileRunning {
                Button("Request Screen Recording", action: request)
            }
            HStack {
                Button("Open Privacy & Security", action: privacy)
                Button("Quit & Reopen", action: reopen)
            }
            HStack { Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 412)
    }
}
