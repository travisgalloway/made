import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

@Suite struct BRepTessellationTests {

    @Test func testBoxTessellationFacesAndEdges() throws {
        guard let shape = Shape.box(origin: .zero, width: 20, height: 30, depth: 40) else {
            Issue.record("Failed to create box shape")
            return
        }
        let payload = try #require(OCCTEngine.toMeshPayload(shape))
        
        // A box has 6 faces and 12 triangles (2 per face)
        #expect(payload.faceRanges.count == 6)
        #expect(payload.triangleCount == 12)
        
        // Every triangle maps to a valid face
        for triIdx in 0..<payload.triangleCount {
            let fid = payload.faceId(atTriangle: triIdx)
            #expect(fid != nil)
        }
        
        // Sum of all triangle range counts equals triangleCount
        let totalFaceTriangles = payload.faceRanges.reduce(0) { $0 + $1.triangleRange.count }
        #expect(totalFaceTriangles == 12)
        
        // A box has 12 edges, each discretized into a straight line (1 segment, 2 points)
        #expect(payload.edgePolylines.count == 12)
        #expect(payload.edgeSegmentRanges.count == 12)
        #expect(payload.totalEdgeSegments == 12)
        #expect(payload.edgeSegments.count == 24) // 12 segments * 2 vertices
        
        for poly in payload.edgePolylines {
            #expect(poly.points.count == 2)
            #expect(poly.segmentRange.count == 1)
        }

        // A box has 8 vertices
        #expect(payload.vertexPoints.count == 8)
        for vp in payload.vertexPoints {
            #expect(payload.vertexPoint(forVertex: vp.vertexId) != nil)
        }
    }

    @Test func testCylinderToleranceScalingChordal() throws {
        guard let shape = Shape.cylinder(at: SIMD2(0, 0), bottomZ: 0, radius: 10, height: 30) else {
            Issue.record("Failed to create cylinder shape")
            return
        }
        
        let coarseTol = KernelTolerances(chordalTolerance: 1.0)
        let fineTol = KernelTolerances(chordalTolerance: 0.01)
        
        let coarsePayload = try #require(OCCTEngine.toMeshPayload(shape, tolerances: coarseTol))
        let finePayload = try #require(OCCTEngine.toMeshPayload(shape, tolerances: fineTol))
        
        // Finer chordal tolerance must produce more triangles and more edge segments
        #expect(finePayload.triangleCount > coarsePayload.triangleCount)
        #expect(finePayload.totalEdgeSegments > coarsePayload.totalEdgeSegments)
    }

    @Test func testCylinderToleranceScalingAngular() throws {
        guard let shapeCoarse = Shape.cylinder(at: SIMD2(0, 0), bottomZ: 0, radius: 15, height: 40),
              let shapeFine = Shape.cylinder(at: SIMD2(0, 0), bottomZ: 0, radius: 15, height: 40) else {
            Issue.record("Failed to create cylinder shape")
            return
        }
        
        // Keep chordal tolerance coarse so angular tolerance controls curved surface deflection
        let coarseAngleTol = KernelTolerances(angularTolerance: 30.0, chordalTolerance: 2.0)
        let fineAngleTol = KernelTolerances(angularTolerance: 2.0, chordalTolerance: 2.0)
        
        let coarsePayload = try #require(OCCTEngine.toMeshPayload(shapeCoarse, tolerances: coarseAngleTol))
        let finePayload = try #require(OCCTEngine.toMeshPayload(shapeFine, tolerances: fineAngleTol))
        
        // Angular tolerance controls curved surface deflection and increases triangle density
        #expect(finePayload.triangleCount > coarsePayload.triangleCount)
    }

    @Test func testAllowQualityDecreaseAllowsCoarserRetessellation() throws {
        guard let shape = Shape.cylinder(at: SIMD2(0, 0), bottomZ: 0, radius: 12, height: 25) else {
            Issue.record("Failed to create cylinder shape")
            return
        }
        
        // First tessellate with fine tolerance
        let fineTol = KernelTolerances(chordalTolerance: 0.005)
        let finePayload = try #require(OCCTEngine.toMeshPayload(shape, tolerances: fineTol))
        
        // Then re-tessellate the exact same Shape with coarse tolerance
        let coarseTol = KernelTolerances(chordalTolerance: 1.0)
        let coarsePayload = try #require(OCCTEngine.toMeshPayload(shape, tolerances: coarseTol))
        
        // Because allowQualityDecrease = true, the coarse mesh replaces the fine mesh
        #expect(coarsePayload.triangleCount < finePayload.triangleCount)
        #expect(coarsePayload.totalEdgeSegments < finePayload.totalEdgeSegments)
    }

    @Test func testTopologicalQueryHelpers() throws {
        guard let shape = Shape.box(origin: .zero, width: 10, height: 10, depth: 10) else {
            Issue.record("Failed to create box shape")
            return
        }
        let payload = try #require(OCCTEngine.toMeshPayload(shape))
        
        // Face lookup
        let face0 = try #require(payload.faceId(atTriangle: 0))
        let rangesForFace0 = payload.triangleRanges(forFace: face0)
        #expect(!rangesForFace0.isEmpty)
        #expect(rangesForFace0.contains(where: { $0.contains(0) }))
        
        #expect(payload.faceId(atTriangle: -1) == nil)
        #expect(payload.faceId(atTriangle: payload.triangleCount) == nil)
        #expect(payload.triangleRanges(forFace: 9999).isEmpty)
        
        // Edge lookup
        let edge0 = try #require(payload.edgeId(atSegment: 0))
        let segRange0 = try #require(payload.segmentRange(forEdge: edge0))
        #expect(segRange0.contains(0))
        
        let poly0 = try #require(payload.polyline(forEdge: edge0))
        #expect(poly0.edgeId == edge0)
        #expect(poly0.segmentRange == segRange0)
        
        #expect(payload.edgeId(atSegment: -1) == nil)
        #expect(payload.edgeId(atSegment: payload.totalEdgeSegments) == nil)
        #expect(payload.segmentRange(forEdge: 9999) == nil)
        #expect(payload.polyline(forEdge: 9999) == nil)
    }

    @Test func testLocalKernelEngineRetessellate() async throws {
        let engine = LocalKernelEngine()
        let sId = SolidId("box-test-1")
        
        // Create box
        let makeRes = await engine.execute(.makeBox(jobId: JobId("mk-1"), solidId: sId, params: BoxParams(width: 10, depth: 20, height: 30)))
        #expect(makeRes.isSuccess)
        
        // Re-tessellate with fine tolerance
        let tessRes = await engine.execute(.tessellate(jobId: JobId("tess-1"), solidId: sId, tolerances: KernelTolerances(chordalTolerance: 0.05)))
        #expect(tessRes.isSuccess)
        let payload = try #require(tessRes.value)
        #expect(payload.faceRanges.count == 6)
        #expect(payload.triangleCount == 12)
        #expect(payload.edgePolylines.count == 12)
        
        // Re-tessellate unknown solid returns .unknownSolid
        let unknownRes = await engine.execute(.tessellate(jobId: JobId("tess-unknown"), solidId: SolidId("nonexistent"), tolerances: nil))
        #expect(unknownRes.error?.code == .unknownSolid)
    }

    @Test func testKernelWireRoundtripTopologicalMetadata() throws {
        let storage = MeshStorage(positionCount: 9, normalCount: 9, indexCount: 3) { p, n, i in
            p[0] = 0; p[1] = 0; p[2] = 0
            p[3] = 1; p[4] = 0; p[5] = 0
            p[6] = 0; p[7] = 1; p[8] = 0
            n[0] = 0; n[1] = 0; n[2] = 1
            n[3] = 0; n[4] = 0; n[5] = 1
            n[6] = 0; n[7] = 0; n[8] = 1
            i[0] = 0; i[1] = 1; i[2] = 2
        }
        let deterministicFaceId = UUID()
        let deterministicEdgeId = UUID()
        let deterministicVertexId = UUID()
        let faceRanges = [FaceTriangleRange(faceId: 42, triangleRange: 0..<1, deterministicId: deterministicFaceId)]
        let edgePolylines = [EdgePolyline(edgeId: 7, points: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0)], segmentRange: 0..<1, deterministicId: deterministicEdgeId)]
        let edgeSegmentRanges = [EdgeSegmentRange(edgeId: 7, segmentRange: 0..<1, deterministicId: deterministicEdgeId)]
        let vertexPoints = [VertexPoint(vertexId: 99, position: SIMD3<Float>(1, 2, 3), deterministicId: deterministicVertexId)]
        
        let originalPayload = MeshPayload(
            storage: storage,
            faceRanges: faceRanges,
            edgePolylines: edgePolylines,
            edgeSegmentRanges: edgeSegmentRanges,
            vertexPoints: vertexPoints
        )
        
        let jobId = JobId("wire-roundtrip-test")
        let encoded = KernelWire.encodeReply(.success(jobId: jobId, value: originalPayload), instance: "inst-1")
        let decodedResult = KernelWire.decodeReply(encoded, jobId: jobId)
        
        let decodedPayload = try #require(decodedResult.value)
        #expect(decodedPayload.triangleCount == 1)
        #expect(decodedPayload.faceRanges == faceRanges)
        #expect(decodedPayload.edgePolylines == edgePolylines)
        #expect(decodedPayload.edgeSegmentRanges == edgeSegmentRanges)
        #expect(decodedPayload.vertexPoints == vertexPoints)
        #expect(decodedPayload.faceId(atTriangle: 0) == 42)
        #expect(decodedPayload.edgeId(atSegment: 0) == 7)
        #expect(decodedPayload.vertexPoint(forVertex: 99)?.position == SIMD3<Float>(1, 2, 3))
    }

    @Test func testNonBRepFallbackDegradesGracefully() {
        let euclid = EuclidEngine.makeBox(width: 10, depth: 10, height: 10)
        let payload = EuclidEngine.toMeshPayload(euclid)
        
        #expect(!payload.isEmpty)
        #expect(payload.triangleCount > 0)
        #expect(payload.faceRanges.count == 1)
        #expect(payload.faceRanges[0].faceId == 0)
        #expect(payload.faceRanges[0].triangleRange == 0..<payload.triangleCount)
        #expect(payload.faceId(atTriangle: 0) == 0)
        #expect(payload.edgePolylines.isEmpty)
        #expect(payload.edgeSegmentRanges.isEmpty)
        #expect(payload.totalEdgeSegments == 0)
        #expect(payload.edgeSegments.isEmpty)
        #expect(payload.edgeId(atSegment: 0) == nil)
        #expect(payload.vertexPoints.count == 8)
    }
}
