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
}
