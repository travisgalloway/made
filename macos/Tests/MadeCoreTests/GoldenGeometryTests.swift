import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

@Suite struct GoldenGeometryTests {

    private func assertClose(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-3, label: String) {
        guard let actual else {
            Issue.record("Expected \(label) to be non-nil")
            return
        }
        let diff = abs(actual - expected)
        #expect(diff <= tolerance, "\(label): actual \(actual) differs from expected \(expected) by \(diff) (tol: \(tolerance))")
    }

    // MARK: - Task 2: Golden Box Primitive Verification

    @Test func testGoldenBoxPrimitive() throws {
        // Analytical Baselines:
        // Box: 40 × 40 × 20 mm centered at origin (extents [-20, -20, -10] to [20, 20, 10])
        // Volume = 40 * 40 * 20 = 32,000.0 mm³
        // Surface Area = 2*(40*40) + 4*(40*20) = 3,200 + 3,200 = 6,400.0 mm²
        // Topology: 6 faces, 12 edges, 8 vertices
        guard let box = Shape.box(
            origin: SIMD3(-20, -20, -10),
            width: 40,
            height: 40,
            depth: 20
        ) else {
            Issue.record("Failed to construct golden box primitive")
            return
        }

        #expect(box.isValid)
        #expect(box.solidCount == 1)

        // Analytical volume and surface area assertions
        assertClose(box.volume, 32000.0, label: "Golden box volume")
        assertClose(box.surfaceArea, 6400.0, label: "Golden box surface area")

        // B-Rep topology counts
        #expect(box.faceCount == 6)
        #expect(box.uniqueFaceCount == 6)
        #expect(box.uniqueEdgeCount == 12)
        #expect(box.uniqueVertexCount == 8)
        #expect(box.faces().count == 6)
        #expect(box.edges().count == 12)
        #expect(box.vertices().count == 8)

        // Tessellation: 6 face ranges, 12 triangles (2 per face), 12 edge polylines (1 segment each, 2 points each), 8 vertices
        let payload = try #require(OCCTEngine.toMeshPayload(box))
        #expect(payload.faceRanges.count == 6)
        #expect(payload.triangleCount == 12)
        #expect(payload.edgePolylines.count == 12)
        #expect(payload.edgeSegmentRanges.count == 12)
        #expect(payload.totalEdgeSegments == 12)
        #expect(payload.edgeSegments.count == 24)
        for poly in payload.edgePolylines {
            #expect(poly.points.count == 2)
            #expect(poly.segmentRange.count == 1)
        }
        #expect(payload.vertexPoints.count == 8)

        // Triangle mapping to valid face IDs
        let totalFaceTriangles = payload.faceRanges.reduce(0) { $0 + $1.triangleRange.count }
        #expect(totalFaceTriangles == 12)
        for triIdx in 0..<payload.triangleCount {
            #expect(payload.faceId(atTriangle: triIdx) != nil)
        }
    }

    // MARK: - Task 3: Golden Cylinder Primitive Verification

    @Test func testGoldenCylinderPrimitive() throws {
        // Analytical Baselines:
        // Cylinder: r = 5 mm, h = 30 mm centered at (0, 0) spanning Z in [-15, 15]
        // Volume = π * r² * h = π * 25 * 30 = 750π ≈ 2,356.194490 mm³
        // Surface Area = 2πr² + 2πrh = 50π + 300π = 350π ≈ 1,099.557429 mm²
        // Topology: 3 faces (top cap, bottom cap, lateral cylinder wall), 3 edges (top rim, bottom rim, lateral seam), 2 vertices
        let radius: Double = 5.0
        let height: Double = 30.0
        guard let cylinder = Shape.cylinder(
            at: SIMD2(0, 0),
            bottomZ: -15,
            radius: radius,
            height: height
        ) else {
            Issue.record("Failed to construct golden cylinder primitive")
            return
        }

        #expect(cylinder.isValid)
        #expect(cylinder.solidCount == 1)

        let expectedVolume = Double.pi * radius * radius * height // 750π ≈ 2356.194490
        let expectedArea = 2.0 * Double.pi * radius * radius + 2.0 * Double.pi * radius * height // 350π ≈ 1099.557429

        assertClose(cylinder.volume, expectedVolume, label: "Golden cylinder volume")
        assertClose(cylinder.surfaceArea, expectedArea, label: "Golden cylinder surface area")

        // B-Rep topology counts
        #expect(cylinder.faceCount == 3)
        #expect(cylinder.uniqueFaceCount == 3)
        #expect(cylinder.uniqueEdgeCount == 3)
        #expect(cylinder.uniqueVertexCount == 2)
        #expect(cylinder.faces().count == 3)
        #expect(cylinder.edges().count == 3)
        #expect(cylinder.vertices().count == 2)

        // Tessellation: 3 face ranges, non-empty triangle buffer, 3 edge polylines, 2 vertex points
        let payload = try #require(OCCTEngine.toMeshPayload(cylinder))
        #expect(payload.faceRanges.count == 3)
        #expect(payload.triangleCount > 0)
        #expect(payload.edgePolylines.count == 3)
        #expect(payload.vertexPoints.count == 2)
    }

    // MARK: - Task 4: Golden Through-Hole Boolean Subtraction Verification

    @Test func testGoldenThroughHoleBooleanSubtraction() throws {
        // Box: 40 × 40 × 20 mm, Z in [-10, 10]
        guard let box = Shape.box(
            origin: SIMD3(-20, -20, -10),
            width: 40,
            height: 40,
            depth: 20
        ) else {
            Issue.record("Failed to construct box")
            return
        }

        // Cylinder: r = 5 mm, h = 30 mm, Z in [-15, 15] (extends past box top and bottom to avoid coplanar artifacts)
        guard let cylinder = Shape.cylinder(
            at: SIMD2(0, 0),
            bottomZ: -15,
            radius: 5.0,
            height: 30.0
        ) else {
            Issue.record("Failed to construct cylinder")
            return
        }

        guard let throughHoleShape = try OCCTEngine.booleanOperation(op: .subtract, shapeA: box, shapeB: cylinder) else {
            Issue.record("Boolean subtraction returned nil")
            return
        }

        #expect(throughHoleShape.isValid)
        #expect(throughHoleShape.solidCount == 1)

        // Analytical Calculations:
        // Cut volume = π * r² * h_box = π * 5² * 20 = 500π ≈ 1,570.796327 mm³
        // Remaining volume = 32,000.0 - 500π ≈ 30,429.203673 mm³
        let expectedVolume = 32000.0 - 500.0 * Double.pi
        assertClose(throughHoleShape.volume, expectedVolume, label: "Through-hole volume")

        // Analytical Surface Area:
        // Original box = 6,400.0 mm²
        // Area removed from top and bottom faces = 2 * (π * 5²) = 50π
        // Area added from cylindrical bore wall = 2π * r * h_box = 2π * 5 * 20 = 200π
        // Total surface area = 6,400.0 - 50π + 200π = 6,400.0 + 150π ≈ 6,871.238898 mm²
        let expectedArea = 6400.0 + 150.0 * Double.pi
        assertClose(throughHoleShape.surfaceArea, expectedArea, label: "Through-hole surface area")

        // Topology counts:
        // 7 faces: 4 outer sides, 1 holed top face, 1 holed bottom face, 1 inner cylindrical bore wall
        #expect(throughHoleShape.faceCount == 7)
        #expect(throughHoleShape.uniqueFaceCount == 7)
        #expect(throughHoleShape.faces().count == 7)
        // In OCCT B-Rep topology: 12 outer box edges + 2 circular bore rims + 1 cylindrical bore seam edge = 15 edges
        // Vertices: 8 outer box vertices + 2 bore seam vertices = 10 vertices
        #expect(throughHoleShape.uniqueEdgeCount == 15)
        #expect(throughHoleShape.uniqueVertexCount == 10)

        // Tessellation: 7 face ranges, non-empty triangles, watertight
        let payload = try #require(OCCTEngine.toMeshPayload(throughHoleShape))
        #expect(payload.faceRanges.count == 7)
        #expect(payload.triangleCount > 0)
        #expect(payload.storage.length % Int(getpagesize()) == 0)
    }

    // MARK: - Task 5: Golden Blind-Hole Boolean Subtraction (Partial Depth)

    @Test func testGoldenBlindHoleBooleanSubtraction() throws {
        // Box: 40 × 40 × 20 mm, Z in [-10, 10]
        guard let box = Shape.box(
            origin: SIMD3(-20, -20, -10),
            width: 40,
            height: 40,
            depth: 20
        ) else {
            Issue.record("Failed to construct box")
            return
        }

        // Blind hole cylinder: r = 5 mm, h = 10 mm, positioned from Z = 0 to Z = 10 (coincident top face)
        guard let cylinder = Shape.cylinder(
            at: SIMD2(0, 0),
            bottomZ: 0,
            radius: 5.0,
            height: 10.0
        ) else {
            Issue.record("Failed to construct cylinder")
            return
        }

        guard let blindHoleShape = try OCCTEngine.booleanOperation(op: .subtract, shapeA: box, shapeB: cylinder) else {
            Issue.record("Boolean subtraction returned nil")
            return
        }

        #expect(blindHoleShape.isValid)
        #expect(blindHoleShape.solidCount == 1)

        // Analytical Calculations:
        // Cut volume = π * r² * depth = π * 5² * 10 = 250π ≈ 785.398163 mm³
        // Remaining volume = 32,000.0 - 250π ≈ 31,214.601837 mm³
        let expectedVolume = 32000.0 - 250.0 * Double.pi
        assertClose(blindHoleShape.volume, expectedVolume, label: "Blind-hole volume")

        // Topology counts:
        // 8 faces: 4 outer sides, 1 outer bottom, 1 holed top, 1 blind pocket bottom, 1 cylindrical bore wall
        #expect(blindHoleShape.faceCount == 8)
        #expect(blindHoleShape.uniqueFaceCount == 8)

        // Verify bottom face (Z = -10) is intact (area = 40 × 40 = 1600 mm²) while top face (Z = 10) is holed (area = 1600 - 25π)
        let faces = blindHoleShape.faces()
        let bottomFaces = faces.filter { ($0.normal?.z ?? 0) < -0.99 }
        #expect(bottomFaces.count == 1)
        assertClose(bottomFaces.first?.area(), 1600.0, label: "Intact bottom face area")

        let topFaces = faces.filter { ($0.normal?.z ?? 0) > 0.99 }
        // Two upward-pointing planar faces: top face with hole and pocket bottom face
        #expect(topFaces.count == 2)
        let largerTopFace = topFaces.max(by: { $0.area() < $1.area() })
        let pocketBottomFace = topFaces.min(by: { $0.area() < $1.area() })

        let expectedHoledTopArea = 1600.0 - Double.pi * 25.0
        let expectedPocketBottomArea = Double.pi * 25.0
        assertClose(largerTopFace?.area(), expectedHoledTopArea, label: "Holed top face area")
        assertClose(pocketBottomFace?.area(), expectedPocketBottomArea, label: "Pocket bottom face area")

        let payload = try #require(OCCTEngine.toMeshPayload(blindHoleShape))
        #expect(payload.faceRanges.count == 8)
        #expect(payload.triangleCount > 0)
    }

    // MARK: - Task 6: Golden Box-Cylinder Union / Boss Verification

    @Test func testGoldenBoxCylinderBossUnion() throws {
        // Box: 40 × 40 × 20 mm, Z in [-10, 10]
        guard let box = Shape.box(
            origin: SIMD3(-20, -20, -10),
            width: 40,
            height: 40,
            depth: 20
        ) else {
            Issue.record("Failed to construct box")
            return
        }

        // Boss cylinder sitting atop box: r = 5 mm, h = 10 mm, Z in [10, 20]
        guard let boss = Shape.cylinder(
            at: SIMD2(0, 0),
            bottomZ: 10,
            radius: 5.0,
            height: 10.0
        ) else {
            Issue.record("Failed to construct boss cylinder")
            return
        }

        guard let unionShape = try OCCTEngine.booleanOperation(op: .union, shapeA: box, shapeB: boss) else {
            Issue.record("Boolean union returned nil")
            return
        }

        #expect(unionShape.isValid)
        #expect(unionShape.solidCount == 1)

        // Analytical Calculations:
        // Box volume = 32,000.0 mm³
        // Boss volume = π * 5² * 10 = 250π ≈ 785.398163 mm³
        // Total volume = 32,000.0 + 250π ≈ 32,785.398163 mm³
        let expectedVolume = 32000.0 + 250.0 * Double.pi
        assertClose(unionShape.volume, expectedVolume, label: "Boss union volume")

        // Analytical Surface Area:
        // Box area = 6,400.0 mm²
        // Attached bottom cap of boss subtracts 25π from box top face
        // Boss lateral face adds 2π * 5 * 10 = 100π
        // Boss top cap adds 25π
        // Total surface area = 6,400 - 25π + 100π + 25π = 6,400 + 100π ≈ 6,714.159265 mm²
        let expectedArea = 6400.0 + 100.0 * Double.pi
        assertClose(unionShape.surfaceArea, expectedArea, label: "Boss union surface area")

        // Topology counts:
        // 8 faces: 4 box sides, 1 box bottom, 1 top annulus, 1 cylinder lateral face, 1 cylinder top cap
        #expect(unionShape.faceCount == 8)
        #expect(unionShape.uniqueFaceCount == 8)

        let payload = try #require(OCCTEngine.toMeshPayload(unionShape))
        #expect(payload.faceRanges.count == 8)
        #expect(payload.triangleCount > 0)
    }

    // MARK: - Task 7: Disjoint Boolean Subtraction Edge Case

    @Test func testDisjointBooleanSubtraction() throws {
        // Box: 40 × 40 × 20 mm centered at origin
        guard let box = Shape.box(
            origin: SIMD3(-20, -20, -10),
            width: 40,
            height: 40,
            depth: 20
        ) else {
            Issue.record("Failed to construct box")
            return
        }

        // Disjoint cylinder positioned at X = 100 (outside box [-20, 20])
        guard let cylinder = Shape.cylinder(
            at: SIMD2(100, 0),
            bottomZ: -15,
            radius: 5.0,
            height: 30.0
        ) else {
            Issue.record("Failed to construct disjoint cylinder")
            return
        }

        guard let resultShape = try OCCTEngine.booleanOperation(op: .subtract, shapeA: box, shapeB: cylinder) else {
            Issue.record("Disjoint subtraction returned nil")
            return
        }

        #expect(resultShape.isValid)
        #expect(resultShape.solidCount == 1)

        // Subtraction with disjoint tool leaves original volume, surface area, and topology unchanged
        assertClose(resultShape.volume, 32000.0, label: "Disjoint subtraction box volume")
        assertClose(resultShape.surfaceArea, 6400.0, label: "Disjoint subtraction box surface area")
        #expect(resultShape.faceCount == 6)
        #expect(resultShape.uniqueFaceCount == 6)
        #expect(resultShape.uniqueEdgeCount == 12)
        #expect(resultShape.uniqueVertexCount == 8)

        let payload = try #require(OCCTEngine.toMeshPayload(resultShape))
        #expect(payload.faceRanges.count == 6)
        #expect(payload.triangleCount == 12)
    }

    // MARK: - Task 8: Golden STEP Export and Re-Import Round-Trip

    @Test func testGoldenStepRoundTripThroughHole() throws {
        // Create golden through-hole shape
        guard let box = Shape.box(
            origin: SIMD3(-20, -20, -10),
            width: 40,
            height: 40,
            depth: 20
        ), let cylinder = Shape.cylinder(
            at: SIMD2(0, 0),
            bottomZ: -15,
            radius: 5.0,
            height: 30.0
        ), let originalShape = try OCCTEngine.booleanOperation(op: .subtract, shapeA: box, shapeB: cylinder) else {
            Issue.record("Failed to construct original through-hole shape")
            return
        }

        let originalVolume = try #require(originalShape.volume)
        let originalArea = try #require(originalShape.surfaceArea)

        // Export shape to binary STEP data
        let stepData = try OCCTEngine.exportStep(shape: originalShape, name: "GoldenThroughHole")
        #expect(!stepData.isEmpty)

        // Re-import STEP data
        let reimportedShape = try OCCTEngine.importStep(data: stepData)
        #expect(reimportedShape.isValid)
        #expect(reimportedShape.solidCount == 1)
        #expect(reimportedShape.faceCount == 7)

        // Volume and surface area round-trip precision verification
        assertClose(reimportedShape.volume, originalVolume, tolerance: 1e-3, label: "Re-imported volume")
        assertClose(reimportedShape.surfaceArea, originalArea, tolerance: 1e-3, label: "Re-imported surface area")

        // Analytical baseline comparisons
        let analyticalVolume = 32000.0 - 500.0 * Double.pi
        let analyticalArea = 6400.0 + 150.0 * Double.pi
        assertClose(reimportedShape.volume, analyticalVolume, tolerance: 1e-3, label: "Re-imported vs analytical volume")
        assertClose(reimportedShape.surfaceArea, analyticalArea, tolerance: 1e-3, label: "Re-imported vs analytical area")

        // Verify solid count helper
        let count = try OCCTEngine.solidCount(data: stepData)
        #expect(count == 1)
    }

    // MARK: - Task 9: LocalKernelEngine Request Pipeline End-to-End

    @Test func testLocalKernelEngineThroughHolePipeline() async throws {
        let engine = LocalKernelEngine()
        let boxId = SolidId("golden-box")
        let cylId = SolidId("golden-cyl")
        let subId = SolidId("golden-through-hole")

        // Step 1: Make box (40 × 40 × 20 mm)
        let boxRes = await engine.execute(.makeBox(
            jobId: JobId("gb-box-job"),
            solidId: boxId,
            params: BoxParams(width: 40, depth: 40, height: 20)
        ))
        #expect(boxRes.isSuccess)

        // Step 2: Make cylinder (r = 5 mm, h = 30 mm)
        let cylRes = await engine.execute(.makeCylinder(
            jobId: JobId("gb-cyl-job"),
            solidId: cylId,
            params: CylinderParams(radius: 5, height: 30)
        ))
        #expect(cylRes.isSuccess)

        // Step 3: Perform B-Rep subtraction
        let subRes = await engine.execute(.booleanOperation(
            jobId: JobId("gb-sub-job"),
            solidId: subId,
            op: .subtract,
            solidA: boxId,
            solidB: cylId
        ))
        #expect(subRes.isSuccess)

        let payload = try #require(subRes.value)

        // Verify MeshPayload topology: 7 face ranges
        #expect(payload.faceRanges.count == 7)
        #expect(payload.triangleCount > 0)

        // Invariant 6: Shared memory backing is page-aligned
        #expect(payload.storage.length > 0)
        #expect(payload.storage.length % Int(getpagesize()) == 0)
    }
}
