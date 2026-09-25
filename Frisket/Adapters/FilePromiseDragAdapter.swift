import AppKit
import FrisketCore

/// Copy-only file promise. Move and delete are refused, including a drop on the Trash.
@MainActor public final class FilePromiseDragAdapter: NSObject, DragHandoff, NSDraggingSource, NSFilePromiseProviderDelegate {
    public nonisolated static func operationMask(for context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication, .outsideApplication: return .copy
        @unknown default: return .copy
        }
    }

    private let writeCopy: @Sendable (Data, URL) async throws -> Void
    private var provider: NSFilePromiseProvider?
    private var active: Active?
    private var queuedWrite: (URL, @Sendable (Error?) -> Void)?
    private var queuedSessionEnd: NSDragOperation?
    private var accepting = false

    /// The promised file is written from memory; nothing is staged on disk first (DA-3).
    public init(writer: DragPromiseWriter) {
        writeCopy = { try await writer.writePromiseCopy($0, to: $1) }
    }

    // Filesystem boundary injection for deterministic in-flight write tests.
    init(writeCopy: @escaping @Sendable (Data, URL) async throws -> Void) {
        self.writeCopy = writeCopy
    }

    @discardableResult func beginSession(from view: NSView, event: NSEvent, image: NSImage?) -> Bool {
        guard active == nil else { return false }
        accepting = true
        queuedWrite = nil
        queuedSessionEnd = nil
        let provider = NSFilePromiseProvider(fileType: "public.png", delegate: self)
        self.provider = provider
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(view.bounds, contents: image)
        view.beginDraggingSession(with: [item], event: event, source: self)
        return true
    }

    /// After the command returns, fail a promise write that never met a handoff.
    func endHandoff() {
        accepting = false
        if let queuedWrite {
            queuedWrite.1(promiseError())
            self.queuedWrite = nil
        }
        if let active, active.resumed, active.sessionHandled {
            self.active = nil
            provider = nil
        }
    }

    public func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        guard operation == .copy else { return .failed }
        let current = Active(image: image, events: events)
        if let queuedWrite {
            current.destination = queuedWrite.0
            current.completion = queuedWrite.1
            self.queuedWrite = nil
        }
        if let queuedSessionEnd {
            current.sessionEnded = true
            current.sessionAccepted = queuedSessionEnd == .copy
            self.queuedSessionEnd = nil
        }
        active = current
        return try await withCheckedThrowingContinuation { continuation in
            current.continuation = continuation
            Task { await self.pump(current) }
        }
    }

    public nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.operationMask(for: context)
    }

    public nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated { _ = self.noteSessionEnded(operation: operation) }
    }

    public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        // Dragged-out files are named like Save's exports (D17, ticket 81); the receiver resolves collisions.
        ExportFilenamePolicy.filename(at: Date(), in: .current)
    }

    public func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }

    public nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping @Sendable (Error?) -> Void) {
        MainActor.assumeIsolated { self.notePromiseDestination(url, completion: completionHandler) }
    }

    func notePromiseDestination(_ url: URL, completion: @escaping @Sendable (Error?) -> Void) {
        guard accepting || active != nil else {
            completion(promiseError())
            return
        }
        if let active {
            active.destination = url
            active.completion = completion
            Task { await self.pump(active) }
        } else {
            queuedWrite = (url, completion)
        }
    }

    @discardableResult func noteSessionEnded(operation: NSDragOperation) -> Task<Void, Never>? {
        if let active {
            active.sessionEnded = true
            active.sessionAccepted = operation == .copy
            return Task { await self.pump(active) }
        } else if accepting {
            queuedSessionEnd = operation
        }
        return nil
    }

    private func pump(_ active: Active) async {
        // Callback tasks can reenter while a write or lifetime event is suspended.
        // Starting an operation prevents duplicates; only its return permits delivery.
        if let url = active.destination, let completion = active.completion, !active.writeStarted {
            active.writeStarted = true
            var failed = false
            do { try await writeCopy(active.image.pngData, url) }
            catch { failed = true }
            active.writeFailed = failed
            completion(failed ? promiseError() : nil)
            do { try await active.events.promiseWriteReturned() }
            catch {
                active.writeHandled = true
                resume(active, throwing: error)
                return
            }
            active.writeHandled = true
        }
        if active.sessionEnded && !active.sessionStarted {
            active.sessionStarted = true
            await active.events.dragSessionEnded()
            active.sessionHandled = true
        }
        finishIfReady(active)
    }

    private func finishIfReady(_ active: Active) {
        guard !active.resumed else {
            if active.sessionHandled {
                self.active = nil
                provider = nil
            }
            return
        }
        if active.writeHandled && active.sessionHandled {
            resume(active, returning: active.writeFailed ? .failed : .copied)
        } else if active.sessionHandled && !active.sessionAccepted && active.destination == nil {
            resume(active, returning: .failed)
        }
    }

    private func resume(_ active: Active, returning delivery: DragDelivery) {
        guard let continuation = active.continuation, !active.resumed else { return }
        active.resumed = true
        if active.sessionHandled {
            self.active = nil
            provider = nil
        }
        continuation.resume(returning: delivery)
    }

    private func resume(_ active: Active, throwing error: Error) {
        guard let continuation = active.continuation, !active.resumed else { return }
        active.resumed = true
        if active.sessionHandled {
            self.active = nil
            provider = nil
        }
        continuation.resume(throwing: error)
    }

    private func promiseError() -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
    }

    @MainActor private final class Active {
        let image: DragImage
        let events: any DragCopyEvents
        var destination: URL?
        var completion: (@Sendable (Error?) -> Void)?
        var sessionEnded = false
        var sessionAccepted = false
        var writeStarted = false
        var writeHandled = false
        var sessionStarted = false
        var sessionHandled = false
        var writeFailed = false
        var resumed = false
        var continuation: CheckedContinuation<DragDelivery, Error>?
        init(image: DragImage, events: any DragCopyEvents) {
            self.image = image
            self.events = events
        }
    }
}

final class ThumbnailDragWellView: NSView {
    var image: NSImage?
    var dragEnabled = true
    var onMouseDown: ((NSView, NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        guard dragEnabled else { return }
        DragStart.track(from: self, event: event) { [weak self] drag in
            guard let self, self.dragEnabled else { return }
            self.onMouseDown?(self, drag)
        }
    }
}

@MainActor enum DragStart {
    /// Accessory apps ignore a drag that begins on mouse-down before the app is active.
    static func track(from view: NSView, event: NSEvent, perform: (NSEvent) -> Void) {
        guard let window = view.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        let start = view.convert(event.locationInWindow, from: nil)
        var dragEvent: NSEvent?
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { next, stop in
            guard let next else { return }
            if next.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let point = view.convert(next.locationInWindow, from: nil)
            if hypot(point.x - start.x, point.y - start.y) >= 3 {
                dragEvent = next
                stop.pointee = true
            }
        }
        if let dragEvent { perform(dragEvent) }
    }
}
