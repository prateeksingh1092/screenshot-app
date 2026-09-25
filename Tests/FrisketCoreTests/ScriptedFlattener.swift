import Foundation
import FrisketCore
import Synchronization

/// The test adapter at the coordinator's flatten seam (ticket 65). Scripted results are returned
/// in order, one per call; after the script runs out, every call goes to `fallback`, which is
/// the production `CaptureRenderer` unless a test gives fixed bytes. Every input is recorded.
/// Kept identical in both test targets, like `KnownDefect.swift`.
final class ScriptedFlattener: CaptureFlattening {
    private let script: Mutex<[Result<Data, RenderFailure>]>
    private let received = Mutex<[Data]>([])
    private let fallback: Result<Data, RenderFailure>?

    /// Scripted results first, then the production renderer.
    init(_ script: [Result<Data, RenderFailure>] = []) {
        self.script = Mutex(script)
        fallback = nil
    }

    /// Every call returns `output`.
    init(always output: Data) {
        script = Mutex([])
        fallback = .success(output)
    }

    var inputs: [Data] { received.withLock { $0 } }

    func flatten(_ capture: Data, edits: DocumentEdits) throws(RenderFailure) -> Data {
        received.withLock { $0.append(capture) }
        let next = script.withLock { script in script.isEmpty ? nil : script.removeFirst() }
        switch next ?? fallback {
        case let .success(data)?: return data
        case let .failure(failure)?: throw failure
        case nil: return try CaptureRenderer().flatten(capture, edits: edits)
        }
    }
}
