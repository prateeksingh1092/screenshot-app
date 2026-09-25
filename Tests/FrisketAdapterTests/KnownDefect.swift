import Foundation
import Testing

/// Runs a test body that reproduces a defect listed in `Plans/dreamy-giggling-barto.md` §1.2
/// (decision 58).
///
/// While the defect exists, the test passes: each failed expectation whose comment names `id`
/// (for example `#expect(saved == preview, "D1: row 450")`) is recorded as a known issue.
/// Once the defect is fixed, the test fails with "Known issue was not recorded", so the fix
/// must delete this wrapper and keep the test as a regression guard. A thrown error, or a
/// failed expectation that doesn't name `id`, is never treated as the defect: a broken fixture
/// still fails the test. Name the test function after the defect (`d1…`) so
/// `scripts/ci.sh --defects` can find it. Set `FRISKET_SHOW_DEFECTS=1` to run bodies unwrapped.
func knownDefect(_ id: String, sourceLocation: SourceLocation = #_sourceLocation,
                 _ body: () async throws -> Void) async throws {
    try await knownDefect(id, showDefects: ProcessInfo.processInfo.environment["FRISKET_SHOW_DEFECTS"] == "1",
                          sourceLocation: sourceLocation, body)
}

func knownDefect(_ id: String, showDefects: Bool, sourceLocation: SourceLocation = #_sourceLocation,
                 _ body: () async throws -> Void) async throws {
    if showDefects {
        try await body()
        return
    }
    try await withKnownIssue(Comment(rawValue: "Known defect \(id)"), sourceLocation: sourceLocation) {
        try await body()
    } matching: { issue in
        guard case .expectationFailed = issue.kind else { return false }
        return issue.comments.contains { $0.rawValue.hasPrefix(id + ":") || $0.rawValue == id }
    }
}
