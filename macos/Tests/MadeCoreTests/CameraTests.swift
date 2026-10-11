import XCTest
import simd
@testable import MadeCore

final class CameraTests: XCTestCase {
    
    // MARK: - Initial State
    
    func testInitialCameraState() {
        let camera = Camera()
        XCTAssertEqual(camera.target, SIMD3<Float>(0, 0, 10))
        let expectedPos = Orientation.defaultViewDirection * 150.0
        XCTAssertEqual(camera.position.x, expectedPos.x, accuracy: 1e-4)
        XCTAssertEqual(camera.position.y, expectedPos.y, accuracy: 1e-4)
        XCTAssertEqual(camera.position.z, expectedPos.z, accuracy: 1e-4)
        
        let dist = simd_length(camera.position - camera.target)
        XCTAssertGreaterThan(dist, camera.minDistance)
        XCTAssertLessThan(dist, camera.maxDistance)
    }
    
    // MARK: - Orbit Tests
    
    func testOrbitChangesAzimuthAndElevation() {
        let camera = Camera()
        let initialDist = simd_length(camera.position - camera.target)
        
        let orbited = Camera.orbit(camera: camera, deltaAzimuth: 0.5, deltaElevation: 0.2)
        let orbitedDist = simd_length(orbited.position - orbited.target)
        
        XCTAssertEqual(orbited.target, camera.target)
        XCTAssertEqual(orbitedDist, initialDist, accuracy: 1e-3)
        XCTAssertNotEqual(orbited.position, camera.position)
    }
    
    func testOrbitZeroMovementLeavesCameraUnchanged() {
        let camera = Camera()
        let orbited = Camera.orbit(camera: camera, deltaAzimuth: 0.0, deltaElevation: 0.0)
        XCTAssertEqual(orbited, camera)
    }
    
    func testOrbitPitchStopsBeforePoleSoViewNeverFlips() {
        let camera = Camera()
        
        // Excessive upward elevation delta (+10 radians)
        let highCamera = Camera.orbit(camera: camera, deltaAzimuth: 0.0, deltaElevation: 10.0)
        let highVec = highCamera.position - highCamera.target
        let highDist = simd_length(highVec)
        let highElevation = asin(highVec.z / highDist)
        XCTAssertLessThanOrEqual(highElevation, camera.maxPitch + 1e-5)
        XCTAssertLessThan(highElevation, Float.pi / 2.0) // Strictly below north pole
        
        // Excessive downward elevation delta (-10 radians)
        let lowCamera = Camera.orbit(camera: camera, deltaAzimuth: 0.0, deltaElevation: -10.0)
        let lowVec = lowCamera.position - lowCamera.target
        let lowDist = simd_length(lowVec)
        let lowElevation = asin(lowVec.z / lowDist)
        XCTAssertGreaterThanOrEqual(lowElevation, camera.minPitch - 1e-5)
        XCTAssertGreaterThan(lowElevation, -Float.pi / 2.0) // Strictly above south pole
    }
    
    // MARK: - Pan Tests
    
    func testPanMovesPositionAndTargetEqually() {
        let camera = Camera()
        let initialDist = simd_length(camera.position - camera.target)
        
        let panned = Camera.pan(camera: camera, deltaX: 50.0, deltaY: -30.0)
        let pannedDist = simd_length(panned.position - panned.target)
        
        // Target and position shifted by the exact same offset
        let posOffset = panned.position - camera.position
        let targetOffset = panned.target - camera.target
        XCTAssertEqual(posOffset.x, targetOffset.x, accuracy: 1e-4)
        XCTAssertEqual(posOffset.y, targetOffset.y, accuracy: 1e-4)
        XCTAssertEqual(posOffset.z, targetOffset.z, accuracy: 1e-4)
        
        // Distance is strictly preserved
        XCTAssertEqual(pannedDist, initialDist, accuracy: 1e-4)
    }
    
    func testPanZeroMovementLeavesCameraUnchanged() {
        let camera = Camera()
        let panned = Camera.pan(camera: camera, deltaX: 0.0, deltaY: 0.0)
        XCTAssertEqual(panned, camera)
    }
    
    // MARK: - Zoom Tests
    
    func testZoomChangesDistance() {
        let camera = Camera()
        let initialDist = simd_length(camera.position - camera.target)
        
        // Zoom in: factor > 1 decreases distance
        let zoomedIn = Camera.zoom(camera: camera, factor: 1.5)
        let inDist = simd_length(zoomedIn.position - zoomedIn.target)
        XCTAssertLessThan(inDist, initialDist)
        XCTAssertEqual(zoomedIn.target, camera.target)
        
        // Zoom out: factor < 1 increases distance
        let zoomedOut = Camera.zoom(camera: camera, factor: 0.5)
        let outDist = simd_length(zoomedOut.position - zoomedOut.target)
        XCTAssertGreaterThan(outDist, initialDist)
        XCTAssertEqual(zoomedOut.target, camera.target)
    }
    
    func testZoomStopsAtMinAndMaxDistance() {
        let camera = Camera()
        
        // Zoom in excessively
        let extremeIn = Camera.zoom(camera: camera, factor: 10000.0)
        let inDist = simd_length(extremeIn.position - extremeIn.target)
        XCTAssertEqual(inDist, camera.minDistance, accuracy: 1e-3)
        
        // Zoom out excessively
        let extremeOut = Camera.zoom(camera: camera, factor: 0.0001)
        let outDist = simd_length(extremeOut.position - extremeOut.target)
        XCTAssertEqual(outDist, camera.maxDistance, accuracy: 1e-3)
    }
    
    func testZoomZeroOrOneLeavesCameraUnchanged() {
        let camera = Camera()
        XCTAssertEqual(Camera.zoom(camera: camera, factor: 1.0), camera)
        XCTAssertEqual(Camera.zoom(camera: camera, deltaDistance: 0.0), camera)
    }
    
    // MARK: - View Orientation & No Roll Invariant
    
    func testViewKeepsPlusZWorldUpWithNoRollAfterGestureSequence() {
        var camera = Camera()
        
        // Perform a series of mixed navigation gestures
        camera = Camera.orbit(camera: camera, deltaAzimuth: 1.2, deltaElevation: 0.4)
        camera = Camera.pan(camera: camera, deltaX: 30, deltaY: -20)
        camera = Camera.zoom(camera: camera, factor: 1.3)
        camera = Camera.orbit(camera: camera, deltaAzimuth: -2.1, deltaElevation: -0.6)
        camera = Camera.pan(camera: camera, deltaX: -15, deltaY: 10)
        camera = Camera.zoom(camera: camera, factor: 0.8)
        
        // Build view matrix with world up +Z
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        
        // Right vector is row 0 of the column-major view matrix: (columns.0.x, columns.1.x, columns.2.x).
        // In a turntable Z-up camera, the horizontal right vector lies strictly in the XY plane:
        // its Z component must be 0 (no camera roll).
        let rightVector = SIMD3<Float>(viewMatrix.columns.0.x, viewMatrix.columns.1.x, viewMatrix.columns.2.x)
        XCTAssertEqual(rightVector.z, 0.0, accuracy: 1e-5, "Camera right vector must have 0 Z component for level horizon (zero roll)")
        
        // Camera up vector is row 1: (columns.0.y, columns.1.y, columns.2.y).
        // In +Z world up, its Z component must be positive.
        let upVector = SIMD3<Float>(viewMatrix.columns.0.y, viewMatrix.columns.1.y, viewMatrix.columns.2.y)
        XCTAssertGreaterThan(upVector.z, 0.0, "Camera up vector must point in positive Z hemisphere")
    }
    
    func testCancelledGestureLeavesValidCamera() {
        let camera = Camera()
        
        // Mid-drag orbit cancelled
        let partiallyOrbited = Camera.orbit(camera: camera, deltaAzimuth: 0.3, deltaElevation: 0.2)
        XCTAssertFalse(partiallyOrbited.position.x.isNaN)
        XCTAssertFalse(partiallyOrbited.position.y.isNaN)
        XCTAssertFalse(partiallyOrbited.position.z.isNaN)
        XCTAssertFalse(partiallyOrbited.position.x.isInfinite)
        XCTAssertFalse(partiallyOrbited.position.y.isInfinite)
        XCTAssertFalse(partiallyOrbited.position.z.isInfinite)
    }
    
    // MARK: - PointerRouter Tests
    
    func testPointerRouterClickVsDragThreshold() {
        let router = PointerRouter()
        
        // Mouse down at (100, 100)
        let down = router.handle(.down(pointerType: .mouse, pointer: ArbiterPointer(pointerId: 0, x: 100, y: 100)))
        XCTAssertNil(down.mode)
        XCTAssertFalse(down.locked)
        
        // Small move <= 6 px (e.g. 3 px dx) -> manipulate, not locked
        let smallMove = router.handle(.move(pointerType: .mouse, pointer: ArbiterPointer(pointerId: 0, x: 103, y: 100)))
        XCTAssertEqual(smallMove.mode, .manipulate)
        XCTAssertFalse(smallMove.locked)
        
        // Drag past threshold > 6 px (e.g. 10 px dx) -> navigate, locked
        let dragMove = router.handle(.move(pointerType: .mouse, pointer: ArbiterPointer(pointerId: 0, x: 110, y: 100)))
        XCTAssertEqual(dragMove.mode, .navigate)
        XCTAssertTrue(dragMove.locked)
        
        // Mouse up completes navigate gesture
        let up = router.handle(.up(pointerType: .mouse, pointerId: 0))
        XCTAssertEqual(up.mode, .navigate)
        XCTAssertTrue(up.locked)
    }
    
    func testPointerRouterScrollAndMagnifyEvents() {
        let router = PointerRouter()
        
        // Non-zero scroll is navigate
        let scrollDecision = router.handle(.scroll(deltaX: 10, deltaY: 20))
        XCTAssertEqual(scrollDecision.mode, .navigate)
        XCTAssertTrue(scrollDecision.locked)
        
        // Zero scroll is undecided
        let zeroScroll = router.handle(.scroll(deltaX: 0, deltaY: 0))
        XCTAssertNil(zeroScroll.mode)
        XCTAssertFalse(zeroScroll.locked)
        
        // Non-unit magnify is navigate
        let magDecision = router.handle(.magnify(factor: 1.2))
        XCTAssertEqual(magDecision.mode, .navigate)
        XCTAssertTrue(magDecision.locked)
        
        // Unit magnify is undecided
        let unitMag = router.handle(.magnify(factor: 1.0))
        XCTAssertNil(unitMag.mode)
        XCTAssertFalse(unitMag.locked)
    }
    
    func testPointerRouterPenAlwaysManipulate() {
        let router = PointerRouter()
        let down = router.handle(.down(pointerType: .pen, pointer: ArbiterPointer(pointerId: 1, x: 50, y: 50)))
        XCTAssertEqual(down.mode, .manipulate)
        XCTAssertTrue(down.locked)
        
        let move = router.handle(.move(pointerType: .pen, pointer: ArbiterPointer(pointerId: 1, x: 150, y: 150)))
        XCTAssertEqual(move.mode, .manipulate)
        XCTAssertTrue(move.locked)
    }
    
    // MARK: - Presets and Orthographic Tests
    
    func testCameraPresets() {
        for perspective in ViewportPerspective.allCases {
            let camera = Camera.preset(perspective)
            XCTAssertEqual(camera.target, Camera.defaultTarget)
            let dist = simd_length(camera.position - camera.target)
            XCTAssertEqual(dist, 150.0, accuracy: 1e-2)
        }
        
        let top = Camera.preset(.top)
        XCTAssertGreaterThan(top.position.z, top.target.z)
        
        let front = Camera.preset(.front)
        XCTAssertLessThan(front.position.y, front.target.y)
        
        let right = Camera.preset(.right)
        XCTAssertGreaterThan(right.position.x, right.target.x)
    }
    
    func testMakeOrthographicProjection() {
        let ortho = Orientation.makeOrthographic(left: -100, right: 100, bottom: -50, top: 50, nearZ: 0.1, farZ: 1000.0)
        // Check diagonal elements
        XCTAssertEqual(ortho.columns.0.x, 2.0 / 200.0, accuracy: 1e-5)
        XCTAssertEqual(ortho.columns.1.y, 2.0 / 100.0, accuracy: 1e-5)
        XCTAssertEqual(ortho.columns.3.w, 1.0, accuracy: 1e-5)
    }
}
