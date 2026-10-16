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
}
