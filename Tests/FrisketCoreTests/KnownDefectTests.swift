import Testing

/// The known-defect wrapper (decision 58) must hide only the defect it names.
struct KnownDefectTests {
    private struct FixtureBroke: Error {}

    @Test func passesWhileTheNamedExpectationFails() async throws {
        try await knownDefect("D0", showDefects: false) {
            #expect(1 + 1 == 3, "D0: arithmetic is still broken")
        }
    }

    @Test func failsOnceTheDefectIsFixed() async throws {
        try await withKnownIssue {
            try await knownDefect("D0", showDefects: false) {
                #expect(1 + 1 == 2, "D0: fixed")
            }
        } matching: { issue in
            if case .knownIssueNotRecorded = issue.kind { return true }
            return false
        }
    }

    @Test func neverHidesAThrownError() async throws {
        try await withKnownIssue {
            try await knownDefect("D0", showDefects: false) {
                #expect(1 + 1 == 3, "D0: still broken")
                throw FixtureBroke()
            }
        } matching: { issue in
            if case .errorCaught = issue.kind { return true }
            return false
        }
    }

    @Test func neverHidesAnExpectationThatDoesNotNameTheDefect() async throws {
        try await withKnownIssue {
            try await knownDefect("D0", showDefects: false) {
                #expect(1 + 1 == 3, "D0: still broken")
                #expect(Bool(false), "fixture setup")
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue == "fixture setup" }
        }
    }

    @Test func showModeRunsTheBodyUnwrapped() async throws {
        try await withKnownIssue {
            try await knownDefect("D0", showDefects: true) {
                #expect(1 + 1 == 3, "D0: visible red")
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue == "D0: visible red" }
        }
    }
}
