import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct CameraTests {
    
    // MARK: - Initial State
    
    @Test func testInitialCameraState() {
        let camera = Camera()
        #expect(camera.target == (SIMD3<Float>(0, 0, 10)))
        let expectedPos = Orientation.defaultViewDirection * 150.0
        #expect(abs(camera.position.x - expectedPos.x) <= 1e-4)
        #expect(abs(camera.position.y - expectedPos.y) <= 1e-4)
        #expect(abs(camera.position.z - expectedPos.z) <= 1e-4)
        
        let dist = simd_length(camera.position - camera.target)
        #expect(dist > camera.minDistance)
        #expect(dist < camera.maxDistance)
    }
    
    // MARK: - Orbit Tests
    
    @Test func testOrbitChangesAzimuthAndElevation() {
        let camera = Camera()
        let initialDist = simd_length(camera.position - camera.target)
        
        let orbited = Camera.orbit(camera: camera, deltaAzimuth: 0.5, deltaElevation: 0.2)
        let orbitedDist = simd_length(orbited.position - orbited.target)
        
        #expect(orbited.target == camera.target)
        #expect(abs(orbitedDist - initialDist) <= 1e-3)
        #expect(orbited.position != camera.position)
    }
    
    @Test func testOrbitZeroMovementLeavesCameraUnchanged() {
        let camera = Camera()
        let orbited = Camera.orbit(camera: camera, deltaAzimuth: 0.0, deltaElevation: 0.0)
        #expect(orbited == camera)
    }
    
    @Test func testOrbitPitchStopsBeforePoleSoViewNeverFlips() {
        let camera = Camera()
        
        // Excessive upward elevation delta (+10 radians)
        let highCamera = Camera.orbit(camera: camera, deltaAzimuth: 0.0, deltaElevation: 10.0)
        let highVec = highCamera.position - highCamera.target
        let highDist = simd_length(highVec)
        let highElevation = asin(highVec.z / highDist)
        #expect(highElevation <= (camera.maxPitch + 1e-5))
        #expect(highElevation < (Float.pi / 2.0)) // Strictly below north pole
        
        // Excessive downward elevation delta (-10 radians)
        let lowCamera = Camera.orbit(camera: camera, deltaAzimuth: 0.0, deltaElevation: -10.0)
        let lowVec = lowCamera.position - lowCamera.target
        let lowDist = simd_length(lowVec)
        let lowElevation = asin(lowVec.z / lowDist)
        #expect(lowElevation >= (camera.minPitch - 1e-5))
        #expect(lowElevation > (-Float.pi / 2.0)) // Strictly above south pole
    }
    
    // MARK: - Pan Tests
    
    @Test func testPanMovesPositionAndTargetEqually() {
        let camera = Camera()
        let initialDist = simd_length(camera.position - camera.target)
        
        let panned = Camera.pan(camera: camera, deltaX: 50.0, deltaY: -30.0)
        let pannedDist = simd_length(panned.position - panned.target)
        
        // Target and position shifted by the exact same offset
        let posOffset = panned.position - camera.position
        let targetOffset = panned.target - camera.target
        #expect(abs(posOffset.x - targetOffset.x) <= 1e-4)
        #expect(abs(posOffset.y - targetOffset.y) <= 1e-4)
        #expect(abs(posOffset.z - targetOffset.z) <= 1e-4)
        
        // Distance is strictly preserved
        #expect(abs(pannedDist - initialDist) <= 1e-4)
    }
    
    @Test func testPanZeroMovementLeavesCameraUnchanged() {
        let camera = Camera()
        let panned = Camera.pan(camera: camera, deltaX: 0.0, deltaY: 0.0)
        #expect(panned == camera)
    }
    
    // MARK: - Zoom Tests
    
    @Test func testZoomChangesDistance() {
        let camera = Camera()
        let initialDist = simd_length(camera.position - camera.target)
        
        // Zoom in: factor > 1 decreases distance
        let zoomedIn = Camera.zoom(camera: camera, factor: 1.5)
        let inDist = simd_length(zoomedIn.position - zoomedIn.target)
        #expect(inDist < initialDist)
        #expect(zoomedIn.target == camera.target)
        
        // Zoom out: factor < 1 increases distance
        let zoomedOut = Camera.zoom(camera: camera, factor: 0.5)
        let outDist = simd_length(zoomedOut.position - zoomedOut.target)
        #expect(outDist > initialDist)
        #expect(zoomedOut.target == camera.target)
    }
    
    @Test func testZoomStopsAtMinAndMaxDistance() {
        let camera = Camera()
        
        // Zoom in excessively
        let extremeIn = Camera.zoom(camera: camera, factor: 10000.0)
        let inDist = simd_length(extremeIn.position - extremeIn.target)
        #expect(abs(inDist - camera.minDistance) <= 1e-3)
        
        // Zoom out excessively
        let extremeOut = Camera.zoom(camera: camera, factor: 0.0001)
        let outDist = simd_length(extremeOut.position - extremeOut.target)
        #expect(abs(outDist - camera.maxDistance) <= 1e-3)
    }
    
    @Test func testZoomZeroOrOneLeavesCameraUnchanged() {
        let camera = Camera()
        #expect(Camera.zoom(camera: camera, factor: 1.0) == camera)
        #expect(Camera.zoom(camera: camera, deltaDistance: 0.0) == camera)
    }
    
    // MARK: - View Orientation & No Roll Invariant
    
    @Test func testViewKeepsPlusZWorldUpWithNoRollAfterGestureSequence() {
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
        #expect(abs(rightVector.z - 0.0) <= 1e-5, "Camera right vector must have 0 Z component for level horizon (zero roll)")
        
        // Camera up vector is row 1: (columns.0.y, columns.1.y, columns.2.y).
        // In +Z world up, its Z component must be positive.
        let upVector = SIMD3<Float>(viewMatrix.columns.0.y, viewMatrix.columns.1.y, viewMatrix.columns.2.y)
        #expect(upVector.z > 0.0, "Camera up vector must point in positive Z hemisphere")
    }
    
    @Test func testCancelledGestureLeavesValidCamera() {
        let camera = Camera()
        
        // Mid-drag orbit cancelled
        let partiallyOrbited = Camera.orbit(camera: camera, deltaAzimuth: 0.3, deltaElevation: 0.2)
        #expect(!partiallyOrbited.position.x.isNaN)
        #expect(!partiallyOrbited.position.y.isNaN)
        #expect(!partiallyOrbited.position.z.isNaN)
        #expect(!partiallyOrbited.position.x.isInfinite)
        #expect(!partiallyOrbited.position.y.isInfinite)
        #expect(!partiallyOrbited.position.z.isInfinite)
    }
    
    // MARK: - PointerRouter Tests
    
    @Test func testPointerRouterClickVsDragThreshold() {
        let router = PointerRouter()
        
        // Mouse down at (100, 100)
        let down = router.handle(.down(pointerType: .mouse, pointer: ArbiterPointer(pointerId: 0, x: 100, y: 100)))
        #expect(down.mode == nil)
        #expect(!down.locked)
        
        // Small move <= 6 px (e.g. 3 px dx) -> manipulate, not locked
        let smallMove = router.handle(.move(pointerType: .mouse, pointer: ArbiterPointer(pointerId: 0, x: 103, y: 100)))
        #expect(smallMove.mode == .manipulate)
        #expect(!smallMove.locked)
        
        // Drag past threshold > 6 px (e.g. 10 px dx) -> navigate, locked
        let dragMove = router.handle(.move(pointerType: .mouse, pointer: ArbiterPointer(pointerId: 0, x: 110, y: 100)))
        #expect(dragMove.mode == .navigate)
        #expect(dragMove.locked)
        
        // Mouse up completes navigate gesture
        let up = router.handle(.up(pointerType: .mouse, pointerId: 0))
        #expect(up.mode == .navigate)
        #expect(up.locked)
    }
    
    @Test func testPointerRouterScrollAndMagnifyEvents() {
        let router = PointerRouter()
        
        // Non-zero scroll is navigate
        let scrollDecision = router.handle(.scroll(deltaX: 10, deltaY: 20))
        #expect(scrollDecision.mode == .navigate)
        #expect(scrollDecision.locked)
        
        // Zero scroll is undecided
        let zeroScroll = router.handle(.scroll(deltaX: 0, deltaY: 0))
        #expect(zeroScroll.mode == nil)
        #expect(!zeroScroll.locked)
        
        // Non-unit magnify is navigate
        let magDecision = router.handle(.magnify(factor: 1.2))
        #expect(magDecision.mode == .navigate)
        #expect(magDecision.locked)
        
        // Unit magnify is undecided
        let unitMag = router.handle(.magnify(factor: 1.0))
        #expect(unitMag.mode == nil)
        #expect(!unitMag.locked)
    }
    
    @Test func testPointerRouterPenAlwaysManipulate() {
        let router = PointerRouter()
        let down = router.handle(.down(pointerType: .pen, pointer: ArbiterPointer(pointerId: 1, x: 50, y: 50)))
        #expect(down.mode == .manipulate)
        #expect(down.locked)
        
        let move = router.handle(.move(pointerType: .pen, pointer: ArbiterPointer(pointerId: 1, x: 150, y: 150)))
        #expect(move.mode == .manipulate)
        #expect(move.locked)
    }
    
    // MARK: - Presets and Orthographic Tests
    
    @Test func testCameraPresets() {
        for perspective in ViewportPerspective.allCases {
            let camera = Camera.preset(perspective)
            #expect(camera.target == Camera.defaultTarget)
            let dist = simd_length(camera.position - camera.target)
            #expect(abs(dist - 150.0) <= 1e-2)
        }
        
        let top = Camera.preset(.top)
        #expect(top.position.z > top.target.z)
        
        let front = Camera.preset(.front)
        #expect(front.position.y < front.target.y)
        
        let right = Camera.preset(.right)
        #expect(right.position.x > right.target.x)
    }
    
    @Test func testMakeOrthographicProjection() {
        let ortho = Orientation.makeOrthographic(left: -100, right: 100, bottom: -50, top: 50, nearZ: 0.1, farZ: 1000.0)
        // Check diagonal elements
        #expect(abs(ortho.columns.0.x - (2.0 / 200.0)) <= 1e-5)
        #expect(abs(ortho.columns.1.y - (2.0 / 100.0)) <= 1e-5)
        #expect(abs(ortho.columns.3.w - 1.0) <= 1e-5)
    }

    @Test func testOrthographicZoomScalesViewVolumeWithoutMovingEye() {
        let camera = Camera(projection: .orthographic)
        let initialPos = camera.position
        let initialTarget = camera.target
        let initialScale = camera.orthographicScale
        #expect(initialScale == 1.0)
        
        // Zoom in by factor > 1: orthographicScale decreases (narrows view volume)
        let zoomedIn = Camera.zoom(camera: camera, factor: 2.0)
        #expect(zoomedIn.position == initialPos)
        #expect(zoomedIn.target == initialTarget)
        #expect(zoomedIn.orthographicScale < initialScale)
        #expect(abs(zoomedIn.orthographicScale - 0.5) <= 1e-4)
        
        // Zoom out by factor < 1: orthographicScale increases (widens view volume)
        let zoomedOut = Camera.zoom(camera: camera, factor: 0.5)
        #expect(zoomedOut.position == initialPos)
        #expect(zoomedOut.target == initialTarget)
        #expect(zoomedOut.orthographicScale > initialScale)
        #expect(abs(zoomedOut.orthographicScale - 2.0) <= 1e-4)
        
        // Zoom via deltaDistance: delta < 0 zooms in, delta > 0 zooms out
        let zoomedDeltaIn = Camera.zoom(camera: camera, deltaDistance: -20.0)
        #expect(zoomedDeltaIn.position == initialPos)
        #expect(zoomedDeltaIn.target == initialTarget)
        #expect(zoomedDeltaIn.orthographicScale < initialScale)
        
        let zoomedDeltaOut = Camera.zoom(camera: camera, deltaDistance: 20.0)
        #expect(zoomedDeltaOut.position == initialPos)
        #expect(zoomedDeltaOut.target == initialTarget)
        #expect(zoomedDeltaOut.orthographicScale > initialScale)
        
        // Extreme zooms clamp within minDistance and maxDistance effective bounds
        let forward = camera.position - camera.target
        let dist = simd_length(forward)
        let extremeIn = Camera.zoom(camera: camera, factor: 10000.0)
        #expect(extremeIn.position == initialPos)
        #expect(extremeIn.target == initialTarget)
        #expect(abs(extremeIn.orthographicScale * dist - camera.minDistance) <= 1e-3)
        
        let extremeOut = Camera.zoom(camera: camera, factor: 0.0001)
        #expect(extremeOut.position == initialPos)
        #expect(extremeOut.target == initialTarget)
        #expect(abs(extremeOut.orthographicScale * dist - camera.maxDistance) <= 1e-3)
    }

    @Test func testOrbitDragPreservesTargetAcrossProjectionSwitch() {
        var camera = Camera(projection: .perspective)
        let initialDist = simd_length(camera.position - camera.target)
        let initialTarget = camera.target
        
        // Orbit in perspective
        camera = Camera.orbit(camera: camera, deltaAzimuth: 0.4, deltaElevation: 0.2)
        let distAfterFirstOrbit = simd_length(camera.position - camera.target)
        #expect(abs(distAfterFirstOrbit - initialDist) <= 1e-3)
        #expect(camera.target == initialTarget)
        
        // Switch projection to orthographic
        camera.projection = .orthographic
        
        // Orbit in orthographic
        let cameraAfterSwitchOrbit = Camera.orbit(camera: camera, deltaAzimuth: -0.3, deltaElevation: 0.1)
        let distAfterSecondOrbit = simd_length(cameraAfterSwitchOrbit.position - cameraAfterSwitchOrbit.target)
        #expect(abs(distAfterSecondOrbit - initialDist) <= 1e-3)
        #expect(cameraAfterSwitchOrbit.target == initialTarget)
        #expect(!cameraAfterSwitchOrbit.position.x.isNaN)
        #expect(!cameraAfterSwitchOrbit.position.y.isNaN)
        #expect(!cameraAfterSwitchOrbit.position.z.isNaN)
        #expect(cameraAfterSwitchOrbit.projection == .orthographic)
    }
}
