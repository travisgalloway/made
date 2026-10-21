import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct MeasureToolTests {

    @Test func testUnitSettingsFormatArea() {
        var settings = UnitSettings(lengthUnit: .millimeters, decimalPrecision: 2)
        // 100 mm²
        #expect(settings.formatArea(100.0) == "100.00 mm²")
        #expect(settings.formatArea(100.0, includeSymbol: false) == "100.00")

        // In centimeters: 100 mm² = 1 cm²
        settings.lengthUnit = .centimeters
        #expect(settings.formatArea(100.0) == "1.00 cm²")

        // In meters: 1,000,000 mm² = 1 m²
        settings.lengthUnit = .meters
        #expect(settings.formatArea(1_000_000.0) == "1.00 m²")

        // In inches: 25.4 * 25.4 = 645.16 mm² = 1 in²
        settings.lengthUnit = .inches
        #expect(settings.formatArea(645.16) == "1.00 in²")

        // In feet: 304.8 * 304.8 = 92903.04 mm² = 1 ft²
        settings.lengthUnit = .feet
        #expect(settings.formatArea(92903.04) == "1.00 ft²")
    }

    @Test func test10mmBoxOppositeFaces() {
        let doc = DocumentModel()
        let boxSolidId = SolidId("box-1")
        let boxFeat = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = doc.addFeature(boxFeat)

        let topFace = MeasuredElement.face(solidId: boxSolidId, faceId: 0)
        let bottomFace = MeasuredElement.face(solidId: boxSolidId, faceId: 1)

        let result = MeasureTool.measure(
            elementA: topFace,
            elementB: bottomFace,
            in: doc
        )

        #expect(result != nil)
        guard let res = result else { return }

        // Opposite faces are 10 mm apart
        #expect(abs(res.minDistance - 10.0) < 1e-4)
        #expect(abs(res.centerDistance - 10.0) < 1e-4)
        if let normDist = res.normalDistance {
            #expect(abs(normDist - 10.0) < 1e-4)
        } else {
            Issue.record("Expected normal distance to be present for planar faces")
        }

        // Parallel opposite faces report angle of 0.0 degrees
        if let angle = res.angleDegrees {
            #expect(abs(angle - 0.0) < 1e-4)
        } else {
            Issue.record("Expected angle to be present for planar faces")
        }

        // Face area is 100 mm²
        if let area = res.geometryA.area {
            #expect(abs(area - 100.0) < 1e-4)
        } else {
            Issue.record("Expected top face area to be 100 mm²")
        }
    }

    @Test func test10mmBoxAdjacentFaces() {
        let doc = DocumentModel()
        let boxSolidId = SolidId("box-1")
        let boxFeat = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = doc.addFeature(boxFeat)

        // Top face (faceId 0, +Z) and Front face (faceId 5, -Y)
        let topFace = MeasuredElement.face(solidId: boxSolidId, faceId: 0)
        let frontFace = MeasuredElement.face(solidId: boxSolidId, faceId: 5)

        let result = MeasureTool.measure(
            elementA: topFace,
            elementB: frontFace,
            in: doc
        )

        #expect(result != nil)
        guard let res = result else { return }

        // Adjacent faces touch, minimum distance is 0.0
        #expect(abs(res.minDistance - 0.0) < 1e-4)

        // Adjacent perpendicular faces report 90.0 degrees
        if let angle = res.angleDegrees {
            #expect(abs(angle - 90.0) < 1e-4)
        } else {
            Issue.record("Expected angle to be present for adjacent perpendicular faces")
        }
    }

    @Test func testCircularEdges() {
        let doc = DocumentModel()
        let cylSolidId = SolidId("cyl-1")
        let cylFeat = Feature.makeCylinder(
            solidId: cylSolidId,
            params: CylinderParams(radius: 5, height: 20)
        )
        _ = doc.addFeature(cylFeat)

        // Edge 0 is the top circular rim
        let circularEdge = MeasuredElement.edge(solidId: cylSolidId, edgeId: 0)
        let result = MeasureTool.measure(
            elementA: circularEdge,
            elementB: nil,
            in: doc
        )

        #expect(result != nil)
        guard let res = result else { return }

        let geom = res.geometryA
        #expect(geom.isCircular)
        if let r = geom.radius {
            #expect(abs(r - 5.0) < 1e-3)
        } else {
            Issue.record("Expected circular edge to report radius of 5.0")
        }

        if let d = geom.diameter {
            #expect(abs(d - 10.0) < 1e-3)
        } else {
            Issue.record("Expected circular edge to report diameter of 10.0")
        }

        if let l = geom.length {
            let expectedLength = 2.0 * Double.pi * 5.0
            #expect(abs(l - expectedLength) < 0.2)
        } else {
            Issue.record("Expected circular edge to report perimeter length")
        }
    }

    @Test func testNonCircularEdges() {
        let doc = DocumentModel()
        let boxSolidId = SolidId("box-1")
        let boxFeat = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = doc.addFeature(boxFeat)

        // Edge 0 on 10 mm box
        let linearEdge = MeasuredElement.edge(solidId: boxSolidId, edgeId: 0)
        let result = MeasureTool.measure(
            elementA: linearEdge,
            elementB: nil,
            in: doc
        )

        #expect(result != nil)
        guard let res = result else { return }

        let geom = res.geometryA
        #expect(!geom.isCircular)
        #expect(geom.radius == nil)
        #expect(geom.diameter == nil)
        if let l = geom.length {
            #expect(abs(l - 10.0) < 1e-4)
        } else {
            Issue.record("Expected linear edge length to be 10.0")
        }
    }

    @Test func testSameElementZeroDistance() {
        let doc = DocumentModel()
        let boxSolidId = SolidId("box-1")
        let boxFeat = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = doc.addFeature(boxFeat)

        let topFace = MeasuredElement.face(solidId: boxSolidId, faceId: 0)

        let result = MeasureTool.measure(
            elementA: topFace,
            elementB: topFace,
            in: doc
        )

        #expect(result != nil)
        guard let res = result else { return }

        #expect(res.minDistance == 0.0)
        #expect(res.centerDistance == 0.0)
        #expect(res.normalDistance == 0.0)
        #expect(res.angleDegrees == 0.0)
    }

    @Test func testHiddenBodyExclusion() {
        let doc = DocumentModel()
        let boxSolidId = SolidId("box-hidden")
        var boxFeat = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        boxFeat.isVisible = false
        _ = doc.addFeature(boxFeat)

        #expect(!MeasureTool.isSolidVisible(boxSolidId, in: doc))

        let topFace = MeasuredElement.face(solidId: boxSolidId, faceId: 0)
        let result = MeasureTool.measure(
            elementA: topFace,
            elementB: nil,
            in: doc
        )
        #expect(result == nil)

        // Also test hiddenSolidIds set
        let visibleSolidId = SolidId("box-visible")
        let visibleFeat = Feature.makeBox(
            solidId: visibleSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = doc.addFeature(visibleFeat)

        #expect(MeasureTool.isSolidVisible(visibleSolidId, in: doc, hiddenSolidIds: [visibleSolidId]) == false)
    }

    @Test func testImportedMeshMeasurement() {
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 30, height: 40)
        let candidate = CandidateMesh(id: SolidId("imported-box"), payload: payload, transform: .identity)

        let face0 = MeasuredElement.face(solidId: candidate.id, faceId: 0) // +Z face (20 x 30 = 600)
        let face1 = MeasuredElement.face(solidId: candidate.id, faceId: 1) // -Z face

        guard let geom0 = MeasureTool.evaluateGeometry(for: face0, mesh: candidate),
              let geom1 = MeasureTool.evaluateGeometry(for: face1, mesh: candidate) else {
            Issue.record("Failed to evaluate geometry for imported mesh faces")
            return
        }

        #expect(geom0.isPlanar)
        if let area = geom0.area {
            #expect(abs(area - 600.0) < 1e-3)
        } else {
            Issue.record("Expected imported mesh top face area to be 600.0")
        }

        let result = MeasureTool.measure(
            elementA: face0,
            elementB: face1,
            geometryA: geom0,
            geometryB: geom1,
            meshA: candidate,
            meshB: candidate
        )

        // Height is 40
        #expect(abs(result.minDistance - 40.0) < 1e-3)
        #expect(abs(result.centerDistance - 40.0) < 1e-3)
        if let normDist = result.normalDistance {
            #expect(abs(normDist - 40.0) < 1e-3)
        }
        if let angle = result.angleDegrees {
            #expect(abs(angle - 0.0) < 1e-3)
        }
    }

    @Test func testVertexToVertexDistance() {
        let doc = DocumentModel()
        let boxSolidId = SolidId("box-1")
        let boxFeat = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = doc.addFeature(boxFeat)

        // Vertex 0: (-5, -5, -5), Vertex 6: (5, 5, 5) -> distance = sqrt(100 + 100 + 100) = sqrt(300) ≈ 17.3205
        let v0 = MeasuredElement.vertex(solidId: boxSolidId, vertexId: 0)
        let v6 = MeasuredElement.vertex(solidId: boxSolidId, vertexId: 6)

        let result = MeasureTool.measure(
            elementA: v0,
            elementB: v6,
            in: doc
        )

        #expect(result != nil)
        guard let res = result else { return }
        let expectedDist = sqrt(300.0)
        #expect(abs(res.minDistance - expectedDist) < 1e-3)
        #expect(abs(res.centerDistance - expectedDist) < 1e-3)
    }
}
