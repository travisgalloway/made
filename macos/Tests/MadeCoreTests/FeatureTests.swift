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
        let box = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        #expect(box.outputSolidId == boxSolidId)
        #expect(box.inputExpressions["width"]?.value == 40.0)
        #expect(box.inputExpressions["depth"]?.value == 30.0)
        #expect(box.inputExpressions["height"]?.value == 20.0)
        #expect(box.generatedTopology["face:top"] != nil)
        #expect(box.generatedTopology["face:bottom"] != nil)
        #expect(box.generatedTopology["face:front"] != nil)
        #expect(box.generatedTopology["face:back"] != nil)
        #expect(box.generatedTopology["face:left"] != nil)
        #expect(box.generatedTopology["face:right"] != nil)
        #expect(box.generatedTopology["face:top"]?.disambiguator?.normal == SIMD3<Float>(0, 0, 1))

        let cylinder = Feature.makeCylinder(
            solidId: cylinderSolidId,
            params: CylinderParams(radius: 15, height: 40)
        )
        #expect(cylinder.outputSolidId == cylinderSolidId)
        #expect(cylinder.inputExpressions["radius"]?.value == 15.0)
        #expect(cylinder.inputExpressions["height"]?.value == 40.0)
        #expect(cylinder.generatedTopology["face:top"] != nil)
        #expect(cylinder.generatedTopology["face:bottom"] != nil)
        #expect(cylinder.generatedTopology["face:side"] != nil)
        #expect(cylinder.generatedTopology["face:side"]?.disambiguator?.surfaceOrCurveType == "cylinder")
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

        doc.setFeatureError(id: boxFeature.id, error: nil)
        #expect(doc.features[0].errorState == nil)
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
}
