import AppKit
import Carbon

@MainActor final class CarbonHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private let signature: OSType = 0x46524B54 // FRKT

    func register(action: @escaping () -> Void) -> Bool {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<CarbonHotKey>.fromOpaque(context).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == owner.signature, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                owner.action?()
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return false }
        let identifier = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(controlKey | optionKey | cmdKey),
                                         identifier, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { stop(); return false }
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }
}
