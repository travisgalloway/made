import Testing
import Foundation
@testable import MadeCore

@Suite struct GestureArbiterTests {
    @Test func testSinglePointerDragLocksManipulateOnMove() {
        let arbiter = GestureArbiter()
        
        let down = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        #expect(down.mode == nil)
        #expect(!down.locked)
        
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 20, y: 20)))
        #expect(move.mode == .manipulate)
        #expect(move.locked)
        
        let up = arbiter.handle(.up(pointerId: 1))
        #expect(up.mode == .manipulate)
        #expect(up.locked)
        
        // Reset after all pointers released
        #expect(arbiter.current().mode == nil)
    }
    
    @Test func testTwoPointersLockNavigateOnMove() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 30, y: 30)))
        
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 15, y: 15)))
        #expect(move.mode == .navigate)
        #expect(move.locked)
    }
    
    @Test func testPureTapDecidesAtReleaseUsingPeakCount() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 30, y: 30)))
        
        // Finger 2 releases first without any move event having occurred
        let up1 = arbiter.handle(.up(pointerId: 2))
        #expect(!up1.locked)
        
        // Finger 1 releases - should still decide .navigate because peak count was 2
        let up2 = arbiter.handle(.up(pointerId: 1))
        #expect(up2.mode == .navigate)
        #expect(up2.locked)
    }
    
    @Test func testSecondPointerJoiningLockedGestureDoesNotChangeMode() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        let move1 = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 20, y: 20)))
        #expect(move1.mode == .manipulate)
        #expect(move1.locked)
        
        // Second pointer joins locked manipulate gesture
        let down2 = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 100, y: 100)))
        #expect(down2.mode == .manipulate)
        #expect(down2.locked)
        
        let move2 = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 2, x: 105, y: 105)))
        #expect(move2.mode == .manipulate)
        #expect(move2.locked)
        
        let up1 = arbiter.handle(.up(pointerId: 1))
        #expect(up1.mode == .manipulate)
        #expect(up1.locked)
        
        let up2 = arbiter.handle(.up(pointerId: 2))
        #expect(up2.mode == .manipulate)
        #expect(up2.locked)
        
        // Resets after all pointers lift
        #expect(arbiter.current().mode == nil)
    }
    
    @Test func testPointersDroppingInLockedNavigateDoesNotChangeMode() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 30, y: 30)))
        
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 15, y: 15)))
        #expect(move.mode == .navigate)
        #expect(move.locked)
        
        // One pointer lifts, dropping to single pointer
        let up2 = arbiter.handle(.up(pointerId: 2))
        #expect(up2.mode == .navigate)
        #expect(up2.locked)
        
        // Remaining pointer continues moving: mode stays navigate
        let move2 = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 25, y: 25)))
        #expect(move2.mode == .navigate)
        #expect(move2.locked)
        
        let up1 = arbiter.handle(.up(pointerId: 1))
        #expect(up1.mode == .navigate)
        #expect(up1.locked)
        #expect(arbiter.current().mode == nil)
    }
    
    @Test func testSinglePointerPureTapDecidesManipulateAtRelease() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        let up = arbiter.handle(.up(pointerId: 1))
        #expect(up.mode == .manipulate)
        #expect(up.locked)
        #expect(arbiter.current().mode == nil)
    }
    
    @Test func testCancelledGestureResetsArbiter() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 20, y: 20)))
        #expect(arbiter.current().locked)
        
        let cancel = arbiter.handle(.cancel(pointerId: 1))
        #expect(cancel.mode == .manipulate)
        #expect(arbiter.current().mode == nil)
    }
}
