import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct SimulationDocumentCoderTests {

    @Test func testSimulationDocumentRoundTrip() throws {
        let study = SimulationStudy(
            name: "Cantilever Beam",
            studyType: .linearStatic,
            fixtures: [
                SimulationFixture(name: "Root Fixed", kind: .fixed)
            ],
            loads: [
                SimulationLoad(name: "Tip Load", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
            ]
        )

        let sourceDoc = DocumentModel()
        sourceDoc.addStudy(study)
        sourceDoc.setActiveStudy(id: study.id)

        let encoded = try DocumentModelCoder.encode(document: sourceDoc)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.studies?.count == 1)
        #expect(decoded.studies?.first?.name == "Cantilever Beam")
        #expect(decoded.studies?.first?.studyType == .linearStatic)
        #expect(decoded.studies?.first?.fixtures.count == 1)
        #expect(decoded.studies?.first?.loads.count == 1)
        #expect(decoded.activeStudyId == study.id)

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        #expect(restoredDoc.studies.count == 1)
        #expect(restoredDoc.activeStudyId == study.id)
        #expect(restoredDoc.activeStudy?.name == "Cantilever Beam")
    }

    @Test func testLegacyDocumentDecodingWithoutStudies() throws {
        let legacyJSON = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": []
        }
        """.data(using: .utf8)!

        let decodedData = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decodedData.studies == nil)
        #expect(decodedData.activeStudyId == nil)

        let doc = DocumentModel()
        try DocumentModelCoder.decode(into: doc, from: legacyJSON)

        #expect(doc.studies.isEmpty)
        #expect(doc.activeStudyId == nil)
        #expect(doc.activeStudy == nil)
    }

    @Test func testMultiStudyDocumentSerialization() throws {
        let studyA = SimulationStudy(name: "Stress Analysis", studyType: .linearStatic)
        let studyB = SimulationStudy(name: "Thermal Dissipation", studyType: .thermalConduction)

        let doc = DocumentModel()
        doc.addStudy(studyA)
        doc.addStudy(studyB)
        doc.setActiveStudy(id: studyB.id)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        #expect(restoredDoc.studies.count == 2)
        #expect(restoredDoc.activeStudyId == studyB.id)
        #expect(restoredDoc.study(id: studyA.id)?.studyType == .linearStatic)
        #expect(restoredDoc.study(id: studyB.id)?.studyType == .thermalConduction)
    }

    @Test func testEmptyStudiesOmitsKeyInCompactedJSON() throws {
        let emptyDoc = DocumentModel()
        let encoded = try DocumentModelCoder.encode(document: emptyDoc)

        let jsonObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(jsonObject?["studies"] == nil)
        #expect(jsonObject?["activeStudyId"] == nil)
    }
}
