import Testing
@testable import FrisketCore

@MainActor @Test func commandShiftNumberDefaultsRegisterWhenSystemScreenshotKeysAreOff() {
    let system = ShortcutSystemStandIn()
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.failures.isEmpty)
    #expect(commands.active.count == ShortcutAction.allCases.count)
    #expect(commands.active[.showHistory] == ShortcutBinding(keyCode: 18, modifiers: 768))
    #expect(commands.active[.focusThumbnails] == ShortcutBinding(keyCode: 19, modifiers: 768))
    #expect(commands.active[.captureFullScreen] == ShortcutBinding(keyCode: 20, modifiers: 768))
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 768))
    #expect(commands.active[.captureWindow] == ShortcutBinding(keyCode: 23, modifiers: 768))
    #expect(commands.active[.captureScrolling] == ShortcutBinding(keyCode: 22, modifiers: 768))
}

@MainActor @Test func commandShiftScreenshotDefaultsStayInactiveWhileMacOSOwnsThem() {
    let system = ShortcutSystemStandIn()
    system.enabled = [20, 21, 23, 22].flatMap { key in
        [ShortcutBinding(keyCode: key, modifiers: 768), ShortcutBinding(keyCode: key, modifiers: 4864)]
    }
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.active[.showHistory] == ShortcutBinding(keyCode: 18, modifiers: 768))
    #expect(commands.active[.focusThumbnails] == ShortcutBinding(keyCode: 19, modifiers: 768))
    #expect(commands.active[.captureArea] == nil)
    #expect(commands.active[.captureFullScreen] == nil)
    #expect(commands.active[.captureWindow] == nil)
    #expect(commands.active[.captureScrolling] == nil)
    #expect(commands.failures[.captureArea] == .systemCollision)
    #expect(commands.failures[.captureFullScreen] == .systemCollision)
    #expect(commands.failures[.captureWindow] == .systemCollision)
    #expect(commands.failures[.captureScrolling] == .systemCollision)
}

@MainActor @Test func claimingSystemScreenshotShortcutsLetsThoseDefaultsRegister() {
    let system = ShortcutSystemStandIn()
    let family = [20, 21, 22, 23].map { ShortcutBinding(keyCode: $0, modifiers: 768) }
    system.enabled = family
    let commands = ShortcutCommands(system: system)
    commands.start(claimingSystemShortcuts: family)
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 768))
    #expect(commands.permits(.captureArea))
    #expect(commands.permits(.captureScrolling))
}

@MainActor @Test func unchangedLegacyDefaultsMigrateToCommandShiftNumbers() {
    let system = ShortcutSystemStandIn()
    system.saved = [
        .captureArea: ShortcutBinding(keyCode: 21, modifiers: 6400),
        .captureFullScreen: ShortcutBinding(keyCode: 20, modifiers: 6400),
        .focusThumbnails: ShortcutBinding(keyCode: 17, modifiers: 6400),
    ]
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 768))
    #expect(commands.active[.captureFullScreen] == ShortcutBinding(keyCode: 20, modifiers: 768))
    #expect(commands.active[.focusThumbnails] == ShortcutBinding(keyCode: 19, modifiers: 768))
    #expect(commands.active[.showHistory] == ShortcutBinding(keyCode: 18, modifiers: 768))
}

@MainActor @Test func aCustomShortcutSurvivesTheNumberRowMigration() {
    let system = ShortcutSystemStandIn()
    let custom = ShortcutBinding(keyCode: 0, modifiers: 256)
    system.saved = [.captureArea: custom]
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.active[.captureArea] == custom)
    #expect(commands.active[.captureFullScreen] == ShortcutBinding(keyCode: 20, modifiers: 768))
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
    let screenshot = ShortcutBinding(keyCode: 22, modifiers: 4864)
    system.enabled = [screenshot]
    #expect(throws: ShortcutFailure.systemCollision) { try commands.remap(.captureArea, to: screenshot) }
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 768))
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
    var candidate = ShortcutBinding(keyCode: 0, modifiers: 768)
    switch failure {
    case .cannotVerify: system.queryFails = true
    case .registrationFailed: system.registrationFails = true
    case .duplicate: candidate = ShortcutBinding(keyCode: 20, modifiers: 768)
    case .invalidBinding: candidate = ShortcutBinding(keyCode: 0, modifiers: 0)
    default: break
    }
    #expect(throws: failure) { try commands.remap(.captureArea, to: candidate) }
    #expect(commands.active[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 768))
    #expect(system.registered[.captureArea] == ShortcutBinding(keyCode: 21, modifiers: 768))
    #expect(system.saved.isEmpty)
}

@MainActor @Test func shortcutStartupAndDispatchFailClosedWhenSystemListChanges() throws {
    let system = ShortcutSystemStandIn()
    system.queryFails = true
    let commands = ShortcutCommands(system: system)
    commands.start()
    #expect(commands.active.isEmpty)
    #expect(commands.failures.count == ShortcutAction.allCases.count)
    system.queryFails = false
    commands.start()
    #expect(commands.permits(.captureArea))
    system.enabled = [ShortcutBinding(keyCode: 21, modifiers: 768)]
    #expect(!commands.permits(.captureArea))
    #expect(commands.failures[.captureArea] == .systemCollision)
    system.queryFails = true
    #expect(!commands.permits(.captureFullScreen))
    #expect(commands.failures[.captureFullScreen] == .cannotVerify)
    commands.stop()
    #expect(commands.active.isEmpty)
    #expect(system.registered.isEmpty)
}

@Test func screenshotFamilyIsTheNumberRowMacOSUses() {
    #expect(SystemScreenshotHotkeys.isFamily(ShortcutBinding(keyCode: 21, modifiers: 768)))
    #expect(SystemScreenshotHotkeys.isFamily(ShortcutBinding(keyCode: 20, modifiers: 4864)))
    #expect(!SystemScreenshotHotkeys.isFamily(ShortcutBinding(keyCode: 21, modifiers: 6400)))
    #expect(!SystemScreenshotHotkeys.isFamily(ShortcutBinding(keyCode: 18, modifiers: 768)))
}

@Test func disablingTheFamilyTurnsOffOnlyEnabledScreenshotIdentifiers() {
    let enabled = ["28": true, "30": false, "184": true, "99": true]
    let result = SystemScreenshotHotkeys.turnedOff(byDisablingFamily: enabled)
    #expect(result.changed == ["28", "184"])
    #expect(result.enabled["28"] == false)
    #expect(result.enabled["30"] == false)
    #expect(result.enabled["184"] == false)
    #expect(result.enabled["99"] == true)
}

@Test func collisionsAreDesiredFamilyBindingsTheSystemStillHas() {
    let desired = [ShortcutBinding(keyCode: 21, modifiers: 768), ShortcutBinding(keyCode: 18, modifiers: 768)]
    let enabled = [ShortcutBinding(keyCode: 21, modifiers: 768)]
    #expect(SystemScreenshotHotkeys.collisions(desired: desired, systemEnabled: enabled) == [desired[0]])
}
