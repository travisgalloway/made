import Testing
import Foundation
@testable import MadeCore

@Suite struct PointerRouterTests {
    private func p(_ id: Int, _ x: Float = 0, _ y: Float = 0) -> ArbiterPointer {
        ArbiterPointer(pointerId: id, x: x, y: y)
    }
    
    private let manipulateLocked = GestureDecision(mode: .manipulate, locked: true)
    private let navigateLocked = GestureDecision(mode: .navigate, locked: true)
    private let manipulateOpen = GestureDecision(mode: .manipulate, locked: false)
    
    @Test func testTouchSinglePointerDragLocksManipulate() {
        let router = PointerRouter()
        #expect(router.handle(.down(pointerType: .touch, pointer: p(1))) == .undecided)
        #expect(router.handle(.move(pointerType: .touch, pointer: p(1, 20, 20))) == manipulateLocked)
        #expect(router.handle(.up(pointerType: .touch, pointerId: 1)) == manipulateLocked)
    }
    
    @Test func testTouchSecondPointerLocksNavigate() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .touch, pointer: p(1)))
        _ = router.handle(.down(pointerType: .touch, pointer: p(2)))
        #expect(router.handle(.move(pointerType: .touch, pointer: p(1, 20, 20))) == navigateLocked)
        _ = router.handle(.up(pointerType: .touch, pointerId: 2))
        #expect(router.handle(.up(pointerType: .touch, pointerId: 1)) == navigateLocked)
    }
    
    @Test func testTouchCancelResetsArbiter() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .touch, pointer: p(1)))
        _ = router.handle(.move(pointerType: .touch, pointer: p(1, 20, 20)))
        #expect(router.handle(.cancel(pointerType: .touch, pointerId: 1)) == manipulateLocked)
        #expect(router.arbiter.current().mode == nil)
    }
    
    @Test func testPenUpAndCancelStayManipulate() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .pen, pointer: p(1)))
        #expect(router.handle(.up(pointerType: .pen, pointerId: 1)) == manipulateLocked)
        #expect(router.handle(.cancel(pointerType: .pen, pointerId: 1)) == manipulateLocked)
    }
    
    @Test func testMouseMoveExactlyAtThresholdStaysManipulate() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0)))
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(0, 6, 0))) == manipulateOpen)
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(0, 3, 4))) == manipulateOpen)
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(0, 6.01, 0))) == navigateLocked)
    }
    
    @Test func testMouseDragLatchesNavigateAfterReturningUnderThreshold() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0, 10, 10)))
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(0, 30, 10))) == navigateLocked)
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(0, 10, 10))) == navigateLocked)
        #expect(router.handle(.up(pointerType: .mouse, pointerId: 0)) == navigateLocked)
    }
    
    @Test func testMouseClickWithoutDragEndsManipulate() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0)))
        #expect(router.handle(.up(pointerType: .mouse, pointerId: 0)) == manipulateLocked)
    }
    
    @Test func testMouseCancelAfterDragReportsNavigate() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0)))
        _ = router.handle(.move(pointerType: .mouse, pointer: p(0, 50, 0)))
        #expect(router.handle(.cancel(pointerType: .mouse, pointerId: 0)) == navigateLocked)
    }
    
    @Test func testMouseCancelWithoutDragReportsManipulate() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0)))
        #expect(router.handle(.cancel(pointerType: .mouse, pointerId: 0)) == manipulateLocked)
    }
    
    @Test func testMouseEventsForUnknownPointerAreUndecided() {
        let router = PointerRouter()
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(7, 50, 0))) == .undecided)
        #expect(router.handle(.up(pointerType: .mouse, pointerId: 7)) == .undecided)
        #expect(router.handle(.cancel(pointerType: .mouse, pointerId: 7)) == .undecided)
        
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0)))
        _ = router.handle(.up(pointerType: .mouse, pointerId: 0))
        #expect(router.handle(.up(pointerType: .mouse, pointerId: 0)) == .undecided)
    }
    
    @Test func testMousePointersAreTrackedIndependently() {
        let router = PointerRouter()
        _ = router.handle(.down(pointerType: .mouse, pointer: p(0)))
        _ = router.handle(.down(pointerType: .mouse, pointer: p(1)))
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(0, 50, 0))) == navigateLocked)
        #expect(router.handle(.move(pointerType: .mouse, pointer: p(1, 1, 0))) == manipulateOpen)
        #expect(router.handle(.up(pointerType: .mouse, pointerId: 1)) == manipulateLocked)
    }
}
