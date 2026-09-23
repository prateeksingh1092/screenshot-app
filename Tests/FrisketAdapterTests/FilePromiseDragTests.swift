import AppKit
@testable import FrisketAdapters
import FrisketCore
import Testing

@MainActor private final class PromiseEvents: DragCopyEvents {
    var writeReturned = false
    var sessionEnded = false
    func promiseWriteReturned() async throws { writeReturned = true }
    func dragSessionEnded() async { sessionEnded = true }
}

@MainActor private func startDelivery(_ adapter: FilePromiseDragAdapter, bytes: Data,
                                      events: PromiseEvents,
                                      onDelivery: @escaping @MainActor (DragDelivery) -> Void = { _ in }) async -> Task<DragDelivery, Error> {
    // The main actor cannot resume the caller until deliver has suspended.
    var delivery: Task<DragDelivery, Error>!
    await withCheckedContinuation { started in
        delivery = Task { @MainActor in
            defer { adapter.endHandoff() }
            started.resume()
            let result = try await adapter.deliver(.copy, image: DragImage(pngData: bytes), events: events)
            onDelivery(result)
            return result
        }
    }
    return delivery
}

@MainActor private final class SuspendedWrite {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?
    var finished = false

    func write(_ bytes: Data, to destination: URL, fails: Bool) async throws {
        started = true
        startWaiter?.resume()
        await withCheckedContinuation { finishWaiter = $0 }
        defer { finished = true }
        if fails { throw CocoaError(.fileWriteUnknown) }
        try bytes.write(to: destination)
    }

    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { startWaiter = $0 } }
    }

    func finish() { finishWaiter?.resume() }
}

@Suite @MainActor struct FilePromiseDragTests {
    @Test func acceptedSessionEndAllowsALaterPromiseDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = FilePromiseDragAdapter(staging: DragStagingLifetime(directory: root))
        let bytes = Data("synthetic promised bytes".utf8)
        let events = PromiseEvents()
        let delivery = await startDelivery(adapter, bytes: bytes, events: events)
        await adapter.noteSessionEnded(operation: .copy)?.value
        let destination = root.appendingPathComponent("Capture.png")
        let succeeded = await withCheckedContinuation { completion in
            adapter.notePromiseDestination(destination) { error in
                completion.resume(returning: error == nil)
            }
        }
        #expect(succeeded)
        #expect(try await delivery.value == .copied)
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(events.writeReturned && events.sessionEnded)
    }

    @Test(arguments: [false, true])
    func sessionEndWaitsForTheInFlightWrite(fails: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SuspendedWrite()
        let adapter = FilePromiseDragAdapter { bytes, destination in
            try await writer.write(bytes, to: destination, fails: fails)
        }
        let events = PromiseEvents()
        let bytes = Data("synthetic promised bytes".utf8)
        let delivery = await startDelivery(adapter, bytes: bytes, events: events) { _ in
            #expect(writer.finished, "Delivery must wait for the write result")
            #expect(events.writeReturned, "Delivery must wait for the completion event")
        }
        let destination = root.appendingPathComponent("Capture.png")
        let completion = Task { @MainActor in
            await withCheckedContinuation { completion in
                adapter.notePromiseDestination(destination) { error in
                    completion.resume(returning: error == nil)
                }
            }
        }
        await writer.waitUntilStarted()
        await adapter.noteSessionEnded(operation: .copy)?.value
        #expect(!events.writeReturned)
        writer.finish()
        #expect(await completion.value == !fails)
        #expect(try await delivery.value == (fails ? .failed : .copied))
        if !fails { #expect(try Data(contentsOf: destination) == bytes) }
    }

    @Test func completedWriteWaitsForSessionEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = FilePromiseDragAdapter(staging: DragStagingLifetime(directory: root))
        let events = PromiseEvents()
        let bytes = Data("synthetic promised bytes".utf8)
        let delivery = await startDelivery(adapter, bytes: bytes, events: events) { _ in
            #expect(events.sessionEnded)
        }
        let destination = root.appendingPathComponent("Capture.png")
        let succeeded = await withCheckedContinuation { completion in
            adapter.notePromiseDestination(destination) { error in
                completion.resume(returning: error == nil)
            }
        }
        #expect(succeeded)
        #expect(!events.sessionEnded)
        await adapter.noteSessionEnded(operation: .copy)?.value
        #expect(try await delivery.value == .copied)
        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test(arguments: [NSDragOperation(), .move, .delete])
    func unacceptedSessionWithoutAPromiseFails(operation: NSDragOperation) async throws {
        let adapter = FilePromiseDragAdapter { _, _ in
            Issue.record("An unaccepted drag must not write a file")
        }
        let events = PromiseEvents()
        let delivery = await startDelivery(adapter, bytes: Data(), events: events)
        await adapter.noteSessionEnded(operation: operation)?.value
        #expect(try await delivery.value == .failed)
        #expect(events.sessionEnded && !events.writeReturned)
    }
}
