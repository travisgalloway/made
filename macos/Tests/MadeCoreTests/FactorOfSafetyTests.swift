import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct FactorOfSafetyTests {

    // MARK: - 1. Uniaxial Tension Benchmark

    @Test func testCauchyStressTensorUniaxialTension() throws {
        let sigma0 = 100.0 // 100 MPa tensile stress in X
        let tensor = CauchyStressTensor(sxx: sigma0, syy: 0, szz: 0, sxy: 0, syz: 0, szx: 0)

        let principals = tensor.principalStresses
        #expect(abs(principals.sigma1 - sigma0) < 1e-6)
        #expect(abs(principals.sigma2 - 0.0) < 1e-6)
        #expect(abs(principals.sigma3 - 0.0) < 1e-6)

        let vm = tensor.vonMisesStress
        #expect(abs(vm - sigma0) < 1e-6)

        let tresca = tensor.trescaStress
        #expect(abs(tresca - sigma0) < 1e-6)

        let rankine = tensor.maxPrincipalStress
        #expect(abs(rankine - sigma0) < 1e-6)

        let allowable = 250.0 // 250 MPa yield strength
        let fosVM = allowable / vm
        let fosTresca = allowable / tresca
        let fosRankine = allowable / rankine

        #expect(abs(fosVM - 2.5) < 1e-6)
        #expect(abs(fosTresca - 2.5) < 1e-6)
        #expect(abs(fosRankine - 2.5) < 1e-6)
    }

    // MARK: - 2. Pure Shear Benchmark (Tresca vs von Mises Ratio)

    @Test func testCauchyStressTensorPureShear() throws {
        let tau = 50.0 // 50 MPa pure shear stress in XY
        let tensor = CauchyStressTensor(sxx: 0, syy: 0, szz: 0, sxy: tau, syz: 0, szx: 0)

        let principals = tensor.principalStresses
        #expect(abs(principals.sigma1 - tau) < 1e-6)
        #expect(abs(principals.sigma2 - 0.0) < 1e-6)
        #expect(abs(principals.sigma3 - (-tau)) < 1e-6)

        let vm = tensor.vonMisesStress
        let expectedVM = sqrt(3.0) * tau
        #expect(abs(vm - expectedVM) < 1e-6)

        let tresca = tensor.trescaStress
        let expectedTresca = 2.0 * tau
        #expect(abs(tresca - expectedTresca) < 1e-6)

        let rankine = tensor.maxPrincipalStress
        #expect(abs(rankine - tau) < 1e-6)

        // Factor of safety comparison under pure shear
        let allowable = 250.0
        let fosVM = allowable / vm
        let fosTresca = allowable / tresca

        let ratio = fosTresca / fosVM
        let expectedRatio = sqrt(3.0) / 2.0 // Exactly ~0.8660254
        #expect(abs(ratio - expectedRatio) < 1e-6, "Tresca FOS should be exactly sqrt(3)/2 of von Mises FOS")
    }

    // MARK: - 3. Hydrostatic Pressure Benchmark

    @Test func testCauchyStressTensorHydrostaticPressure() throws {
        let p = 120.0 // 120 MPa hydrostatic compression
        let tensor = CauchyStressTensor(sxx: -p, syy: -p, szz: -p, sxy: 0, syz: 0, szx: 0)

        let principals = tensor.principalStresses
        #expect(abs(principals.sigma1 - (-p)) < 1e-6)
        #expect(abs(principals.sigma2 - (-p)) < 1e-6)
        #expect(abs(principals.sigma3 - (-p)) < 1e-6)

        #expect(abs(tensor.vonMisesStress) < 1e-6)
        #expect(abs(tensor.trescaStress) < 1e-6)

        let settingsVM = FactorOfSafetySettings(criterion: .vonMises, maxClampedFOS: 15.0)
        let resultVM = FactorOfSafetyCalculator.evaluate(
            nodalTensors: [1: tensor],
            material: nil,
            settings: settingsVM
        )
        #expect(resultVM.minFactorOfSafety == 15.0)
        #expect(resultVM.meetsDesignFactor == true)

        let settingsTresca = FactorOfSafetySettings(criterion: .tresca, maxClampedFOS: 15.0)
        let resultTresca = FactorOfSafetyCalculator.evaluate(
            nodalTensors: [1: tensor],
            material: nil,
            settings: settingsTresca
        )
        #expect(resultTresca.minFactorOfSafety == 15.0)
    }

    // MARK: - 4. Allowable Strength Resolution

    @Test func testAllowableStrengthResolution() throws {
        // Fallback for nil material
        let fallbackYield = FactorOfSafetyCalculator.resolveAllowableStrength(material: nil, basis: .yield)
        let fallbackUltimate = FactorOfSafetyCalculator.resolveAllowableStrength(material: nil, basis: .ultimate)
        #expect(fallbackYield == 250.0)
        #expect(fallbackUltimate == 400.0)

        // Standard structural steel
        let steel = StandardMaterials.structuralSteel
        let steelYield = FactorOfSafetyCalculator.resolveAllowableStrength(material: steel, basis: .yield)
        let steelUltimate = FactorOfSafetyCalculator.resolveAllowableStrength(material: steel, basis: .ultimate)
        #expect(steelYield == 250.0)
        #expect(steelUltimate == 400.0)

        // Aluminum 6061-T6
        let alu = MaterialLibrary.standard.material(withId: "aluminum-6061-t6")
        #expect(alu != nil)
        let aluYield = FactorOfSafetyCalculator.resolveAllowableStrength(material: alu, basis: .yield)
        let aluUltimate = FactorOfSafetyCalculator.resolveAllowableStrength(material: alu, basis: .ultimate)
        #expect(aluYield == 276.0)
        #expect(aluUltimate == 310.0)
    }

    // MARK: - 5. Numerical Clamping and Zero Stress Safety

    @Test func testNumericalClampingAndZeroStress() throws {
        let zeroTensor = CauchyStressTensor()
        let settings = FactorOfSafetySettings(maxClampedFOS: 15.0)

        let result = FactorOfSafetyCalculator.evaluate(
            nodalTensors: [1: zeroTensor],
            material: nil,
            settings: settings
        )

        #expect(result.minFactorOfSafety == 15.0)
        #expect(result.maxFactorOfSafety == 15.0)
        #expect(!result.minFactorOfSafety.isNaN)
        #expect(result.minFactorOfSafety.isFinite)
        #expect(result.meetsDesignFactor == true)
        #expect(result.failingNodeCount == 0)

        // Micro-stress below 1e-6 threshold
        let microTensor = CauchyStressTensor(sxx: 1e-8, syy: 1e-8, szz: 1e-8)
        let microResult = FactorOfSafetyCalculator.evaluate(
            nodalTensors: [1: microTensor],
            material: nil,
            settings: settings
        )
        #expect(microResult.minFactorOfSafety == 15.0)

        // Evaluator from nodal scalar stresses
        let scalarResult = FactorOfSafetyCalculator.evaluate(
            nodalVonMisesStresses: [1: 0.0, 2: 1e-9],
            material: nil,
            settings: settings
        )
        #expect(scalarResult.minFactorOfSafety == 15.0)
        #expect(!scalarResult.minFactorOfSafety.isNaN)
    }

    // MARK: - 6. Codable Round-Trip

    @Test func testFactorOfSafetyCodableRoundTrip() throws {
        let settings = FactorOfSafetySettings(
            basis: .ultimate,
            criterion: .tresca,
            targetDesignFactor: 2.5,
            maxClampedFOS: 20.0
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let settingsData = try encoder.encode(settings)
        let decodedSettings = try decoder.decode(FactorOfSafetySettings.self, from: settingsData)
        #expect(decodedSettings == settings)

        let tensor = CauchyStressTensor(sxx: 120.0, syy: -30.0, szz: 10.0, sxy: 15.0, syz: 5.0, szx: 2.0)
        let tensorData = try encoder.encode(tensor)
        let decodedTensor = try decoder.decode(CauchyStressTensor.self, from: tensorData)
        #expect(decodedTensor == tensor)

        let result = FactorOfSafetyResult(
            basis: .yield,
            criterion: .vonMises,
            allowableStrengthMPa: 250.0,
            minFactorOfSafety: 1.85,
            maxFactorOfSafety: 15.0,
            criticalNodeId: 42,
            criticalStressMPa: 135.135,
            targetDesignFactor: 2.0,
            meetsDesignFactor: false,
            failingNodeCount: 3,
            totalNodeCount: 150,
            nodalFactorsOfSafety: [42: 1.85, 43: 2.15]
        )

        let resultData = try encoder.encode(result)
        let decodedResult = try decoder.decode(FactorOfSafetyResult.self, from: resultData)
        #expect(decodedResult == result)
    }

    // MARK: - 7. Analytical Cantilever Beam Benchmark

    @Test func testAnalyticalCantileverBeamFactorOfSafety() throws {
        let L = 1.0 // 1 meter
        let b = 0.05 // 50 mm
        let h = 0.05 // 50 mm
        let E = 200e9 // 200 GPa
        let nu = 0.0
        let F = 1000.0 // 1000 N downward tip force
        let Iz = (b * pow(h, 3)) / 12.0 // 5.208333e-7 m^4

        // Euler-Bernoulli analytical max bending stress: sigma = M * c / Iz = F * L * (h/2) / Iz = 48.0 MPa
        let analyticMaxStressMPa = ((F * L * (h / 2.0)) / Iz) * 1e-6
        let yieldStrengthMPa = 250.0 // Structural steel yield strength
        let analyticFOS = yieldStrengthMPa / analyticMaxStressMPa // ~5.2083

        let (mesh, _, _) = LinearStaticSolverTests.makeBeamMeshC3D10(length: L, width: b, height: h, nx: 12, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Cantilever Beam FOS", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: F, direction: SIMD3<Double>(0, -1, 0))
        ]
        study.factorOfSafetySettings = FactorOfSafetySettings(
            basis: .yield,
            criterion: .vonMises,
            targetDesignFactor: 2.0
        )

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        let fos = try #require(result.factorOfSafety)
        #expect(fos.allowableStrengthMPa == 250.0)
        #expect(fos.meetsDesignFactor == true)

        let fosExtrema = try #require(result.extrema.first { $0.fieldName == "Factor of Safety" })
        #expect(abs(fosExtrema.minValue - fos.minFactorOfSafety) < 1e-6)

        let fosError = abs(fos.minFactorOfSafety - analyticFOS) / analyticFOS
        #expect(fosError < 0.03, "Cantilever beam FOS error \(fosError * 100)% exceeds 3% (computed \(fos.minFactorOfSafety) vs analytic \(analyticFOS))")
    }
}
