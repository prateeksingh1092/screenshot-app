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

    private var content: PermissionRecoveryContent { PermissionRecoveryContent(state: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Recording permission").font(.headline)
            Text(content.explanation).fixedSize(horizontal: false, vertical: true)
            // A request after macOS has asked is silent, so only a first run offers it (decision 100, D34).
            if content.actions.contains(.requestScreenRecording) {
                Button(PermissionRecoveryAction.requestScreenRecording.title, action: request)
            }
            HStack {
                Button(PermissionRecoveryAction.openSystemSettings.title, action: privacy)
                Button(PermissionRecoveryAction.quitAndReopen.title, action: reopen)
            }
            HStack { Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 412)
    }
}
