import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct DatumPlaneTests {

    @MainActor
    @Test func testOriginPlanes() throws {
        // XY Preset
        let xyData = DatumPlaneFeatureData(mode: .origin, originPreset: "XY")
        let xyPlane = try DatumPlaneEvaluator.evaluate(data: xyData)
        #expect(xyPlane.origin == SketchPlane.xy.origin)
        #expect(xyPlane.normal == SketchPlane.xy.normal)
        #expect(xyPlane.xAxis == SketchPlane.xy.xAxis)

        // XZ Preset
        let xzData = DatumPlaneFeatureData(mode: .origin, originPreset: "XZ")
        let xzPlane = try DatumPlaneEvaluator.evaluate(data: xzData)
        #expect(xzPlane.origin == SketchPlane.xz.origin)
        #expect(xzPlane.normal == SketchPlane.xz.normal)
        #expect(xzPlane.xAxis == SketchPlane.xz.xAxis)

        // YZ Preset
        let yzData = DatumPlaneFeatureData(mode: .origin, originPreset: "YZ")
        let yzPlane = try DatumPlaneEvaluator.evaluate(data: yzData)
        #expect(yzPlane.origin == SketchPlane.yz.origin)
        #expect(yzPlane.normal == SketchPlane.yz.normal)
        #expect(yzPlane.xAxis == SketchPlane.yz.xAxis)

        // Offset along normal
        let offsetData = DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 25.0)
        let offsetPlane = try DatumPlaneEvaluator.evaluate(data: offsetData)
        #expect(offsetPlane.origin == SIMD3<Float>(0, 0, 25.0))
        #expect(offsetPlane.normal == SIMD3<Float>(0, 0, 1))

        // Normal flip with offset
        let flippedData = DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 15.0, isFlipped: true)
        let flippedPlane = try DatumPlaneEvaluator.evaluate(data: flippedData)
        #expect(flippedPlane.normal == SIMD3<Float>(0, 0, -1))
        #expect(flippedPlane.origin == SIMD3<Float>(0, 0, -15.0))
    }

    @MainActor
    @Test func testOffsetPlane() throws {
        let doc = DocumentModel()
        let baseFeat = doc.addDatumPlaneFeature(
            name: "Base Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY")
        )

        let offsetData = DatumPlaneFeatureData(mode: .offset, offsetDistance: 40.0)
        let offsetFeat = doc.addDatumPlaneFeature(
            name: "Offset Plane",
            data: offsetData,
            references: [.feature(baseFeat.id)]
        )

        let evaluated = try DatumPlaneEvaluator.evaluate(feature: offsetFeat, data: offsetData, in: doc)
        #expect(evaluated.origin == SIMD3<Float>(0, 0, 40.0))
        #expect(evaluated.normal == SIMD3<Float>(0, 0, 1))
        #expect(evaluated.xAxis == SIMD3<Float>(1, 0, 0))

        // Negative offset
        let negData = DatumPlaneFeatureData(mode: .offset, offsetDistance: -15.0)
        let negPlane = try DatumPlaneEvaluator.evaluate(feature: offsetFeat, data: negData, in: doc)
        #expect(negPlane.origin == SIMD3<Float>(0, 0, -15.0))

        // Planar face reference
        let faceRef = Reference.face(TopologicalReference(
            id: UUID(),
            sourceFeatureId: baseFeat.id,
            elementType: .face,
            historyPath: [],
            disambiguator: GeometricSignature(
                normal: SIMD3<Float>(0, 1, 0),
                centroid: SIMD3<Float>(0, 10, 0)
            )
        ))
        let faceFeature = Feature(
            name: "Face Offset",
            operation: .datumPlane(DatumPlaneFeatureData(mode: .offset, offsetDistance: 5.0)),
            references: [faceRef]
        )
        let facePlane = try DatumPlaneEvaluator.evaluate(
            feature: faceFeature,
            data: DatumPlaneFeatureData(mode: .offset, offsetDistance: 5.0),
            in: doc
        )
        #expect(abs(facePlane.normal.y - 1.0) < 1e-5)
        #expect(abs(facePlane.origin.y - 15.0) < 1e-5)
    }

    @MainActor
    @Test func testAnglePlane() throws {
        // Rotate 90 degrees around X axis from XY plane
        let angleData = DatumPlaneFeatureData(
            mode: .atAngle,
            originPreset: "XY",
            angleDegrees: 90.0
        )
        let anglePlane = try DatumPlaneEvaluator.evaluate(data: angleData)

        // Normal (0, 0, 1) rotated 90 deg around (1, 0, 0) becomes (0, -1, 0)
        #expect(abs(anglePlane.normal.x) < 1e-5)
        #expect(abs(anglePlane.normal.y - (-1.0)) < 1e-5)
        #expect(abs(anglePlane.normal.z) < 1e-5)
        #expect(abs(anglePlane.xAxis.x - 1.0) < 1e-5)

        // Explicit axis endpoints
        let customAxisData = DatumPlaneFeatureData(
            mode: .atAngle,
            originPreset: "XY",
            angleDegrees: 45.0,
            point1: SIMD3<Float>(0, 0, 0),
            point2: SIMD3<Float>(0, 1, 0)
        )
        let customAxisPlane = try DatumPlaneEvaluator.evaluate(data: customAxisData)
        // Normal (0, 0, 1) rotated 45 deg around (0, 1, 0)
        let expectedNormal = simd_normalize(SIMD3<Float>(sin(Float.pi / 4.0), 0, cos(Float.pi / 4.0)))
        #expect(abs(customAxisPlane.normal.x - expectedNormal.x) < 1e-5)
        #expect(abs(customAxisPlane.normal.z - expectedNormal.z) < 1e-5)
    }

    @MainActor
    @Test func testThreePointPlane() throws {
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(20, 0, 0)
        let p3 = SIMD3<Float>(0, 30, 0)

        let data = DatumPlaneFeatureData(
            mode: .threePoints,
            point1: p1,
            point2: p2,
            point3: p3
        )
        let plane = try DatumPlaneEvaluator.evaluate(data: data)

        #expect(plane.origin == p1)
        #expect(abs(plane.normal.z - 1.0) < 1e-5)
        #expect(abs(plane.xAxis.x - 1.0) < 1e-5)

        // Arbitrary non-cardinal plane: (10, 0, 0), (0, 10, 0), (0, 0, 10)
        let arbData = DatumPlaneFeatureData(
            mode: .threePoints,
            point1: SIMD3<Float>(10, 0, 0),
            point2: SIMD3<Float>(0, 10, 0),
            point3: SIMD3<Float>(0, 0, 10)
        )
        let arbPlane = try DatumPlaneEvaluator.evaluate(data: arbData)
        let expectedNorm = simd_normalize(SIMD3<Float>(1, 1, 1))
        #expect(abs(arbPlane.normal.x - expectedNorm.x) < 1e-4)
        #expect(abs(arbPlane.normal.y - expectedNorm.y) < 1e-4)
        #expect(abs(arbPlane.normal.z - expectedNorm.z) < 1e-4)
    }

    @MainActor
    @Test func testNormalToCurvePlane() throws {
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(0, 0, 50)

        // At midpoint t = 0.5 along Z line
        let data = DatumPlaneFeatureData(
            mode: .normalToCurve,
            curveParameter: 0.5,
            point1: p1,
            point2: p2
        )
        let plane = try DatumPlaneEvaluator.evaluate(data: data)

        #expect(plane.origin == SIMD3<Float>(0, 0, 25))
        #expect(abs(plane.normal.z - 1.0) < 1e-5)

        // Normal to sketch line entity
        let doc = DocumentModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(40, 0))
        let sketchFeat = doc.addSketchFeature(planeName: "XY", entities: [l1])

        let curveRef = Reference.sketchEntity(featureId: sketchFeat.id, entityId: l1.id)
        let curveFeat = doc.addDatumPlaneFeature(
            name: "Normal to Line",
            data: DatumPlaneFeatureData(mode: .normalToCurve, curveParameter: 0.75),
            references: [curveRef]
        )

        let evaluated = try DatumPlaneEvaluator.evaluate(
            feature: curveFeat,
            data: DatumPlaneFeatureData(mode: .normalToCurve, curveParameter: 0.75),
            in: doc
        )
        #expect(abs(evaluated.origin.x - 30.0) < 1e-4)
        #expect(abs(evaluated.normal.x - 1.0) < 1e-4)
    }

    @MainActor
    @Test func testMidplane() throws {
        // Between two points
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(0, 0, 20)

        let pointMidData = DatumPlaneFeatureData(
            mode: .midplane,
            point1: p1,
            point2: p2
        )
        let pointMidPlane = try DatumPlaneEvaluator.evaluate(data: pointMidData)
        #expect(pointMidPlane.origin == SIMD3<Float>(0, 0, 10))
        #expect(abs(pointMidPlane.normal.z - 1.0) < 1e-5)

        // Between two parallel planes
        let doc = DocumentModel()
        let plane1Feat = doc.addDatumPlaneFeature(
            name: "Plane 1",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 0.0)
        )
        let plane2Feat = doc.addDatumPlaneFeature(
            name: "Plane 2",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 40.0)
        )

        let midFeature = doc.addDatumPlaneFeature(
            name: "Midplane",
            data: DatumPlaneFeatureData(mode: .midplane),
            references: [.feature(plane1Feat.id), .feature(plane2Feat.id)]
        )

        let evaluated = try DatumPlaneEvaluator.evaluate(
            feature: midFeature,
            data: DatumPlaneFeatureData(mode: .midplane),
            in: doc
        )
        #expect(abs(evaluated.origin.z - 20.0) < 1e-4)
        #expect(abs(evaluated.normal.z - 1.0) < 1e-4)
    }

    @MainActor
    @Test func testTangentPlane() throws {
        // Tangent to cylinder centered at origin with contact point at (15, 0, 10)
        let contactPt = SIMD3<Float>(15, 0, 10)
        let data = DatumPlaneFeatureData(
            mode: .tangent,
            point1: contactPt
        )
        let plane = try DatumPlaneEvaluator.evaluate(data: data)

        #expect(plane.origin == contactPt)
        #expect(abs(plane.normal.x - 1.0) < 1e-5)
        #expect(abs(plane.normal.y) < 1e-5)
        #expect(abs(plane.normal.z) < 1e-5)

        // Tangent with offset distance
        let offsetData = DatumPlaneFeatureData(
            mode: .tangent,
            offsetDistance: 5.0,
            point1: contactPt
        )
        let offsetPlane = try DatumPlaneEvaluator.evaluate(data: offsetData)
        #expect(abs(offsetPlane.origin.x - 20.0) < 1e-5)
    }

    @MainActor
    @Test func testDegenerateEdgeCases() async {
        // Collinear 3 points
        let collinearData = DatumPlaneFeatureData(
            mode: .threePoints,
            point1: SIMD3<Float>(0, 0, 0),
            point2: SIMD3<Float>(10, 0, 0),
            point3: SIMD3<Float>(20, 0, 0)
        )
        #expect(throws: DatumPlaneError.collinearPoints) {
            try DatumPlaneEvaluator.evaluate(data: collinearData)
        }

        // Coincident points
        let coincidentData = DatumPlaneFeatureData(
            mode: .threePoints,
            point1: SIMD3<Float>(5, 5, 5),
            point2: SIMD3<Float>(5, 5, 5),
            point3: SIMD3<Float>(10, 0, 0)
        )
        #expect(throws: DatumPlaneError.coincidentPoints) {
            try DatumPlaneEvaluator.evaluate(data: coincidentData)
        }

        // Coincident midplane points
        let coincidentMidData = DatumPlaneFeatureData(
            mode: .midplane,
            point1: SIMD3<Float>(1, 2, 3),
            point2: SIMD3<Float>(1, 2, 3)
        )
        #expect(throws: DatumPlaneError.coincidentPoints) {
            try DatumPlaneEvaluator.evaluate(data: coincidentMidData)
        }

        // Zero length normal or tangent
        let zeroCurveData = DatumPlaneFeatureData(
            mode: .normalToCurve,
            point1: SIMD3<Float>(4, 4, 4),
            point2: SIMD3<Float>(4, 4, 4)
        )
        #expect(throws: DatumPlaneError.zeroLengthNormal) {
            try DatumPlaneEvaluator.evaluate(data: zeroCurveData)
        }

        // Timeline regeneration sets FeatureErrorState for degenerate datum planes
        let doc = DocumentModel()
        let brokenFeat = doc.addDatumPlaneFeature(
            name: "Broken Plane",
            data: collinearData
        )
        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(5))
        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)

        let evaluatedBroken = doc.feature(for: brokenFeat.id)
        #expect(evaluatedBroken?.errorState != nil)
        #expect(evaluatedBroken?.errorState?.code == "datum-plane-error")

        // Dependent feature receives parent-failed cascade warning
        let dependentFeat = doc.addDatumPlaneFeature(
            name: "Dependent Offset",
            data: DatumPlaneFeatureData(mode: .offset, offsetDistance: 10.0),
            references: [.feature(brokenFeat.id)]
        )
        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)

        let evaluatedDep = doc.feature(for: dependentFeat.id)
        #expect(evaluatedDep?.errorState != nil)
        #expect(evaluatedDep?.errorState?.code == "parent-failed")
    }

    @MainActor
    @Test func testUndoRedo() throws {
        let doc = DocumentModel()
        let initialVersion = doc.undoStateVersion

        let planeFeat = doc.addDatumPlaneFeature(
            name: "Undo Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 10.0)
        )
        let planeId = planeFeat.id
        #expect(doc.features.contains(where: { $0.id == planeId }))
        #expect(doc.undoStateVersion > initialVersion)

        // Undo addition
        doc.undoManager?.undo()
        #expect(!doc.features.contains(where: { $0.id == planeId }))

        // Redo addition
        doc.undoManager?.redo()
        #expect(doc.features.contains(where: { $0.id == planeId }))

        // Remove feature with undo
        let preRemoveVersion = doc.undoStateVersion
        _ = doc.removeFeature(id: planeId)
        #expect(!doc.features.contains(where: { $0.id == planeId }))
        #expect(doc.undoStateVersion > preRemoveVersion)

        doc.undoManager?.undo()
        #expect(doc.features.contains(where: { $0.id == planeId }))
    }

    @MainActor
    @Test func testSerializationRoundTrip() throws {
        let doc = DocumentModel()
        let p1 = doc.addDatumPlaneFeature(
            name: "Datum 1",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 30.0, isFlipped: true)
        )
        _ = doc.addDatumPlaneFeature(
            name: "Datum 2",
            data: DatumPlaneFeatureData(mode: .threePoints, point1: SIMD3(0,0,0), point2: SIMD3(10,0,0), point3: SIMD3(0,10,0))
        )

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = doc.addSketchFeature(planeName: p1.name, entities: [l1])
        var updatedSketch = sketch
        if case .sketch(var sData) = updatedSketch.operation {
            sData.datumPlaneFeatureId = p1.id
            updatedSketch.operation = .sketch(sData)
            _ = doc.updateFeature(updatedSketch)
        }

        // Encode to DocumentData JSON
        let encoded = try DocumentModelCoder.encode(document: doc)
        #expect(!encoded.isEmpty)

        // Decode into a fresh document
        let decodedDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: decodedDoc, from: encoded)

        #expect(decodedDoc.features.count == doc.features.count)
        let decodedP1 = decodedDoc.feature(for: p1.id)
        #expect(decodedP1 != nil)
        #expect(decodedP1?.name == "Datum 1")

        if case .datumPlane(let data) = decodedP1?.operation {
            #expect(data.mode == .origin)
            #expect(data.offsetDistance == 30.0)
            #expect(data.isFlipped == true)
        } else {
            Issue.record("Expected .datumPlane operation on decoded feature")
        }

        let decodedSketch = decodedDoc.feature(for: sketch.id)
        if case .sketch(let data) = decodedSketch?.operation {
            #expect(data.datumPlaneFeatureId == p1.id)
        } else {
            Issue.record("Expected .sketch operation with datumPlaneFeatureId on decoded feature")
        }
    }
}
