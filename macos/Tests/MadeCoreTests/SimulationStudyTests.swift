import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SimulationStudyTests {

    @Test func testDefaultStudyInitialization() {
        let study = SimulationStudy(name: "Static Test", studyType: .linearStatic)
        #expect(study.name == "Static Test")
        #expect(study.studyType == .linearStatic)
        #expect(study.isCollapsed == false)
        #expect(study.materials.isEmpty)
        #expect(study.connections.isEmpty)
        #expect(study.fixtures.isEmpty)
        #expect(study.loads.isEmpty)
        #expect(study.results.status == .notRun)
        #expect(study.mesh.elementOrder == .quadratic)
        #expect(study.mesh.growthRate == 1.2)
        #expect(study.mesh.curvatureRefinement == false)
        #expect(study.mesh.curvatureElementsPerCircle == 12.0)
        #expect(study.solver.engine == .calculix)
        #expect(study.solver.maxIterations == 100)
        #expect(study.coordinateSystemId == nil)
    }

    @Test func testStudyTypeDisplayNames() {
        #expect(SimulationStudyType.linearStatic.displayName == "Linear Static")
        #expect(SimulationStudyType.modalFrequency.displayName == "Modal Frequency")
        #expect(SimulationStudyType.thermalConduction.displayName == "Thermal Conduction")
    }

    @Test func testFixtureAndLoadDefaults() {
        let fixture = SimulationFixture(name: "Fixed Base", kind: .fixed)
        #expect(fixture.name == "Fixed Base")
        #expect(fixture.kind == .fixed)
        #expect(fixture.targetReferences.isEmpty)
        #expect(fixture.isRestrainedX == true)
        #expect(fixture.isRestrainedY == true)
        #expect(fixture.isRestrainedZ == true)
        #expect(fixture.coordinateSystemId == nil)

        let load = SimulationLoad(
            name: "Top Force",
            kind: .force,
            magnitude: 500.0,
            direction: SIMD3<Double>(0, -1, 0)
        )
        #expect(load.name == "Top Force")
        #expect(load.kind == .force)
        #expect(load.magnitude == 500.0)
        #expect(load.direction == SIMD3<Double>(0, -1, 0))
        #expect(load.kind.unitSymbol == "N")
        #expect(load.coordinateSystemId == nil)
    }

    @Test func testCAEErrorCodeCases() {
        let err1 = CAEErrorCode.solverBinaryNotFound(solver: "ccx", searchedPaths: ["/usr/local/bin"])
        let err2 = CAEErrorCode.meshingFailed(reason: "Self-intersecting surface", exitCode: 1)
        let err3 = CAEErrorCode.solverFailed(reason: "Singular stiffness matrix", exitCode: -1)
        let err4 = CAEErrorCode.solverDiverged(iterations: 100, residual: 1e-2)
        let err5 = CAEErrorCode.invalidStudyConfiguration(message: "No boundary conditions")
        let err6 = CAEErrorCode.resultParsingFailed(details: "FRD file missing")
        let err7 = CAEErrorCode.executionCancelled

        #expect(err1 != err2)
        #expect(err3 != err4)
        #expect(err5 != err6)
        #expect(err7 == CAEErrorCode.executionCancelled)
    }

    @Test func testMeshSpecificationDefaults() {
        let spec = MeshSpecification()
        #expect(spec.elementOrder == .quadratic)
        #expect(spec.targetElementSize == 5.0)
        #expect(spec.minElementSize == 1.0)
        #expect(spec.growthRate == 1.2)
        #expect(spec.curvatureRefinement == false)
        #expect(spec.curvatureElementsPerCircle == 12.0)
        #expect(spec.refinementRegions.isEmpty)
    }

    @Test func testMeshSpecificationClamping() {
        var spec = MeshSpecification(
            elementOrder: .linear,
            targetElementSize: -5.0,
            minElementSize: 10.0,
            growthRate: 0.5,
            curvatureRefinement: true,
            curvatureElementsPerCircle: 1.0
        )
        spec.clamp()
        #expect(spec.targetElementSize == 0.001)
        #expect(spec.minElementSize == 0.001)
        #expect(spec.growthRate == 1.0)
        #expect(spec.curvatureElementsPerCircle == 3.0)

        let clampedCopy = MeshSpecification(
            targetElementSize: 2.0,
            minElementSize: 4.0,
            growthRate: -2.0,
            curvatureElementsPerCircle: 0.0
        ).clamped()
        #expect(clampedCopy.targetElementSize == 2.0)
        #expect(clampedCopy.minElementSize == 2.0)
        #expect(clampedCopy.growthRate == 1.0)
        #expect(clampedCopy.curvatureElementsPerCircle == 3.0)
    }

    @Test func testMeshRefinementRegionDefaultsAndClamping() {
        let defaultRegion = MeshRefinementRegion()
        #expect(defaultRegion.name == "Refinement")
        #expect(defaultRegion.targetReferences.isEmpty)
        #expect(defaultRegion.targetElementSize == 1.0)

        var invalidRegion = MeshRefinementRegion(name: "   ", targetElementSize: -2.5)
        invalidRegion.clamp()
        #expect(invalidRegion.name == "Refinement")
        #expect(invalidRegion.targetElementSize == 0.0001)

        var spec = MeshSpecification(refinementRegions: [
            MeshRefinementRegion(name: "Edge Blend", targetElementSize: 0.00001),
            MeshRefinementRegion(name: "", targetElementSize: -1.0)
        ])
        spec.clamp()
        #expect(spec.refinementRegions[0].name == "Edge Blend")
        #expect(spec.refinementRegions[0].targetElementSize == 0.0001)
        #expect(spec.refinementRegions[1].name == "Refinement")
        #expect(spec.refinementRegions[1].targetElementSize == 0.0001)
    }

    @Test func testCodableRoundTrip() throws {
        var study = SimulationStudy(name: "Bracket Simulation", studyType: .linearStatic)
        let studyUCS = UUID()
        let fixtureUCS = UUID()
        let loadUCS = UUID()

        study.coordinateSystemId = studyUCS
        let fixture = SimulationFixture(name: "Bolt Restraint", kind: .fixed, coordinateSystemId: fixtureUCS)
        let load = SimulationLoad(name: "Tensile Load", kind: .pressure, magnitude: 1.5e6, coordinateSystemId: loadUCS)
        study.fixtures.append(fixture)
        study.loads.append(load)
        study.mesh.targetElementSize = 3.5
        study.mesh.curvatureRefinement = true
        study.mesh.curvatureElementsPerCircle = 16.0
        study.solver.maxIterations = 500

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(study)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SimulationStudy.self, from: data)

        #expect(decoded == study)
        #expect(decoded.coordinateSystemId == studyUCS)
        #expect(decoded.fixtures.count == 1)
        #expect(decoded.fixtures[0].coordinateSystemId == fixtureUCS)
        #expect(decoded.loads.count == 1)
        #expect(decoded.loads[0].coordinateSystemId == loadUCS)
        #expect(decoded.mesh.targetElementSize == 3.5)
        #expect(decoded.mesh.curvatureRefinement == true)
        #expect(decoded.mesh.curvatureElementsPerCircle == 16.0)
        #expect(decoded.solver.maxIterations == 500)
    }

    @Test func testCoordinateSystemIdInitialization() {
        let ucsId = UUID()
        let study = SimulationStudy(name: "UCS Study", coordinateSystemId: ucsId)
        let fixture = SimulationFixture(name: "Restraint", coordinateSystemId: ucsId)
        let load = SimulationLoad(name: "Load", coordinateSystemId: ucsId)

        #expect(study.coordinateSystemId == ucsId)
        #expect(fixture.coordinateSystemId == ucsId)
        #expect(load.coordinateSystemId == ucsId)
    }

    @Test func testResultsModelAndSummary() {
        let results = SimulationStudyResults(
            status: .completed,
            runtimeDuration: 4.25,
            meshStatistics: SimulationMeshStatistics(
                nodeCount: 15400,
                elementCount: 8200,
                minElementQuality: 0.45,
                avgElementQuality: 0.88
            ),
            extrema: [
                SimulationFieldExtrema(fieldName: "Von Mises Stress", unitSymbol: "MPa", minValue: 0.0, maxValue: 215.4),
                SimulationFieldExtrema(fieldName: "Displacement", unitSymbol: "mm", minValue: 0.0, maxValue: 0.12)
            ]
        )

        #expect(results.status == .completed)
        #expect(results.meshStatistics.nodeCount == 15400)
        #expect(results.meshStatistics.elementCount == 8200)
        #expect(results.runtimeDuration == 4.25)
        #expect(results.extrema.count == 2)
        #expect(results.extrema[0].maxValue == 215.4)
    }

    @Test func testSimulationMeshDisplaySettingsDefaultsAndClamping() {
        var settings = SimulationMeshDisplaySettings()
        #expect(settings.isVisible == true)
        #expect(settings.showEdges == true)
        #expect(settings.showFaces == true)
        #expect(settings.elementShrink == 0.0)
        #expect(settings.isSliceEnabled == false)
        #expect(settings.sliceAxis == .z)
        #expect(settings.slicePosition == 0.5)
        #expect(settings.isSliceInverted == false)
        #expect(settings.hideSolidBody == false)

        settings.elementShrink = 1.5
        settings.slicePosition = -0.2
        settings.clamp()
        #expect(settings.elementShrink == 0.9)
        #expect(settings.slicePosition == 0.0)

        let clamped = SimulationMeshDisplaySettings(elementShrink: -0.5, slicePosition: 1.5).clamped()
        #expect(clamped.elementShrink == 0.0)
        #expect(clamped.slicePosition == 1.0)

        #expect(MeshSliceAxis.x.displayName == "X Axis")
        #expect(MeshSliceAxis.y.displayName == "Y Axis")
        #expect(MeshSliceAxis.z.displayName == "Z Axis")
    }

    @Test func testThermalLoadKindsAndAmbientTemperature() {
        let convection = SimulationLoad(
            name: "Cooling",
            kind: .convection,
            magnitude: 50.0,
            ambientTemperature: 22.5
        )
        #expect(convection.kind == .convection)
        #expect(convection.kind.displayName == "Convection")
        #expect(convection.kind.unitSymbol == "W/(m²·K)")
        #expect(convection.kind.systemImageName == "wind")
        #expect(convection.ambientTemperature == 22.5)

        let defaultConvection = SimulationLoad(kind: .convection)
        #expect(defaultConvection.ambientTemperature == 20.0)

        let power = SimulationLoad(name: "Heater", kind: .heatPower, magnitude: 150.0)
        #expect(power.kind == .heatPower)
        #expect(power.kind.displayName == "Heat Power")
        #expect(power.kind.unitSymbol == "W")
        #expect(power.kind.systemImageName == "bolt.fill")
    }

    @Test func testNodalTemperaturesInResults() {
        var results = SimulationStudyResults()
        #expect(results.nodalTemperatures == nil)

        results.nodalTemperatures = [1: 100.0, 2: 80.5, 3: 20.0]
        #expect(results.nodalTemperatures?[1] == 100.0)
        #expect(results.nodalTemperatures?[2] == 80.5)
        #expect(results.nodalTemperatures?[3] == 20.0)
    }

    @Test func testBackwardCompatibleDecodingOfLegacyLoadsAndResults() throws {
        let legacyLoadJSON = """
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "name": "Legacy Force",
            "kind": "force",
            "magnitude": 500.0,
            "direction": [0.0, -1.0, 0.0]
        }
        """.data(using: .utf8)!

        let decodedLoad = try JSONDecoder().decode(SimulationLoad.self, from: legacyLoadJSON)
        #expect(decodedLoad.name == "Legacy Force")
        #expect(decodedLoad.ambientTemperature == nil)

        let legacyResultsJSON = """
        {
            "status": "completed",
            "runtimeDuration": 1.5,
            "meshStatistics": {
                "nodeCount": 100,
                "elementCount": 50
            },
            "extrema": []
        }
        """.data(using: .utf8)!

        let decodedResults = try JSONDecoder().decode(SimulationStudyResults.self, from: legacyResultsJSON)
        #expect(decodedResults.status == .completed)
        #expect(decodedResults.nodalTemperatures == nil)
    }

    @Test func testLinearStaticResultsFields() {
        var results = SimulationStudyResults()
        #expect(results.nodalDisplacements == nil)
        #expect(results.nodalVonMisesStresses == nil)

        results.nodalDisplacements = [1: SIMD3<Double>(0.01, -0.05, 0.002), 2: SIMD3<Double>(0.02, -0.10, 0.004)]
        results.nodalVonMisesStresses = [1: 150.5, 2: 240.2]

        #expect(results.nodalDisplacements?[1] == SIMD3<Double>(0.01, -0.05, 0.002))
        #expect(results.nodalDisplacements?[2]?.y == -0.10)
        #expect(results.nodalVonMisesStresses?[1] == 150.5)
        #expect(results.nodalVonMisesStresses?[2] == 240.2)
    }

    @Test func testBackwardCompatibleDecodingOfLinearStaticResults() throws {
        let legacyResultsJSON = """
        {
            "status": "completed",
            "runtimeDuration": 2.1,
            "meshStatistics": {
                "nodeCount": 120,
                "elementCount": 60
            },
            "extrema": []
        }
        """.data(using: .utf8)!

        let decodedResults = try JSONDecoder().decode(SimulationStudyResults.self, from: legacyResultsJSON)
        #expect(decodedResults.status == .completed)
        #expect(decodedResults.nodalDisplacements == nil)
        #expect(decodedResults.nodalVonMisesStresses == nil)
    }
}

