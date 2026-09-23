public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case captureArea, captureFullScreen, focusThumbnails

    public var title: String {
        switch self {
        case .captureArea: "Capture Area"
        case .captureFullScreen: "Capture Full Screen"
        case .focusThumbnails: "Focus Latest Thumbnail"
        }
    }

    public var defaultBinding: ShortcutBinding {
        let code: UInt32 = switch self {
        case .captureArea: 21
        case .captureFullScreen: 20
        case .focusThumbnails: 17
        }
        return ShortcutBinding(keyCode: code, modifiers: 6400) // Control–Option–Command
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

@MainActor public final class ShortcutCommands {
    public private(set) var active: [ShortcutAction: ShortcutBinding] = [:]
    public private(set) var failures: [ShortcutAction: ShortcutFailure] = [:]
    private let system: any ShortcutSystem

    public init(system: any ShortcutSystem) { self.system = system }

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
        // Carbon command, shift, option, control bits. Require a non-typing modifier.
        guard binding.keyCode < 128, binding.modifiers & ~UInt32(6912) == 0,
              binding.modifiers & 6400 != 0 else { throw ShortcutFailure.invalidBinding }
        if active.contains(where: { $0.key != action && $0.value == binding }) {
            throw ShortcutFailure.duplicate
        }
        let enabled: [ShortcutBinding]
        do { enabled = try system.enabledShortcuts() }
        catch { throw ShortcutFailure.cannotVerify }
        if enabled.contains(binding) { throw ShortcutFailure.systemCollision }
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

    public func start() {
        stop()
        failures = [:]
        let saved = system.load()
        for action in ShortcutAction.allCases {
            let binding = saved[action] ?? action.defaultBinding
            do {
                try validate(binding, for: action)
                try system.replace(action, with: binding)
                active[action] = binding
            } catch { failures[action] = (error as? ShortcutFailure) ?? .registrationFailed }
        }
    }
}
