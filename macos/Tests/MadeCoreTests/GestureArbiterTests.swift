import XCTest
@testable import MadeCore

final class GestureArbiterTests: XCTestCase {
    func testSinglePointerDragLocksManipulateOnMove() {
        let arbiter = GestureArbiter()
        
        let down = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        XCTAssertEqual(down.mode, nil)
        XCTAssertFalse(down.locked)
        
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 20, y: 20)))
        XCTAssertEqual(move.mode, .manipulate)
        XCTAssertTrue(move.locked)
        
        let up = arbiter.handle(.up(pointerId: 1))
        XCTAssertEqual(up.mode, .manipulate)
        XCTAssertTrue(up.locked)
        
        // Reset after all pointers released
        XCTAssertEqual(arbiter.current().mode, nil)
    }
    
    func testTwoPointersLockNavigateOnMove() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 30, y: 30)))
        
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 15, y: 15)))
        XCTAssertEqual(move.mode, .navigate)
        XCTAssertTrue(move.locked)
    }
    
    func testPureTapDecidesAtReleaseUsingPeakCount() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 30, y: 30)))
        
        // Finger 2 releases first without any move event having occurred
        let up1 = arbiter.handle(.up(pointerId: 2))
        XCTAssertFalse(up1.locked)
        
        // Finger 1 releases - should still decide .navigate because peak count was 2
        let up2 = arbiter.handle(.up(pointerId: 1))
        XCTAssertEqual(up2.mode, .navigate)
        XCTAssertTrue(up2.locked)
    }
    
    func testSecondPointerJoiningLockedGestureDoesNotChangeMode() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        let move1 = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 20, y: 20)))
        XCTAssertEqual(move1.mode, .manipulate)
        XCTAssertTrue(move1.locked)
        
        // Second pointer joins locked manipulate gesture
        let down2 = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 100, y: 100)))
        XCTAssertEqual(down2.mode, .manipulate)
        XCTAssertTrue(down2.locked)
        
        let move2 = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 2, x: 105, y: 105)))
        XCTAssertEqual(move2.mode, .manipulate)
        XCTAssertTrue(move2.locked)
        
        let up1 = arbiter.handle(.up(pointerId: 1))
        XCTAssertEqual(up1.mode, .manipulate)
        XCTAssertTrue(up1.locked)
        
        let up2 = arbiter.handle(.up(pointerId: 2))
        XCTAssertEqual(up2.mode, .manipulate)
        XCTAssertTrue(up2.locked)
        
        // Resets after all pointers lift
        XCTAssertEqual(arbiter.current().mode, nil)
    }
    
    func testPointersDroppingInLockedNavigateDoesNotChangeMode() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 2, x: 30, y: 30)))
        
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 15, y: 15)))
        XCTAssertEqual(move.mode, .navigate)
        XCTAssertTrue(move.locked)
        
        // One pointer lifts, dropping to single pointer
        let up2 = arbiter.handle(.up(pointerId: 2))
        XCTAssertEqual(up2.mode, .navigate)
        XCTAssertTrue(up2.locked)
        
        // Remaining pointer continues moving: mode stays navigate
        let move2 = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 25, y: 25)))
        XCTAssertEqual(move2.mode, .navigate)
        XCTAssertTrue(move2.locked)
        
        let up1 = arbiter.handle(.up(pointerId: 1))
        XCTAssertEqual(up1.mode, .navigate)
        XCTAssertTrue(up1.locked)
        XCTAssertEqual(arbiter.current().mode, nil)
    }
    
    func testSinglePointerPureTapDecidesManipulateAtRelease() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        let up = arbiter.handle(.up(pointerId: 1))
        XCTAssertEqual(up.mode, .manipulate)
        XCTAssertTrue(up.locked)
        XCTAssertEqual(arbiter.current().mode, nil)
    }
    
    func testCancelledGestureResetsArbiter() {
        let arbiter = GestureArbiter()
        
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 1, x: 10, y: 10)))
        _ = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 1, x: 20, y: 20)))
        XCTAssertTrue(arbiter.current().locked)
        
        let cancel = arbiter.handle(.cancel(pointerId: 1))
        XCTAssertEqual(cancel.mode, .manipulate)
        XCTAssertEqual(arbiter.current().mode, nil)
    }
}
