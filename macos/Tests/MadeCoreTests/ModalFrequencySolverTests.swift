import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ModalFrequencySolverTests {

    @Test func testCantileverBeamEulerBernoulliFirstBendingMode() throws {
        // Analytical Euler-Bernoulli cantilever beam:
        // L = 1.0 m, w = 0.05 m, h = 0.05 m
        // E = 2.0e11 Pa, rho = 7850 kg/m^3
        // I = w * h^3 / 12 = 5.208333e-7 m^4, A = 0.0025 m^2
        // f1 = (1.875104^2 / (2 * pi * L^2)) * sqrt(E * I / (rho * A)) ≈ 40.77 Hz
        let (mesh, rootNodeIds, _) = LinearStaticSolverTests.makeBeamMeshC3D10(
            length: 1.0,
            width: 0.05,
            height: 0.05,
            nx: 6,
            ny: 1,
            nz: 1
        )

        var study = SimulationStudy(name: "Cantilever Beam Modal", studyType: .modalFrequency)
        study.solver.modeCount = 1
        study.solver.engine = .pureSwift
        study.fixtures = [
            SimulationFixture(
                name: "FixedRoot",
                kind: .fixed,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "RootFace")]
            )
        ]

        let result = try ModalFrequencySolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 2.0e11,
            poissonsRatio: 0.3,
            density: 7850.0,
            lengthScaleToMeters: 1.0
        )

        #expect(result.modeShapes.count == 1)
        let f1 = result.modeShapes[0].frequencyHz
        // Verify within 5% of analytical 40.77 Hz (38.7 Hz <= f1 <= 42.8 Hz)
        #expect(f1 >= 38.7 && f1 <= 42.8, "First natural frequency \(f1) Hz outside 5% analytical window [38.7, 42.8] Hz")
        #expect(result.modeShapes[0].modeNumber == 1)

        // Peak normalized displacement should be 1.0
        let maxDisp = result.modeShapes[0].nodalDisplacements.values.reduce(0.0) { max($0, simd_length($1)) }
        #expect(abs(maxDisp - 1.0) < 1e-6)

        // Fixed root nodes must have zero displacement
        for rootId in rootNodeIds {
            let disp = result.modeShapes[0].nodalDisplacements[rootId] ?? .zero
            #expect(simd_length(disp) < 1e-12)
        }
    }

    @Test func testMultiModeExtraction() throws {
        let (mesh, _, _) = LinearStaticSolverTests.makeBeamMeshC3D4(
            length: 1.0,
            width: 0.05,
            height: 0.05,
            nx: 6,
            ny: 1,
            nz: 1
        )

        var study = SimulationStudy(name: "Multi-Mode Modal", studyType: .modalFrequency)
        study.solver.modeCount = 5
        study.solver.engine = .pureSwift
        study.fixtures = [
            SimulationFixture(
                name: "FixedRoot",
                kind: .fixed,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "RootFace")]
            )
        ]

        let result = try ModalFrequencySolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 2.0e11,
            poissonsRatio: 0.3,
            density: 7850.0,
            lengthScaleToMeters: 1.0
        )

        #expect(result.modeShapes.count == 5)

        // Check monotonically non-decreasing natural frequencies
        for i in 0..<4 {
            let fA = result.modeShapes[i].frequencyHz
            let fB = result.modeShapes[i + 1].frequencyHz
            #expect(fA <= fB, "Mode \(i + 1) frequency \(fA) Hz is not <= Mode \(i + 2) frequency \(fB) Hz")
        }

        // Verify summary extrema contains Natural Frequency and Mode 1 Displacement
        let freqExtrema = result.extrema.first { $0.fieldName == "Natural Frequency" }
        #expect(freqExtrema != nil)
        #expect(freqExtrema?.unitSymbol == "Hz")
        #expect(freqExtrema?.minValue == result.modeShapes[0].frequencyHz)
        #expect(freqExtrema?.maxValue == result.modeShapes[4].frequencyHz)

        let dispExtrema = result.extrema.first { $0.fieldName == "Mode 1 Displacement" }
        #expect(dispExtrema != nil)
        #expect(dispExtrema?.unitSymbol == "mm")
        #expect(dispExtrema?.maxValue == 1.0)
    }

    @Test func testPrestressedTensionStiffening() throws {
        let (mesh, _, _) = LinearStaticSolverTests.makeBeamMeshC3D4(
            length: 1.0,
            width: 0.05,
            height: 0.05,
            nx: 5,
            ny: 1,
            nz: 1
        )

        // 1. Unstressed baseline solve
        var unstressedStudy = SimulationStudy(name: "Unstressed", studyType: .modalFrequency)
        unstressedStudy.solver.modeCount = 1
        unstressedStudy.solver.isPrestressEnabled = false
        unstressedStudy.fixtures = [
            SimulationFixture(
                name: "FixedRoot",
                kind: .fixed,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "RootFace")]
            )
        ]

        let unstressedResult = try ModalFrequencySolver.solve(
            study: unstressedStudy,
            mesh: mesh,
            youngsModulus: 2.0e11,
            poissonsRatio: 0.3,
            density: 7850.0,
            lengthScaleToMeters: 1.0
        )
        let fUnstressed = unstressedResult.modeShapes[0].frequencyHz

        // 2. Prestressed solve with 1e5 N axial tensile load
        var prestressedStudy = SimulationStudy(name: "Prestressed", studyType: .modalFrequency)
        prestressedStudy.solver.modeCount = 1
        prestressedStudy.solver.isPrestressEnabled = true
        prestressedStudy.fixtures = [
            SimulationFixture(
                name: "FixedRoot",
                kind: .fixed,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "RootFace")]
            )
        ]
        prestressedStudy.loads = [
            SimulationLoad(
                name: "AxialTension",
                kind: .force,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "TipFace")],
                magnitude: 1.0e5, // 100 kN tension along beam X axis
                direction: SIMD3<Double>(1, 0, 0)
            )
        ]

        let prestressedResult = try ModalFrequencySolver.solve(
            study: prestressedStudy,
            mesh: mesh,
            youngsModulus: 2.0e11,
            poissonsRatio: 0.3,
            density: 7850.0,
            lengthScaleToMeters: 1.0
        )
        let fTension = prestressedResult.modeShapes[0].frequencyHz

        // Verify tension stiffening strictly increases fundamental frequency
        #expect(fTension > fUnstressed, "Tensile prestress frequency (\(fTension) Hz) must be strictly higher than unstressed (\(fUnstressed) Hz)")
    }

    @Test func testUnconstrainedMeshThrows() {
        let (mesh, _, _) = LinearStaticSolverTests.makeBeamMeshC3D4(
            length: 1.0,
            width: 0.05,
            height: 0.05,
            nx: 5,
            ny: 1,
            nz: 1
        )

        let study = SimulationStudy(name: "No Fixtures", studyType: .modalFrequency)
        // No fixtures configured on study

        #expect(throws: CAEErrorCode.self) {
            _ = try ModalFrequencySolver.solve(study: study, mesh: mesh)
        }
    }

    @Test func testC3D10ModalAnalysis() throws {
        let (mesh, _, _) = LinearStaticSolverTests.makeBeamMeshC3D10(
            length: 1.0,
            width: 0.05,
            height: 0.05,
            nx: 6,
            ny: 1,
            nz: 1
        )

        var study = SimulationStudy(name: "C3D10 Modal", studyType: .modalFrequency)
        study.solver.modeCount = 1
        study.solver.engine = .pureSwift
        study.fixtures = [
            SimulationFixture(
                name: "FixedRoot",
                kind: .fixed,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "RootFace")]
            )
        ]

        let result = try ModalFrequencySolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 2.0e11,
            poissonsRatio: 0.3,
            density: 7850.0,
            lengthScaleToMeters: 1.0
        )

        #expect(result.modeShapes.count == 1)
        let f1 = result.modeShapes[0].frequencyHz
        // Verify C3D10 fundamental frequency within 5% of theoretical ~40.77 Hz
        #expect(f1 >= 38.7 && f1 <= 42.8, "C3D10 fundamental frequency \(f1) Hz outside 5% analytical window [38.7, 42.8] Hz")
    }
}
