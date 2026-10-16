import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct PickingTests {
    @Test func testRayIntersectsBoxBounds() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let result = pickSolid(ray: ray, candidateMeshes: [mesh])

        #expect(result != nil)
        #expect(result?.id == SolidId("box-1"))
        #expect(abs((result?.distance ?? 0) - 40.0) < 1e-4)
        #expect(abs((result?.hitPoint.x ?? 0) - 0.0) < 1e-4)
        #expect(abs((result?.hitPoint.y ?? 0) - (-10.0)) < 1e-4)
        #expect(abs((result?.hitPoint.z ?? 0) - 0.0) < 1e-4)
    }

    @Test func testRayMissesBoxBounds() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        // Ray aimed above the box
        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 50), direction: SIMD3<Float>(0, 1, 0))
        let result = pickSolid(ray: ray, candidateMeshes: [mesh])

        #expect(result == nil)
    }

    @Test func testRayIntersectsCylinderBounds() {
        let payload = NativeGeometryGenerator.generateCylinder(radius: 10, height: 20, segments: 16)
        let mesh = CandidateMesh(id: SolidId("cyl-1"), payload: payload)

        // Ray aimed down from above the top cap (Z = 10)
        let ray = Ray3D(origin: SIMD3<Float>(0, 0, 50), direction: SIMD3<Float>(0, 0, -1))
        let result = pickSolid(ray: ray, candidateMeshes: [mesh])

        #expect(result != nil)
        #expect(result?.id == SolidId("cyl-1"))
        #expect(abs((result?.distance ?? 0) - 40.0) < 1e-4)
        #expect(abs((result?.hitPoint.z ?? 0) - 10.0) < 1e-4)
    }

    @Test func testOverlappingSolidsSelectsNearest() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let nearSolid = CandidateMesh(
            id: SolidId("box-near"),
            payload: payload,
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        let farSolid = CandidateMesh(
            id: SolidId("box-far"),
            payload: payload,
            transform: Transform(position: SIMD3<Float>(0, 50, 0))
        )

        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))

        // Order in array should not matter: nearest hit must always win
        let result1 = pickSolid(ray: ray, candidateMeshes: [nearSolid, farSolid])
        #expect(result1?.id == SolidId("box-near"))
        #expect(abs((result1?.distance ?? 0) - 40.0) < 1e-4)

        let result2 = pickSolid(ray: ray, candidateMeshes: [farSolid, nearSolid])
        #expect(result2?.id == SolidId("box-near"))
        #expect(abs((result2?.distance ?? 0) - 40.0) < 1e-4)
    }

    @Test func testCandidateMeshTransformRespected() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let translatedMesh = CandidateMesh(
            id: SolidId("box-translated"),
            payload: payload,
            transform: Transform(position: SIMD3<Float>(50, 0, 0))
        )

        // Ray aimed at untranslated origin should miss
        let rayOrigin = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        #expect(pickSolid(ray: rayOrigin, candidateMeshes: [translatedMesh]) == nil)

        // Ray aimed at translated location (X = 50) should hit
        let rayTarget = Ray3D(origin: SIMD3<Float>(50, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let result = pickSolid(ray: rayTarget, candidateMeshes: [translatedMesh])
        #expect(result != nil)
        #expect(result?.id == SolidId("box-translated"))
        #expect(abs((result?.distance ?? 0) - 40.0) < 1e-4)
        #expect(abs((result?.hitPoint.x ?? 0) - 50.0) < 1e-4)

        // Test scaled mesh
        let scaledMesh = CandidateMesh(
            id: SolidId("box-scaled"),
            payload: payload,
            transform: Transform(scale: SIMD3<Float>(2, 2, 2))
        )
        // Scaled box has bounds [-20, 20] along each axis.
        // A ray at Y = 15 should hit the scaled box (which extends to Y = 20) but would miss an unscaled box (Y max 10).
        let rayOffset = Ray3D(origin: SIMD3<Float>(15, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let scaledHit = pickSolid(ray: rayOffset, candidateMeshes: [scaledMesh])
        #expect(scaledHit != nil)
        #expect(scaledHit?.id == SolidId("box-scaled"))
        #expect(abs((scaledHit?.distance ?? 0) - 30.0) < 1e-4) // hit front face at Y = -20: -50 to -20 is 30
    }

    @Test func testScreenPointToRayPicking() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(
            id: SolidId("center-box"),
            payload: payload,
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )

        let viewportSize = CGSize(width: 800, height: 600)
        let eye = SIMD3<Float>(0, -100, 100)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )

        // Center pointer picks the box at target (0, 0, 0)
        let centerPointer = SIMD2<Float>(400, 300)
        let hitId = pickSolidAtPointer(
            pointer: centerPointer,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            candidateMeshes: [mesh]
        )
        #expect(hitId == SolidId("center-box"))

        // Corner pointer pointing into empty space picks nothing
        let cornerPointer = SIMD2<Float>(10, 10)
        let missId = pickSolidAtPointer(
            pointer: cornerPointer,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            candidateMeshes: [mesh]
        )
        #expect(missId == nil)
    }

    // MARK: - BL-VPT-08: Orbit Pivot Resolution Tests

    @Test func testResolveOrbitPivotPrecedenceHitOverSelection() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-hit"), payload: payload)

        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let selectedCenter = SIMD3<Float>(100, 100, 100)
        let fallbackTarget = SIMD3<Float>(0, 0, 10)

        let pivot = resolveOrbitPivot(
            ray: ray,
            candidateMeshes: [mesh],
            selectedSolidCenter: selectedCenter,
            fallbackTarget: fallbackTarget
        )

        // Hit point is on front face of box: (0, -10, 0)
        #expect(abs(pivot.x - 0.0) <= 1e-4)
        #expect(abs(pivot.y - (-10.0)) <= 1e-4)
        #expect(abs(pivot.z - 0.0) <= 1e-4)
        #expect(pivot != selectedCenter, "Geometry hit under cursor must take precedence over active selection center")
        #expect(pivot != fallbackTarget)
    }

    @Test func testResolveOrbitPivotPrecedenceSelectionOverGround() {
        // Ray aimed into empty space, but angled down so it intersects ground plane Z=0
        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 50), direction: simd_normalize(SIMD3<Float>(0, 1, -1)))
        let groundHit = ray.intersectPlaneZZero()
        #expect(groundHit != nil)

        let selectedCenter = SIMD3<Float>(35, -20, 15)
        let fallbackTarget = SIMD3<Float>(0, 0, 10)

        let pivot = resolveOrbitPivot(
            ray: ray,
            candidateMeshes: [], // Misses geometry
            selectedSolidCenter: selectedCenter,
            fallbackTarget: fallbackTarget
        )

        #expect(pivot == selectedCenter, "Active selection center must take precedence over ground plane intersection")
        #expect(pivot != groundHit)
        #expect(pivot != fallbackTarget)
    }

    @Test func testResolveOrbitPivotPrecedenceGroundOverTarget() {
        // Ray aimed into empty space, intersecting ground plane Z=0 at distance <= 1000
        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 50), direction: simd_normalize(SIMD3<Float>(0, 1, -1)))
        let groundHit = ray.intersectPlaneZZero()
        #expect(groundHit != nil)
        #expect(simd_length(groundHit! - ray.origin) <= 1000.0)

        let fallbackTarget = SIMD3<Float>(0, 0, 10)

        let pivot = resolveOrbitPivot(
            ray: ray,
            candidateMeshes: [], // Misses geometry
            selectedSolidCenter: nil, // No selection
            fallbackTarget: fallbackTarget
        )

        #expect(abs(pivot.x - groundHit!.x) <= 1e-4, "Ground plane hit must take precedence over fallback target")
        #expect(abs(pivot.y - groundHit!.y) <= 1e-4)
        #expect(abs(pivot.z - 0.0) <= 1e-4)
        #expect(pivot != fallbackTarget)
    }

    @Test func testResolveOrbitPivotFarGroundPlaneFallsBackToTarget() {
        // Ray hitting ground plane far away (> 1000 units)
        // Origin at (0, 0, 10), direction with tiny downward slope so ground hit distance is >> 1000
        let farRay = Ray3D(origin: SIMD3<Float>(0, 0, 10), direction: simd_normalize(SIMD3<Float>(10000, 0, -1)))
        let farGroundHit = farRay.intersectPlaneZZero()
        #expect(farGroundHit != nil)
        #expect(simd_length(farGroundHit! - farRay.origin) > 1000.0)

        let fallbackTarget = SIMD3<Float>(0, 0, 10)

        let farPivot = resolveOrbitPivot(
            ray: farRay,
            candidateMeshes: [],
            selectedSolidCenter: nil,
            fallbackTarget: fallbackTarget
        )
        #expect(farPivot == fallbackTarget, "Ground plane hit beyond maxGroundPlaneDistance must fall back to target")

        // Ray parallel to ground plane (direction.z == 0)
        let parallelRay = Ray3D(origin: SIMD3<Float>(0, 0, 10), direction: SIMD3<Float>(0, 1, 0))
        let parallelPivot = resolveOrbitPivot(
            ray: parallelRay,
            candidateMeshes: [],
            selectedSolidCenter: nil,
            fallbackTarget: fallbackTarget
        )
        #expect(parallelPivot == fallbackTarget, "Parallel ray must fall back to target")

        // Ray pointing away from ground plane (direction.z > 0 from z > 0)
        let upwardRay = Ray3D(origin: SIMD3<Float>(0, 0, 10), direction: SIMD3<Float>(0, 0, 1))
        let upwardPivot = resolveOrbitPivot(
            ray: upwardRay,
            candidateMeshes: [],
            selectedSolidCenter: nil,
            fallbackTarget: fallbackTarget
        )
        #expect(upwardPivot == fallbackTarget, "Upward ray must fall back to target")

        // Ray is nil
        let nilRayPivot = resolveOrbitPivot(
            ray: nil,
            candidateMeshes: [],
            selectedSolidCenter: nil,
            fallbackTarget: fallbackTarget
        )
        #expect(nilRayPivot == fallbackTarget, "Nil ray must fall back to target")
    }

    // MARK: - Sub-Element Picking Tests (BL-SEL-02)

    @Test func testPickSubElementFace() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        // Ray aimed directly into the center of the front face (y = -10)
        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let result = pickSubElement(ray: ray, candidateMeshes: [mesh])

        #expect(result != nil)
        #expect(result?.solidId == SolidId("box-1"))
        #expect(result?.elementType == SubelementType.face)
        #expect(abs((result?.distance ?? 0) - 40.0) < 1e-4)
    }

    @Test func testPickSubElementEdgePrecedence() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        let eye = SIMD3<Float>(0, -50, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: .zero, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 1000.0)
        let viewport = CGSize(width: 800, height: 600)

        // Point on top-front edge: (0, -10, 10)
        let edgeMidpoint = SIMD3<Float>(0, -10, 10)
        let screenPt = projectToScreen(point: edgeMidpoint, viewProjectionMatrix: projMatrix * viewMatrix, viewportSize: viewport)!
        let ray = screenPointToRay(screenPoint: screenPt, viewportSize: viewport, viewMatrix: viewMatrix, projectionMatrix: projMatrix)!

        let result = pickSubElement(
            ray: ray,
            candidateMeshes: [mesh],
            screenTolerancePx: 8.0,
            viewportSize: viewport,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )

        #expect(result != nil)
        #expect(result?.solidId == SolidId("box-1"))
        #expect(result?.elementType == SubelementType.edge)
    }

    @Test func testPickSubElementVertexPrecedence() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        let eye = SIMD3<Float>(0, -50, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: .zero, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 1000.0)
        let viewport = CGSize(width: 800, height: 600)

        // Corner vertex at (10, -10, 10)
        let cornerVertex = SIMD3<Float>(10, -10, 10)
        let screenPt = projectToScreen(point: cornerVertex, viewProjectionMatrix: projMatrix * viewMatrix, viewportSize: viewport)!
        let ray = screenPointToRay(screenPoint: screenPt, viewportSize: viewport, viewMatrix: viewMatrix, projectionMatrix: projMatrix)!

        let result = pickSubElement(
            ray: ray,
            candidateMeshes: [mesh],
            screenTolerancePx: 8.0,
            viewportSize: viewport,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )

        #expect(result != nil)
        #expect(result?.solidId == SolidId("box-1"))
        #expect(result?.elementType == SubelementType.vertex)
    }

    @Test func testPickSubElementMiss() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        // Ray pointing completely away
        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 50), direction: SIMD3<Float>(0, 1, 0))
        let result = pickSubElement(ray: ray, candidateMeshes: [mesh])

        #expect(result == nil)
    }
}
