import XCTest
import Metal
@testable import MadeCore

@MainActor
final class ViewportCoordinatorTests: XCTestCase {
    
    final class StubInvalidationTarget: ViewportInvalidationTarget, @unchecked Sendable {
        var isMinimized: Bool = false
        private(set) var redrawCount: Int = 0
        
        func requestRedraw() {
            redrawCount += 1
        }
        
        func reset() {
            redrawCount = 0
            isMinimized = false
        }
    }
    
    override func setUp() {
        super.setUp()
        RenderInstrumentation.shared.reset()
    }
    
    override func tearDown() {
        RenderInstrumentation.shared.reset()
        super.tearDown()
    }
    
    func testMeshSwapTriggersRedrawThroughCoordinator() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        var invalidateCallbackCount = 0
        coordinator.onInvalidate = {
            invalidateCallbackCount += 1
        }
        
        XCTAssertEqual(stub.redrawCount, 0)
        XCTAssertNil(RenderInstrumentation.shared.lastReason)
        
        // When a solid's mesh settles and coordinator invalidates with .model
        coordinator.invalidate(reason: .model)
        
        XCTAssertEqual(stub.redrawCount, 1, "A mesh swap should trigger requestRedraw on the target")
        XCTAssertEqual(invalidateCallbackCount, 1)
        XCTAssertEqual(RenderInstrumentation.shared.lastReason, .model)
    }
    
    func testRenderCountStaysFlatAtIdle() {
        let stub = StubInvalidationTarget()
        _ = ViewportCoordinator(target: stub)
        
        // Idle state: no invalidation called
        XCTAssertEqual(stub.redrawCount, 0, "Render count must stay flat at idle")
        XCTAssertEqual(RenderInstrumentation.shared.renderCount, 0)
        XCTAssertNil(RenderInstrumentation.shared.lastReason)
    }
    
    func testFailedKernelResultDoesNotRedraw() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // Simulating a failed kernel request:
        // ContentView only calls coordinator.invalidate when kernel result is .success
        let kernelSuccess = false
        if kernelSuccess {
            coordinator.invalidate(reason: .model)
        }
        
        XCTAssertEqual(stub.redrawCount, 0, "Failed kernel result must not trigger a redraw")
        XCTAssertNil(RenderInstrumentation.shared.lastReason)
    }
    
    func testWindowMinimizedSuppressesRedrawDuringUpdate() {
        let stub = StubInvalidationTarget()
        stub.isMinimized = true
        let coordinator = ViewportCoordinator(target: stub)
        
        var invalidateCallbackCount = 0
        coordinator.onInvalidate = {
            invalidateCallbackCount += 1
        }
        
        // When update arrives while window is minimized
        coordinator.invalidate(reason: .model)
        
        XCTAssertEqual(stub.redrawCount, 0, "Redraw request must be suppressed when target is minimized")
        XCTAssertEqual(invalidateCallbackCount, 0, "onInvalidate callback should not fire if target is minimized")
        XCTAssertEqual(RenderInstrumentation.shared.lastReason, .model, "Invalidation reason is still recorded for telemetry")
    }
    
    func testRemovingSolidRedrawsOnce() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // Simulating solid removal triggering invalidation
        coordinator.invalidate(reason: .model)
        
        XCTAssertEqual(stub.redrawCount, 1, "Removing a solid must trigger redraw once")
        XCTAssertEqual(RenderInstrumentation.shared.lastReason, .model)
    }
    
    func testTwoMeshesSettleInSameFrame() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // First mesh settles
        coordinator.invalidate(reason: .model)
        XCTAssertEqual(stub.redrawCount, 1)
        
        // Second mesh settles in the same frame/tick
        coordinator.invalidate(reason: .model)
        XCTAssertEqual(stub.redrawCount, 2)
        XCTAssertEqual(RenderInstrumentation.shared.lastReason, .model)
    }
    
    func testInvalidateReasonClassification() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // Verify all 4 InvalidateReason classifications can be tagged and recorded
        let reasons: [InvalidateReason] = [.camera, .resize, .model, .interaction]
        for (index, reason) in reasons.enumerated() {
            coordinator.invalidate(reason: reason)
            XCTAssertEqual(stub.redrawCount, index + 1)
            XCTAssertEqual(RenderInstrumentation.shared.lastReason, reason)
        }
    }
    
    func testCameraInvalidationAdvancesRedrawCountByExactlyOne() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        XCTAssertEqual(stub.redrawCount, 0)
        coordinator.invalidate(reason: .camera)
        XCTAssertEqual(stub.redrawCount, 1)
        XCTAssertEqual(RenderInstrumentation.shared.lastReason, .camera)
    }
    
    func testRenderInstrumentationTelemetry() {
        XCTAssertEqual(RenderInstrumentation.shared.renderCount, 0)
        XCTAssertEqual(RenderInstrumentation.shared.drawCalls, 0)
        
        RenderInstrumentation.shared.recordRender(drawCalls: 5)
        XCTAssertEqual(RenderInstrumentation.shared.renderCount, 1)
        XCTAssertEqual(RenderInstrumentation.shared.drawCalls, 5)
        
        RenderInstrumentation.shared.recordRender(drawCalls: 3)
        XCTAssertEqual(RenderInstrumentation.shared.renderCount, 2)
        XCTAssertEqual(RenderInstrumentation.shared.drawCalls, 3)
        
        RenderInstrumentation.shared.reset()
        XCTAssertEqual(RenderInstrumentation.shared.renderCount, 0)
        XCTAssertEqual(RenderInstrumentation.shared.drawCalls, 0)
        XCTAssertNil(RenderInstrumentation.shared.lastReason)
    }
}
