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

    private let staging: DragStagingLifetime
    private var active: Active?
    private var queuedWrite: (URL, @Sendable (Error?) -> Void)?
    private var queuedSessionEnd = false
    private var accepting = false

    public init(staging: DragStagingLifetime) { self.staging = staging }

    @discardableResult func beginSession(from view: NSView, event: NSEvent, image: NSImage?) -> Bool {
        guard active == nil else { return false }
        accepting = true
        queuedWrite = nil
        queuedSessionEnd = false
        let provider = NSFilePromiseProvider(fileType: "public.png", delegate: self)
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
        if let active, active.resumed, active.sessionHandled { self.active = nil }
    }

    public func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery {
        guard operation == .copy else { return .failed }
        let current = Active(image: image, events: events)
        if let queuedWrite {
            current.destination = queuedWrite.0
            current.completion = queuedWrite.1
            self.queuedWrite = nil
        }
        if queuedSessionEnd {
            current.sessionEnded = true
            queuedSessionEnd = false
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
        MainActor.assumeIsolated { self.noteSessionEnded() }
    }

    public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "Capture.png"
    }

    public func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }

    public nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping @Sendable (Error?) -> Void) {
        MainActor.assumeIsolated { self.notePromiseDestination(url, completion: completionHandler) }
    }

    private func notePromiseDestination(_ url: URL, completion: @escaping @Sendable (Error?) -> Void) {
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

    private func noteSessionEnded() {
        if let active {
            active.sessionEnded = true
            Task { await self.pump(active) }
        } else if accepting {
            queuedSessionEnd = true
        }
    }

    private func pump(_ active: Active) async {
        if let url = active.destination, let completion = active.completion, !active.writeHandled {
            active.writeHandled = true
            var failed = false
            do { try await staging.writePromiseCopy(active.image.pngData, to: url) }
            catch { failed = true }
            active.writeFailed = failed
            completion(failed ? promiseError() : nil)
            do { try await active.events.promiseWriteReturned() }
            catch {
                resume(active, throwing: error)
                return
            }
        }
        if active.sessionEnded && !active.sessionHandled {
            active.sessionHandled = true
            await active.events.dragSessionEnded()
        }
        finishIfReady(active)
    }

    private func finishIfReady(_ active: Active) {
        guard !active.resumed else { return }
        if active.writeHandled && active.sessionHandled {
            resume(active, returning: active.writeFailed ? .failed : .copied)
        } else if active.sessionHandled && active.destination == nil {
            resume(active, returning: .failed)
        }
    }

    private func resume(_ active: Active, returning delivery: DragDelivery) {
        guard let continuation = active.continuation, !active.resumed else { return }
        active.resumed = true
        if active.sessionHandled { self.active = nil }
        continuation.resume(returning: delivery)
    }

    private func resume(_ active: Active, throwing error: Error) {
        guard let continuation = active.continuation, !active.resumed else { return }
        active.resumed = true
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
        var writeHandled = false
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
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        image.draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        guard dragEnabled else { return }
        onMouseDown?(self, event)
    }
}
