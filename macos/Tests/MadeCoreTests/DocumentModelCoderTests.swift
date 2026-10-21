import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct DocumentModelCoderTests {
    @Test func testDocumentDataBodiesRoundTrip() throws {
        let doc = DocumentModel()
        let encoded = try DocumentModelCoder.encode(document: doc)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.bodies?.count == 2)
        #expect(decoded.bodies?.map(\.id) == [boxSolidId, cylinderSolidId])
        #expect(decoded.bodies?.first?.name == "box-1")
    }

    @Test func testDocumentDataWithoutBodiesDecodesFallback() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "name": "My Box",
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
        #expect(decoded.bodies != nil)
        #expect(decoded.bodies?.count == 1)
        #expect(decoded.bodies?.first?.id == SolidId("box-1"))
        #expect(decoded.bodies?.first?.name == "My Box")
    }

    @Test func testDocumentDataDecodeIntoDocumentModelRestoresBodies() throws {
        let doc = DocumentModel()
        let encoded = try DocumentModelCoder.encode(document: doc)

        let targetDoc = DocumentModel(features: [])
        #expect(targetDoc.bodies.isEmpty)

        try DocumentModelCoder.decode(into: targetDoc, from: encoded)
        #expect(targetDoc.bodies.count == 2)
        #expect(targetDoc.bodies.map(\.id) == [boxSolidId, cylinderSolidId])
    }

    // MARK: - Selection Serialization (BL-SEL-03)

    @Test func testDocumentDataSelectionRoundTrip() throws {
        let doc = DocumentModel()
        let topRef = try #require(doc.features[0].generatedTopology["face:top"])
        let boxRef = Reference.body(boxSolidId)
        let faceRef = Reference.face(topRef)
        doc.selection = [boxRef, faceRef]

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decodedData = try DocumentModelCoder.decode(from: encoded)

        #expect(decodedData.selection != nil)
        #expect(decodedData.selection?.count == 2)

        let restoredDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        #expect(restoredDoc.selection.contains(boxRef))
        #expect(restoredDoc.selection.contains(faceRef))
        #expect(restoredDoc.selection.count == 2)
        #expect(restoredDoc.selectedId == boxSolidId)
    }

    @Test func testLegacyDocumentDataDecodesSelection() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "name": "My Box",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ],
          "selectedId": "box-1"
        }
        """.data(using: .utf8)!

        let decodedData = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decodedData.selectedId == SolidId("box-1"))
        #expect(decodedData.selection == nil)

        let targetDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: targetDoc, from: legacyJSON)

        #expect(targetDoc.selectedId == SolidId("box-1"))
        #expect(targetDoc.selection == [Reference.body(SolidId("box-1"))])
    }

    @Test func testDocumentDataEmptySelectionRoundTrip() throws {
        let doc = DocumentModel()
        doc.clearSelection()
        #expect(doc.selection.isEmpty)
        #expect(doc.selectedId == nil)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decodedData = try DocumentModelCoder.decode(from: encoded)
        #expect(decodedData.selection?.isEmpty == true)
        #expect(decodedData.selectedId == nil)

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)
        #expect(restoredDoc.selection.isEmpty)
        #expect(restoredDoc.selectedId == nil)
    }

    // MARK: - Single-Owner document.json (Issue #562 / API-006dc4bd)

    @Test func testDocumentDataOmitsObjectsAndBodiesWhenFeaturesPresent() throws {
        let doc = DocumentModel()
        #expect(!doc.features.isEmpty)
        #expect(!doc.objects.isEmpty)
        #expect(!doc.bodies.isEmpty)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let jsonObject = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(jsonObject["features"] != nil)
        #expect(jsonObject["objects"] == nil)
        #expect(jsonObject["bodies"] == nil)
    }

    @Test func testDocumentDataDecodesDerivedObjectsAndBodiesWhenOmitted() throws {
        let jsonWithFeaturesOnly = """
        {
          "schemaVersion": 1,
          "features": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Custom Box",
              "outputSolidId": "box-1",
              "operation": {
                "primitive": {
                  "box": {
                    "width": 50.0,
                    "depth": 40.0,
                    "height": 30.0
                  }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: jsonWithFeaturesOnly)
        #expect(decoded.features?.count == 1)
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects.first?.id == SolidId("box-1"))
        #expect(decoded.objects.first?.name == "Custom Box")
        #expect(decoded.bodies?.count == 1)
        #expect(decoded.bodies?.first?.id == SolidId("box-1"))
        #expect(decoded.bodies?.first?.name == "Custom Box")
    }

    @Test func testDocumentDataRejectsObjectsDisagreeingWithFeatures() throws {
        let conflictingJSON = """
        {
          "schemaVersion": 1,
          "features": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Custom Box",
              "outputSolidId": "box-1",
              "operation": {
                "primitive": {
                  "box": {
                    "width": 50.0,
                    "depth": 40.0,
                    "height": 30.0
                  }
                }
              }
            }
          ],
          "objects": [
            {
              "id": "box-1",
              "name": "Conflicting Name",
              "def": {
                "kind": "box",
                "params": {
                  "width": 99.0,
                  "depth": 40.0,
                  "height": 30.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try DocumentModelCoder.decode(from: conflictingJSON)
        }

        do {
            _ = try DocumentModelCoder.decode(from: conflictingJSON)
            Issue.record("Expected decoding to throw DecodingError.dataCorrupted")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("Declared objects disagree with active features projection"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testDocumentDataRejectsBodiesDisagreeingWithFeatures() throws {
        let conflictingJSON = """
        {
          "schemaVersion": 1,
          "features": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Custom Box",
              "outputSolidId": "box-1",
              "operation": {
                "primitive": {
                  "box": {
                    "width": 50.0,
                    "depth": 40.0,
                    "height": 30.0
                  }
                }
              }
            }
          ],
          "bodies": [
            {
              "id": "box-99",
              "name": "Mismatched Body",
              "type": "solid",
              "isVisible": true,
              "isLocked": false,
              "material": {
                "color": [0.35, 0.65, 0.95, 1.0]
              },
              "transform": {
                "position": [0, 0, 0],
                "rotation": {"w": 1, "x": 0, "y": 0, "z": 0},
                "scale": [1, 1, 1]
              }
            }
          ]
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try DocumentModelCoder.decode(from: conflictingJSON)
        }

        do {
            _ = try DocumentModelCoder.decode(from: conflictingJSON)
            Issue.record("Expected decoding to throw DecodingError.dataCorrupted")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("Declared bodies disagree with active features projection"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testDocumentDataAcceptsMatchingObjectsAndBodies() throws {
        let doc = DocumentModel()
        let activeObjects = doc.activeFeatures.compactMap { $0.toSceneObject() }
        let activeBodies = activeObjects.map { Body(from: $0) }

        let legacyData = DocumentData(
            schemaVersion: 1,
            features: doc.features,
            objects: activeObjects,
            selectedId: doc.selectedId,
            rollbackIndex: doc.rollbackIndex,
            bodies: activeBodies,
            selection: Array(doc.selection)
        )

        var dict = try #require(try JSONSerialization.jsonObject(with: try DocumentModelCoder.encode(legacyData)) as? [String: Any])
        dict["objects"] = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(activeObjects))
        dict["bodies"] = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(activeBodies))
        let payloadWithExplicitMatching = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try DocumentModelCoder.decode(from: payloadWithExplicitMatching)
        #expect(decoded.features?.count == doc.features.count)
        #expect(decoded.objects == activeObjects)
        #expect(decoded.bodies == activeBodies)
    }

    // MARK: - Document Parameters Serialization (BL-PAR-01)

    @Test func testDocumentParametersRoundTrip() throws {
        let doc = DocumentModel()
        let p1 = DocumentParameter(name: "box_width", value: 50.0, unit: "mm", comment: "Primary width")
        let p2 = DocumentParameter(name: "box_height", value: 30.0, unit: "mm", comment: "Primary height")
        try doc.addParameter(p1)
        try doc.addParameter(p2)
        doc.setParam(id: boxSolidId, key: "width", value: 50.0, expression: "box_width")

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decodedData = try DocumentModelCoder.decode(from: encoded)
        #expect(decodedData.parameters?.count == 2)
        #expect(decodedData.parameters?[0].name == "box_width")
        #expect(decodedData.parameters?[0].value == 50.0)
        #expect(decodedData.parameters?[0].comment == "Primary width")
        #expect(decodedData.parameters?[1].name == "box_height")

        let targetDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: targetDoc, from: encoded)
        #expect(targetDoc.parameters.count == 2)
        #expect(targetDoc.parameters[0].name == "box_width")
        #expect(targetDoc.parameters[0].value == 50.0)
        #expect(targetDoc.parameters[1].name == "box_height")
        #expect(targetDoc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.formula == "box_width")
    }

    @Test func testDocumentParametersLegacyDecodeDefaultsEmpty() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "name": "Box 1",
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
        #expect(decoded.parameters == nil)

        let targetDoc = DocumentModel()
        try targetDoc.addParameter(DocumentParameter(name: "temp", value: 1.0))
        #expect(targetDoc.parameters.count == 1)

        try DocumentModelCoder.decode(into: targetDoc, from: legacyJSON)
        #expect(targetDoc.parameters.isEmpty)
    }

    // MARK: - Parameter Range Constraints Serialization (BL-PAR-06)

    @Test func testDocumentParametersRangeRoundTrip() throws {
        let doc = DocumentModel()
        let p1 = DocumentParameter(
            name: "walled_width",
            value: 45.0,
            unit: "mm",
            comment: "Wall width constraint",
            min: 10.0,
            max: 100.0,
            step: 0.5
        )
        let p2 = DocumentParameter(
            name: "unbounded_depth",
            value: 20.0,
            unit: "mm"
        )
        try doc.addParameter(p1)
        try doc.addParameter(p2)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decodedData = try DocumentModelCoder.decode(from: encoded)

        #expect(decodedData.parameters?.count == 2)
        let d1 = try #require(decodedData.parameters?[0])
        #expect(d1.name == "walled_width")
        #expect(d1.value == 45.0)
        #expect(d1.min == 10.0)
        #expect(d1.max == 100.0)
        #expect(d1.step == 0.5)

        let d2 = try #require(decodedData.parameters?[1])
        #expect(d2.name == "unbounded_depth")
        #expect(d2.min == nil)
        #expect(d2.max == nil)
        #expect(d2.step == nil)

        let targetDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: targetDoc, from: encoded)
        #expect(targetDoc.parameters.count == 2)
        #expect(targetDoc.parameters[0].name == "walled_width")
        #expect(targetDoc.parameters[0].min == 10.0)
        #expect(targetDoc.parameters[0].max == 100.0)
        #expect(targetDoc.parameters[0].step == 0.5)
        #expect(targetDoc.parameters[1].min == nil)
        #expect(targetDoc.parameters[1].max == nil)
        #expect(targetDoc.parameters[1].step == nil)
    }

    @Test func testLegacyDocumentParameterDecodesWithNilRanges() throws {
        let legacyParameterJSON = """
        {
          "schemaVersion": 1,
          "objects": [],
          "parameters": [
            {
              "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
              "name": "legacy_param",
              "value": 35.0,
              "unit": "mm",
              "comment": "Legacy parameter without ranges"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyParameterJSON)
        let param = try #require(decoded.parameters?.first)
        #expect(param.name == "legacy_param")
        #expect(param.value == 35.0)
        #expect(param.min == nil)
        #expect(param.max == nil)
        #expect(param.step == nil)

        let targetDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: targetDoc, from: legacyParameterJSON)
        #expect(targetDoc.parameters.count == 1)
        #expect(targetDoc.parameters[0].name == "legacy_param")
        #expect(targetDoc.parameters[0].min == nil)
        #expect(targetDoc.parameters[0].max == nil)
        #expect(targetDoc.parameters[0].step == nil)
    }
}
