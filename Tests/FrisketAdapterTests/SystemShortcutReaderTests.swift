import Carbon
import FrisketCore
import FrisketAdapters
import Testing

@MainActor @Test func systemShortcutReaderRejectsMissingOrMalformedVerification() throws {
    let enabled: [String: Any] = [kHISymbolicHotKeyCode: 22, kHISymbolicHotKeyModifiers: 768, kHISymbolicHotKeyEnabled: true]
    let disabled: [String: Any] = [kHISymbolicHotKeyCode: 21, kHISymbolicHotKeyModifiers: 768, kHISymbolicHotKeyEnabled: false]
    #expect(try SystemShortcutReader.decode([enabled, disabled] as CFArray) == [ShortcutBinding(keyCode: 22, modifiers: 768)])
    for malformed: CFArray? in [nil, [[:]] as CFArray, [[kHISymbolicHotKeyEnabled: "yes"]] as CFArray,
                                [[kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: -1, kHISymbolicHotKeyModifiers: 768]] as CFArray] {
        #expect(throws: ShortcutFailure.cannotVerify) { try SystemShortcutReader.decode(malformed) }
    }
}
