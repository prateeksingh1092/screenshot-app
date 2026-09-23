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
        case .systemCollision: "This shortcut is enabled in macOS. Choose another combination."
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
        let special: [UInt32: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            117: "Forward Delete", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let name = special[code] { return name }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(data) {
                let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKey: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKey,
                    characters.count, &length, &characters)
                if status == noErr, length > 0 { return String(utf16CodeUnits: characters, count: length).uppercased() }
            }
        }
        return "Key \(code)"
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var settings: ShortcutSettings

    var body: some View {
        Section("Global shortcuts") {
            Text("Choose a key and modifiers, then Apply. Include Command, Control, or Option.")
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                ShortcutRow(settings: settings, action: action)
                    .id("\(action.rawValue)-\(settings.bindings[action]?.displayName ?? "inactive")")
            }
        }
    }
}

private struct ShortcutRow: View {
    @ObservedObject var settings: ShortcutSettings
    let action: ShortcutAction
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32

    init(settings: ShortcutSettings, action: ShortcutAction) {
        self.settings = settings
        self.action = action
        let binding = settings.bindings[action] ?? action.defaultBinding
        _keyCode = State(initialValue: binding.keyCode)
        _modifiers = State(initialValue: binding.modifiers)
    }

    // Character keys plus navigation/function keys. Labels follow the current layout.
    private var keyCodes: [UInt32] {
        Array(UInt32(0)...50) + [51, 53, 96, 97, 98, 99, 100, 101, 103, 109, 111,
                                  115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126]
    }

    private func modifier(_ flag: Int) -> Binding<Bool> {
        Binding(get: { modifiers & UInt32(flag) != 0 }, set: { enabled in
            if enabled { modifiers |= UInt32(flag) } else { modifiers &= ~UInt32(flag) }
        })
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(action.title).font(.headline)
            Text(settings.bindings[action]?.displayName ?? "Inactive")
            HStack {
                Picker("Key", selection: $keyCode) {
                    ForEach(keyCodes, id: \.self) { code in
                        Text(ShortcutBinding(keyCode: code, modifiers: 0).displayName).tag(code)
                    }
                }.frame(width: 160).accessibilityLabel("\(action.title) key")
                Toggle("⌃", isOn: modifier(controlKey)).accessibilityLabel("\(action.title) Control")
                Toggle("⌥", isOn: modifier(optionKey)).accessibilityLabel("\(action.title) Option")
                Toggle("⇧", isOn: modifier(shiftKey)).accessibilityLabel("\(action.title) Shift")
                Toggle("⌘", isOn: modifier(cmdKey)).accessibilityLabel("\(action.title) Command")
                Button("Apply") { settings.apply(action, binding: ShortcutBinding(keyCode: keyCode, modifiers: modifiers)) }
                    .accessibilityLabel("Apply \(action.title) shortcut")
                Button("Default") {
                    settings.apply(action, binding: action.defaultBinding)
                    if settings.bindings[action] == action.defaultBinding {
                        keyCode = action.defaultBinding.keyCode
                        modifiers = action.defaultBinding.modifiers
                    }
                }
                    .accessibilityLabel("Restore default \(action.title) shortcut")
            }
            if let message = settings.messages[action] { Text(message).foregroundStyle(.red) }
        }
    }
}
