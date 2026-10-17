import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchProjectionTests {

    // MARK: - SketchEntity & Codable Backward Compatibility

    @Test func testSketchEntityReferenceAndCodable() throws {
        let dummyRef = Reference.feature(UUID(), role: "proj")
        let line = SketchEntity.line(
            start: SIMD2(0, 0),
            end: SIMD2(10, 0),
            reference: dummyRef
        )
        #expect(line.isProjected)
        #expect(line.reference == dummyRef)

        let regularLine = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(5, 5))
        #expect(!regularLine.isProjected)
        #expect(regularLine.reference == nil)

        // Roundtrip Codable
        let encoder = JSONEncoder()
        let data = try encoder.encode(line)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SketchEntity.self, from: data)
        #expect(decoded.id == line.id)
        #expect(decoded.reference == dummyRef)
        #expect(decoded.isProjected)

        // Backward compatibility: JSON without "reference" field
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "kind": "line",
            "data": {"startX": 0.0, "startY": 0.0, "endX": 10.0, "endY": 0.0},
            "isConstruction": false
        }
        """.data(using: .utf8)!
        let legacyDecoded = try decoder.decode(SketchEntity.self, from: legacyJSON)
        #expect(legacyDecoded.reference == nil)
        #expect(!legacyDecoded.isProjected)
    }

    // MARK: - SketchPlane Math

    @Test func testSketchPlaneProjectionMath() {
        let plane = SketchPlane.xy
        #expect(plane.yAxis == SIMD3<Float>(0, 1, 0))

        let pt3D = SIMD3<Float>(10, 20, 0)
        let pt2D = plane.projectPoint(pt3D)
        #expect(abs(pt2D.x - 10.0) < 1e-5)
        #expect(abs(pt2D.y - 20.0) < 1e-5)

        let unprojected = plane.unprojectPoint(pt2D)
        #expect(simd_distance(unprojected, pt3D) < 1e-5)

        // XZ Plane
        let xzPlane = SketchPlane.xz
        #expect(abs(xzPlane.yAxis.z - 1.0) < 1e-5) // Y axis in XZ plane points to +Z
        let xzPt = SIMD3<Float>(5, 0, 15)
        let xz2D = xzPlane.projectPoint(xzPt)
        #expect(abs(xz2D.x - 5.0) < 1e-5)
        #expect(abs(xz2D.y - 15.0) < 1e-5)
        let xzUnprojected = xzPlane.unprojectPoint(xz2D)
        #expect(simd_distance(xzUnprojected, xzPt) < 1e-5)
    }

    // MARK: - Line Projection Math & Degeneracy

    @Test func testProjectLineMath() throws {
        let plane = SketchPlane.xy
        let curve = EvaluatedCurve3D.line(
            start: SIMD3<Float>(0, 0, 10),
            end: SIMD3<Float>(20, 0, 10)
        )
        let projected = try SketchOperations.project(curve: curve, onto: plane)
        #expect(projected.kind == "line")
        #expect(abs((projected.startPoint?.x ?? 0) - 0.0) < 1e-4)
        #expect(abs((projected.endPoint?.x ?? 0) - 20.0) < 1e-4)
        #expect(abs((projected.length ?? 0) - 20.0) < 1e-4)

        // Degenerate line: perpendicular to plane (projects to a single point)
        let perpCurve = EvaluatedCurve3D.line(
            start: SIMD3<Float>(5, 5, 0),
            end: SIMD3<Float>(5, 5, 20)
        )
        #expect(throws: SketchError.self) {
            try SketchOperations.project(curve: perpCurve, onto: plane)
        }
    }

    // MARK: - Circle Projection Math

    @Test func testProjectCircleMath() throws {
        let plane = SketchPlane.xy

        // Parallel circle
        let parallelCircle = EvaluatedCurve3D.circle(
            center: SIMD3<Float>(10, 10, 5),
            normal: SIMD3<Float>(0, 0, 1),
            radius: 15.0
        )
        let projCircle = try SketchOperations.project(curve: parallelCircle, onto: plane)
        #expect(projCircle.kind == "circle")
        #expect(abs((projCircle.centerPoint?.x ?? 0) - 10.0) < 1e-4)
        #expect(abs((projCircle.centerPoint?.y ?? 0) - 10.0) < 1e-4)
        #expect(abs((projCircle.radius ?? 0) - 15.0) < 1e-4)

        // Perpendicular circle: projects to a 2D line of length 2*r
        let perpCircle = EvaluatedCurve3D.circle(
            center: SIMD3<Float>(0, 0, 0),
            normal: SIMD3<Float>(1, 0, 0), // circle in YZ plane
            radius: 10.0
        )
        let projLine = try SketchOperations.project(curve: perpCircle, onto: plane)
        #expect(projLine.kind == "line")
        #expect(abs((projLine.length ?? 0) - 20.0) < 1e-4)

        // Oblique circle: unsupported, throws invalidEntity
        let obliqueCircle = EvaluatedCurve3D.circle(
            center: SIMD3<Float>(0, 0, 0),
            normal: simd_normalize(SIMD3<Float>(1, 1, 1)),
            radius: 10.0
        )
        #expect(throws: SketchError.self) {
            try SketchOperations.project(curve: obliqueCircle, onto: plane)
        }
    }

    // MARK: - Arc Projection Math

    @Test func testProjectArcMath() throws {
        let plane = SketchPlane.xy

        let parallelArc = EvaluatedCurve3D.arc(
            center: SIMD3<Float>(0, 0, 0),
            normal: SIMD3<Float>(0, 0, 1),
            radius: 10.0,
            startAngle: 0,
            endAngle: .pi / 2,
            startPoint: SIMD3<Float>(10, 0, 0),
            endPoint: SIMD3<Float>(0, 10, 0),
            clockwise: false
        )
        let projArc = try SketchOperations.project(curve: parallelArc, onto: plane)
        #expect(projArc.kind == "arc")
        #expect(abs((projArc.centerPoint?.x ?? 0) - 0.0) < 1e-4)
        #expect(abs((projArc.startPoint?.x ?? 0) - 10.0) < 1e-4)
        #expect(abs((projArc.endPoint?.y ?? 0) - 10.0) < 1e-4)
    }

    // MARK: - ModelEdgeEvaluator Primitives

    @Test @MainActor func testModelEdgeEvaluatorBox() throws {
        let document = DocumentModel()
        let boxFeat = Feature.makeBox(
            id: UUID(),
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        _ = document.addFeature(boxFeat)

        guard let topFrontRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("edge:top-front missing in box topology")
            return
        }

        let ref = Reference.edge(topFrontRef)
        let evalResult = ModelEdgeEvaluator.evaluate(reference: ref, in: document)
        guard case .success(let curve) = evalResult else {
            Issue.record("Failed to evaluate box edge: \(evalResult)")
            return
        }

        guard case .line(let start, let end) = curve else {
            Issue.record("Expected line for box edge")
            return
        }

        // Box: w=40, d=30, h=20. hw=20, hd=15, hh=10.
        // top-front: x goes from -20 to 20, y = -15, z = 10.
        #expect(abs(start.x - (-20.0)) < 1e-4)
        #expect(abs(end.x - 20.0) < 1e-4)
        #expect(abs(start.y - (-15.0)) < 1e-4)
        #expect(abs(start.z - 10.0) < 1e-4)
    }

    @Test @MainActor func testModelEdgeEvaluatorCylinder() throws {
        let document = DocumentModel()
        let cylFeat = Feature.makeCylinder(
            id: UUID(),
            params: CylinderParams(radius: 12.0, height: 50.0)
        )
        _ = document.addFeature(cylFeat)

        guard let topRef = cylFeat.generatedTopology["edge:top"] else {
            Issue.record("edge:top missing in cylinder topology")
            return
        }

        let ref = Reference.edge(topRef)
        let evalResult = ModelEdgeEvaluator.evaluate(reference: ref, in: document)
        guard case .success(let curve) = evalResult else {
            Issue.record("Failed to evaluate cylinder top rim")
            return
        }

        guard case .circle(let center, let normal, let radius) = curve else {
            Issue.record("Expected circle for cylinder top rim")
            return
        }

        #expect(abs(center.z - 25.0) < 1e-4)
        #expect(abs(radius - 12.0) < 1e-4)
        #expect(abs(normal.z - 1.0) < 1e-4)
    }

    // MARK: - ModelEdgeEvaluator Sketch Entity

    @Test @MainActor func testModelEdgeEvaluatorSketchEntity() throws {
        let document = DocumentModel()
        let sketchFeat = document.addSketchFeature(planeName: "xy")
        let line = SketchEntity.line(start: SIMD2(5, 5), end: SIMD2(25, 5))
        _ = document.addSketchEntity(to: sketchFeat.id, entity: line)

        let ref = Reference.sketchEntity(featureId: sketchFeat.id, entityId: line.id)
        let evalResult = ModelEdgeEvaluator.evaluate(reference: ref, in: document)
        guard case .success(let curve) = evalResult else {
            Issue.record("Failed to evaluate sketch entity reference")
            return
        }

        guard case .line(let start, let end) = curve else {
            Issue.record("Expected line from sketch entity")
            return
        }
        #expect(abs(start.x - 5.0) < 1e-4)
        #expect(abs(end.x - 25.0) < 1e-4)
    }

    // MARK: - KernelRegeneration Associative Reprojection

    @Test @MainActor func testKernelRegenerationAssociativeReprojection() async throws {
        let document = DocumentModel()

        // 1. Upstream box
        let boxFeat = Feature.makeBox(
            id: UUID(),
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        _ = document.addFeature(boxFeat)

        // 2. Downstream sketch on XY plane
        let sketchFeat = document.addSketchFeature(planeName: "xy")
        guard let edgeTopFront = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge")
            return
        }

        let ref = Reference.edge(edgeTopFront)
        let projResult = document.projectEntity(reference: ref, into: sketchFeat.id)
        guard case .success(let projected) = projResult else {
            Issue.record("Failed to project entity: \(projResult)")
            return
        }
        #expect(projected.isProjected)
        #expect(abs((projected.length ?? 0) - 40.0) < 1e-3)

        // 3. Edit upstream box width from 40 to 60
        var updatedBox = boxFeat
        updatedBox.operation = .primitive(.box(BoxParams(width: 60, depth: 30, height: 20)))
        _ = document.updateFeature(updatedBox)

        // 4. Regenerate timeline
        let mockClient = MockKernelClient()
        await KernelRegeneration.regenerate(features: document.features, in: document, client: mockClient)

        // 5. Verify projected sketch entity updated in place to length 60!
        guard let updatedSketch = document.feature(for: sketchFeat.id),
              case .sketch(let sketchData) = updatedSketch.operation,
              let updatedEntity = sketchData.entities.first(where: { $0.id == projected.id }) else {
            Issue.record("Updated sketch entity not found")
            return
        }

        #expect(abs((updatedEntity.length ?? 0) - 60.0) < 1e-3)
        #expect(updatedSketch.errorState == nil)

        // 6. Suppress upstream box: verify sketch receives reference-broken
        _ = document.setFeatureSuppressed(id: boxFeat.id, isSuppressed: true)
        await KernelRegeneration.regenerate(features: document.features, in: document, client: mockClient)

        guard let brokenSketch = document.feature(for: sketchFeat.id) else {
            Issue.record("Broken sketch not found")
            return
        }
        #expect(brokenSketch.errorState?.code == "reference-broken")
    }
}

private final class MockKernelClient: KernelClientProtocol, @unchecked Sendable {
    func request(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        .success(jobId: request.jobId, value: MeshPayload(positions: [], normals: [], indices: []))
    }
    func cancel(jobId: JobId) async {}
    func dispose(solidId: SolidId) async {}
    func getStats() async -> KernelStats { KernelStats() }
}
