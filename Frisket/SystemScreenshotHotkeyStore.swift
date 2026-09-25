import Foundation
import FrisketCore

/// Frisket no longer turns macOS screenshot shortcuts off (DA-2). An earlier build did, and remembered
/// which ones; `restore` turns only those back on, and only when the user asks.
@MainActor enum SystemScreenshotHotkeyStore {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let hotkeysKey = "AppleSymbolicHotKeys"
    private static let memoryKey = PreferenceKey.systemScreenshotShortcutsTurnedOff.rawValue

    static func turnedOffIdentifiers(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: memoryKey) ?? []
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

    private static func write(_ hotkeys: [String: Any]) throws {
        CFPreferencesSetAppValue(hotkeysKey as CFString, hotkeys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
    }

    /// notify_post(3) through its real C entry point. Swift's Darwin module doesn't export it, and
    /// `@_silgen_name` would call it with the Swift calling convention (D22).
    private static func postChange() {
        typealias NotifyPost = @convention(c) (UnsafePointer<CChar>) -> UInt32
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "notify_post") {   // RTLD_DEFAULT
            let notifyPost = unsafeBitCast(symbol, to: NotifyPost.self)
            _ = "com.apple.HIToolbox.hotkeysChanged".withCString { notifyPost($0) }
        }
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.HIToolbox.hotkeysChanged"), object: nil)
    }
}
