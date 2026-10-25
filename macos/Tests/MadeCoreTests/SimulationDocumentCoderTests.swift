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

    @Test func testSimulationStudyMeshDisplayRoundTripSerialization() throws {
        let doc = DocumentModel()
        var study = SimulationStudy(name: "Mesh Display Study", studyType: .linearStatic)
        study.meshDisplay = SimulationMeshDisplaySettings(
            isVisible: true,
            showEdges: true,
            showFaces: false,
            elementShrink: 0.35,
            isSliceEnabled: true,
            sliceAxis: .y,
            slicePosition: 0.72,
            isSliceInverted: true,
            hideSolidBody: true
        )
        doc.addStudy(study)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        guard let restoredStudy = restoredDoc.studies.first else {
            Issue.record("Expected 1 restored study")
            return
        }

        #expect(restoredStudy.meshDisplay.isVisible == true)
        #expect(restoredStudy.meshDisplay.showEdges == true)
        #expect(restoredStudy.meshDisplay.showFaces == false)
        #expect(abs(restoredStudy.meshDisplay.elementShrink - 0.35) < 1e-4)
        #expect(restoredStudy.meshDisplay.isSliceEnabled == true)
        #expect(restoredStudy.meshDisplay.sliceAxis == .y)
        #expect(abs(restoredStudy.meshDisplay.slicePosition - 0.72) < 1e-4)
        #expect(restoredStudy.meshDisplay.isSliceInverted == true)
        #expect(restoredStudy.meshDisplay.hideSolidBody == true)
    }

    @Test func testLegacySimulationStudyWithoutMeshDisplayDecodesGracefully() throws {
        let legacyJSON = """
        {
          "version": 1,
          "studies": [
            {
              "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
              "name": "Legacy Mesh Study",
              "studyType": "linearStatic",
              "targets": [],
              "groups": [],
              "materials": [],
              "connections": [],
              "fixtures": [],
              "loads": [],
              "mesh": {
                "elementOrder": "linear",
                "targetElementSize": 5.0,
                "minElementSize": 1.0,
                "growthRate": 1.2,
                "curvatureRefinement": false,
                "curvatureElementsPerCircle": 12.0,
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
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSON)

        guard let study = restoredDoc.studies.first else {
            Issue.record("Expected 1 restored study")
            return
        }

        #expect(study.meshDisplay.isVisible == true)
        #expect(study.meshDisplay.showEdges == true)
        #expect(study.meshDisplay.showFaces == true)
        #expect(study.meshDisplay.elementShrink == 0.0)
        #expect(study.meshDisplay.isSliceEnabled == false)
        #expect(study.meshDisplay.sliceAxis == .z)
        #expect(study.meshDisplay.slicePosition == 0.5)
        #expect(study.meshDisplay.isSliceInverted == false)
        #expect(study.meshDisplay.hideSolidBody == false)
    }

    @Test func testLegacySimulationStudyWithoutCoordinateSystemIdDecodesGracefully() throws {
        let legacyJSON = """
        {
          "version": 1,
          "studies": [
            {
              "id": "B2C3D4E5-F6A1-7890-ABCD-EF1234567890",
              "name": "Legacy No UCS Study",
              "studyType": "linearStatic",
              "fixtures": [
                {
                  "id": "C3D4E5F6-A1B2-7890-ABCD-EF1234567890",
                  "name": "Legacy Fixture",
                  "kind": "fixed"
                }
              ],
              "loads": [
                {
                  "id": "D4E5F6A1-B2C3-7890-ABCD-EF1234567890",
                  "name": "Legacy Load",
                  "kind": "force",
                  "magnitude": 500.0,
                  "direction": [0.0, 0.0, -1.0]
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSON)

        guard let study = restoredDoc.studies.first else {
            Issue.record("Expected 1 restored study")
            return
        }

        #expect(study.coordinateSystemId == nil)
        #expect(study.fixtures.count == 1)
        #expect(study.fixtures[0].coordinateSystemId == nil)
        #expect(study.loads.count == 1)
        #expect(study.loads[0].coordinateSystemId == nil)
    }

    @Test func testSimulationStudyWithCoordinateSystemIdRoundTrip() throws {
        let studyUCS = UUID()
        let fixtureUCS = UUID()
        let loadUCS = UUID()

        let study = SimulationStudy(
            name: "Study With UCS",
            studyType: .linearStatic,
            fixtures: [
                SimulationFixture(name: "Fixture with UCS", kind: .prescribedDisplacement, coordinateSystemId: fixtureUCS)
            ],
            loads: [
                SimulationLoad(name: "Load with UCS", kind: .force, magnitude: 750.0, coordinateSystemId: loadUCS)
            ],
            coordinateSystemId: studyUCS
        )

        let doc = DocumentModel()
        doc.addStudy(study)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        guard let restoredStudy = restoredDoc.studies.first else {
            Issue.record("Expected 1 restored study")
            return
        }

        #expect(restoredStudy.coordinateSystemId == studyUCS)
        #expect(restoredStudy.fixtures.count == 1)
        #expect(restoredStudy.fixtures[0].coordinateSystemId == fixtureUCS)
        #expect(restoredStudy.loads.count == 1)
        #expect(restoredStudy.loads[0].coordinateSystemId == loadUCS)
    }

    @Test func testSimulationStudyWithResultFieldStorageDescriptorRoundTrip() throws {
        let storage = ResultFieldStorageDescriptor(
            storagePath: "cache/results/study-1/results.vtu",
            format: .vtu,
            availableFields: [
                ResultFieldMetadata(name: "Displacement", kind: .displacement, componentCount: 3, entityCount: 100, unitSymbol: "mm")
            ],
            byteSize: 1024,
            isResident: false
        )

        let results = SimulationStudyResults(
            status: .completed,
            fieldStorage: storage,
            elementVonMisesStresses: [1: 25.0, 2: 50.0],
            elementHeatFluxes: [1: SIMD3<Double>(0, 10, 0)]
        )

        let study = SimulationStudy(
            name: "Study With Storage Descriptor",
            studyType: .linearStatic,
            results: results
        )

        let doc = DocumentModel()
        doc.addStudy(study)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        let restoredStudy = try #require(restoredDoc.studies.first)
        #expect(restoredStudy.results.fieldStorage?.storagePath == "cache/results/study-1/results.vtu")
        #expect(restoredStudy.results.fieldStorage?.format == .vtu)
        #expect(restoredStudy.results.fieldStorage?.byteSize == 1024)
        #expect(restoredStudy.results.fieldStorage?.isResident == false)
        #expect(restoredStudy.results.fieldStorage?.availableFields.count == 1)
        #expect(restoredStudy.results.elementVonMisesStresses?[2] == 50.0)
        #expect(restoredStudy.results.elementHeatFluxes?[1]?.y == 10.0)
    }

    @Test func testLegacyDocumentResultsWithoutFieldStorageDecodeCleanly() throws {
        let legacyJSON = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": [],
          "studies": [
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "name": "Legacy Solved Study",
              "studyType": "linearStatic",
              "targets": [],
              "groups": [],
              "materials": [],
              "connections": [],
              "fixtures": [],
              "loads": [],
              "results": {
                "status": "completed",
                "nodalDisplacements": {
                  "1": [0.01, 0.02, 0.03]
                },
                "nodalVonMisesStresses": {
                  "1": 45.6
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSON)

        let study = try #require(restoredDoc.studies.first)
        #expect(study.results.status == .completed)
        #expect(study.results.nodalDisplacements?[1] == SIMD3<Double>(0.01, 0.02, 0.03))
        #expect(study.results.nodalVonMisesStresses?[1] == 45.6)
        #expect(study.results.fieldStorage == nil)
        #expect(study.results.elementVonMisesStresses == nil)
        #expect(study.results.elementHeatFluxes == nil)
        #expect(study.results.isFieldsLoaded == true)
    }

    @Test func testSimulationContourSettingsRoundTripSerialization() throws {
        var study = SimulationStudy(name: "Contour Test Study", studyType: .linearStatic)
        study.contourSettings = SimulationContourSettings(
            isVisible: true,
            field: .displacementMagnitude,
            colorMap: .magma,
            autoRange: false,
            customMin: 2.5,
            customMax: 80.0,
            showMinMaxMarkers: false,
            isDeformed: true,
            deformationScale: 5.0,
            showMeshEdges: false
        )

        let doc = DocumentModel()
        doc.addStudy(study)
        doc.setActiveStudy(id: study.id)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        let restoredStudy = try #require(restoredDoc.study(id: study.id))
        let settings = restoredStudy.contourSettings
        #expect(settings.isVisible == true)
        #expect(settings.field == .displacementMagnitude)
        #expect(settings.colorMap == .magma)
        #expect(settings.autoRange == false)
        #expect(settings.customMin == 2.5)
        #expect(settings.customMax == 80.0)
        #expect(settings.showMinMaxMarkers == false)
        #expect(settings.isDeformed == true)
        #expect(settings.deformationScale == 5.0)
        #expect(settings.showMeshEdges == false)
    }

    @Test func testLegacyStudyWithoutContourSettingsDecodesWithDefaults() throws {
        let legacyJSON = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": [],
          "studies": [
            {
              "id": "22222222-3333-4444-5555-666666666666",
              "name": "Legacy Study",
              "studyType": "linearStatic"
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSON)

        let study = try #require(restoredDoc.studies.first)
        #expect(study.contourSettings.isVisible == false)
        #expect(study.contourSettings.field == .vonMisesStress)
        #expect(study.contourSettings.colorMap == .turbo)
        #expect(study.contourSettings.autoRange == true)
        #expect(study.contourSettings.customMin == nil)
        #expect(study.contourSettings.customMax == nil)
        #expect(study.contourSettings.showMinMaxMarkers == true)
        #expect(study.contourSettings.isDeformed == false)
        #expect(study.contourSettings.deformationScale == 1.0)
        #expect(study.contourSettings.showMeshEdges == true)
        #expect(study.contourSettings.showUndeformedWireframe == false)
        #expect(study.contourSettings.animationMode == .harmonic)
        #expect(study.contourSettings.animationSpeed == 1.0)
        #expect(study.contourSettings.activeLoadStepNumber == nil)
    }

    // MARK: - Animation Settings and Load Steps Persistence (BL-RES-03, #324)

    @Test func testSimulationContourSettingsAnimationRoundTrip() throws {
        var settings = SimulationContourSettings()
        settings.isVisible = true
        settings.isDeformed = true
        settings.deformationScale = 3.5
        settings.showUndeformedWireframe = true
        settings.animationMode = .linearRamp
        settings.animationSpeed = 2.0
        settings.activeLoadStepNumber = 4

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let restored = try decoder.decode(SimulationContourSettings.self, from: data)

        #expect(restored.showUndeformedWireframe == true)
        #expect(restored.animationMode == .linearRamp)
        #expect(restored.animationSpeed == 2.0)
        #expect(restored.activeLoadStepNumber == 4)
        #expect(restored.deformationScale == 3.5)
        #expect(restored.isDeformed == true)
    }

    @Test func testSimulationStudyResultsWithLoadStepsRoundTrip() throws {
        let step1 = SimulationLoadStep(
            stepNumber: 1,
            timeOrFactor: 0.25,
            nodalDisplacements: [1: SIMD3<Double>(0.01, 0, 0), 2: SIMD3<Double>(0.05, 0, 0)],
            nodalVonMisesStresses: [1: 25.0, 2: 75.0],
            elementVonMisesStresses: [1: 50.0]
        )
        let step2 = SimulationLoadStep(
            stepNumber: 2,
            timeOrFactor: 0.50,
            nodalDisplacements: [1: SIMD3<Double>(0.02, 0, 0), 2: SIMD3<Double>(0.10, 0, 0)],
            nodalVonMisesStresses: [1: 50.0, 2: 150.0],
            elementVonMisesStresses: [1: 100.0]
        )

        var results = SimulationStudyResults(status: .completed)
        results.loadSteps = [step1, step2]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(results)
        let restored = try decoder.decode(SimulationStudyResults.self, from: data)

        #expect(restored.loadSteps?.count == 2)
        #expect(restored.loadSteps?[0].stepNumber == 1)
        #expect(restored.loadSteps?[0].timeOrFactor == 0.25)
        #expect(restored.loadSteps?[0].nodalDisplacements[2] == SIMD3<Double>(0.05, 0, 0))
        #expect(restored.loadSteps?[0].nodalVonMisesStresses?[2] == 75.0)
        #expect(restored.loadSteps?[0].elementVonMisesStresses?[1] == 50.0)

        #expect(restored.loadSteps?[1].stepNumber == 2)
        #expect(restored.loadSteps?[1].timeOrFactor == 0.50)
        #expect(restored.loadSteps?[1].nodalDisplacements[2] == SIMD3<Double>(0.10, 0, 0))
    }

    @Test func testLegacyStudyResultsWithoutLoadStepsDecodesCleanly() throws {
        let json = """
        {
          "status": "completed",
          "meshStatistics": {
            "nodeCount": 10,
            "elementCount": 4
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let results = try decoder.decode(SimulationStudyResults.self, from: json)
        #expect(results.status == .completed)
        #expect(results.loadSteps == nil)
        #expect(results.isFieldsLoaded == false)
    }

    @Test func testLoadStepsMemoryUnloading() {
        var results = SimulationStudyResults(status: .completed)
        #expect(results.isFieldsLoaded == false)

        results.loadSteps = [
            SimulationLoadStep(
                stepNumber: 1,
                timeOrFactor: 1.0,
                nodalDisplacements: [1: .zero]
            )
        ]
        #expect(results.isFieldsLoaded == true)

        results.unloadFields()
        #expect(results.loadSteps == nil)
        #expect(results.isFieldsLoaded == false)
    }

    @Test func testSimulationProbeTableRoundTripSerialization() throws {
        var study = SimulationStudy(name: "Probe RoundTrip Study")
        let p1 = SimulationProbePoint(
            name: "Probe Alpha",
            kind: .point,
            position: SIMD3<Double>(10, 20, 30),
            nodeId: 101,
            elementId: 202,
            fieldValues: [.vonMisesStress: 145.5, .displacementMagnitude: 0.12]
        )
        let path = SimulationPathProbeDefinition(
            name: "Path Beta",
            startPoint: SIMD3<Double>(0, 0, 0),
            endPoint: SIMD3<Double>(10, 0, 0),
            sampleCount: 5
        )
        study.probeTable = SimulationProbeTable(
            probes: [p1],
            paths: [path],
            showProbeBadges: true,
            isProbingActive: true
        )

        let doc = DocumentModel()
        doc.addStudy(study)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        guard let restoredStudy = restoredDoc.study(id: study.id) else {
            Issue.record("Failed to restore study")
            return
        }

        #expect(restoredStudy.probeTable.showProbeBadges == true)
        #expect(restoredStudy.probeTable.isProbingActive == true)
        #expect(restoredStudy.probeTable.probes.count == 1)
        #expect(restoredStudy.probeTable.probes[0].name == "Probe Alpha")
        #expect(restoredStudy.probeTable.probes[0].position == SIMD3<Double>(10, 20, 30))
        #expect(restoredStudy.probeTable.probes[0].nodeId == 101)
        #expect(restoredStudy.probeTable.probes[0].elementId == 202)
        #expect(restoredStudy.probeTable.probes[0].fieldValues[.vonMisesStress] == 145.5)
        #expect(restoredStudy.probeTable.paths.count == 1)
        #expect(restoredStudy.probeTable.paths[0].name == "Path Beta")
        #expect(restoredStudy.probeTable.paths[0].sampleCount == 5)
    }

    @Test func testLegacyStudyWithoutProbeTableDecodesWithDefaults() throws {
        let legacyJSON = """
        {
          "id": "A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D",
          "name": "Legacy Study",
          "studyType": "linearStatic"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let study = try decoder.decode(SimulationStudy.self, from: legacyJSON)

        #expect(study.name == "Legacy Study")
        #expect(study.probeTable.probes.isEmpty)
        #expect(study.probeTable.paths.isEmpty)
        #expect(study.probeTable.showProbeBadges == true)
        #expect(study.probeTable.isProbingActive == false)
    }

    // MARK: - Constraint Reactions & Body Summaries Round-Trip Serialization (BL-RES-06, #326)

    @Test func testSimulationStudyWithConstraintReactionsRoundTrip() throws {
        let fixtureId1 = UUID()
        let fixtureId2 = UUID()
        let bodyId = UUID()

        let rxn1 = SimulationConstraintReaction(
            id: fixtureId1,
            fixtureName: "Clamp A",
            reactionForce: SIMD3<Double>(10.5, 250.0, -5.2),
            reactionMoment: SIMD3<Double>(0.0, 15.2, 85.0),
            referencePoint: SIMD3<Double>(100.0, 50.0, 25.0),
            nodeCount: 16,
            nodalReactionForces: [1: SIMD3<Double>(0.5, 12.5, -0.2), 2: SIMD3<Double>(1.0, 15.0, -0.5)]
        )

        let rxn2 = SimulationConstraintReaction(
            id: fixtureId2,
            fixtureName: "Support B",
            reactionForce: SIMD3<Double>(-10.5, 750.0, 5.2),
            reactionMoment: SIMD3<Double>(0.0, -15.2, 115.0),
            referencePoint: SIMD3<Double>(900.0, 50.0, 25.0),
            nodeCount: 24,
            nodalReactionForces: nil
        )

        let summary = SimulationBodySummary(
            id: bodyId,
            bodyName: "Main Bracket",
            nodeCount: 120,
            elementCount: 450,
            maxVonMisesStress: 185.4,
            maxDisplacement: 1.25,
            minFactorOfSafety: 2.15,
            maxTemperature: 65.0,
            extrema: [
                SimulationFieldExtrema(fieldName: "von Mises Stress", unitSymbol: "MPa", minValue: 10.0, maxValue: 185.4),
                SimulationFieldExtrema(fieldName: "Displacement Magnitude", unitSymbol: "mm", minValue: 0.0, maxValue: 1.25)
            ]
        )

        var study = SimulationStudy(name: "Reaction Serialization Test", studyType: .linearStatic)
        study.results.status = .completed
        study.results.constraintReactions = [rxn1, rxn2]
        study.results.bodySummaries = [summary]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(study)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SimulationStudy.self, from: encoded)

        let decodedReactions = try #require(decoded.results.constraintReactions)
        #expect(decodedReactions.count == 2)
        #expect(decodedReactions[0].id == fixtureId1)
        #expect(decodedReactions[0].fixtureName == "Clamp A")
        #expect(decodedReactions[0].reactionForce == SIMD3<Double>(10.5, 250.0, -5.2))
        #expect(decodedReactions[0].reactionMoment == SIMD3<Double>(0.0, 15.2, 85.0))
        #expect(decodedReactions[0].referencePoint == SIMD3<Double>(100.0, 50.0, 25.0))
        #expect(decodedReactions[0].nodeCount == 16)
        #expect(decodedReactions[0].nodalReactionForces?[1] == SIMD3<Double>(0.5, 12.5, -0.2))

        #expect(decodedReactions[1].id == fixtureId2)
        #expect(decodedReactions[1].fixtureName == "Support B")
        #expect(decodedReactions[1].nodalReactionForces == nil)

        // Verify total reaction computed properties
        let totalF = try #require(decoded.results.totalReactionForce)
        #expect(abs(totalF.x) < 1e-6)
        #expect(abs(totalF.y - 1000.0) < 1e-6)
        #expect(abs(totalF.z) < 1e-6)

        let totalM = try #require(decoded.results.totalReactionMoment)
        #expect(abs(totalM.x) < 1e-6)
        #expect(abs(totalM.y) < 1e-6)
        #expect(abs(totalM.z - 200.0) < 1e-6)

        let decodedSummaries = try #require(decoded.results.bodySummaries)
        #expect(decodedSummaries.count == 1)
        #expect(decodedSummaries[0].id == bodyId)
        #expect(decodedSummaries[0].bodyName == "Main Bracket")
        #expect(decodedSummaries[0].nodeCount == 120)
        #expect(decodedSummaries[0].elementCount == 450)
        #expect(decodedSummaries[0].maxVonMisesStress == 185.4)
        #expect(decodedSummaries[0].maxDisplacement == 1.25)
        #expect(decodedSummaries[0].minFactorOfSafety == 2.15)
        #expect(decodedSummaries[0].maxTemperature == 65.0)
        #expect(decodedSummaries[0].extrema.count == 2)
    }

    @Test func testLegacyDocumentResultsWithoutReactionsDecodeCleanly() throws {
        let legacyJSON = """
        {
          "version": 1,
          "documentType": "part",
          "objects": [],
          "parameters": [],
          "studies": [
            {
              "id": "22222222-3333-4444-5555-666666666666",
              "name": "Legacy Solved Study Without Reactions",
              "studyType": "linearStatic",
              "targets": [],
              "groups": [],
              "materials": [],
              "connections": [],
              "fixtures": [],
              "loads": [],
              "results": {
                "status": "completed",
                "nodalDisplacements": {
                  "1": [0.01, 0.02, 0.03]
                },
                "nodalVonMisesStresses": {
                  "1": 45.6
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: legacyJSON)

        let study = try #require(restoredDoc.studies.first)
        #expect(study.results.status == .completed)
        #expect(study.results.constraintReactions == nil)
        #expect(study.results.bodySummaries == nil)
        #expect(study.results.totalReactionForce == nil)
        #expect(study.results.totalReactionMoment == nil)
    }
}

