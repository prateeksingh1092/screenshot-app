import Foundation

public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case showHistory
    case focusThumbnails
    case captureFullScreen
    case captureArea
    case captureWindow

    public var title: String {
        switch self {
        case .showHistory: "History"
        case .focusThumbnails: "Focus Latest Thumbnail"
        case .captureFullScreen: "Capture Full Screen"
        case .captureArea: "Capture Area"
        case .captureWindow: "Capture Window"
        }
    }

    /// Command–Shift and a number, matching the macOS screenshot row and CleanShot.
    /// 1 History, 2 thumbnails, 3 full screen, 4 area, 5 window. ⌘⇧6 is left free (decision 60).
    public var defaultBinding: ShortcutBinding {
        let code: UInt32 = switch self {
        case .showHistory: 18
        case .focusThumbnails: 19
        case .captureFullScreen: 20
        case .captureArea: 21
        case .captureWindow: 23
        }
        return ShortcutBinding(keyCode: code, modifiers: 768) // Command–Shift
    }
}

extension ShortcutAction {
    /// The saved-shortcuts preference: JSON of `[ShortcutAction: ShortcutBinding]`.
    public static func encoded(_ bindings: [ShortcutAction: ShortcutBinding]) throws -> Data {
        try JSONEncoder().encode(bindings)
    }

    /// Reads the saved-shortcuts preference. An action Frisket no longer has, such as the
    /// retired scrolling capture (decision 60), is skipped; the other bindings are kept.
    public static func savedBindings(from data: Data) -> [ShortcutAction: ShortcutBinding] {
        (try? JSONDecoder().decode(SavedShortcuts.self, from: data))?.bindings ?? [:]
    }
}

/// A dictionary with non-String keys encodes as a flat array: key, value, key, value.
private struct SavedShortcuts: Decodable {
    var bindings: [ShortcutAction: ShortcutBinding] = [:]
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            let name = try container.decode(String.self)
            let binding = try container.decode(ShortcutBinding.self)
            if let action = ShortcutAction(rawValue: name) { bindings[action] = binding }
        }
    }
}

public struct ShortcutBinding: Hashable, Codable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

extension ShortcutBinding {
    /// The modifiers as Frisket writes them: Control, Option, Command, then Shift, so Command–Shift reads ⌘⇧
    /// everywhere (story 101, ticket 81). Carbon masks: cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000.
    public var modifierSymbols: String {
        [(UInt32(0x1000), "⌃"), (0x0800, "⌥"), (0x0100, "⌘"), (0x0200, "⇧")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
    }
}

/// OS registration, symbolic shortcuts and preferences are the external boundary.
@MainActor public protocol ShortcutSystem: AnyObject {
    func enabledShortcuts() throws -> [ShortcutBinding]
    func load() -> [ShortcutAction: ShortcutBinding]
    func save(_ bindings: [ShortcutAction: ShortcutBinding])
    /// On failure, the previous registration must remain intact.
    func replace(_ action: ShortcutAction, with binding: ShortcutBinding) throws
    func unregister(_ action: ShortcutAction)
}

public enum ShortcutFailure: Error, Equatable {
    case systemCollision, cannotVerify, duplicate, invalidBinding, registrationFailed
}

/// macOS screenshot symbolic hotkeys. Frisket uses this same number row.
public enum SystemScreenshotHotkeys {
    /// com.apple.symbolichotkeys identifiers for ⇧⌘3/4/5/6 and the Control variants of 3/4/6.
    public static let familyIdentifiers = ["28", "29", "30", "31", "181", "182", "184"]

    public static func isFamily(_ binding: ShortcutBinding) -> Bool {
        let numberRow: Set<UInt32> = [20, 21, 22, 23]
        let commandShift: Set<UInt32> = [768, 4864] // ⇧⌘ and ⌃⇧⌘
        return numberRow.contains(binding.keyCode) && commandShift.contains(binding.modifiers)
    }

    public static func collisions(desired: [ShortcutBinding], systemEnabled: [ShortcutBinding]) -> [ShortcutBinding] {
        desired.filter { isFamily($0) && systemEnabled.contains($0) }
    }

}

@MainActor public final class ShortcutCommands {
    public private(set) var active: [ShortcutAction: ShortcutBinding] = [:]
    public private(set) var failures: [ShortcutAction: ShortcutFailure] = [:]
    private let system: any ShortcutSystem

    public init(system: any ShortcutSystem) { self.system = system }

    /// Saved shortcuts, with the default for any action that has none saved.
    public static func resolved(saved: [ShortcutAction: ShortcutBinding]) -> [ShortcutAction: ShortcutBinding] {
        var resolved: [ShortcutAction: ShortcutBinding] = [:]
        for action in ShortcutAction.allCases { resolved[action] = saved[action] ?? action.defaultBinding }
        return resolved
    }

    public func remap(_ action: ShortcutAction, to binding: ShortcutBinding) throws {
        try validate(binding, for: action)
        do { try system.replace(action, with: binding) }
        catch { throw ShortcutFailure.registrationFailed }
        active[action] = binding
        failures[action] = nil
        var saved = system.load()
        saved[action] = binding
        system.save(saved)
    }

    private func validate(_ binding: ShortcutBinding, for action: ShortcutAction) throws {
        // Carbon command, shift, option, control bits. Require Command, Control, or Option.
        guard binding.keyCode < 128, binding.modifiers & ~UInt32(6912) == 0,
              binding.modifiers & 6400 != 0 else { throw ShortcutFailure.invalidBinding }
        if active.contains(where: { $0.key != action && $0.value == binding }) {
            throw ShortcutFailure.duplicate
        }
        let enabled: [ShortcutBinding]
        do { enabled = try system.enabledShortcuts() }
        catch { throw ShortcutFailure.cannotVerify }
        if enabled.contains(binding) {
            throw ShortcutFailure.systemCollision
        }
    }

    public func permits(_ action: ShortcutAction) -> Bool {
        guard let binding = active[action] else { return false }
        do {
            try validate(binding, for: action)
            failures[action] = nil
            return true
        } catch {
            failures[action] = (error as? ShortcutFailure) ?? .cannotVerify
            return false
        }
    }

    public func stop() {
        for action in ShortcutAction.allCases { system.unregister(action) }
        active = [:]
    }

    /// Registers every saved shortcut that macOS doesn't own. Frisket never changes macOS settings
    /// (DA-2): a collision stays a `.systemCollision` failure until the user turns it off in System Settings.
    public func start() {
        stop()
        failures = [:]
        let resolved = Self.resolved(saved: system.load())
        for action in ShortcutAction.allCases {
            let binding = resolved[action] ?? action.defaultBinding
            do {
                try validate(binding, for: action)
                try system.replace(action, with: binding)
                active[action] = binding
            } catch { failures[action] = (error as? ShortcutFailure) ?? .registrationFailed }
        }
    }
}
