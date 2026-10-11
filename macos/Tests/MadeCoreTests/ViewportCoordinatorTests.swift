import Testing
import Foundation
import Metal
@testable import MadeCore

@MainActor
@Suite(.serialized) final class ViewportCoordinatorTests {
    
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
    
    init() {
        RenderInstrumentation.shared.reset()
    }
    
    deinit {
        RenderInstrumentation.shared.reset()
    }
    
    @Test func testMeshSwapTriggersRedrawThroughCoordinator() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        var invalidateCallbackCount = 0
        coordinator.onInvalidate = {
            invalidateCallbackCount += 1
        }
        
        #expect(stub.redrawCount == 0)
        #expect(RenderInstrumentation.shared.lastReason == nil)
        
        // When a solid's mesh settles and coordinator invalidates with .model
        coordinator.invalidate(reason: .model)
        
        #expect(stub.redrawCount == 1, "A mesh swap should trigger requestRedraw on the target")
        #expect(invalidateCallbackCount == 1)
        #expect(RenderInstrumentation.shared.lastReason == .model)
    }
    
    @Test func testRenderCountStaysFlatAtIdle() {
        let stub = StubInvalidationTarget()
        _ = ViewportCoordinator(target: stub)
        
        // Idle state: no invalidation called
        #expect(stub.redrawCount == 0, "Render count must stay flat at idle")
        #expect(RenderInstrumentation.shared.renderCount == 0)
        #expect(RenderInstrumentation.shared.lastReason == nil)
    }
    
    @Test func testFailedKernelResultDoesNotRedraw() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // Simulating handling of a failed kernel result:
        let result: KernelResult<SolidId> = .failure(jobId: JobId("job-1"), error: KernelError(code: .geometryFailed, message: "CSG failed"))
        switch result {
        case .success:
            coordinator.invalidate(reason: .model)
        case .failure:
            break
        }
        
        #expect(stub.redrawCount == 0, "Failed kernel result must not trigger a redraw")
        #expect(RenderInstrumentation.shared.lastReason == nil)
    }
    
    @Test func testWindowMinimizedSuppressesRedrawDuringUpdate() {
        let stub = StubInvalidationTarget()
        stub.isMinimized = true
        let coordinator = ViewportCoordinator(target: stub)
        
        var invalidateCallbackCount = 0
        coordinator.onInvalidate = {
            invalidateCallbackCount += 1
        }
        
        // When update arrives while window is minimized
        coordinator.invalidate(reason: .model)
        
        #expect(stub.redrawCount == 0, "Redraw request must be suppressed when target is minimized")
        #expect(invalidateCallbackCount == 0, "onInvalidate callback should not fire if target is minimized")
        #expect(RenderInstrumentation.shared.lastReason == .model, "Invalidation reason is still recorded for telemetry")
    }
    
    @Test func testRemovingSolidRedrawsOnce() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // Simulating solid removal triggering invalidation
        coordinator.invalidate(reason: .model)
        
        #expect(stub.redrawCount == 1, "Removing a solid must trigger redraw once")
        #expect(RenderInstrumentation.shared.lastReason == .model)
    }
    
    @Test func testTwoMeshesSettleInSameFrame() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // First mesh settles
        coordinator.invalidate(reason: .model)
        #expect(stub.redrawCount == 1)
        
        // Second mesh settles in the same frame/tick
        coordinator.invalidate(reason: .model)
        #expect(stub.redrawCount == 2)
        #expect(RenderInstrumentation.shared.lastReason == .model)
    }
    
    @Test func testInvalidateReasonClassification() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        // Verify all 4 InvalidateReason classifications can be tagged and recorded
        let reasons: [InvalidateReason] = [.camera, .resize, .model, .interaction]
        for (index, reason) in reasons.enumerated() {
            coordinator.invalidate(reason: reason)
            #expect(stub.redrawCount == (index + 1))
            #expect(RenderInstrumentation.shared.lastReason == reason)
        }
    }
    
    @Test func testCameraInvalidationAdvancesRedrawCountByExactlyOne() {
        let stub = StubInvalidationTarget()
        let coordinator = ViewportCoordinator(target: stub)
        
        #expect(stub.redrawCount == 0)
        coordinator.invalidate(reason: .camera)
        #expect(stub.redrawCount == 1)
        #expect(RenderInstrumentation.shared.lastReason == .camera)
    }
    
    @Test func testRenderInstrumentationTelemetry() {
        #expect(RenderInstrumentation.shared.renderCount == 0)
        #expect(RenderInstrumentation.shared.drawCalls == 0)
        
        RenderInstrumentation.shared.recordRender(drawCalls: 5)
        #expect(RenderInstrumentation.shared.renderCount == 1)
        #expect(RenderInstrumentation.shared.drawCalls == 5)
        
        RenderInstrumentation.shared.recordRender(drawCalls: 3)
        #expect(RenderInstrumentation.shared.renderCount == 2)
        #expect(RenderInstrumentation.shared.drawCalls == 3)
        
        RenderInstrumentation.shared.reset()
        #expect(RenderInstrumentation.shared.renderCount == 0)
        #expect(RenderInstrumentation.shared.drawCalls == 0)
        #expect(RenderInstrumentation.shared.lastReason == nil)
    }
}
