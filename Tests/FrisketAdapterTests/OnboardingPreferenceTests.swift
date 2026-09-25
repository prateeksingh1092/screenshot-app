import FrisketCore
@testable import FrisketAdapters
import Testing

@Suite struct OnboardingPreferenceTests {
    @Test func completionWritesOnlyTheBundlePreferenceKey() {
        var stored: [String: Bool] = [:]
        let preference = OnboardingPreference(
            read: { stored[$0] ?? false },
            write: { stored[$0] = $1 }
        )
        #expect(!preference.isComplete)
        preference.markComplete()
        #expect(stored == [PreferenceKey.onboardingCompleted.rawValue: true])
        #expect(preference.isComplete)
    }
}
