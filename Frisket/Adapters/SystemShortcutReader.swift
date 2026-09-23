import Carbon
import Foundation
import FrisketCore

/// CopySymbolicHotKeys is documented by CarbonEvents.h as not thread safe.
@MainActor public enum SystemShortcutReader {
    public static func enabled() throws -> [ShortcutBinding] {
        var list: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&list)
        let owned = list?.takeRetainedValue()
        guard status == noErr else { throw ShortcutFailure.cannotVerify }
        return try decode(owned)
    }

    /// Treat incomplete or unexpected OS data as unverified, never as an empty list.
    public static func decode(_ list: CFArray?) throws -> [ShortcutBinding] {
        guard let entries = list as? [[String: Any]] else { throw ShortcutFailure.cannotVerify }
        var result: [ShortcutBinding] = []
        for entry in entries {
            guard let enabled = entry[kHISymbolicHotKeyEnabled] as? NSNumber,
                  CFGetTypeID(enabled) == CFBooleanGetTypeID(),
                  let code = entry[kHISymbolicHotKeyCode] as? NSNumber,
                  CFGetTypeID(code) == CFNumberGetTypeID(),
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? NSNumber,
                  CFGetTypeID(modifiers) == CFNumberGetTypeID(),
                  let keyCode = UInt32(exactly: code.doubleValue),
                  let flags = UInt32(exactly: modifiers.doubleValue) else {
                throw ShortcutFailure.cannotVerify
            }
            if enabled.boolValue { result.append(ShortcutBinding(keyCode: keyCode, modifiers: flags)) }
        }
        return result
    }
}
