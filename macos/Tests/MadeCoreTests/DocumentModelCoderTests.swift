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
}
