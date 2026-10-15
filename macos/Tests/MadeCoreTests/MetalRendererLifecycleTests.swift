import Testing
import Foundation
import Metal
import simd
@testable import MadeCore

@MainActor
@Suite struct MetalRendererLifecycleTests {
    private func makePayload() -> MeshPayload {
        EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 20, depth: 20, height: 20))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testInstallMeshAndVisibility() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let solidId = SolidId("box-test-1")
        let payload = makePayload()
        let color = SIMD4<Float>(0.2, 0.4, 0.8, 1.0)
        let transform = Transform(position: SIMD3<Float>(10, 20, 30))

        #expect(renderer.meshes[solidId] == nil)
        let installed = renderer.installMesh(payload, for: solidId, transform: transform, color: color, isHidden: false)
        #expect(installed)
        #expect(renderer.meshes[solidId] != nil)
        #expect(renderer.meshes[solidId]?.transform == transform)
        #expect(renderer.meshes[solidId]?.candidateMesh.transform == transform)
        #expect(renderer.meshes[solidId]?.color == color)
        #expect(!renderer.hiddenSolidIds.contains(solidId))

        // Re-install with isHidden: true
        let hiddenInstalled = renderer.installMesh(payload, for: solidId, transform: transform, color: color, isHidden: true)
        #expect(hiddenInstalled)
        #expect(renderer.hiddenSolidIds.contains(solidId))

        // Re-install with isHidden: false
        let unhiddenInstalled = renderer.installMesh(payload, for: solidId, transform: transform, color: color, isHidden: false)
        #expect(unhiddenInstalled)
        #expect(!renderer.hiddenSolidIds.contains(solidId))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testUpdateTransformInPlace() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let solidId = SolidId("box-transform-test")
        let payload = makePayload()
        #expect(renderer.installMesh(payload, for: solidId, transform: .identity, color: SIMD4<Float>(1, 1, 1, 1), isHidden: false))

        let newTransform = Transform(
            position: SIMD3<Float>(5, -10, 15),
            rotation: simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 0, 1)),
            scale: SIMD3<Float>(2, 2, 2)
        )

        let updated = renderer.updateTransform(newTransform, for: solidId)
        #expect(updated)
        #expect(renderer.meshes[solidId]?.transform == newTransform)
        #expect(renderer.meshes[solidId]?.candidateMesh.transform == newTransform)

        // Updating transform for non-existent solid returns false
        #expect(!renderer.updateTransform(newTransform, for: SolidId("non-existent")))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testUpdateColorInPlace() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let solidId = SolidId("box-color-test")
        let payload = makePayload()
        let initialColor = SIMD4<Float>(0.2, 0.4, 0.8, 1.0)
        #expect(renderer.installMesh(payload, for: solidId, transform: .identity, color: initialColor, isHidden: false))
        #expect(renderer.meshes[solidId]?.color == initialColor)

        let newColor = SIMD4<Float>(0.9, 0.1, 0.1, 1.0)
        let updated = renderer.updateColor(newColor, for: solidId)
        #expect(updated)
        #expect(renderer.meshes[solidId]?.color == newColor)

        // Updating color for non-existent solid returns false
        #expect(!renderer.updateColor(newColor, for: SolidId("non-existent")))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRemoveMeshPrunesRendererAndHiddenState() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let solidId = SolidId("box-remove-test")
        let payload = makePayload()
        #expect(renderer.installMesh(payload, for: solidId, transform: .identity, color: SIMD4<Float>(1, 1, 1, 1), isHidden: true))
        #expect(renderer.meshes[solidId] != nil)
        #expect(renderer.hiddenSolidIds.contains(solidId))

        let removed = renderer.removeMesh(for: solidId)
        #expect(removed)
        #expect(renderer.meshes[solidId] == nil)
        #expect(!renderer.hiddenSolidIds.contains(solidId))

        // Second removal returns false
        #expect(!renderer.removeMesh(for: solidId))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRemoveThenReaddCreatesFreshMeshWithNewId() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let id1 = SolidId("box-1")
        let id2 = SolidId("box-2")
        let payload = makePayload()

        #expect(renderer.installMesh(payload, for: id1, transform: Transform(position: SIMD3<Float>(-25, 0, 0)), color: SIMD4<Float>(1, 0, 0, 1), isHidden: false))
        #expect(renderer.meshes[id1] != nil)

        #expect(renderer.removeMesh(for: id1))
        #expect(renderer.meshes[id1] == nil)

        #expect(renderer.installMesh(payload, for: id2, transform: Transform(position: SIMD3<Float>(25, 0, 0)), color: SIMD4<Float>(0, 1, 0, 1), isHidden: false))
        #expect(renderer.meshes[id1] == nil)
        #expect(renderer.meshes[id2] != nil)
        #expect(renderer.meshes[id2]?.transform.position == SIMD3<Float>(25, 0, 0))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRenderPassWithRotatedAndScaledTransform() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = makePayload()
        let solidId = SolidId("box-rotated-scaled")
        let rot = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let transform = Transform(
            position: SIMD3<Float>(10, -5, 0),
            rotation: rot,
            scale: SIMD3<Float>(1.5, 0.8, 2.0)
        )

        #expect(renderer.installMesh(payload, for: solidId, transform: transform, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0), isHidden: false))

        // Verify modelMatrix and normalMatrix calculation
        let m = transform.matrix
        let expectedPos = transform.position
        #expect(m.columns.3 == SIMD4<Float>(expectedPos, 1.0))

        let nm = transform.normalMatrix
        // Under non-singular scale, columns are scaled by inverse
        let rot3 = simd_float3x3(rot)
        #expect(abs(nm.columns.0.x - rot3.columns.0.x / 1.5) < 1e-5)
        #expect(abs(nm.columns.1.y - rot3.columns.1.y / 0.8) < 1e-5)
        #expect(abs(nm.columns.2.z - rot3.columns.2.z / 2.0) < 1e-5)

        // Capture snapshot to verify render pass executes without error and binds uniforms cleanly
        let snapshot = await renderer.captureSnapshotPngBase64()
        #expect(snapshot != nil)
    }

    @Test func testTransformMatrixAndNormalMatrixSingularityFallback() {
        let rot = simd_quatf(angle: Float.pi / 3, axis: simd_normalize(SIMD3<Float>(1, 1, 1)))
        let singularTransform = Transform(
            position: SIMD3<Float>(1, 2, 3),
            rotation: rot,
            scale: SIMD3<Float>(0, 1, 1)
        )
        // With scale.x == 0, normalMatrix falls back to simd_float3x3(rotation)
        let expected = simd_float3x3(rot)
        let actual = singularTransform.normalMatrix
        #expect(actual == expected)

        let nearZeroTransform = Transform(
            position: SIMD3<Float>(0, 0, 0),
            rotation: rot,
            scale: SIMD3<Float>(1e-7, 1, 1)
        )
        #expect(nearZeroTransform.normalMatrix == expected)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testFiftyAddAndRemoveCyclesLeavesMeshesAtStartingCount() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        let payload = makePayload()
        let startingCount = renderer.meshes.count

        for i in 0..<50 {
            let solidId = SolidId("box-cycle-\(i)")
            #expect(renderer.installMesh(payload, for: solidId, transform: .identity, color: SIMD4<Float>(1, 1, 1, 1), isHidden: false))
            #expect(renderer.removeMesh(for: solidId))
        }

        #expect(renderer.meshes.count == startingCount)
    }
}
