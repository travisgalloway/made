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
}
