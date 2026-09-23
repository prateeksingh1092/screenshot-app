import AppKit
import FrisketAdapters
import Testing

@Suite struct DragOperationMaskTests {
    @Test(arguments: [NSDraggingContext.withinApplication, .outsideApplication])
    private func dragAdvertisesCopyAndRefusesMoveAndDelete(context: NSDraggingContext) {
        let mask = FilePromiseDragAdapter.operationMask(for: context)
        #expect(mask == .copy)
        #expect(!mask.contains(.move))
        #expect(!mask.contains(.delete))
    }
}
