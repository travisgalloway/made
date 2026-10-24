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

    @Test func testSimulationStudyWithGroupsAndMeshSetsRoundTripSerialization() throws {
        let group = SimulationGeometryGroup(
            name: "Clamp Surface",
            targetReferences: [
                SimulationGeometryReference(targetId: UUID(), targetName: "Face 1", subelementType: .face)
            ],
            subelementType: .face
        )
        let fixture = SimulationFixture(
            name: "Fixed Base",
            kind: .fixed,
            groupNames: ["Clamp Surface"]
        )
        let load = SimulationLoad(
            name: "Tension Load",
            kind: .force,
            groupNames: ["Clamp Surface"],
            magnitude: 5000.0
        )
        let meshSet = VolumeMeshSet(
            name: "Fixed Set",
            nodeIds: [1, 2, 3],
            elementIds: [10],
            subelementType: .face,
            tag: 101
        )
        let results = SimulationStudyResults(
            status: .completed,
            runtimeDuration: 2.5,
            meshSets: [meshSet]
        )
        let study = SimulationStudy(
            name: "Group Study",
            groups: [group],
            fixtures: [fixture],
            loads: [load],
            results: results
        )

        let doc = DocumentModel()
        doc.addStudy(study)
        doc.setActiveStudy(id: study.id)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        guard let restoredStudy = restoredDoc.study(id: study.id) else {
            Issue.record("Failed to restore study")
            return
        }

        #expect(restoredStudy.groups.count == 1)
        #expect(restoredStudy.groups.first?.name == "Clamp Surface")
        #expect(restoredStudy.fixtures.first?.groupNames == ["Clamp Surface"])
        #expect(restoredStudy.loads.first?.groupNames == ["Clamp Surface"])
        #expect(restoredStudy.results.meshSets.count == 1)
        #expect(restoredStudy.results.meshSets.first?.name == "Fixed Set")
        #expect(restoredStudy.results.meshSets.first?.nodeIds == [1, 2, 3])
        #expect(restoredStudy.results.meshSets.first?.tag == 101)
    }

    @Test func testLegacySimulationStudyWithoutGroupsDecodesGracefully() throws {
        // Legacy study JSON without groups, groupNames on fixtures/loads, or meshSets in results
        let legacyStudyJSON = """
        {
          "version": 1,
          "studies": [
            {
              "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
              "name": "Legacy Study",
              "studyType": "linearStatic",
              "targets": [],
              "materials": [],
              "connections": [],
              "fixtures": [
                {
                  "id": "11111111-2222-3333-4444-555555555555",
                  "name": "Old Fixture",
                  "kind": "fixed"
                }
              ],
              "loads": [
                {
                  "id": "66666666-7777-8888-9999-000000000000",
                  "name": "Old Load",
                  "kind": "force"
                }
              ],
              "mesh": {
                "elementOrder": "linear",
                "targetElementSize": 5.0,
                "minElementSize": 1.0,
                "growthRate": 1.2,
                "refinementRegions": []
              },
              "solver": {
                "engine": "calculix",
                "maxIterations": 100,
                "convergenceTolerance": 0.0001,
                "timeStep": 0.01
              },
              "results": {
                "status": "notRun",
                "meshStatistics": {
                  "nodeCount": 0,
                  "elementCount": 0,
                  "minElementQuality": 1.0,
                  "avgElementQuality": 1.0
                },
                "extrema": []
              },
              "isCollapsed": false
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyStudyJSON)

        #expect(restoredDoc.studies.count == 1)
        guard let study = restoredDoc.studies.first else {
            Issue.record("Expected 1 study")
            return
        }
        #expect(study.name == "Legacy Study")
        #expect(study.groups.isEmpty)
        #expect(study.fixtures.first?.groupNames.isEmpty == true)
        #expect(study.loads.first?.groupNames.isEmpty == true)
        #expect(study.results.meshSets.isEmpty)
        #expect(study.mesh.curvatureRefinement == false)
        #expect(study.mesh.curvatureElementsPerCircle == 12.0)
    }

    @Test func testLegacyMeshSpecificationWithoutCurvatureDecodesGracefully() throws {
        let legacyMeshJSON = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": [],
          "studies": [
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "name": "Pre-Curvature Study",
              "studyType": "linearStatic",
              "materials": [],
              "fixtures": [],
              "loads": [],
              "mesh": {
                "elementOrder": "quadratic",
                "targetElementSize": 4.5,
                "minElementSize": 0.8,
                "growthRate": 1.3,
                "refinementRegions": []
              },
              "solver": {
                "engine": "calculix",
                "maxIterations": 100,
                "convergenceTolerance": 0.0001,
                "timeStep": 0.01
              },
              "results": {
                "status": "notRun",
                "meshStatistics": {
                  "nodeCount": 0,
                  "elementCount": 0,
                  "minElementQuality": 1.0,
                  "avgElementQuality": 1.0
                },
                "extrema": []
              },
              "isCollapsed": false
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyMeshJSON)

        guard let study = restoredDoc.studies.first else {
            Issue.record("Expected 1 study")
            return
        }
        #expect(study.mesh.elementOrder == .quadratic)
        #expect(study.mesh.targetElementSize == 4.5)
        #expect(study.mesh.minElementSize == 0.8)
        #expect(study.mesh.growthRate == 1.3)
        #expect(study.mesh.curvatureRefinement == false)
        #expect(study.mesh.curvatureElementsPerCircle == 12.0)
    }

    @Test func testMeshSpecificationRefinementRegionsRoundTrip() throws {
        let doc = DocumentModel()
        var study = SimulationStudy(name: "Refinement Study", studyType: .linearStatic)
        let region1 = MeshRefinementRegion(
            id: UUID(),
            name: "Hole Chamfer",
            targetReferences: [
                SimulationGeometryReference(targetId: UUID(), targetName: "Face 3", subelementType: .face)
            ],
            targetElementSize: 0.5
        )
        let region2 = MeshRefinementRegion(
            id: UUID(),
            name: "Fillet Edge",
            targetReferences: [
                SimulationGeometryReference(targetId: UUID(), targetName: "Edge 12", subelementType: .edge)
            ],
            targetElementSize: 0.25
        )
        study.mesh.refinementRegions = [region1, region2]
        doc.addStudy(study)

        let encodedData = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encodedData)

        guard let restoredStudy = restoredDoc.studies.first else {
            Issue.record("Expected 1 study")
            return
        }
        #expect(restoredStudy.mesh.refinementRegions.count == 2)
        #expect(restoredStudy.mesh.refinementRegions[0].name == "Hole Chamfer")
        #expect(restoredStudy.mesh.refinementRegions[0].targetElementSize == 0.5)
        #expect(restoredStudy.mesh.refinementRegions[0].targetReferences.first?.targetName == "Face 3")
        #expect(restoredStudy.mesh.refinementRegions[1].name == "Fillet Edge")
        #expect(restoredStudy.mesh.refinementRegions[1].targetElementSize == 0.25)
        #expect(restoredStudy.mesh.refinementRegions[1].targetReferences.first?.targetName == "Edge 12")
    }

    @Test func testLegacyMeshSpecificationWithoutRefinementRegionsDecodesGracefully() throws {
        let legacyJSONWithoutRegions = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": [],
          "studies": [
            {
              "id": "22222222-3333-4444-5555-666666666666",
              "name": "Legacy Study Without Regions",
              "studyType": "linearStatic",
              "materials": [],
              "fixtures": [],
              "loads": [],
              "mesh": {
                "elementOrder": "linear",
                "targetElementSize": 3.0,
                "minElementSize": 1.0,
                "growthRate": 1.2
              },
              "solver": {
                "engine": "calculix",
                "maxIterations": 50,
                "convergenceTolerance": 0.001,
                "timeStep": 0.02
              },
              "results": {
                "status": "notRun",
                "meshStatistics": {
                  "nodeCount": 0,
                  "elementCount": 0,
                  "minElementQuality": 1.0,
                  "avgElementQuality": 1.0
                },
                "extrema": []
              },
              "isCollapsed": false
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSONWithoutRegions)

        guard let study = restoredDoc.studies.first else {
            Issue.record("Expected 1 study")
            return
        }
        #expect(study.mesh.refinementRegions.isEmpty)
        #expect(study.mesh.elementOrder == .linear)
        #expect(study.mesh.targetElementSize == 3.0)
    }

    @Test func testSimulationMeshStatisticsQualityReportRoundTrip() throws {
        let arSummary = MeshQualityMetricSummary(
            kind: .aspectRatio,
            minValue: 1.05,
            maxValue: 3.42,
            averageValue: 1.85,
            failureThreshold: 3.0,
            failingCount: 2,
            failingPercentage: 10.0,
            failingElementIds: [4, 7],
            histogramBins: [
                MeshQualityHistogramBin(index: 0, rangeMin: 1.05, rangeMax: 1.5, count: 10, isFailing: false),
                MeshQualityHistogramBin(index: 1, rangeMin: 1.5, rangeMax: 3.5, count: 10, isFailing: true)
            ]
        )
        let report = MeshQualityReport(aspectRatioSummary: arSummary)
        let stats = SimulationMeshStatistics(
            nodeCount: 50,
            elementCount: 20,
            minElementQuality: 0.35,
            avgElementQuality: 0.88,
            qualityReport: report
        )

        var study = SimulationStudy(name: "Quality Test Study", studyType: .linearStatic)
        study.results.meshStatistics = stats

        let doc = DocumentModel()
        doc.addStudy(study)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        guard let restoredStats = restoredDoc.studies.first?.results.meshStatistics else {
            Issue.record("Expected restored mesh statistics")
            return
        }

        #expect(restoredStats.nodeCount == 50)
        #expect(restoredStats.elementCount == 20)
        #expect(restoredStats.qualityReport != nil)
        #expect(restoredStats.qualityReport?.aspectRatioSummary.failingCount == 2)
        #expect(restoredStats.qualityReport?.aspectRatioSummary.failingElementIds == [4, 7])
        #expect(restoredStats.qualityReport?.aspectRatioSummary.histogramBins.count == 2)
        #expect(restoredStats.qualityReport?.aspectRatioSummary.histogramBins[1].isFailing == true)
    }

    @Test func testLegacyMeshStatisticsWithoutQualityReportDecodesSuccessfully() throws {
        let legacyJSONWithoutQuality = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": [],
          "studies": [
            {
              "id": "33333333-4444-5555-6666-777777777777",
              "name": "Legacy Study",
              "studyType": "linearStatic",
              "materials": [],
              "fixtures": [],
              "loads": [],
              "mesh": {
                "elementOrder": "linear",
                "targetElementSize": 2.0,
                "minElementSize": 1.0,
                "growthRate": 1.2
              },
              "solver": {
                "engine": "calculix",
                "maxIterations": 50,
                "convergenceTolerance": 0.001,
                "timeStep": 0.02
              },
              "results": {
                "status": "notRun",
                "meshStatistics": {
                  "nodeCount": 100,
                  "elementCount": 45,
                  "minElementQuality": 0.72,
                  "avgElementQuality": 0.91
                },
                "extrema": []
              },
              "isCollapsed": false
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSONWithoutQuality)

        guard let study = restoredDoc.studies.first else {
            Issue.record("Expected 1 study")
            return
        }

        #expect(study.results.meshStatistics.nodeCount == 100)
        #expect(study.results.meshStatistics.elementCount == 45)
        #expect(study.results.meshStatistics.qualityReport == nil)
    }
}

