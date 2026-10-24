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
        #expect(fixture.elasticStiffness == SIMD3<Double>(repeating: 1e6))
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

    @Test func testSimulationFixtureKindEnumeration() {
        let allKinds = SimulationFixtureKind.allCases
        #expect(allKinds.count == 6)
        #expect(allKinds.contains(.fixed))
        #expect(allKinds.contains(.rollerSlider))
        #expect(allKinds.contains(.pinned))
        #expect(allKinds.contains(.prescribedDisplacement))
        #expect(allKinds.contains(.symmetry))
        #expect(allKinds.contains(.elasticSupport))

        #expect(SimulationFixtureKind.fixed.displayName == "Fixed Support")
        #expect(SimulationFixtureKind.rollerSlider.displayName == "Roller / Slider")
        #expect(SimulationFixtureKind.pinned.displayName == "Pinned Support")
        #expect(SimulationFixtureKind.prescribedDisplacement.displayName == "Prescribed Displacement")
        #expect(SimulationFixtureKind.symmetry.displayName == "Symmetry")
        #expect(SimulationFixtureKind.elasticSupport.displayName == "Elastic Support")

        #expect(SimulationFixtureKind.symmetry.systemImageName == "square.split.2x1")
        #expect(SimulationFixtureKind.elasticSupport.systemImageName == "waveform")
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
        #expect(decodedResults.factorOfSafety == nil)
        #expect(decodedResults.nodalCauchyTensors == nil)
    }

    @Test func testBackwardCompatibleDecodingOfLinearStaticResultsWithoutFactorOfSafety() throws {
        let legacyStudyJSON = """
        {
            "id": "11112222-3333-4444-5555-666677778888",
            "name": "Legacy Study",
            "studyType": "linearStatic",
            "results": {
                "status": "completed",
                "meshStatistics": {
                    "nodeCount": 10,
                    "elementCount": 4
                },
                "extrema": []
            }
        }
        """.data(using: .utf8)!

        let decodedStudy = try JSONDecoder().decode(SimulationStudy.self, from: legacyStudyJSON)
        #expect(decodedStudy.name == "Legacy Study")
        #expect(decodedStudy.factorOfSafetySettings.basis == .yield)
        #expect(decodedStudy.factorOfSafetySettings.criterion == .vonMises)
        #expect(decodedStudy.factorOfSafetySettings.targetDesignFactor == 1.0)
        #expect(decodedStudy.results.factorOfSafety == nil)
    }

    @Test func testBackwardCompatibleDecodingOfSimulationFixture() throws {
        let legacyFixtureJSON = """
        {
            "id": "A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D",
            "name": "Legacy Fixed Base",
            "kind": "fixed",
            "targetReferences": [],
            "groupNames": [],
            "prescribedDisplacement": [0.0, 0.0, 0.0],
            "isRestrainedX": true,
            "isRestrainedY": true,
            "isRestrainedZ": true
        }
        """.data(using: .utf8)!

        let decodedFixture = try JSONDecoder().decode(SimulationFixture.self, from: legacyFixtureJSON)
        #expect(decodedFixture.name == "Legacy Fixed Base")
        #expect(decodedFixture.kind == .fixed)
        #expect(decodedFixture.elasticStiffness == SIMD3<Double>(repeating: 1e6))
    }

    @Test func testSimulationLoadKindBLFEA03Extensions() {
        let allKinds = SimulationLoadKind.allCases
        #expect(allKinds.contains(.moment))
        #expect(allKinds.contains(.remoteLoad))
        #expect(allKinds.contains(.bearing))
        #expect(allKinds.contains(.centrifugal))
        #expect(allKinds.contains(.thermalLoad))

        #expect(SimulationLoadKind.moment.displayName == "Moment")
        #expect(SimulationLoadKind.moment.unitSymbol == "N·m")
        #expect(SimulationLoadKind.moment.systemImageName == "arrow.triangle.2.circlepath")

        #expect(SimulationLoadKind.remoteLoad.displayName == "Remote Load")
        #expect(SimulationLoadKind.remoteLoad.unitSymbol == "N")
        #expect(SimulationLoadKind.remoteLoad.systemImageName == "arrow.up.and.line.horizontal.and.arrow.down")

        #expect(SimulationLoadKind.bearing.displayName == "Bearing Load")
        #expect(SimulationLoadKind.bearing.unitSymbol == "N")
        #expect(SimulationLoadKind.bearing.systemImageName == "circle.circle")

        #expect(SimulationLoadKind.centrifugal.displayName == "Centrifugal")
        #expect(SimulationLoadKind.centrifugal.unitSymbol == "rad/s")
        #expect(SimulationLoadKind.centrifugal.systemImageName == "arrow.counterclockwise")

        #expect(SimulationLoadKind.thermalLoad.displayName == "Thermal Load")
        #expect(SimulationLoadKind.thermalLoad.unitSymbol == "°C")
        #expect(SimulationLoadKind.thermalLoad.systemImageName == "thermometer.sun.fill")

        #expect(SimulationForceDistribution.allCases.count == 2)
        #expect(SimulationForceDistribution.total.displayName == "Total")
        #expect(SimulationForceDistribution.perUnitArea.displayName == "Per Unit Area")

        let defaultLoad = SimulationLoad(kind: .moment)
        #expect(defaultLoad.forceDistribution == .total)
        #expect(defaultLoad.remotePoint == nil)
        #expect(defaultLoad.remoteMoment == nil)
        #expect(defaultLoad.axisOrigin == nil)
        #expect(defaultLoad.referenceTemperature == nil)
    }

    @Test func testBackwardCompatibleDecodingOfSimulationLoadBLFEA03() throws {
        let legacyLoadJSON = """
        {
            "id": "11223344-5566-7788-99AA-BBCCDDEEFF00",
            "name": "Legacy Point Force",
            "kind": "force",
            "magnitude": 2500.0,
            "direction": [1.0, 0.0, 0.0]
        }
        """.data(using: .utf8)!

        let decodedLoad = try JSONDecoder().decode(SimulationLoad.self, from: legacyLoadJSON)
        #expect(decodedLoad.name == "Legacy Point Force")
        #expect(decodedLoad.kind == .force)
        #expect(decodedLoad.magnitude == 2500.0)
        #expect(decodedLoad.forceDistribution == .total)
        #expect(decodedLoad.remotePoint == nil)
        #expect(decodedLoad.remoteMoment == nil)
        #expect(decodedLoad.axisOrigin == nil)
        #expect(decodedLoad.referenceTemperature == nil)
    }

    @Test func testLinearBucklingStudyTypeAndSolverConfig() {
        #expect(SimulationStudyType.linearBuckling.displayName == "Linear Buckling")
        #expect(SimulationStudyType.linearBuckling.systemImageName == "arrow.triangle.swap")

        let config = SolverConfiguration()
        #expect(config.bucklingModesCount == 1)

        let customConfig = SolverConfiguration(bucklingModesCount: 5)
        #expect(customConfig.bucklingModesCount == 5)
    }

    @Test func testLinearBucklingModelCodableBackwardCompatibility() throws {
        let legacySolverJSON = """
        {
            "engine": "calculix",
            "maxIterations": 50,
            "convergenceTolerance": 0.0001,
            "timeStep": 0.01
        }
        """.data(using: .utf8)!

        let decodedSolver = try JSONDecoder().decode(SolverConfiguration.self, from: legacySolverJSON)
        #expect(decodedSolver.bucklingModesCount == 1)
        #expect(decodedSolver.maxIterations == 50)

        let legacyResultsJSON = """
        {
            "status": "completed",
            "runtimeDuration": 1.25,
            "extrema": []
        }
        """.data(using: .utf8)!

        let decodedResults = try JSONDecoder().decode(SimulationStudyResults.self, from: legacyResultsJSON)
        #expect(decodedResults.status == .completed)
        #expect(decodedResults.bucklingModes == nil)

        let mode = SimulationBucklingMode(
            modeNumber: 1,
            loadFactor: 3.1415,
            nodalDisplacements: [1: SIMD3<Double>(0, 1, 0)]
        )
        let modeData = try JSONEncoder().encode(mode)
        let decodedMode = try JSONDecoder().decode(SimulationBucklingMode.self, from: modeData)
        #expect(decodedMode.modeNumber == 1)
        #expect(decodedMode.id == 1)
        #expect(decodedMode.loadFactor == 3.1415)
        #expect(decodedMode.nodalDisplacements[1] == SIMD3<Double>(0, 1, 0))
    }

    @Test func testSolverConfigurationModalDefaults() {
        let config = SolverConfiguration()
        #expect(config.modeCount == 5)
        #expect(config.isPrestressEnabled == false)
    }

    @Test func testBackwardCompatibleDecodingOfSolverConfiguration() throws {
        let legacyJSON = """
        {
            "engine": "calculix",
            "maxIterations": 120,
            "convergenceTolerance": 0.0001,
            "timeStep": 0.02
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SolverConfiguration.self, from: legacyJSON)
        #expect(decoded.engine == .calculix)
        #expect(decoded.maxIterations == 120)
        #expect(decoded.convergenceTolerance == 0.0001)
        #expect(decoded.timeStep == 0.02)
        #expect(decoded.modeCount == 5)
        #expect(decoded.isPrestressEnabled == false)
    }

    @Test func testBackwardCompatibleDecodingOfModalResults() throws {
        let legacyResultsJSON = """
        {
            "status": "completed",
            "runtimeDuration": 1.25,
            "meshStatistics": {
                "nodeCount": 100,
                "elementCount": 80,
                "minElementQuality": 0.5,
                "avgElementQuality": 0.8
            },
            "meshSets": [],
            "extrema": []
        }
        """.data(using: .utf8)!

        let decodedResults = try JSONDecoder().decode(SimulationStudyResults.self, from: legacyResultsJSON)
        #expect(decodedResults.status == .completed)
        #expect(decodedResults.runtimeDuration == 1.25)
        #expect(decodedResults.modeShapes == nil)
    }

    @Test func testBackwardCompatibleDecodingOfSimulationConnection() throws {
        let legacyConnectionJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Legacy Bonded",
            "kind": "bonded",
            "sourceReferences": [],
            "targetReferences": [],
            "stiffness": 500000.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SimulationConnection.self, from: legacyConnectionJSON)
        #expect(decoded.name == "Legacy Bonded")
        #expect(decoded.kind == .bonded)
        #expect(decoded.stiffness == 500000.0)
        #expect(decoded.searchTolerance == nil)
        #expect(decoded.sourceGroupNames.isEmpty)
        #expect(decoded.targetGroupNames.isEmpty)
    }

    @Test func testSimulationModeShapeInitialization() {
        let mode = SimulationModeShape(
            modeNumber: 1,
            frequencyHz: 42.5,
            nodalDisplacements: [1: SIMD3<Double>(0.0, 1.0, 0.0)]
        )
        #expect(mode.modeNumber == 1)
        #expect(mode.frequencyHz == 42.5)
        #expect(mode.nodalDisplacements[1] == SIMD3<Double>(0.0, 1.0, 0.0))
    }
}

