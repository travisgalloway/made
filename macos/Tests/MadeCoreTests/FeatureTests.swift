import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct FeatureTests {
    @Test func testFeatureCreationAndDefaults() {
        let featureId = UUID()
        let feature = Feature(
            id: featureId,
            name: "Custom Feature",
            operation: .primitive(.box(BoxParams(width: 10, depth: 20, height: 30))),
            inputExpressions: ["width": FeatureExpression(value: 10.0)],
            outputSolidId: SolidId("custom-1")
        )

        #expect(feature.id == featureId)
        #expect(feature.name == "Custom Feature")
        #expect(feature.outputSolidId == SolidId("custom-1"))
        #expect(!feature.isSuppressed)
        #expect(feature.errorState == nil)
        #expect(feature.isVisible)
        #expect(!feature.isLocked)
        #expect(feature.inputExpressions["width"]?.value == 10.0)
    }

    @Test func testDefaultBoxAndCylinderPrimitiveFeatures() {
        let fixedBoxId = UUID()
        let box = Feature.makeBox(
            id: fixedBoxId,
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        #expect(box.outputSolidId == boxSolidId)
        #expect(box.inputExpressions["width"]?.value == 40.0)
        #expect(box.inputExpressions["depth"]?.value == 30.0)
        #expect(box.inputExpressions["height"]?.value == 20.0)
        #expect(box.generatedTopology.count == 26)

        // 6 Faces
        let expectedFaces = ["face:top", "face:bottom", "face:front", "face:back", "face:left", "face:right"]
        for faceKey in expectedFaces {
            let ref = box.generatedTopology[faceKey]
            #expect(ref != nil, "Missing face \(faceKey)")
            #expect(ref?.elementType == .face)
            #expect(ref?.disambiguator?.surfaceOrCurveType == "plane")
        }
        #expect(box.generatedTopology["face:top"]?.disambiguator?.normal == SIMD3<Float>(0, 0, 1))

        // 12 Edges
        let expectedEdges = [
            "edge:top-front", "edge:top-back", "edge:top-left", "edge:top-right",
            "edge:bottom-front", "edge:bottom-back", "edge:bottom-left", "edge:bottom-right",
            "edge:front-left", "edge:front-right", "edge:back-left", "edge:back-right"
        ]
        for edgeKey in expectedEdges {
            let ref = box.generatedTopology[edgeKey]
            #expect(ref != nil, "Missing edge \(edgeKey)")
            #expect(ref?.elementType == .edge)
            #expect(ref?.disambiguator?.surfaceOrCurveType == "line")
        }

        // 8 Vertices
        let expectedVertices = [
            "vertex:top-front-left", "vertex:top-front-right", "vertex:top-back-left", "vertex:top-back-right",
            "vertex:bottom-front-left", "vertex:bottom-front-right", "vertex:bottom-back-left", "vertex:bottom-back-right"
        ]
        for vertKey in expectedVertices {
            let ref = box.generatedTopology[vertKey]
            #expect(ref != nil, "Missing vertex \(vertKey)")
            #expect(ref?.elementType == .vertex)
            #expect(ref?.disambiguator?.centroid != nil)
        }

        // Deterministic ID invariance under dimension change
        let resizedBox = Feature.makeBox(
            id: fixedBoxId,
            solidId: boxSolidId,
            params: BoxParams(width: 80, depth: 50, height: 35)
        )
        #expect(resizedBox.generatedTopology.count == 26)
        for key in box.generatedTopology.keys {
            #expect(box.generatedTopology[key]?.id == resizedBox.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        let fixedCylinderId = UUID()
        let cylinder = Feature.makeCylinder(
            id: fixedCylinderId,
            solidId: cylinderSolidId,
            params: CylinderParams(radius: 15, height: 40)
        )
        #expect(cylinder.outputSolidId == cylinderSolidId)
        #expect(cylinder.inputExpressions["radius"]?.value == 15.0)
        #expect(cylinder.inputExpressions["height"]?.value == 40.0)
        #expect(cylinder.generatedTopology.count == 8)

        #expect(cylinder.generatedTopology["face:top"]?.elementType == .face)
        #expect(cylinder.generatedTopology["face:bottom"]?.elementType == .face)
        #expect(cylinder.generatedTopology["face:side"]?.elementType == .face)
        #expect(cylinder.generatedTopology["face:side"]?.disambiguator?.surfaceOrCurveType == "cylinder")

        #expect(cylinder.generatedTopology["edge:top"]?.elementType == .edge)
        #expect(cylinder.generatedTopology["edge:bottom"]?.elementType == .edge)
        #expect(cylinder.generatedTopology["edge:seam"]?.elementType == .edge)
        #expect(cylinder.generatedTopology["edge:top"]?.disambiguator?.surfaceOrCurveType == "circle")
        #expect(cylinder.generatedTopology["edge:seam"]?.disambiguator?.surfaceOrCurveType == "line")

        #expect(cylinder.generatedTopology["vertex:top-seam"]?.elementType == .vertex)
        #expect(cylinder.generatedTopology["vertex:bottom-seam"]?.elementType == .vertex)

        // Cylinder deterministic ID invariance under dimension change
        let resizedCylinder = Feature.makeCylinder(
            id: fixedCylinderId,
            solidId: cylinderSolidId,
            params: CylinderParams(radius: 30, height: 80)
        )
        #expect(resizedCylinder.generatedTopology.count == 8)
        for key in cylinder.generatedTopology.keys {
            #expect(cylinder.generatedTopology[key]?.id == resizedCylinder.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }
    }

    @Test func testAllFeatureOperations() {
        let sketchEntity = SketchEntity(kind: "line", data: ["length": 25.0])
        let sketchData = SketchFeatureData(planeName: "XY", entities: [sketchEntity])
        let sketchFeature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        if case .sketch(let data) = sketchFeature.operation {
            #expect(data.planeName == "XY")
            #expect(data.entities.count == 1)
            #expect(data.entities[0].data["length"] == 25.0)
        } else {
            Issue.record("Expected sketch operation")
        }

        let extrudeData = ExtrudeFeatureData(
            sketchFeatureId: sketchFeature.id,
            distance: 50.0,
            isSymmetric: true,
            draftAngle: 1.5
        )
        let extrudeFeature = Feature(name: "Extrude 1", operation: .extrude(extrudeData))
        if case .extrude(let data) = extrudeFeature.operation {
            #expect(data.sketchFeatureId == sketchFeature.id)
            #expect(data.distance == 50.0)
            #expect(data.isSymmetric)
            #expect(data.draftAngle == 1.5)
        } else {
            Issue.record("Expected extrude operation")
        }

        let booleanData = BooleanFeatureData(
            op: .subtract,
            targetSolidId: boxSolidId,
            toolSolidId: cylinderSolidId
        )
        let booleanFeature = Feature(name: "Boolean 1", operation: .boolean(booleanData))
        if case .boolean(let data) = booleanFeature.operation {
            #expect(data.op == .subtract)
            #expect(data.targetSolidId == boxSolidId)
            #expect(data.toolSolidId == cylinderSolidId)
        } else {
            Issue.record("Expected boolean operation")
        }

        let partData = PartFeatureData(url: URL(fileURLWithPath: "/parts/bracket.part.ts"), shape: nil)
        let partFeature = Feature(name: "Part 1", operation: .part(partData))
        if case .part(let data) = partFeature.operation {
            #expect(data.url.lastPathComponent == "bracket.part.ts")
            #expect(data.shape == nil)
        } else {
            Issue.record("Expected part operation")
        }

        let importedData = ImportedFeatureData(name: "model.step", data: Data([10, 20, 30]))
        let importedFeature = Feature(name: "Imported 1", operation: .imported(importedData))
        if case .imported(let data) = importedFeature.operation {
            #expect(data.name == "model.step")
            #expect(data.data == Data([10, 20, 30]))
        } else {
            Issue.record("Expected imported operation")
        }
    }

    @Test func testFeatureExpressionStorageAndEvaluation() {
        let exprWithFormula = FeatureExpression(formula: "width * 2", value: 80.0)
        #expect(exprWithFormula.formula == "width * 2")
        #expect(exprWithFormula.value == 80.0)

        let exprFromDouble = FeatureExpression(value: 42.5)
        #expect(exprFromDouble.formula == "42.5")
        #expect(exprFromDouble.value == 42.5)

        let exprFromFloat = FeatureExpression(value: Float(15.25))
        #expect(exprFromFloat.value == Double(Float(15.25)))
    }

    @Test func testTypedTopologicalReferences() {
        let sourceId = UUID()
        let step = HistoryStep(kind: .generated, label: "face:top", sourceIndex: 0)
        let sig = GeometricSignature(
            surfaceOrCurveType: "plane",
            normal: SIMD3<Float>(0, 0, 1),
            centroid: SIMD3<Float>(0, 0, 10),
            areaOrLength: 1200.0
        )
        let ref = TopologicalReference(
            sourceFeatureId: sourceId,
            elementType: .face,
            historyPath: [step],
            disambiguator: sig
        )

        #expect(ref.sourceFeatureId == sourceId)
        #expect(ref.elementType == .face)
        #expect(ref.historyPath.count == 1)
        #expect(ref.historyPath[0].kind == .generated)
        #expect(ref.disambiguator?.normal == SIMD3<Float>(0, 0, 1))
        #expect(ref.disambiguator?.areaOrLength == 1200.0)
    }

    @Test func testSuppressionExcludesFromProjectedObjects() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)
        #expect(doc.objects.count == 2)

        let boxFeature = doc.features[0]
        #expect(boxFeature.outputSolidId == boxSolidId)

        let suppressResult = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        #expect(suppressResult == .success(()))
        #expect(doc.features[0].isSuppressed)
        #expect(doc.objects.count == 1)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.objects.first?.id == cylinderSolidId)

        let unsuppressResult = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: false)
        #expect(unsuppressResult == .success(()))
        #expect(!doc.features[0].isSuppressed)
        #expect(doc.objects.count == 2)
        #expect(doc.objects.contains(where: { $0.id == boxSolidId }))
    }

    @Test func testUndoRedoFeatureSuppression() {
        let doc = DocumentModel()
        let boxFeature = doc.features[0]

        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        #expect(doc.objects.count == 1)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Suppress Feature")

        doc.undo()
        #expect(doc.objects.count == 2)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Suppress Feature")

        doc.redo()
        #expect(doc.objects.count == 1)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
    }

    @Test func testFeatureErrorStateRecordingAndClearing() {
        let doc = DocumentModel()
        let boxFeature = doc.features[0]

        let error = FeatureErrorState(code: "geometry-failed", message: "Non-manifold boolean result")
        doc.setFeatureError(id: boxFeature.id, error: error)

        #expect(doc.features[0].errorState?.code == "geometry-failed")
        #expect(doc.features[0].errorState?.message == "Non-manifold boolean result")
        #expect(doc.features[0].errorState?.severity == .error)

        doc.setFeatureError(id: boxFeature.id, error: nil)
        #expect(doc.features[0].errorState == nil)
    }

    @Test func testFeatureErrorSeverityDefaultAndCustomValues() {
        let defaultError = FeatureErrorState(code: "invalid-params", message: "Negative width")
        #expect(defaultError.severity == .error)

        let customWarning = FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
        #expect(customWarning.severity == .warning)
        #expect(customWarning.code == "parent-failed")
        #expect(customWarning.message == "parent failed")
    }

    @Test func testFeatureErrorStateBackwardCompatibleDecoding() throws {
        let legacyJSON = """
        {
          "code": "legacy-error",
          "message": "Legacy failure message"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FeatureErrorState.self, from: legacyJSON)
        #expect(decoded.code == "legacy-error")
        #expect(decoded.message == "Legacy failure message")
        #expect(decoded.severity == .error)
    }

    @Test func testFeatureErrorStateCodableRoundTripWithWarning() throws {
        let state = FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(FeatureErrorState.self, from: data)

        #expect(decoded.code == "parent-failed")
        #expect(decoded.message == "parent failed")
        #expect(decoded.severity == .warning)
    }

    @Test func testJSONSerializationRoundTrip() throws {
        let boxFeature = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )

        let encoder = DocumentModelCoder.makeJSONEncoder()
        let decoder = DocumentModelCoder.makeJSONDecoder()

        let data = try encoder.encode(boxFeature)
        let decoded = try decoder.decode(Feature.self, from: data)

        #expect(decoded.id == boxFeature.id)
        #expect(decoded.name == boxFeature.name)
        #expect(decoded.outputSolidId == boxFeature.outputSolidId)
        #expect(decoded.inputExpressions == boxFeature.inputExpressions)
        #expect(decoded.generatedTopology.count == boxFeature.generatedTopology.count)

        // DocumentData round trip
        let doc = DocumentModel()
        let encodedDoc = try DocumentModelCoder.encode(document: doc)
        let decodedData = try DocumentModelCoder.decode(from: encodedDoc)

        #expect(decodedData.features?.count == 2)
        #expect(decodedData.objects.count == 2)
        #expect(decodedData.features?[0].outputSolidId == boxSolidId)
        #expect(decodedData.features?[1].outputSolidId == cylinderSolidId)
    }

    @Test func testLegacyDocumentDataSynthesizesFeatures() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decoded.objects.count == 1)
        #expect(decoded.features?.count == 1)

        let synthesized = try #require(decoded.features?.first)
        #expect(synthesized.outputSolidId == boxSolidId)
        #expect(synthesized.inputExpressions["width"]?.value == 30.0)
        #expect(synthesized.inputExpressions["depth"]?.value == 20.0)
        #expect(synthesized.inputExpressions["height"]?.value == 10.0)
    }

    @Test func testBooleanFeatureDataKeepToolSerializationAndBackwardCompatibility() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // With keepTool: true
        let dataWithKeepTool = BooleanFeatureData(op: .union, targetSolidId: SolidId("a"), toolSolidId: SolidId("b"), keepTool: true)
        let encoded = try encoder.encode(dataWithKeepTool)
        let decoded = try decoder.decode(BooleanFeatureData.self, from: encoded)
        #expect(decoded.op == .union)
        #expect(decoded.targetSolidId == SolidId("a"))
        #expect(decoded.toolSolidId == SolidId("b"))
        #expect(decoded.keepTool == true)

        // Legacy JSON without keepTool key defaults to false
        let legacyJSON = """
        {
          "op": "subtract",
          "targetSolidId": "box-1",
          "toolSolidId": "cylinder-1"
        }
        """.data(using: .utf8)!
        let legacyDecoded = try decoder.decode(BooleanFeatureData.self, from: legacyJSON)
        #expect(legacyDecoded.op == .subtract)
        #expect(legacyDecoded.targetSolidId == SolidId("box-1"))
        #expect(legacyDecoded.toolSolidId == SolidId("cylinder-1"))
        #expect(legacyDecoded.keepTool == false)
    }

    // MARK: - Rollback Marker (BL-FND-05)

    @Test func testRollbackMarkerExcludesFromProjectedObjects() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)
        #expect(doc.activeFeatures.count == 2)
        #expect(doc.objects.count == 2)
        #expect(!doc.isRolledBack)
        #expect(doc.rollbackIndex == nil)
        #expect(doc.effectiveRollbackIndex == 2)

        // Roll back to 1
        doc.setRollbackIndex(1)
        #expect(doc.isRolledBack)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.effectiveRollbackIndex == 1)
        #expect(doc.activeFeatures.count == 1)
        #expect(doc.rolledBackFeatures.count == 1)
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.id == boxSolidId)

        // Roll back to 0
        doc.setRollbackIndex(0)
        #expect(doc.isRolledBack)
        #expect(doc.rollbackIndex == 0)
        #expect(doc.effectiveRollbackIndex == 0)
        #expect(doc.activeFeatures.isEmpty)
        #expect(doc.rolledBackFeatures.count == 2)
        #expect(doc.objects.isEmpty)
        #expect(doc.selectedId == nil)
    }

    @Test func testRollbackMarkerClamping() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)

        // Negative index clamps to 0
        doc.setRollbackIndex(-5)
        #expect(doc.rollbackIndex == 0)
        #expect(doc.isRolledBack)

        // Index >= count normalizes to nil (unrolled)
        doc.setRollbackIndex(2)
        #expect(doc.rollbackIndex == nil)
        #expect(!doc.isRolledBack)

        doc.setRollbackIndex(100)
        #expect(doc.rollbackIndex == nil)
        #expect(!doc.isRolledBack)
    }

    @Test func testRollbackDataSerializationRoundTrip() throws {
        let f1 = Feature.makeBox(solidId: boxSolidId, params: BoxParams(width: 20, depth: 20, height: 20))
        let f2 = Feature.makeCylinder(solidId: cylinderSolidId, params: CylinderParams(radius: 10, height: 30))
        let docData = DocumentData(
            schemaVersion: 1,
            features: [f1, f2],
            selectedId: boxSolidId,
            rollbackIndex: 1
        )

        let encoded = try DocumentModelCoder.encode(docData)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.rollbackIndex == 1)
        #expect(decoded.features?.count == 2)
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects.first?.id == boxSolidId)
    }

    @Test func testRollbackDataBackwardCompatibility() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decoded.rollbackIndex == nil)
        #expect(decoded.objects.count == 1)
        #expect(decoded.features?.count == 1)
    }

    // MARK: - Body Operation & Target Body Tests (BL-FND-12)

    @Test func testFeatureBodyOperationAndTargetDefaults() {
        let f = Feature.makeBox(solidId: boxSolidId, params: BoxParams(width: 10, depth: 10, height: 10))
        #expect(f.bodyOperation == .create)
        #expect(f.targetBodyId == nil)

        let fCut = Feature.makeCylinder(
            solidId: SolidId("cut-1"),
            params: CylinderParams(radius: 5, height: 10),
            bodyOperation: .cut,
            targetBodyId: boxSolidId
        )
        #expect(fCut.bodyOperation == .cut)
        #expect(fCut.targetBodyId == boxSolidId)
    }

    @Test func testFeatureBodyOperationSerializationRoundTrip() throws {
        let feature = Feature(
            name: "Boolean Add",
            operation: .primitive(.box(BoxParams(width: 20, depth: 20, height: 20))),
            outputSolidId: SolidId("box-add"),
            bodyOperation: .add,
            targetBodyId: SolidId("target-solid-1")
        )

        let encoder = DocumentModelCoder.makeJSONEncoder()
        let data = try encoder.encode(feature)
        let decoder = DocumentModelCoder.makeJSONDecoder()
        let decoded = try decoder.decode(Feature.self, from: data)

        #expect(decoded.bodyOperation == .add)
        #expect(decoded.targetBodyId == SolidId("target-solid-1"))
        #expect(decoded.name == "Boolean Add")
    }

    @Test func testFeatureLegacyPayloadDecodesWithDefaultBodyOperationAndNilTargetBodyId() throws {
        let boxFeature = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        let encoder = DocumentModelCoder.makeJSONEncoder()
        let data = try encoder.encode(boxFeature)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "bodyOperation")
        dict.removeValue(forKey: "targetBodyId")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = DocumentModelCoder.makeJSONDecoder()
        let decoded = try decoder.decode(Feature.self, from: legacyData)

        #expect(decoded.bodyOperation == .create)
        #expect(decoded.targetBodyId == nil)
        #expect(decoded.outputSolidId == boxSolidId)
        #expect(decoded.name == boxFeature.name)
    }
}
