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
    
    @Test func testPenAlwaysLocksManipulate() {
        let router = PointerRouter()
        #expect(!router.isPenActive)
        
        let down = router.handle(.down(pointerType: .pen, pointer: p(10, 5, 5)))
        #expect(down == manipulateLocked)
        #expect(router.isPenActive)
        
        let move = router.handle(.move(pointerType: .pen, pointer: p(10, 25, 30)))
        #expect(move == manipulateLocked)
        #expect(router.isPenActive)
        
        let up = router.handle(.up(pointerType: .pen, pointerId: 10))
        #expect(up == manipulateLocked)
        #expect(!router.isPenActive)
    }
    
    @Test func testPalmRejectionSingleTouchWhilePenIsActiveSuppressed() {
        let router = PointerRouter()
        // Pencil is touching the screen
        _ = router.handle(.down(pointerType: .pen, pointer: p(10, 100, 100)))
        #expect(router.isPenActive)
        
        // Single palm contact occurs
        _ = router.handle(.down(pointerType: .touch, pointer: p(1, 10, 10)))
        
        // Palm moves slightly across screen: suppressed as palm contact
        let palmMove = router.handle(.move(pointerType: .touch, pointer: p(1, 15, 12)))
        #expect(palmMove == .undecided)
        #expect(router.arbiter.current() == .undecided)
        
        // Palm lifts: returns undecided, does not trigger a tap/manipulate lock
        let palmUp = router.handle(.up(pointerType: .touch, pointerId: 1))
        #expect(palmUp == .undecided)
        #expect(router.arbiter.current() == .undecided)
        
        // Pen is still active and manipulating
        let penMove = router.handle(.move(pointerType: .pen, pointer: p(10, 120, 120)))
        #expect(penMove == manipulateLocked)
    }
    
    @Test func testTwoFingerNavigateWhilePenIsActive() {
        let router = PointerRouter()
        // Pencil is down
        _ = router.handle(.down(pointerType: .pen, pointer: p(10, 50, 50)))
        #expect(router.isPenActive)
        
        // Two fingers touch down for camera navigation
        _ = router.handle(.down(pointerType: .touch, pointer: p(1, 10, 10)))
        _ = router.handle(.down(pointerType: .touch, pointer: p(2, 40, 40)))
        
        // Two fingers move: locks to navigate
        let touchMove = router.handle(.move(pointerType: .touch, pointer: p(1, 15, 15)))
        #expect(touchMove == navigateLocked)
        #expect(router.arbiter.current() == navigateLocked)
        
        // Finger 2 lifts
        let up2 = router.handle(.up(pointerType: .touch, pointerId: 2))
        #expect(up2 == navigateLocked)
        
        // Finger 1 lifts
        let up1 = router.handle(.up(pointerType: .touch, pointerId: 1))
        #expect(up1 == navigateLocked)
        #expect(router.arbiter.current() == .undecided)
    }
    
    @Test func testPencilReleaseRestoresNormalTouchBehavior() {
        let router = PointerRouter()
        // Pen touches and releases
        _ = router.handle(.down(pointerType: .pen, pointer: p(10)))
        _ = router.handle(.up(pointerType: .pen, pointerId: 10))
        #expect(!router.isPenActive)
        
        // Subsequent single touch drag operates normally (locks manipulate)
        _ = router.handle(.down(pointerType: .touch, pointer: p(1)))
        let move = router.handle(.move(pointerType: .touch, pointer: p(1, 10, 10)))
        #expect(move == manipulateLocked)
        let up = router.handle(.up(pointerType: .touch, pointerId: 1))
        #expect(up == manipulateLocked)
    }
}
