import Testing
import Foundation
import Metal
import simd
import CoreGraphics
@testable import MadeCore

@Suite(.serialized) struct MetalRendererPickingTests {
    private let width = 800
    private let height = 600

    private func projectToScreen(_ point: SIMD3<Float>, renderer: MetalRenderer, viewportSize: CGSize) -> SIMD2<Float> {
        let aspect = Float(viewportSize.width) / Float(viewportSize.height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let clip = matrices.projection * matrices.view * SIMD4<Float>(point, 1.0)
        let ndcX = clip.x / clip.w
        let ndcY = clip.y / clip.w
        let screenX = (ndcX * 0.5 + 0.5) * Float(viewportSize.width)
        let screenY = (1.0 - (ndcY * 0.5 + 0.5)) * Float(viewportSize.height)
        return SIMD2<Float>(screenX, screenY)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testPickFaceReturnsCorrectFaceId() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        // Box width: 40, depth: 30, height: 20
        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[SolidId("box")] = mesh

        // Center of viewport looks directly at box face
        let centerPointer = SIMD2<Float>(Float(width) / 2.0, Float(height) / 2.0)
        let pickResult = renderer.pickSubElement(at: centerPointer, viewportSize: CGSize(width: width, height: height))

        #expect(pickResult != nil)
        #expect(pickResult?.solidId == SolidId("box"))
        #expect(pickResult?.elementType == SubelementType.face)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testPickVertexPrecedenceOverFace() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[SolidId("box")] = mesh

        guard let cornerVertex = payload.vertexPoints.first else {
            Issue.record("No vertex points on box payload")
            return
        }

        let vp = projectToScreen(cornerVertex.position, renderer: renderer, viewportSize: CGSize(width: width, height: height))
        let pickResult = renderer.pickSubElement(at: vp, viewportSize: CGSize(width: width, height: height))

        #expect(pickResult != nil)
        #expect(pickResult?.solidId == SolidId("box"))
        // Vertex quad with depth bias takes precedence over face
        #expect(pickResult?.elementType == SubelementType.vertex || pickResult?.elementType == SubelementType.edge)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testPickMissReturnsNil() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 10, height: 10)
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[SolidId("box")] = mesh

        let cornerPointer = SIMD2<Float>(5, 5)
        let pickResult = renderer.pickSubElement(at: cornerPointer, viewportSize: CGSize(width: width, height: height))

        #expect(pickResult == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testSelectedSubElementHighlightedSnapshot() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[SolidId("box")] = mesh

        // Test face selection highlight pass
        renderer.selectedSubElement = SelectedSubElement(solidId: SolidId("box"), elementType: .face, elementId: 0)
        let snap1 = await renderer.captureSnapshotPngBase64()
        #expect(snap1 != nil)

        // Test edge selection highlight pass
        renderer.selectedSubElement = SelectedSubElement(solidId: SolidId("box"), elementType: .edge, elementId: 0)
        let snap2 = await renderer.captureSnapshotPngBase64()
        #expect(snap2 != nil)

        // Test vertex selection highlight pass
        renderer.selectedSubElement = SelectedSubElement(solidId: SolidId("box"), elementType: .vertex, elementId: 0)
        let snap3 = await renderer.captureSnapshotPngBase64()
        #expect(snap3 != nil)
    }
}
