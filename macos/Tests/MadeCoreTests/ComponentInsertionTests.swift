import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ComponentInsertionTests {

    @Test func testPendingComponentPlacementCreation() {
        let id = UUID()
        let ref = ComponentReference.internalPart(name: "BracketPart", bodyId: SolidId("part-1"))
        let material = MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1))

        let pending = PendingComponentPlacement(
            id: id,
            name: "Bracket",
            reference: ref,
            material: material
        )

        #expect(pending.id == id)
        #expect(pending.name == "Bracket")
        #expect(pending.reference == ref)
        #expect(pending.material == material)

        let pendingDefaultId = PendingComponentPlacement(
            name: "DefaultIdComponent",
            reference: .externalDocument(url: URL(fileURLWithPath: "/models/part.step"))
        )
        #expect(pendingDefaultId.material == nil)
        #expect(pendingDefaultId.name == "DefaultIdComponent")
    }

    @Test func testResolvePlacementPoint_SurfaceHit() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        // Ray aimed at front face of the box (-10 on Y axis)
        let ray = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let point = ComponentPlacementSolver.resolvePlacementPoint(
            ray: ray,
            candidateMeshes: [mesh],
            fallback: SIMD3<Float>(999, 999, 999)
        )

        #expect(abs(point.x - 0.0) < 1e-4)
        #expect(abs(point.y - (-10.0)) < 1e-4)
        #expect(abs(point.z - 0.0) < 1e-4)
    }

    @Test func testResolvePlacementPoint_GroundPlaneSnapping() {
        // Ray aimed down at an angle hitting the ground plane at Z = 0
        let ray = Ray3D(origin: SIMD3<Float>(10, 20, 30), direction: SIMD3<Float>(0, 0, -1))
        let point = ComponentPlacementSolver.resolvePlacementPoint(
            ray: ray,
            candidateMeshes: [],
            fallback: SIMD3<Float>(999, 999, 999)
        )

        #expect(abs(point.x - 10.0) < 1e-4)
        #expect(abs(point.y - 20.0) < 1e-4)
        #expect(abs(point.z - 0.0) < 1e-4)
    }

    @Test func testResolvePlacementPoint_FallbackWhenRayPointsAway() {
        // Ray aimed upward from above the ground plane, missing all geometry and ground plane
        let upwardRay = Ray3D(origin: SIMD3<Float>(5, 5, 10), direction: SIMD3<Float>(0, 0, 1))
        let fallback = SIMD3<Float>(42, 42, 42)
        let point = ComponentPlacementSolver.resolvePlacementPoint(
            ray: upwardRay,
            candidateMeshes: [],
            fallback: fallback
        )

        #expect(point == fallback)
    }

    @Test func testResolvePlacementPoint_FallbackWhenNilRay() {
        let fallback = SIMD3<Float>(10, 20, 30)
        let point = ComponentPlacementSolver.resolvePlacementPoint(
            ray: nil,
            candidateMeshes: [],
            fallback: fallback
        )

        #expect(point == fallback)
    }

    @Test func testResolvePlacementPoint_DefaultFallbackIsZero() {
        let upwardRay = Ray3D(origin: SIMD3<Float>(5, 5, 10), direction: SIMD3<Float>(0, 0, 1))
        let point = ComponentPlacementSolver.resolvePlacementPoint(
            ray: upwardRay,
            candidateMeshes: []
        )

        #expect(point == .zero)
    }
}
