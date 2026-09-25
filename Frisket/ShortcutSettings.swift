import AppKit
import Carbon
import SwiftUI
import FrisketCore

@MainActor final class ShortcutSettings: ObservableObject {
    let commands: ShortcutCommands
    @Published private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:]
    @Published private(set) var messages: [ShortcutAction: String] = [:]
    var changed: (() -> Void)?

    init(system: any ShortcutSystem) { commands = ShortcutCommands(system: system) }

    var onCheckSystemScreenshots: () -> Void = {}
    var onRestoreSystemScreenshots: () -> Void = {}
    @Published var canRestoreSystemScreenshots = false
    /// Frisket shortcuts that macOS still uses for its own screenshots (read-only, DA-2).
    @Published var systemCollisions: [ShortcutBinding] = []

    func start() {
        commands.start()
        bindings = commands.active
        messages = commands.failures.mapValues(Self.message)
        changed?()
    }

    func apply(_ action: ShortcutAction, binding: ShortcutBinding) {
        do {
            try commands.remap(action, to: binding)
            bindings = commands.active
            messages[action] = nil
            changed?()
        } catch {
            messages[action] = Self.message((error as? ShortcutFailure) ?? .registrationFailed)
        }
    }

    func permits(_ action: ShortcutAction) -> Bool {
        let allowed = commands.permits(action)
        messages[action] = commands.failures[action].map(Self.message)
        return allowed
    }

    private static func message(_ failure: ShortcutFailure) -> String {
        switch failure {
        case .systemCollision: "macOS uses this shortcut for screenshots. Turn it off in System Settings, or choose another combination."
        case .cannotVerify: "Cannot verify macOS shortcuts. The change was not applied; try again."
        case .duplicate: "Another Frisket action uses this shortcut. Choose another combination."
        case .invalidBinding: "Include Command, Control, or Option with a key."
        case .registrationFailed: "This shortcut is unavailable, possibly in another app. Choose another combination."
        }
    }
}

extension ShortcutBinding {
    var displayName: String {
        let symbols = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"),
                       (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
        return symbols.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        if let name = specialNames[code] { return name }
        return layoutCharacter(code)?.uppercased() ?? "Key \(code)"
    }

    /// A single printable character for a menu key equivalent, without the Shift glyph doubled.
    var menuKeyEquivalent: (character: String, modifiers: NSEvent.ModifierFlags)? {
        guard ShortcutBinding.specialNames[keyCode] == nil, let raw = ShortcutBinding.layoutCharacter(keyCode),
              raw.count == 1, raw.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return nil }
        return (raw.lowercased(), ShortcutBinding.eventModifiers(modifiers))
    }

    private static let specialNames: [UInt32: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        117: "Forward Delete", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]

    private static func layoutCharacter(_ code: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKey,
            characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    fileprivate static func eventModifiers(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var settings: ShortcutSettings

    var body: some View {
        Section("Global shortcuts") {
            Text("Command–Shift and a number. ⌘⇧4 captures an area, ⌘⇧3 the full screen, ⌘⇧5 a window, and ⌘⇧6 a scrolling page. ⌘⇧2 focuses the latest thumbnail. ⌘⇧1 opens History.")
            Text("Click Change and press the keys. Include Command, Control, or Option.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                ShortcutRow(settings: settings, action: action)
                    .id("\(action.rawValue)-\(settings.bindings[action]?.displayName ?? "inactive")")
            }
            if !settings.systemCollisions.isEmpty {
                // DA-2: Frisket never changes macOS settings; it says what to turn off and where.
                let names = settings.systemCollisions.map(\.displayName).joined(separator: ", ")
                Text("macOS still uses \(names) for its own screenshots, so Frisket can't. Turn those off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots. Frisket picks them up when you come back.")
                    .font(.callout)
                HStack {
                    Button("Open Keyboard Shortcuts…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .accessibilityLabel("Open Keyboard settings in System Settings to turn off the macOS screenshot shortcuts")
                    Button("Check Again") { settings.onCheckSystemScreenshots() }
                        .accessibilityLabel("Check the macOS screenshot shortcuts again")
                }
            }
            if settings.canRestoreSystemScreenshots {
                Button("Restore macOS screenshot shortcuts") { settings.onRestoreSystemScreenshots() }
                    .accessibilityLabel("Restore the macOS screenshot shortcuts Frisket turned off")
            }
        }
    }
}

private struct ShortcutRow: View {
    @ObservedObject var settings: ShortcutSettings
    let action: ShortcutAction
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(.headline)
                    Text(settings.bindings[action]?.displayName ?? "Inactive")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(action.title) shortcut \(settings.bindings[action]?.displayName ?? "inactive")")
                }
                Spacer(minLength: 12)
                Button(recording ? "Press shortcut" : "Change") { recording = true }
                    .accessibilityLabel(recording ? "Press the new \(action.title) shortcut" : "Change \(action.title) shortcut")
                Button("Default") { settings.apply(action, binding: action.defaultBinding) }
                    .accessibilityLabel("Restore default \(action.title) shortcut")
            }
            if let message = settings.messages[action] {
                Text(message).font(.caption).foregroundStyle(.red).accessibilityLabel(message)
            }
        }
        .background {
            if recording {
                ShortcutKeyCatcher(onCancel: { recording = false }) { code, modifiers in
                    recording = false
                    settings.apply(action, binding: ShortcutBinding(keyCode: code, modifiers: modifiers))
                }
            }
        }
    }
}

private struct ShortcutKeyCatcher: NSViewRepresentable {
    var onCancel: () -> Void
    var onKey: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutKeyCatcherView {
        let view = ShortcutKeyCatcherView()
        view.onCancel = onCancel
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: ShortcutKeyCatcherView, context: Context) {
        view.onCancel = onCancel
        view.onKey = onKey
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}

private final class ShortcutKeyCatcherView: NSView {
    var onCancel: (() -> Void)?
    var onKey: ((UInt32, UInt32) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        onKey?(UInt32(event.keyCode), Self.carbon(event.modifierFlags))
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    private static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}
