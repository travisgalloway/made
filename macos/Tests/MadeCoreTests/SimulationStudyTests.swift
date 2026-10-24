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

    @Test func testCodableRoundTrip() throws {
        var study = SimulationStudy(name: "Bracket Simulation", studyType: .linearStatic)
        let fixture = SimulationFixture(name: "Bolt Restraint", kind: .fixed)
        let load = SimulationLoad(name: "Tensile Load", kind: .pressure, magnitude: 1.5e6)
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
        #expect(decoded.fixtures.count == 1)
        #expect(decoded.loads.count == 1)
        #expect(decoded.mesh.targetElementSize == 3.5)
        #expect(decoded.mesh.curvatureRefinement == true)
        #expect(decoded.mesh.curvatureElementsPerCircle == 16.0)
        #expect(decoded.solver.maxIterations == 500)
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
}
