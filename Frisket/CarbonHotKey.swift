import AppKit
import Carbon
import FrisketCore

@MainActor final class CarbonHotKey: ShortcutSystem {
    private struct Registration {
        let reference: EventHotKeyRef
        let identifier: UInt32
    }
    private var registrations: [ShortcutAction: Registration] = [:]
    private var bindings: [ShortcutAction: ShortcutBinding] = [:]
    private var handler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1
    private let signature: OSType = 0x46524B54 // FRKT
    private let defaults: UserDefaults
    var action: ((ShortcutAction) -> Void)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func enabledShortcuts() throws -> [ShortcutBinding] { try SystemShortcutReader.enabled() }

    func load() -> [ShortcutAction: ShortcutBinding] {
        guard let data = defaults.data(forKey: "globalShortcuts.v1") else { return [:] }
        return ShortcutAction.savedBindings(from: data)
    }

    func save(_ bindings: [ShortcutAction: ShortcutBinding]) {
        guard let data = try? ShortcutAction.encoded(bindings) else { return }
        defaults.set(data, forKey: "globalShortcuts.v1")
    }

    func replace(_ action: ShortcutAction, with binding: ShortcutBinding) throws {
        if bindings[action] == binding { return }
        if handler == nil { try installHandler() }
        guard nextIdentifier < UInt32.max else { throw ShortcutFailure.registrationFailed }
        let identifier = EventHotKeyID(signature: signature, id: nextIdentifier)
        nextIdentifier += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, identifier,
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { throw ShortcutFailure.registrationFailed }
        // Keep the previous registration until the replacement has succeeded.
        if let old = registrations[action], UnregisterEventHotKey(old.reference) != noErr {
            UnregisterEventHotKey(reference)
            throw ShortcutFailure.registrationFailed
        }
        registrations[action] = Registration(reference: reference, identifier: identifier.id)
        bindings[action] = binding
    }

    private func installHandler() throws {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<CarbonHotKey>.fromOpaque(context).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == owner.signature,
                      let action = owner.registrations.first(where: { $0.value.identifier == identifier.id })?.key else {
                    return OSStatus(eventNotHandledErr)
                }
                owner.action?(action)
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { throw ShortcutFailure.registrationFailed }
    }

    func unregister(_ action: ShortcutAction) {
        if let registration = registrations.removeValue(forKey: action) { UnregisterEventHotKey(registration.reference) }
        bindings[action] = nil
    }

    func stop() {
        for action in ShortcutAction.allCases { unregister(action) }
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        action = nil
    }
}
