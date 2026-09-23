import Testing
@testable import FrisketCore

@MainActor @Test func shortcutDefaultsCoexistWithSystemScreenshots() throws {
    let system = ShortcutSystemStandIn()
    // macOS screenshot keys 3, 4, 5, 6 (including their Control variants).
    system.enabled = [20, 21, 23, 22].flatMap { key in
        [ShortcutBinding(keyCode: key, modifiers: 768), ShortcutBinding(keyCode: key, modifiers: 4864)]
    }
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.active.count == 3)
    #expect(Set(commands.active.values).count == 3)
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 6400))
    #expect(commands.active[.captureFullScreen] == ShortcutBinding(keyCode: 20, modifiers: 6400))
    #expect(commands.active[.focusThumbnails] == ShortcutBinding(keyCode: 17, modifiers: 6400))
}

@MainActor private final class ShortcutSystemStandIn: ShortcutSystem {
    var queryFails = false
    var registrationFails = false
    var enabled: [ShortcutBinding] = []
    var saved: [ShortcutAction: ShortcutBinding] = [:]
    var registered: [ShortcutAction: ShortcutBinding] = [:]
    func enabledShortcuts() throws -> [ShortcutBinding] {
        if queryFails { throw ShortcutFailure.cannotVerify }; return enabled
    }
    func load() -> [ShortcutAction: ShortcutBinding] { saved }
    func save(_ bindings: [ShortcutAction: ShortcutBinding]) { saved = bindings }
    func replace(_ action: ShortcutAction, with binding: ShortcutBinding) throws {
        if registrationFails { throw ShortcutFailure.registrationFailed }; registered[action] = binding
    }
    func unregister(_ action: ShortcutAction) { registered[action] = nil }
}

@MainActor @Test func shortcutRemappingRejectsEnabledSystemKeysAndPreservesPreviousBinding() throws {
    let system = ShortcutSystemStandIn()
    let commands = ShortcutCommands(system: system)
    commands.start()
    let screenshot = ShortcutBinding(keyCode: 22, modifiers: 768)
    system.enabled = [screenshot]
    #expect(throws: ShortcutFailure.systemCollision) { try commands.remap(.captureArea, to: screenshot) }
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 6400))
    #expect(system.saved.isEmpty)
    system.enabled = []
    try commands.remap(.captureArea, to: screenshot)
    #expect(commands.active[.captureArea] == screenshot)
    #expect(system.saved[.captureArea] == screenshot)
    let restarted = ShortcutCommands(system: system)
    restarted.start()
    #expect(restarted.active[.captureArea] == screenshot)
}

@MainActor @Test(arguments: [ShortcutFailure.cannotVerify, .duplicate, .invalidBinding, .registrationFailed])
func shortcutFailedRemapNeverChangesActiveOrSavedBinding(failure: ShortcutFailure) throws {
    let system = ShortcutSystemStandIn()
    let commands = ShortcutCommands(system: system)
    commands.start()
    var candidate = ShortcutBinding(keyCode: 0, modifiers: 6400)
    switch failure {
    case .cannotVerify: system.queryFails = true
    case .registrationFailed: system.registrationFails = true
    case .duplicate: candidate = ShortcutBinding(keyCode: 20, modifiers: 6400)
    case .invalidBinding: candidate = ShortcutBinding(keyCode: 0, modifiers: 0)
    default: break
    }
    #expect(throws: failure) { try commands.remap(.captureArea, to: candidate) }
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 6400))
    #expect(system.registered[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 6400))
    #expect(system.saved.isEmpty)
}

@MainActor @Test func shortcutStartupAndDispatchFailClosedWhenSystemListChanges() throws {
    let system = ShortcutSystemStandIn()
    system.queryFails = true
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.active.isEmpty)
    #expect(commands.failures.count == 3)
    system.queryFails = false
    commands.start()
    #expect(commands.permits(.captureArea))
    system.enabled = [ShortcutBinding(keyCode: 21, modifiers: 6400)]
    #expect(!commands.permits(.captureArea))
    #expect(commands.failures[.captureArea] == .systemCollision)
    system.queryFails = true
    #expect(!commands.permits(.captureFullScreen))
    #expect(commands.failures[.captureFullScreen] == .cannotVerify)
    commands.stop()
    #expect(commands.active.isEmpty)
    #expect(system.registered.isEmpty)
}
