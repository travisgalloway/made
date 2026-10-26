import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct TopologySelectionTests {
    @Test func testTangentEdgeChainStraightLineSegments() {
        // Build 3 collinear connected edges along X axis: [0,0,0]->[1,0,0], [1,0,0]->[2,0,0], [2,0,0]->[3,0,0]
        let p0 = SIMD3<Float>(0, 0, 0)
        let p1 = SIMD3<Float>(1, 0, 0)
        let p2 = SIMD3<Float>(2, 0, 0)
        let p3 = SIMD3<Float>(3, 0, 0)

        let e0 = EdgePolyline(edgeId: 0, points: [p0, p1], segmentRange: 0..<1)
        let e1 = EdgePolyline(edgeId: 1, points: [p1, p2], segmentRange: 1..<2)
        let e2 = EdgePolyline(edgeId: 2, points: [p2, p3], segmentRange: 2..<3)

        let mesh = CandidateMesh(
            id: SolidId("mesh-1"),
            positions: [p0, p1, p2, p3],
            edges: [],
            edgePolylines: [e0, e1, e2]
        )

        // Seed in middle edge (edgeId: 1)
        let chain = findTangentEdgeChain(seedEdgeId: 1, in: mesh)
        #expect(chain.count == 3)
        let edgeIds = Set(chain.map(\.elementId))
        #expect(edgeIds == [0, 1, 2])
    }

    @Test func testTangentEdgeChainSharpCornerTerminates() {
        // e0 along +X, e1 turns 90 degrees along +Y
        let p0 = SIMD3<Float>(0, 0, 0)
        let p1 = SIMD3<Float>(1, 0, 0)
        let p2 = SIMD3<Float>(1, 1, 0)

        let e0 = EdgePolyline(edgeId: 0, points: [p0, p1], segmentRange: 0..<1)
        let e1 = EdgePolyline(edgeId: 1, points: [p1, p2], segmentRange: 1..<2)

        let mesh = CandidateMesh(
            id: SolidId("mesh-corner"),
            positions: [p0, p1, p2],
            edges: [],
            edgePolylines: [e0, e1]
        )

        let chain = findTangentEdgeChain(seedEdgeId: 0, in: mesh)
        #expect(chain.count == 1)
        #expect(chain.first?.elementId == 0)
    }

    @Test func testTangentEdgeChainClosedPeriodicCylinderRim() {
        let payload = NativeGeometryGenerator.generateCylinder(radius: 10, height: 20, segments: 16)
        let mesh = CandidateMesh(id: SolidId("cyl"), payload: payload)

        // Edge 0 is the top rim circle
        let chain = findTangentEdgeChain(seedEdgeId: 0, in: mesh)
        #expect(chain.count == 1)
        #expect(chain.first?.elementId == 0)
    }

    @Test func testTangentEdgeChainInvalidEdgeReturnsEmpty() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 10, height: 10)
        let mesh = CandidateMesh(id: SolidId("box"), payload: payload)

        let chain = findTangentEdgeChain(seedEdgeId: 999, in: mesh)
        #expect(chain.isEmpty)
    }

    @Test func testEdgeLoopBoxFace() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 10, height: 10)
        let mesh = CandidateMesh(id: SolidId("box"), payload: payload)

        // Edge 4 is on the top face (edges 4, 5, 6, 7)
        let loop = findEdgeLoop(seedEdgeId: 4, in: mesh)
        #expect(loop.count >= 4)
        let edgeIds = Set(loop.map(\.elementId))
        #expect(edgeIds.contains(4))
    }

    @Test func testEdgeLoopClosedCylinderRim() {
        let payload = NativeGeometryGenerator.generateCylinder(radius: 10, height: 20, segments: 16)
        let mesh = CandidateMesh(id: SolidId("cyl"), payload: payload)

        // Edge 0 is closed circular rim
        let loop = findEdgeLoop(seedEdgeId: 0, in: mesh)
        #expect(loop.count == 1)
        #expect(loop.first?.elementId == 0)
    }

    @Test func testEdgeLoopIsolatedEdgeReturnsSeed() {
        let p0 = SIMD3<Float>(0, 0, 0)
        let p1 = SIMD3<Float>(10, 0, 0)
        let e0 = EdgePolyline(edgeId: 42, points: [p0, p1], segmentRange: 0..<1)
        let mesh = CandidateMesh(
            id: SolidId("iso"),
            positions: [p0, p1],
            edges: [],
            edgePolylines: [e0]
        )

        let loop = findEdgeLoop(seedEdgeId: 42, in: mesh)
        #expect(loop.count == 1)
        #expect(loop.first?.elementId == 42)
    }

    @Test func testTangentFaceChainSharpAnglesTerminate() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 10, height: 10)
        let mesh = CandidateMesh(id: SolidId("box"), payload: payload)

        // In a box, adjacent faces meet at 90 degrees > 10 degrees tolerance
        let chain = findTangentFaceChain(seedFaceId: 0, in: mesh)
        #expect(chain.count == 1)
        #expect(chain.first?.elementId == 0)
    }

    @Test func testTangentFaceChainCoplanarFaces() {
        // Build 2 coplanar adjacent quads on Z = 0: Quad 0 from X=0..1, Y=0..1; Quad 1 from X=1..2, Y=0..1
        let positions: [SIMD3<Float>] = [
            // Quad 0 (vertices 0..3)
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 1, 0), SIMD3<Float>(0, 1, 0),
            // Quad 1 (vertices 4..7)
            SIMD3<Float>(1, 0, 0), SIMD3<Float>(2, 0, 0), SIMD3<Float>(2, 1, 0), SIMD3<Float>(1, 1, 0)
        ]
        let indices: [UInt32] = [
            // Triangles for quad 0
            0, 1, 2, 0, 2, 3,
            // Triangles for quad 1
            4, 5, 6, 4, 6, 7
        ]
        let faceRanges = [
            FaceTriangleRange(faceId: 0, triangleRange: 0..<2),
            FaceTriangleRange(faceId: 1, triangleRange: 2..<4)
        ]
        let mesh = CandidateMesh(
            id: SolidId("coplanar"),
            positions: positions,
            edges: [],
            indices: indices,
            faceRanges: faceRanges
        )

        let chain = findTangentFaceChain(seedFaceId: 0, in: mesh)
        #expect(chain.count == 2)
        let faceIds = Set(chain.map(\.elementId))
        #expect(faceIds == [0, 1])
    }

    @Test func testFindFeatureFacesFiltersNonFacesAndMapsDeterministicIds() {
        let featureId = UUID()
        let faceDetId1 = UUID()
        let faceDetId2 = UUID()
        let edgeDetId = UUID()

        let topoRefs: [TopologicalReference] = [
            TopologicalReference(id: faceDetId1, sourceFeatureId: featureId, elementType: .face),
            TopologicalReference(id: faceDetId2, sourceFeatureId: featureId, elementType: .face),
            TopologicalReference(id: edgeDetId, sourceFeatureId: featureId, elementType: .edge)
        ]

        let faceRanges = [
            FaceTriangleRange(faceId: 0, triangleRange: 0..<2, deterministicId: faceDetId1),
            FaceTriangleRange(faceId: 1, triangleRange: 2..<4, deterministicId: faceDetId2),
            FaceTriangleRange(faceId: 2, triangleRange: 4..<6, deterministicId: UUID())
        ]

        let mesh = CandidateMesh(
            id: SolidId("feat-solid"),
            positions: [],
            edges: [],
            faceRanges: faceRanges
        )

        let result = findFeatureFaces(for: featureId, in: topoRefs, candidateMesh: mesh)
        #expect(result.count == 2)
        let mappedFaceIds = Set(result.map(\.elementId))
        #expect(mappedFaceIds == [0, 1])
        #expect(result.allSatisfy { $0.elementType == .face })
    }

    @Test func testFindFeatureFacesMissingMeshReturnsEmpty() {
        let featureId = UUID()
        let topoRefs: [TopologicalReference] = [
            TopologicalReference(id: UUID(), sourceFeatureId: featureId, elementType: .face)
        ]
        let emptyMesh = CandidateMesh(id: SolidId("empty"), positions: [], edges: [])
        let result = findFeatureFaces(for: featureId, in: topoRefs, candidateMesh: emptyMesh)
        #expect(result.isEmpty)
    }
}
