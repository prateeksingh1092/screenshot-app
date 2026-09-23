import Foundation
import FrisketCore
import Testing

// Xcode-only with the installed CLT 6.3.3: compiler reports "no such module 'Testing'".
@Test func swiftTestingRunsOnSupportedMacOS() {
    #expect(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26)
}
