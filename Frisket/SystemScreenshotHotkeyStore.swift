import Foundation
import FrisketCore

@_silgen_name("notify_post")
private func notifyPost(_ name: UnsafePointer<CChar>) -> UInt32

/// Turns the macOS screenshot symbolic hotkeys off, and can restore only the ones Frisket changed.
@MainActor enum SystemScreenshotHotkeyStore {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let hotkeysKey = "AppleSymbolicHotKeys"
    private static let memoryKey = "systemScreenshotHotkeys.turnedOffByFrisket"

    static func turnedOffIdentifiers(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: memoryKey) ?? []
    }

    /// Disables enabled screenshot-family hotkeys. Does not write when none are on.
    @discardableResult
    static func disableFamilyIfNeeded(defaults: UserDefaults = .standard) throws -> [String] {
        var hotkeys = try readHotkeys()
        let flags = enabledFlags(in: hotkeys)
        let result = SystemScreenshotHotkeys.turnedOff(byDisablingFamily: flags)
        guard !result.changed.isEmpty else { return [] }
        apply(result.enabled, to: &hotkeys)
        try write(hotkeys)
        var remembered = turnedOffIdentifiers(defaults: defaults)
        for identifier in result.changed where !remembered.contains(identifier) {
            remembered.append(identifier)
        }
        defaults.set(remembered, forKey: memoryKey)
        postChange()
        return result.changed
    }

    static func restore(defaults: UserDefaults = .standard) throws {
        let identifiers = turnedOffIdentifiers(defaults: defaults)
        guard !identifiers.isEmpty else { return }
        var hotkeys = try readHotkeys()
        for identifier in identifiers {
            guard var entry = hotkeys[identifier] as? [String: Any] else { continue }
            entry["enabled"] = true
            hotkeys[identifier] = entry
        }
        try write(hotkeys)
        defaults.removeObject(forKey: memoryKey)
        postChange()
    }

    private static func readHotkeys() throws -> [String: Any] {
        guard let value = CFPreferencesCopyAppValue(hotkeysKey as CFString, domain) else { return [:] }
        guard let hotkeys = value as? [String: Any] else { throw ShortcutFailure.cannotVerify }
        return hotkeys
    }

    private static func enabledFlags(in hotkeys: [String: Any]) -> [String: Bool] {
        var flags: [String: Bool] = [:]
        for identifier in SystemScreenshotHotkeys.familyIdentifiers {
            guard let entry = hotkeys[identifier] as? [String: Any] else { continue }
            if let enabled = entry["enabled"] as? Bool {
                flags[identifier] = enabled
            } else if let enabled = entry["enabled"] as? NSNumber {
                flags[identifier] = enabled.boolValue
            }
        }
        return flags
    }

    private static func apply(_ enabled: [String: Bool], to hotkeys: inout [String: Any]) {
        for (identifier, isOn) in enabled {
            guard var entry = hotkeys[identifier] as? [String: Any] else { continue }
            entry["enabled"] = isOn
            hotkeys[identifier] = entry
        }
    }

    private static func write(_ hotkeys: [String: Any]) throws {
        CFPreferencesSetAppValue(hotkeysKey as CFString, hotkeys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func postChange() {
        _ = "com.apple.HIToolbox.hotkeysChanged".withCString { notifyPost($0) }
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.HIToolbox.hotkeysChanged"), object: nil)
    }
}
