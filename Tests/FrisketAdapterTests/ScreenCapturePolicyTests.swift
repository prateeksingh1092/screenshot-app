import Foundation
@testable import FrisketAdapters
import Testing

@Suite struct ScreenCapturePolicyTests {
    @Test func unlistedProcessMayBeCapturedBecauseItCannotAppearInTheSnapshot() {
        #expect(ScreenCapturePolicy.ownProcessListing(listedProcessIDs: [], currentProcessID: 7) == .unlisted)
    }

    @Test func listedCurrentProcessMustBeExcluded() {
        #expect(ScreenCapturePolicy.ownProcessListing(listedProcessIDs: [7, 11], currentProcessID: 7) == .included)
    }

    @Test func listedBundleWithoutThisProcessFailsClosed() {
        #expect(ScreenCapturePolicy.ownProcessListing(listedProcessIDs: [11], currentProcessID: 7) == .staleIdentity)
    }
}
