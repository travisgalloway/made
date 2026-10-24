import Testing
import Foundation
import simd
@testable import MadeCore

@Suite(.serialized) struct SolverVerificationSuiteTests {

    // MARK: - Helper Functions

    private static func computeTetrahedronSignedVolume(
        p0: SIMD3<Double>,
        p1: SIMD3<Double>,
        p2: SIMD3<Double>,
        p3: SIMD3<Double>
    ) -> Double {
        let v10 = p1 - p0
        let v20 = p2 - p0
        let v30 = p3 - p0
        let cross = simd_cross(v20, v30)
        return simd_dot(v10, cross) / 6.0
    }

    // MARK: - 1. Cantilever Beam Euler-Bernoulli Benchmark

    @Test func testCantileverBeamEulerBernoulliBenchmark() throws {
        let result = try SolverVerificationSuite.cantileverEulerBernoulli.execute()

        #expect(result.allPassed, "Cantilever Euler-Bernoulli benchmark failed metric tolerances.")
        let tipMetric = try #require(result.metrics.first { $0.metricName == "Tip Deflection" })
        #expect(tipMetric.passed, "Tip deflection error \(tipMetric.relativeError * 100)% exceeds 2%.")
        #expect(tipMetric.relativeError <= 0.02)

        let stressMetric = try #require(result.metrics.first { $0.metricName == "Maximum Bending Stress" })
        #expect(stressMetric.passed, "Max stress error \(stressMetric.relativeError * 100)% exceeds 3%.")
        #expect(stressMetric.relativeError <= 0.03)
    }

    // MARK: - 2. Cantilever Beam Quadratic C3D10 Benchmark

    @Test func testCantileverBeamQuadraticC3D10Benchmark() throws {
        let result = try SolverVerificationSuite.cantileverC3D10.execute()

        #expect(result.allPassed, "Cantilever C3D10 benchmark failed metric tolerances.")
        let tipMetric = try #require(result.metrics.first { $0.metricName == "Tip Deflection" })
        #expect(tipMetric.passed, "C3D10 tip deflection error \(tipMetric.relativeError * 100)% exceeds 2%.")
        #expect(tipMetric.relativeError <= 0.02)

        let stressMetric = try #require(result.metrics.first { $0.metricName == "Maximum Bending Stress" })
        #expect(stressMetric.passed, "C3D10 max stress error \(stressMetric.relativeError * 100)% exceeds 2%.")
        #expect(stressMetric.relativeError <= 0.02)
    }

    // MARK: - 3. Plate with Hole Kirsch Benchmark

    @Test func testPlateWithHoleKirschBenchmark() throws {
        let result = try SolverVerificationSuite.plateWithHoleKirsch.execute()

        #expect(result.allPassed, "Plate with hole benchmark failed metric tolerances.")
        let ktMetric = try #require(result.metrics.first { $0.metricName == "Stress Concentration Factor Kt" })
        #expect(ktMetric.passed, "Stress concentration factor error \(ktMetric.relativeError * 100)% exceeds 10%.")
        #expect(ktMetric.computedValue >= 2.4 && ktMetric.computedValue <= 3.2, "Kt \(ktMetric.computedValue) not within [2.4, 3.2]")

        let outerMetric = try #require(result.metrics.first { $0.metricName == "Transverse Ligament Outer Stress" })
        #expect(outerMetric.passed, "Transverse ligament outer stress exceeds tolerance.")
        #expect(outerMetric.computedValue <= 13.0, "Outer stress \(outerMetric.computedValue) MPa exceeds 1.3 * sigma0 (13.0 MPa)")
        #expect(outerMetric.computedValue < ktMetric.computedValue * 10.0, "Transverse ligament stress must decay from peak stress.")
    }

    // MARK: - Analytical Closed-Form Equations Integrity

    @Test func testAnalyticalFormulasIntegrity() {
        // Euler-Bernoulli Beam
        let Iz = EulerBernoulliBeam.secondMomentOfArea(width: 0.05, height: 0.05)
        #expect(abs(Iz - (0.05 * pow(0.05, 3)) / 12.0) < 1e-15)
        let vTip = EulerBernoulliBeam.tipDeflection(force: 1000.0, length: 1.0, modulus: 200e9, width: 0.05, height: 0.05)
        #expect(abs(vTip - 0.0032) < 1e-6)
        let sMax = EulerBernoulliBeam.maxBendingStress(force: 1000.0, length: 1.0, width: 0.05, height: 0.05)
        #expect(abs(sMax - 48e6) < 1e-3)

        // Kirsch Plate with Hole
        #expect(abs(KirschPlateWithHole.infinitePlateStressConcentrationFactor() - 3.0) < 1e-9)
        let ktPeterson = KirschPlateWithHole.stressConcentrationFactor(holeDiameter: 0.1, plateWidth: 0.5)
        #expect(ktPeterson > 2.4 && ktPeterson < 3.2)
        let sHole = KirschPlateWithHole.transverseLigamentStress(x: 0.05, holeRadius: 0.05, farFieldStress: 10.0)
        let sMid = KirschPlateWithHole.transverseLigamentStress(x: 0.15, holeRadius: 0.05, farFieldStress: 10.0)
        let sFar = KirschPlateWithHole.transverseLigamentStress(x: 0.25, holeRadius: 0.05, farFieldStress: 10.0)
        #expect(sHole > sMid && sMid > sFar, "Transverse ligament stress must decay monotonically away from hole.")
        #expect(abs(sHole - 30.0) < 1e-6)
        #expect(abs(sFar - 10.224) < 1e-3)

        // Lamé Thick Cylinder
        let a = 0.1, b = 0.2, Pi = 10e6, E = 200e9, nu = 0.3
        let urA = LameThickCylinder.radialDisplacement(radius: a, innerRadius: a, outerRadius: b, internalPressure: Pi, modulus: E, poissonsRatio: nu)
        let urB = LameThickCylinder.radialDisplacement(radius: b, innerRadius: a, outerRadius: b, internalPressure: Pi, modulus: E, poissonsRatio: nu)
        #expect(urA > urB && urB > 0.0)
        let sHoopA = LameThickCylinder.hoopStress(radius: a, innerRadius: a, outerRadius: b, internalPressure: Pi)
        let sRadA = LameThickCylinder.radialStress(radius: a, innerRadius: a, outerRadius: b, internalPressure: Pi)
        #expect(abs(sRadA - (-Pi)) < 1e-3)
        #expect(abs(sHoopA - (10e6 * (0.01 / 0.03) * 5.0)) < 1e-3)
        let sVmA = LameThickCylinder.vonMisesStress(radius: a, innerRadius: a, outerRadius: b, internalPressure: Pi, poissonsRatio: nu)
        #expect(sVmA > 0.0)

        // Thermal Conduction 1D
        let Tmid = ThermalConduction1D.temperature(x: 0.05, length: 0.1, t1: 100.0, t2: 20.0)
        #expect(abs(Tmid - 60.0) < 1e-9)
        let q = ThermalConduction1D.heatFlux(length: 0.1, t1: 100.0, t2: 20.0, conductivity: 50.0)
        #expect(abs(q - 40000.0) < 1e-9)
    }

    // MARK: - 4. Thick Cylinder Lamé Benchmark

    @Test func testThickCylinderLameBenchmark() throws {
        let result = try SolverVerificationSuite.thickCylinderLame.execute()

        #expect(result.allPassed, "Thick cylinder benchmark failed metric tolerances.")

        let urAMetric = try #require(result.metrics.first { $0.metricName == "Inner Radial Displacement" })
        #expect(urAMetric.passed, "Inner radial displacement error \(urAMetric.relativeError * 100)% exceeds 5%.")
        #expect(urAMetric.relativeError <= 0.05)

        let urBMetric = try #require(result.metrics.first { $0.metricName == "Outer Radial Displacement" })
        #expect(urBMetric.passed, "Outer radial displacement error \(urBMetric.relativeError * 100)% exceeds 5%.")
        #expect(urBMetric.relativeError <= 0.05)

        let hoopMetric = try #require(result.metrics.first { $0.metricName == "Inner Hoop Stress" })
        #expect(hoopMetric.passed, "Inner hoop stress error \(hoopMetric.relativeError * 100)% exceeds 5%.")
        #expect(hoopMetric.relativeError <= 0.05)

        let vmMetric = try #require(result.metrics.first { $0.metricName == "Inner von Mises Stress" })
        #expect(vmMetric.passed, "Inner von Mises stress error \(vmMetric.relativeError * 100)% exceeds 5%.")
        #expect(vmMetric.relativeError <= 0.05)
    }

    // MARK: - 5. Thermal Conduction 1D Benchmark

    @Test func testThermalConductionBenchmark() throws {
        let result = try SolverVerificationSuite.thermalConductionSlab.execute()

        #expect(result.allPassed, "Thermal conduction benchmark failed metric tolerances.")

        let tempMetric = try #require(result.metrics.first { $0.metricName == "Midpoint Temperature" })
        #expect(tempMetric.passed, "Midpoint temperature error \(tempMetric.relativeError * 100)% exceeds 1%.")
        #expect(tempMetric.relativeError <= 0.01)

        let fluxMetric = try #require(result.metrics.first { $0.metricName == "Heat Flux" })
        #expect(fluxMetric.passed, "Heat flux error \(fluxMetric.relativeError * 100)% exceeds 1%.")
        #expect(fluxMetric.relativeError <= 0.01)
    }

    // MARK: - 6. Synthetic Mesh Generators Integrity

    @Test func testSyntheticMeshGeneratorsIntegrity() {
        // 1. Cantilever Beam Mesh
        let beamMesh = SolverVerificationSuite.makeCantileverBeamMesh(length: 1.0, width: 0.05, height: 0.05, nx: 4, ny: 2, nz: 2)
        #expect(!beamMesh.nodes.isEmpty)
        #expect(!beamMesh.elements.isEmpty)
        let rootSet = beamMesh.set(named: "RootFace")
        let tipSet = beamMesh.set(named: "TipFace")
        #expect(rootSet != nil && !(rootSet?.nodeIds.isEmpty ?? true))
        #expect(tipSet != nil && !(tipSet?.nodeIds.isEmpty ?? true))

        var nodePosById = [Int: SIMD3<Double>]()
        for n in beamMesh.nodes { nodePosById[n.id] = n.position }

        for el in beamMesh.elements {
            let p0 = nodePosById[el.nodeIndices[0]]!
            let p1 = nodePosById[el.nodeIndices[1]]!
            let p2 = nodePosById[el.nodeIndices[2]]!
            let p3 = nodePosById[el.nodeIndices[3]]!
            let vol = Self.computeTetrahedronSignedVolume(p0: p0, p1: p1, p2: p2, p3: p3)
            #expect(abs(vol) > 1e-12, "Beam tetrahedron has non-positive or near-zero volume.")
        }

        // 2. Plate with Hole Mesh
        let plateMesh = SolverVerificationSuite.makePlateWithHoleMesh(holeRadius: 0.05, width: 0.25, length: 0.25, thickness: 0.01, nu: 4, nv: 2, nw: 1)
        #expect(!plateMesh.nodes.isEmpty)
        #expect(!plateMesh.elements.isEmpty)
        #expect(plateMesh.set(named: "SymmetryX") != nil)
        #expect(plateMesh.set(named: "SymmetryY") != nil)
        #expect(plateMesh.set(named: "RollerZ") != nil)
        #expect(plateMesh.set(named: "HoleEdge") != nil)
        #expect(plateMesh.set(named: "TensionY") != nil)

        nodePosById.removeAll()
        for n in plateMesh.nodes { nodePosById[n.id] = n.position }

        for el in plateMesh.elements {
            let p0 = nodePosById[el.nodeIndices[0]]!
            let p1 = nodePosById[el.nodeIndices[1]]!
            let p2 = nodePosById[el.nodeIndices[2]]!
            let p3 = nodePosById[el.nodeIndices[3]]!
            let vol = Self.computeTetrahedronSignedVolume(p0: p0, p1: p1, p2: p2, p3: p3)
            #expect(abs(vol) > 1e-12, "Plate tetrahedron has non-positive or near-zero volume.")
        }

        // 3. Thick Cylinder Mesh
        let cylinderMesh = SolverVerificationSuite.makeThickCylinderMesh(innerRadius: 0.1, outerRadius: 0.2, length: 0.1, nr: 2, ntheta: 4, nz: 1)
        #expect(!cylinderMesh.nodes.isEmpty)
        #expect(!cylinderMesh.elements.isEmpty)
        #expect(!cylinderMesh.surfaceTriangles.isEmpty)
        #expect(cylinderMesh.set(named: "SymmetryX") != nil)
        #expect(cylinderMesh.set(named: "SymmetryY") != nil)
        #expect(cylinderMesh.set(named: "RestraintZ") != nil)
        #expect(cylinderMesh.set(named: "InnerPressure") != nil)

        nodePosById.removeAll()
        for n in cylinderMesh.nodes { nodePosById[n.id] = n.position }

        for el in cylinderMesh.elements {
            let p0 = nodePosById[el.nodeIndices[0]]!
            let p1 = nodePosById[el.nodeIndices[1]]!
            let p2 = nodePosById[el.nodeIndices[2]]!
            let p3 = nodePosById[el.nodeIndices[3]]!
            let vol = Self.computeTetrahedronSignedVolume(p0: p0, p1: p1, p2: p2, p3: p3)
            #expect(abs(vol) > 1e-12, "Cylinder tetrahedron has non-positive or near-zero volume.")
        }

        // 4. Quadratic C3D10 Conversion
        let quadBeam = SolverVerificationSuite.convertToQuadraticC3D10(linearMesh: beamMesh)
        #expect(quadBeam.elements.count == beamMesh.elements.count)
        #expect(quadBeam.nodes.count > beamMesh.nodes.count)
        #expect(quadBeam.elements.allSatisfy { $0.order == .quadratic && $0.nodeIndices.count == 10 })
    }

    // MARK: - 7. Suite Execution and Timing

    @Test func testSuiteExecutionAndTiming() throws {
        let suiteResult = try SolverVerificationSuite.runAllBenchmarks()

        #expect(suiteResult.allPassed, "One or more benchmarks failed in the suite execution.")
        #expect(suiteResult.results.count == 5, "Expected 5 benchmarks, got \(suiteResult.results.count).")
        #expect(suiteResult.totalDuration < 30.0, "Total execution duration \(suiteResult.totalDuration)s exceeds 30.0s budget.")
    }
}
