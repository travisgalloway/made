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
            
            let lookAt = Orientation.makeLookAt(eye: camera.position, target: camera.target)
            #expect(!lookAt.columns.0.x.isNaN && !lookAt.columns.0.x.isInfinite)
            #expect(!lookAt.columns.1.y.isNaN && !lookAt.columns.1.y.isInfinite)
            #expect(!lookAt.columns.2.z.isNaN && !lookAt.columns.2.z.isInfinite)
            #expect(!lookAt.columns.3.w.isNaN && !lookAt.columns.3.w.isInfinite)
        }
        
        let top = Camera.preset(.top)
        #expect(top.position.z > top.target.z)
        
        let bottom = Camera.preset(.bottom)
        #expect(bottom.position.z < bottom.target.z)
        
        let front = Camera.preset(.front)
        #expect(front.position.y < front.target.y)
        
        let back = Camera.preset(.back)
        #expect(back.position.y > back.target.y)
        
        let right = Camera.preset(.right)
        #expect(right.position.x > right.target.x)
        
        let left = Camera.preset(.left)
        #expect(left.position.x < left.target.x)
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

    // MARK: - BL-VPT-08: Orbit about Pivot Tests

    @Test func testOrbitAroundPivotKeepsPivotScreenProjectionStationary() {
        let camera = Camera(position: SIMD3<Float>(100, -120, 80), target: SIMD3<Float>(0, 0, 10))
        let pivot = SIMD3<Float>(25, -15, 30) // Off-center from camera.target
        let aspect: Float = 800.0 / 600.0
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)

        // Compute NDC of pivot before orbit
        let viewMatrixBefore = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let p4Before = projMatrix * viewMatrixBefore * SIMD4<Float>(pivot, 1.0)
        let ndcBefore = SIMD2<Float>(p4Before.x, p4Before.y) / p4Before.w

        // Perform multiple orbits with different deltas
        let testDeltas: [(Float, Float)] = [
            (0.3, 0.2),
            (-0.5, 0.15),
            (0.8, -0.4),
            (-1.2, -0.25)
        ]

        for (dAz, dEl) in testDeltas {
            let orbited = Camera.orbit(camera: camera, deltaAzimuth: dAz, deltaElevation: dEl, pivot: pivot)
            let viewMatrixAfter = Orientation.makeLookAt(eye: orbited.position, target: orbited.target, up: Orientation.worldUp)
            let p4After = projMatrix * viewMatrixAfter * SIMD4<Float>(pivot, 1.0)
            let ndcAfter = SIMD2<Float>(p4After.x, p4After.y) / p4After.w

            #expect(abs(ndcAfter.x - ndcBefore.x) <= 1e-4, "Pivot NDC X must be stationary under orbit (deltaAz: \(dAz), deltaEl: \(dEl))")
            #expect(abs(ndcAfter.y - ndcBefore.y) <= 1e-4, "Pivot NDC Y must be stationary under orbit (deltaAz: \(dAz), deltaEl: \(dEl))")
        }
    }

    @Test func testOrbitAroundPivotPreservesEyeToTargetAndEyeToPivotDistances() {
        let camera = Camera(position: SIMD3<Float>(60, -90, 70), target: SIMD3<Float>(5, 10, 15))
        let pivot = SIMD3<Float>(-30, 20, 25)

        let initialEyeToTarget = simd_length(camera.position - camera.target)
        let initialEyeToPivot = simd_length(camera.position - pivot)
        let initialTargetToPivot = simd_length(camera.target - pivot)

        let orbited = Camera.orbit(camera: camera, deltaAzimuth: 1.1, deltaElevation: -0.4, pivot: pivot)

        let orbitedEyeToTarget = simd_length(orbited.position - orbited.target)
        let orbitedEyeToPivot = simd_length(orbited.position - pivot)
        let orbitedTargetToPivot = simd_length(orbited.target - pivot)

        #expect(abs(orbitedEyeToTarget - initialEyeToTarget) <= 1e-4, "Eye-to-target distance must be strictly preserved")
        #expect(abs(orbitedEyeToPivot - initialEyeToPivot) <= 1e-4, "Eye-to-pivot distance must be strictly preserved")
        #expect(abs(orbitedTargetToPivot - initialTargetToPivot) <= 1e-4, "Target-to-pivot distance must be strictly preserved")
        #expect(orbited.target != camera.target, "Target must rotate rigidly when orbiting around an off-center pivot")
        #expect(orbited.position != camera.position)
    }

    @Test func testOrbitAroundPivotPitchClampAndNoRoll() {
        let camera = Camera(position: SIMD3<Float>(80, -80, 50), target: SIMD3<Float>(0, 0, 0))
        let pivot = SIMD3<Float>(15, -10, 5)

        // Excessive upward elevation delta (+10.0 radians)
        let highCamera = Camera.orbit(camera: camera, deltaAzimuth: 0.5, deltaElevation: 10.0, pivot: pivot)
        let highViewMatrix = Orientation.makeLookAt(eye: highCamera.position, target: highCamera.target, up: Orientation.worldUp)
        let highRight = SIMD3<Float>(highViewMatrix.columns.0.x, highViewMatrix.columns.1.x, highViewMatrix.columns.2.x)
        #expect(abs(highRight.z) <= 1e-4, "High camera right vector must have 0 Z component (no roll)")

        let highForward = highCamera.position - highCamera.target
        let highElev = asin(min(max(highForward.z / simd_length(highForward), -1.0), 1.0))
        #expect(highElev <= camera.maxPitch + 1e-4)

        // Excessive downward elevation delta (-10.0 radians)
        let lowCamera = Camera.orbit(camera: camera, deltaAzimuth: -0.5, deltaElevation: -10.0, pivot: pivot)
        let lowViewMatrix = Orientation.makeLookAt(eye: lowCamera.position, target: lowCamera.target, up: Orientation.worldUp)
        let lowRight = SIMD3<Float>(lowViewMatrix.columns.0.x, lowViewMatrix.columns.1.x, lowViewMatrix.columns.2.x)
        #expect(abs(lowRight.z) <= 1e-4, "Low camera right vector must have 0 Z component (no roll)")

        let lowForward = lowCamera.position - lowCamera.target
        let lowElev = asin(min(max(lowForward.z / simd_length(lowForward), -1.0), 1.0))
        #expect(lowElev >= camera.minPitch - 1e-4)
    }

    // MARK: - BL-VPT-08: Zoom to Cursor Tests

    @Test func testPerspectiveZoomToCursorKeepsPointStationaryOnScreen() {
        let camera = Camera(position: SIMD3<Float>(0, -120, 60), target: SIMD3<Float>(0, 0, 10))
        let aspect: Float = 800.0 / 600.0
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)

        let initialView = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let cursorRay = screenPointToRay(
            screenPoint: SIMD2<Float>(550, 420),
            viewportSize: CGSize(width: 800, height: 600),
            viewMatrix: initialView,
            projectionMatrix: projMatrix
        )!

        // A test 3D point along this cursor ray
        let testPoint = cursorRay.origin + cursorRay.direction * 80.0

        let p4Before = projMatrix * initialView * SIMD4<Float>(testPoint, 1.0)
        let ndcBefore = SIMD2<Float>(p4Before.x, p4Before.y) / p4Before.w

        // Zoom in by factor 1.6
        let zoomed = Camera.zoom(camera: camera, factor: 1.6, cursorRay: cursorRay)
        let newView = Orientation.makeLookAt(eye: zoomed.position, target: zoomed.target, up: Orientation.worldUp)
        let p4After = projMatrix * newView * SIMD4<Float>(testPoint, 1.0)
        let ndcAfter = SIMD2<Float>(p4After.x, p4After.y) / p4After.w

        #expect(abs(ndcAfter.x - ndcBefore.x) <= 1e-4, "Cursor point NDC X must remain stationary on screen")
        #expect(abs(ndcAfter.y - ndcBefore.y) <= 1e-4, "Cursor point NDC Y must remain stationary on screen")

        // View direction f must be invariant (no yaw/pitch/roll drift)
        let initF = simd_normalize(camera.target - camera.position)
        let zoomedF = simd_normalize(zoomed.target - zoomed.position)
        #expect(abs(initF.x - zoomedF.x) <= 1e-4)
        #expect(abs(initF.y - zoomedF.y) <= 1e-4)
        #expect(abs(initF.z - zoomedF.z) <= 1e-4)
    }

    @Test func testPerspectiveZoomToCursorClampsToMinAndMaxDistance() {
        let camera = Camera(position: SIMD3<Float>(0, -100, 50), target: SIMD3<Float>(0, 0, 10))
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: 4.0 / 3.0, nearZ: 0.1, farZ: 1000.0)
        let cursorRay = screenPointToRay(
            screenPoint: SIMD2<Float>(500, 350),
            viewportSize: CGSize(width: 800, height: 600),
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )!

        // Extreme zoom in (factor)
        let extremeIn = Camera.zoom(camera: camera, factor: 10000.0, cursorRay: cursorRay)
        let distIn = simd_length(extremeIn.position - extremeIn.target)
        #expect(abs(distIn - camera.minDistance) <= 1e-3)

        // Extreme zoom out (factor)
        let extremeOut = Camera.zoom(camera: camera, factor: 0.0001, cursorRay: cursorRay)
        let distOut = simd_length(extremeOut.position - extremeOut.target)
        #expect(abs(distOut - camera.maxDistance) <= 1e-3)

        // Extreme zoom in (deltaDistance)
        let deltaIn = Camera.zoom(camera: camera, deltaDistance: -10000.0, cursorRay: cursorRay)
        #expect(abs(simd_length(deltaIn.position - deltaIn.target) - camera.minDistance) <= 1e-3)

        // Extreme zoom out (deltaDistance)
        let deltaOut = Camera.zoom(camera: camera, deltaDistance: 10000.0, cursorRay: cursorRay)
        #expect(abs(simd_length(deltaOut.position - deltaOut.target) - camera.maxDistance) <= 1e-3)
    }

    @Test func testOrthographicZoomToCursorKeepsPointStationaryOnScreen() {
        let camera = Camera(projection: .orthographic)
        let aspect: Float = 800.0 / 600.0
        let baseDist = max(10.0, simd_length(camera.position - camera.target))
        let dist = max(1.0, baseDist * camera.orthographicScale)
        let halfH = dist * 0.4
        let halfW = halfH * aspect
        let proj = Orientation.makeOrthographic(left: -halfW, right: halfW, bottom: -halfH, top: halfH, nearZ: 0.1, farZ: 1000.0)
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)

        let cursorRay = screenPointToRay(
            screenPoint: SIMD2<Float>(520, 240),
            viewportSize: CGSize(width: 800, height: 600),
            viewMatrix: viewMatrix,
            projectionMatrix: proj
        )!

        let testPoint = cursorRay.intersectPlaneZZero()!
        let p4Before = proj * viewMatrix * SIMD4<Float>(testPoint, 1.0)
        let ndcBefore = SIMD2<Float>(p4Before.x, p4Before.y) / p4Before.w

        // Zoom in by factor 2.0
        let zoomed = Camera.zoom(camera: camera, factor: 2.0, cursorRay: cursorRay)
        let newBaseDist = max(10.0, simd_length(zoomed.position - zoomed.target))
        let newDist = max(1.0, newBaseDist * zoomed.orthographicScale)
        let newHalfH = newDist * 0.4
        let newHalfW = newHalfH * aspect
        let newProj = Orientation.makeOrthographic(left: -newHalfW, right: newHalfW, bottom: -newHalfH, top: newHalfH, nearZ: 0.1, farZ: 1000.0)
        let newView = Orientation.makeLookAt(eye: zoomed.position, target: zoomed.target, up: Orientation.worldUp)

        let p4After = newProj * newView * SIMD4<Float>(testPoint, 1.0)
        let ndcAfter = SIMD2<Float>(p4After.x, p4After.y) / p4After.w

        #expect(abs(ndcAfter.x - ndcBefore.x) <= 1e-4, "Orthographic cursor point NDC X must remain stationary on screen")
        #expect(abs(ndcAfter.y - ndcBefore.y) <= 1e-4, "Orthographic cursor point NDC Y must remain stationary on screen")
    }

    @Test func testOrthographicZoomToCursorClampsToMinAndMaxDistance() {
        let camera = Camera(projection: .orthographic)
        let aspect: Float = 800.0 / 600.0
        let baseDist = max(10.0, simd_length(camera.position - camera.target))
        let dist = max(1.0, baseDist * camera.orthographicScale)
        let halfH = dist * 0.4
        let halfW = halfH * aspect
        let proj = Orientation.makeOrthographic(left: -halfW, right: halfW, bottom: -halfH, top: halfH, nearZ: 0.1, farZ: 1000.0)
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)

        let cursorRay = screenPointToRay(
            screenPoint: SIMD2<Float>(400, 300),
            viewportSize: CGSize(width: 800, height: 600),
            viewMatrix: viewMatrix,
            projectionMatrix: proj
        )!

        let effectiveDist = simd_length(camera.position - camera.target)
        let extremeIn = Camera.zoom(camera: camera, factor: 10000.0, cursorRay: cursorRay)
        #expect(abs(extremeIn.orthographicScale * effectiveDist - camera.minDistance) <= 1e-3)

        let extremeOut = Camera.zoom(camera: camera, factor: 0.0001, cursorRay: cursorRay)
        #expect(abs(extremeOut.orthographicScale * effectiveDist - camera.maxDistance) <= 1e-3)
    }
    
    // MARK: - View Snapping & Normal Alignment Tests
    
    @Test func testCameraAlignedToNormal() {
        let target = SIMD3<Float>(10, 20, 30)
        let distance: Float = 150.0
        
        let testNormals: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(-1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, -1, 0),
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(0, 0, -1),
            simd_normalize(SIMD3<Float>(1, 1, 1)),
            simd_normalize(SIMD3<Float>(-0.5, 0.8, -0.3)),
            simd_normalize(SIMD3<Float>(0.0001, 0.0001, 0.9999))
        ]
        
        for normal in testNormals {
            let camera = Camera.alignedToNormal(normal, target: target, distance: distance)
            #expect(camera.target == target)
            
            let viewDir = simd_normalize(camera.target - camera.position)
            let diff = simd_length(viewDir - (-normal))
            #expect(diff < 0.001, "View direction differs from negated normal by \(diff) for normal \(normal)")
            
            let lookAt = Orientation.makeLookAt(eye: camera.position, target: camera.target)
            #expect(!lookAt.columns.0.x.isNaN && !lookAt.columns.0.x.isInfinite)
            #expect(!lookAt.columns.1.y.isNaN && !lookAt.columns.1.y.isInfinite)
            #expect(!lookAt.columns.2.z.isNaN && !lookAt.columns.2.z.isInfinite)
            #expect(!lookAt.columns.3.w.isNaN && !lookAt.columns.3.w.isInfinite)
        }
        
        let topNormal = SIMD3<Float>(0, 0, 1)
        let cam1 = Camera.alignedToNormal(topNormal, target: target, distance: distance, allowFlip: true)
        let dir1 = simd_normalize(cam1.position - target)
        #expect(dir1.z > 0.99)
        
        let cam2 = Camera.alignedToNormal(topNormal, target: target, distance: distance, currentCamera: cam1, allowFlip: true)
        let dir2 = simd_normalize(cam2.position - target)
        #expect(dir2.z < -0.99)
        
        let cam3 = Camera.alignedToNormal(topNormal, target: target, distance: distance, currentCamera: cam2, allowFlip: true)
        let dir3 = simd_normalize(cam3.position - target)
        #expect(dir3.z > 0.99)
        
        let camNoFlip = Camera.alignedToNormal(topNormal, target: target, distance: distance, currentCamera: cam1, allowFlip: false)
        let dirNoFlip = simd_normalize(camNoFlip.position - target)
        #expect(dirNoFlip.z > 0.99)
        
        let degenerate = Camera.alignedToNormal(.zero, target: target)
        #expect(degenerate.target == target)
    }
    
    @Test func testCameraInterpolate() {
        let fromTarget = SIMD3<Float>(0, 0, 0)
        let toTarget = SIMD3<Float>(10, 20, 30)
        let from = Camera(position: SIMD3<Float>(150, 0, 0), target: fromTarget)
        let to = Camera(position: toTarget + SIMD3<Float>(0, 150, 0), target: toTarget)
        
        let c0 = Camera.interpolate(from: from, to: to, t: 0.0)
        #expect(c0.position == from.position)
        #expect(c0.target == from.target)
        
        let cNeg = Camera.interpolate(from: from, to: to, t: -0.5)
        #expect(cNeg.position == from.position)
        
        let c1 = Camera.interpolate(from: from, to: to, t: 1.0)
        #expect(c1.position == to.position)
        #expect(c1.target == to.target)
        
        let cOver = Camera.interpolate(from: from, to: to, t: 1.5)
        #expect(cOver.position == to.position)
        
        let cHalf = Camera.interpolate(from: from, to: to, t: 0.5)
        #expect(abs(cHalf.target.x - 5.0) < 1e-4)
        #expect(abs(cHalf.target.y - 10.0) < 1e-4)
        #expect(abs(cHalf.target.z - 15.0) < 1e-4)
        
        let distAtHalf = simd_length(cHalf.position - cHalf.target)
        #expect(abs(distAtHalf - 150.0) < 1e-3, "Camera distance plunged to \(distAtHalf)")
        
        let camFront = Camera(position: SIMD3<Float>(0, -150, 0), target: .zero)
        let camBack = Camera(position: SIMD3<Float>(0, 150, 0), target: .zero)
        let camFlipMid = Camera.interpolate(from: camFront, to: camBack, t: 0.5)
        let distFlipMid = simd_length(camFlipMid.position - camFlipMid.target)
        #expect(abs(distFlipMid - 150.0) < 1e-3, "180° flip plunged through origin to distance \(distFlipMid)")
        #expect(!camFlipMid.position.x.isNaN && !camFlipMid.position.y.isNaN && !camFlipMid.position.z.isNaN)
    }
    
    @Test func testCandidateMeshFaceNormalAndCentroid() {
        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let candidate = CandidateMesh(id: SolidId("box"), payload: payload)
        
        let n0 = try! #require(candidate.faceNormal(forFaceId: 0))
        #expect(abs(n0.x) < 1e-4 && abs(n0.y) < 1e-4 && abs(n0.z - 1.0) < 1e-4)
        let c0 = try! #require(candidate.faceCentroid(forFaceId: 0))
        #expect(abs(c0.x) < 1e-4 && abs(c0.y) < 1e-4 && abs(c0.z - 10.0) < 1e-4)
        
        let n1 = try! #require(candidate.faceNormal(forFaceId: 1))
        #expect(abs(n1.x) < 1e-4 && abs(n1.y) < 1e-4 && abs(n1.z - (-1.0)) < 1e-4)
        let c1 = try! #require(candidate.faceCentroid(forFaceId: 1))
        #expect(abs(c1.x) < 1e-4 && abs(c1.y) < 1e-4 && abs(c1.z - (-10.0)) < 1e-4)
        
        let n2 = try! #require(candidate.faceNormal(forFaceId: 2))
        #expect(abs(n2.x - 1.0) < 1e-4 && abs(n2.y) < 1e-4 && abs(n2.z) < 1e-4)
        let c2 = try! #require(candidate.faceCentroid(forFaceId: 2))
        #expect(abs(c2.x - 20.0) < 1e-4 && abs(c2.y) < 1e-4 && abs(c2.z) < 1e-4)
        
        let n3 = try! #require(candidate.faceNormal(forFaceId: 3))
        #expect(abs(n3.x - (-1.0)) < 1e-4 && abs(n3.y) < 1e-4 && abs(n3.z) < 1e-4)
        
        let n4 = try! #require(candidate.faceNormal(forFaceId: 4))
        #expect(abs(n4.x) < 1e-4 && abs(n4.y - 1.0) < 1e-4 && abs(n4.z) < 1e-4)
        
        let n5 = try! #require(candidate.faceNormal(forFaceId: 5))
        #expect(abs(n5.x) < 1e-4 && abs(n5.y - (-1.0)) < 1e-4 && abs(n5.z) < 1e-4)
        
        #expect(candidate.faceNormal(forFaceId: 99) == nil)
        #expect(candidate.faceCentroid(forFaceId: 99) == nil)
        
        let rotX = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let transformed = CandidateMesh(
            id: SolidId("box"),
            payload: payload,
            transform: Transform(position: SIMD3<Float>(10, 20, 30), rotation: rotX)
        )
        let tn0 = try! #require(transformed.faceNormal(forFaceId: 0))
        #expect(abs(tn0.x) < 1e-4 && abs(tn0.y - (-1.0)) < 1e-4 && abs(tn0.z) < 1e-4)
        let tc0 = try! #require(transformed.faceCentroid(forFaceId: 0))
        #expect(abs(tc0.x - 10.0) < 1e-4 && abs(tc0.y - 10.0) < 1e-4 && abs(tc0.z - 30.0) < 1e-4)
    }
}
