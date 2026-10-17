import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct DatumEntitiesTests {

    // MARK: - Datum Axis Tests

    @MainActor
    @Test func testDatumAxisPreset() throws {
        // Preset X
        let xData = DatumAxisFeatureData(mode: .preset, presetName: "X")
        let xAxis = try DatumAxisEvaluator.evaluate(data: xData)
        #expect(xAxis.origin == .zero)
        #expect(xAxis.direction == SIMD3<Float>(1, 0, 0))

        // Preset Y
        let yData = DatumAxisFeatureData(mode: .preset, presetName: "Y")
        let yAxis = try DatumAxisEvaluator.evaluate(data: yData)
        #expect(yAxis.origin == .zero)
        #expect(yAxis.direction == SIMD3<Float>(0, 1, 0))

        // Preset Z
        let zData = DatumAxisFeatureData(mode: .preset, presetName: "Z")
        let zAxis = try DatumAxisEvaluator.evaluate(data: zData)
        #expect(zAxis.origin == .zero)
        #expect(zAxis.direction == SIMD3<Float>(0, 0, 1))

        // Preset with origin and flip
        let flippedData = DatumAxisFeatureData(
            mode: .preset,
            presetName: "Z",
            point1: SIMD3<Float>(10, 20, 30),
            isFlipped: true
        )
        let flippedAxis = try DatumAxisEvaluator.evaluate(data: flippedData)
        #expect(flippedAxis.origin == SIMD3<Float>(10, 20, 30))
        #expect(flippedAxis.direction == SIMD3<Float>(0, 0, -1))
    }

    @MainActor
    @Test func testDatumAxisTwoPoints() throws {
        let p1 = SIMD3<Float>(10, 10, 0)
        let p2 = SIMD3<Float>(10, 40, 0)
        let data = DatumAxisFeatureData(mode: .twoPoints, point1: p1, point2: p2)
        let axis = try DatumAxisEvaluator.evaluate(data: data)
        #expect(axis.origin == p1)
        #expect(axis.direction == SIMD3<Float>(0, 1, 0))

        // Flipped direction
        let flippedData = DatumAxisFeatureData(mode: .twoPoints, point1: p1, point2: p2, isFlipped: true)
        let flippedAxis = try DatumAxisEvaluator.evaluate(data: flippedData)
        #expect(flippedAxis.direction == SIMD3<Float>(0, -1, 0))

        // Diagonal points
        let diagData = DatumAxisFeatureData(
            mode: .twoPoints,
            point1: SIMD3<Float>(0, 0, 0),
            point2: SIMD3<Float>(10, 10, 0)
        )
        let diagAxis = try DatumAxisEvaluator.evaluate(data: diagData)
        let expectedNorm = simd_normalize(SIMD3<Float>(10, 10, 0))
        #expect(abs(diagAxis.direction.x - expectedNorm.x) < 1e-5)
        #expect(abs(diagAxis.direction.y - expectedNorm.y) < 1e-5)
    }

    @MainActor
    @Test func testDatumAxisEdgeAndSketchEntity() throws {
        let doc = DocumentModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(0, 50))
        let sketch = doc.addSketchFeature(planeName: "XY", entities: [line])

        let axisFeat = doc.addDatumAxisFeature(
            name: "Line Axis",
            data: DatumAxisFeatureData(mode: .edge),
            references: [.sketchEntity(featureId: sketch.id, entityId: line.id)]
        )

        let evaluated = try DatumAxisEvaluator.evaluate(feature: axisFeat, data: DatumAxisFeatureData(mode: .edge), in: doc)
        #expect(evaluated.origin == SIMD3<Float>(0, 0, 0))
        #expect(evaluated.direction == SIMD3<Float>(0, 1, 0))
    }

    @MainActor
    @Test func testDatumAxisNormalToPlane() throws {
        let doc = DocumentModel()
        let planeFeat = doc.addDatumPlaneFeature(
            name: "Ref Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XZ")
        )

        let axisFeat = doc.addDatumAxisFeature(
            name: "Normal Axis",
            data: DatumAxisFeatureData(mode: .normalToPlane),
            references: [.feature(planeFeat.id)]
        )

        let evaluated = try DatumAxisEvaluator.evaluate(feature: axisFeat, data: DatumAxisFeatureData(mode: .normalToPlane), in: doc)
        #expect(evaluated.origin == SketchPlane.xz.origin)
        #expect(evaluated.direction == SketchPlane.xz.normal)
    }

    @MainActor
    @Test func testDatumAxisDegenerateErrors() throws {
        // Coincident points
        let coincidentData = DatumAxisFeatureData(
            mode: .twoPoints,
            point1: SIMD3<Float>(5, 5, 5),
            point2: SIMD3<Float>(5, 5, 5)
        )
        #expect(throws: DatumAxisError.coincidentPoints) {
            try DatumAxisEvaluator.evaluate(data: coincidentData)
        }

        // Missing references
        let missingRefData = DatumAxisFeatureData(mode: .edge)
        #expect(throws: DatumAxisError.missingReference("Edge mode requires edge or line sketch entity reference")) {
            try DatumAxisEvaluator.evaluate(data: missingRefData)
        }
    }

    // MARK: - Datum Point Tests

    @MainActor
    @Test func testDatumPointCoordinates() throws {
        let coords = SIMD3<Float>(15.5, -20.0, 42.0)
        let data = DatumPointFeatureData(mode: .coordinates, coordinates: coords)
        let point = try DatumPointEvaluator.evaluate(data: data)
        #expect(point.position == coords)
    }

    @MainActor
    @Test func testDatumPointOnVertex() throws {
        let vertexRef = Reference.vertex(TopologicalReference(
            id: UUID(),
            sourceFeatureId: UUID(),
            elementType: .vertex,
            historyPath: [],
            disambiguator: GeometricSignature(
                normal: nil,
                centroid: SIMD3<Float>(10, 20, 30)
            )
        ))

        let data = DatumPointFeatureData(mode: .onVertex)
        let feature = Feature(name: "Vertex Pt", operation: .datumPoint(data), references: [vertexRef])
        let point = try DatumPointEvaluator.evaluate(feature: feature, data: data)
        #expect(point.position == SIMD3<Float>(10, 20, 30))
    }

    @MainActor
    @Test func testDatumPointArcCenter() throws {
        let doc = DocumentModel()
        let circle = SketchEntity.circle(center: SIMD2(25, 35), radius: 10)
        let sketch = doc.addSketchFeature(planeName: "XY", entities: [circle])

        let data = DatumPointFeatureData(mode: .arcCenter)
        let feature = Feature(
            name: "Center Pt",
            operation: .datumPoint(data),
            references: [.sketchEntity(featureId: sketch.id, entityId: circle.id)]
        )
        let point = try DatumPointEvaluator.evaluate(feature: feature, data: data, in: doc)
        #expect(point.position == SIMD3<Float>(25, 35, 0))
    }

    @MainActor
    @Test func testDatumPointAlongCurve() throws {
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(100, 0, 0)
        let data = DatumPointFeatureData(
            mode: .alongCurve,
            point1: p1,
            point2: p2,
            curveParameter: 0.25
        )
        let point = try DatumPointEvaluator.evaluate(data: data)
        #expect(point.position == SIMD3<Float>(25, 0, 0))
    }

    @MainActor
    @Test func testDatumPointMidpoint() throws {
        let p1 = SIMD3<Float>(10, 20, 30)
        let p2 = SIMD3<Float>(30, 40, 50)
        let data = DatumPointFeatureData(mode: .midpoint, point1: p1, point2: p2)
        let point = try DatumPointEvaluator.evaluate(data: data)
        #expect(point.position == SIMD3<Float>(20, 30, 40))
    }

    @MainActor
    @Test func testDatumPointIntersection() throws {
        // Line along Z from (15, 25, -50) to (15, 25, 50)
        // Plane is XY at Z = 0
        let doc = DocumentModel()
        let planeFeat = doc.addDatumPlaneFeature(
            name: "XY Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY")
        )

        let data = DatumPointFeatureData(
            mode: .intersection,
            point1: SIMD3<Float>(15, 25, -50),
            point2: SIMD3<Float>(15, 25, 50)
        )
        let feature = Feature(
            name: "Intersection Pt",
            operation: .datumPoint(data),
            references: [.feature(planeFeat.id)]
        )

        let point = try DatumPointEvaluator.evaluate(feature: feature, data: data, in: doc)
        #expect(point.position == SIMD3<Float>(15, 25, 0))

        // Parallel line -> throws noIntersection
        let parallelData = DatumPointFeatureData(
            mode: .intersection,
            point1: SIMD3<Float>(0, 0, 10),
            point2: SIMD3<Float>(10, 0, 10)
        )
        let parallelFeat = Feature(
            name: "Parallel Pt",
            operation: .datumPoint(parallelData),
            references: [.feature(planeFeat.id)]
        )
        #expect(throws: DatumPointError.noIntersection) {
            try DatumPointEvaluator.evaluate(feature: parallelFeat, data: parallelData, in: doc)
        }
    }

    // MARK: - Datum Coordinate System (UCS) Tests

    @MainActor
    @Test func testDatumCoordinateSystemOriginAndAxes() throws {
        let data = DatumCoordinateSystemFeatureData(
            mode: .originAndAxes,
            origin: SIMD3<Float>(10, 20, 30),
            xAxis: SIMD3<Float>(1, 0, 0),
            yAxis: SIMD3<Float>(0, 1, 0),
            zAxis: SIMD3<Float>(0, 0, 1)
        )
        let ucs = try DatumCoordinateSystemEvaluator.evaluate(data: data)
        #expect(ucs.origin == SIMD3<Float>(10, 20, 30))
        #expect(ucs.xAxis == SIMD3<Float>(1, 0, 0))
        #expect(ucs.yAxis == SIMD3<Float>(0, 1, 0))
        #expect(ucs.zAxis == SIMD3<Float>(0, 0, 1))

        // World <-> Local transformations
        let worldPt = SIMD3<Float>(15, 25, 35)
        let localPt = ucs.toLocal(point: worldPt)
        #expect(localPt == SIMD3<Float>(5, 5, 5))
        #expect(ucs.toWorld(point: localPt) == worldPt)

        let worldVec = SIMD3<Float>(0, 0, 10)
        let localVec = ucs.toLocal(vector: worldVec)
        #expect(localVec == SIMD3<Float>(0, 0, 10))
        #expect(ucs.toWorld(vector: localVec) == worldVec)

        // Transform representation
        let xform = ucs.asTransform
        #expect(xform.position == SIMD3<Float>(10, 20, 30))
    }

    @MainActor
    @Test func testDatumCoordinateSystemThreePoints() throws {
        // P1: Origin (0, 0, 0)
        // P2: Point on +X (10, 0, 0)
        // P3: Point on +XY (0, 20, 0)
        let data = DatumCoordinateSystemFeatureData(
            mode: .threePoints,
            point1: SIMD3<Float>(0, 0, 0),
            point2: SIMD3<Float>(10, 0, 0),
            point3: SIMD3<Float>(0, 20, 0)
        )
        let ucs = try DatumCoordinateSystemEvaluator.evaluate(data: data)
        #expect(ucs.origin == SIMD3<Float>(0, 0, 0))
        #expect(ucs.xAxis == SIMD3<Float>(1, 0, 0))
        #expect(ucs.yAxis == SIMD3<Float>(0, 1, 0))
        #expect(ucs.zAxis == SIMD3<Float>(0, 0, 1))

        // Collinear points error
        let collinearData = DatumCoordinateSystemFeatureData(
            mode: .threePoints,
            point1: SIMD3<Float>(0, 0, 0),
            point2: SIMD3<Float>(10, 0, 0),
            point3: SIMD3<Float>(20, 0, 0)
        )
        #expect(throws: DatumCoordinateSystemError.collinearPoints) {
            try DatumCoordinateSystemEvaluator.evaluate(data: collinearData)
        }

        // Coincident points error
        let coincidentData = DatumCoordinateSystemFeatureData(
            mode: .threePoints,
            point1: SIMD3<Float>(0, 0, 0),
            point2: SIMD3<Float>(0, 0, 0),
            point3: SIMD3<Float>(10, 10, 0)
        )
        #expect(throws: DatumCoordinateSystemError.coincidentPoints) {
            try DatumCoordinateSystemEvaluator.evaluate(data: coincidentData)
        }
    }

    @MainActor
    @Test func testDatumCoordinateSystemAlignedWithPlane() throws {
        let doc = DocumentModel()
        let planeFeat = doc.addDatumPlaneFeature(
            name: "XZ Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XZ", offsetDistance: 15.0)
        )

        let data = DatumCoordinateSystemFeatureData(mode: .alignedWithPlane)
        let ucsFeat = doc.addDatumCoordinateSystemFeature(
            name: "Plane UCS",
            data: data,
            references: [.feature(planeFeat.id)]
        )

        let ucs = try DatumCoordinateSystemEvaluator.evaluate(feature: ucsFeat, data: data, in: doc)
        #expect(ucs.origin == SIMD3<Float>(0, -15.0, 0))
        #expect(ucs.zAxis == SketchPlane.xz.normal)
        #expect(ucs.xAxis == SketchPlane.xz.xAxis)
    }

    @MainActor
    @Test func testDatumCoordinateSystemOffsetFromParent() throws {
        let doc = DocumentModel()
        let parentUCS = doc.addDatumCoordinateSystemFeature(
            name: "Parent UCS",
            data: DatumCoordinateSystemFeatureData(
                mode: .originAndAxes,
                origin: SIMD3<Float>(100, 0, 0)
            )
        )

        let childData = DatumCoordinateSystemFeatureData(
            mode: .offsetFromParent,
            offsetDistance: SIMD3<Float>(10, 20, 30),
            rotationAngles: SIMD3<Float>(0, 0, 90) // 90 deg rotation around Z
        )
        let childUCS = doc.addDatumCoordinateSystemFeature(
            name: "Child UCS",
            data: childData,
            references: [.feature(parentUCS.id)]
        )

        let evaluated = try DatumCoordinateSystemEvaluator.evaluate(feature: childUCS, data: childData, in: doc)
        #expect(evaluated.origin == SIMD3<Float>(110, 20, 30))
        #expect(abs(evaluated.xAxis.x) < 1e-5)
        #expect(abs(evaluated.xAxis.y - 1.0) < 1e-5)
    }

    // MARK: - DocumentModel Mutators & Undo/Redo

    @MainActor
    @Test func testDocumentModelMutatorsAndUndoRedo() throws {
        let doc = DocumentModel()

        // 1. Datum Axis
        let axis = doc.addDatumAxisFeature(
            name: "Test Axis",
            data: DatumAxisFeatureData(mode: .preset, presetName: "X")
        )
        #expect(doc.features.contains(where: { $0.id == axis.id }))
        #expect(doc.selection.contains(Reference.feature(axis.id)))

        // Undo axis add
        doc.undoManager?.undo()
        #expect(!doc.features.contains(where: { $0.id == axis.id }))

        // Redo axis add
        doc.undoManager?.redo()
        #expect(doc.features.contains(where: { $0.id == axis.id }))

        // 2. Datum Point
        let point = doc.addDatumPointFeature(
            name: "Test Point",
            data: DatumPointFeatureData(mode: .coordinates, coordinates: SIMD3<Float>(1, 2, 3))
        )
        #expect(doc.features.contains(where: { $0.id == point.id }))

        // Undo point add
        doc.undoManager?.undo()
        #expect(!doc.features.contains(where: { $0.id == point.id }))

        // Redo point add
        doc.undoManager?.redo()
        #expect(doc.features.contains(where: { $0.id == point.id }))

        // 3. Datum Coordinate System
        let ucs = doc.addDatumCoordinateSystemFeature(
            name: "Test UCS",
            data: DatumCoordinateSystemFeatureData(mode: .originAndAxes, origin: SIMD3<Float>(5, 5, 5))
        )
        #expect(doc.features.contains(where: { $0.id == ucs.id }))

        // Undo UCS add
        doc.undoManager?.undo()
        #expect(!doc.features.contains(where: { $0.id == ucs.id }))

        // Redo UCS add
        doc.undoManager?.redo()
        #expect(doc.features.contains(where: { $0.id == ucs.id }))

        // 4. UCS Query accessors
        let activeUCSList = doc.activeCoordinateSystems()
        #expect(activeUCSList.contains(where: { $0.id == ucs.id }))

        let geom = doc.coordinateSystemGeometry(id: ucs.id)
        #expect(geom != nil)
        #expect(geom?.origin == SIMD3<Float>(5, 5, 5))

        let exportXform = doc.exportTransform(coordinateSystemId: ucs.id)
        #expect(exportXform != nil)
        #expect(exportXform?.position == SIMD3<Float>(5, 5, 5))
    }

    // MARK: - Package Serialization Round Trip

    @MainActor
    @Test func testPackageSerializationRoundTrip() throws {
        let doc = DocumentModel()
        let axis = doc.addDatumAxisFeature(
            name: "Serialized Axis",
            data: DatumAxisFeatureData(mode: .preset, presetName: "Y", isFlipped: true)
        )
        let point = doc.addDatumPointFeature(
            name: "Serialized Point",
            data: DatumPointFeatureData(mode: .coordinates, coordinates: SIMD3<Float>(12, 34, 56))
        )
        let ucs = doc.addDatumCoordinateSystemFeature(
            name: "Serialized UCS",
            data: DatumCoordinateSystemFeatureData(mode: .originAndAxes, origin: SIMD3<Float>(78, 90, 12))
        )

        // Encode to JSON
        let encoded = try DocumentModelCoder.encode(document: doc)
        #expect(!encoded.isEmpty)

        // Decode into fresh DocumentModel
        let decodedDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: decodedDoc, from: encoded)

        #expect(decodedDoc.features.count == doc.features.count)

        // Verify Axis
        let decodedAxis = decodedDoc.feature(for: axis.id)
        #expect(decodedAxis != nil)
        #expect(decodedAxis?.name == "Serialized Axis")
        if case .datumAxis(let aData) = decodedAxis?.operation {
            #expect(aData.mode == .preset)
            #expect(aData.presetName == "Y")
            #expect(aData.isFlipped == true)
            #expect(aData.cachedAxis?.direction == SIMD3<Float>(0, -1, 0))
        } else {
            Issue.record("Expected .datumAxis operation on decoded feature")
        }

        // Verify Point
        let decodedPoint = decodedDoc.feature(for: point.id)
        #expect(decodedPoint != nil)
        #expect(decodedPoint?.name == "Serialized Point")
        if case .datumPoint(let pData) = decodedPoint?.operation {
            #expect(pData.mode == .coordinates)
            #expect(pData.coordinates == SIMD3<Float>(12, 34, 56))
            #expect(pData.cachedPoint?.position == SIMD3<Float>(12, 34, 56))
        } else {
            Issue.record("Expected .datumPoint operation on decoded feature")
        }

        // Verify UCS
        let decodedUCS = decodedDoc.feature(for: ucs.id)
        #expect(decodedUCS != nil)
        #expect(decodedUCS?.name == "Serialized UCS")
        if case .datumCoordinateSystem(let uData) = decodedUCS?.operation {
            #expect(uData.mode == .originAndAxes)
            #expect(uData.origin == SIMD3<Float>(78, 90, 12))
            #expect(uData.cachedCoordinateSystem?.origin == SIMD3<Float>(78, 90, 12))
        } else {
            Issue.record("Expected .datumCoordinateSystem operation on decoded feature")
        }
    }

    // MARK: - Kernel Regeneration Cascades

    @MainActor
    @Test func testKernelRegenerationCascadeAndRecovery() async {
        let doc = DocumentModel()
        let brokenAxis = doc.addDatumAxisFeature(
            name: "Broken Axis",
            data: DatumAxisFeatureData(mode: .twoPoints, point1: SIMD3(0, 0, 0), point2: SIMD3(0, 0, 0)) // Coincident!
        )

        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(5))
        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)

        let evaluatedBroken = doc.feature(for: brokenAxis.id)
        #expect(evaluatedBroken?.errorState != nil)
        #expect(evaluatedBroken?.errorState?.code == "datum-axis-error")

        // Dependent UCS receives parent-failed cascade warning
        let dependentUCS = doc.addDatumCoordinateSystemFeature(
            name: "Dependent UCS",
            data: DatumCoordinateSystemFeatureData(mode: .offsetFromParent),
            references: [.feature(brokenAxis.id)]
        )
        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)

        let evaluatedDep = doc.feature(for: dependentUCS.id)
        #expect(evaluatedDep?.errorState != nil)
        #expect(evaluatedDep?.errorState?.code == "parent-failed")

        // Fix upstream axis -> regeneration clears parent-failed
        var fixedAxis = brokenAxis
        fixedAxis.operation = .datumAxis(DatumAxisFeatureData(mode: .twoPoints, point1: SIMD3(0, 0, 0), point2: SIMD3(0, 10, 0)))
        _ = doc.updateFeature(fixedAxis)

        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)
        let restoredAxis = doc.feature(for: brokenAxis.id)
        #expect(restoredAxis?.errorState == nil)

        let restoredDep = doc.feature(for: dependentUCS.id)
        #expect(restoredDep?.errorState == nil)
    }
}
