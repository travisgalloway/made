import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct LinearBucklingSolverTests {

    // MARK: - 1. Cantilever Euler Buckling Verification (C3D4)

    @Test func testCantileverBeamEulerBucklingVerification() throws {
        let L = 1.0       // 1.0 meter
        let b = 0.05      // 50 mm
        let h = 0.05      // 50 mm
        let E = 200e9     // 200 GPa
        let nu = 0.3
        let P_applied = 100_000.0 // 100 kN compressive force

        // Euler analytical critical load for cantilever beam: P_cr = (pi^2 * E * I) / (4 * L^2)
        let I = (b * pow(h, 3)) / 12.0
        let theoreticalPcr = (Double.pi * Double.pi * E * I) / (4.0 * L * L)
        let expectedLambda = theoreticalPcr / P_applied

        let (mesh, rootIds, tipIds) = LinearStaticSolverTests.makeBeamMeshC3D10(
            length: L,
            width: b,
            height: h,
            nx: 12,
            ny: 2,
            nz: 2
        )

        var study = SimulationStudy(name: "Cantilever Buckling C3D4", studyType: .linearBuckling)
        study.solver.bucklingModesCount = 1

        let rootSet = VolumeMeshSet(name: "FixedRoot", nodeIds: Array(rootIds), elementIds: [])
        let tipSet = VolumeMeshSet(name: "LoadedTip", nodeIds: Array(tipIds), elementIds: [])
        var configuredMesh = mesh
        configuredMesh.sets = [rootSet, tipSet]

        study.fixtures = [
            SimulationFixture(name: "FixedRoot", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(
                name: "LoadedTip",
                kind: .force,
                magnitude: P_applied,
                direction: SIMD3<Double>(-1, 0, 0) // Axial compression
            )
        ]

        let result = try LinearBucklingSolver.solve(
            study: study,
            mesh: configuredMesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        let mode1 = try #require(result.modes.first)
        #expect(mode1.modeNumber == 1)
        #expect(mode1.loadFactor > 0.0)

        // Compare against analytical Euler critical load (within 10% agreement)
        let relativeError = abs(mode1.loadFactor - expectedLambda) / expectedLambda
        #expect(
            relativeError < 0.10,
            "Euler buckling eigenvalue error \(relativeError * 100)% exceeds 10% (computed λ=\(mode1.loadFactor), expected λ=\(expectedLambda), P_cr=\(mode1.loadFactor * P_applied) N vs \(theoreticalPcr) N)"
        )

        #expect(!result.extrema.isEmpty)
        #expect(result.extrema.contains { $0.fieldName == "Buckling Load Factor" })
    }

    // MARK: - 2. Quadratic C3D10 Beam Buckling Verification

    @Test func testQuadraticC3D10BucklingVerification() throws {
        let L = 0.8
        let b = 0.05
        let h = 0.05
        let E = 200e9
        let nu = 0.3
        let P_applied = 50_000.0

        let (mesh, rootIds, tipIds) = LinearStaticSolverTests.makeBeamMeshC3D10(
            length: L,
            width: b,
            height: h,
            nx: 6,
            ny: 1,
            nz: 1
        )

        var study = SimulationStudy(name: "Cantilever Buckling C3D10", studyType: .linearBuckling)
        study.solver.bucklingModesCount = 1

        let rootSet = VolumeMeshSet(name: "FixedRoot", nodeIds: Array(rootIds), elementIds: [])
        let tipSet = VolumeMeshSet(name: "LoadedTip", nodeIds: Array(tipIds), elementIds: [])
        var configuredMesh = mesh
        configuredMesh.sets = [rootSet, tipSet]

        study.fixtures = [
            SimulationFixture(name: "FixedRoot", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(
                name: "LoadedTip",
                kind: .force,
                magnitude: P_applied,
                direction: SIMD3<Double>(-1, 0, 0)
            )
        ]

        let result = try LinearBucklingSolver.solve(
            study: study,
            mesh: configuredMesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        #expect(!result.modes.isEmpty)
        let mode1 = try #require(result.modes.first)
        #expect(mode1.modeNumber == 1)
        #expect(mode1.loadFactor > 0.0)
    }

    // MARK: - 3. Multiple Buckling Modes Orthogonality

    @Test func testMultipleBucklingModesOrthogonality() throws {
        let L = 1.0
        let b = 0.05
        let h = 0.05
        let E = 200e9
        let nu = 0.3
        let P_applied = 100_000.0

        let (mesh, rootIds, tipIds) = LinearStaticSolverTests.makeBeamMeshC3D4(
            length: L,
            width: b,
            height: h,
            nx: 8,
            ny: 2,
            nz: 2
        )

        var study = SimulationStudy(name: "Multi-Mode Buckling", studyType: .linearBuckling)
        study.solver.bucklingModesCount = 3

        let rootSet = VolumeMeshSet(name: "FixedRoot", nodeIds: Array(rootIds), elementIds: [])
        let tipSet = VolumeMeshSet(name: "LoadedTip", nodeIds: Array(tipIds), elementIds: [])
        var configuredMesh = mesh
        configuredMesh.sets = [rootSet, tipSet]

        study.fixtures = [
            SimulationFixture(name: "FixedRoot", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(
                name: "LoadedTip",
                kind: .force,
                magnitude: P_applied,
                direction: SIMD3<Double>(-1, 0, 0)
            )
        ]

        let result = try LinearBucklingSolver.solve(
            study: study,
            mesh: configuredMesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        #expect(result.modes.count == 3)
        let mode1 = result.modes[0]
        let mode2 = result.modes[1]
        let mode3 = result.modes[2]

        // Ascending load factors
        #expect(mode1.loadFactor <= mode2.loadFactor)
        #expect(mode2.loadFactor <= mode3.loadFactor)

        // Mode shape orthogonality check (dot product of normalized nodal displacement vectors)
        let nodeIds = mesh.nodes.map(\.id)
        var dot12 = 0.0
        var norm1 = 0.0
        var norm2 = 0.0

        for nId in nodeIds {
            let u1 = mode1.nodalDisplacements[nId] ?? .zero
            let u2 = mode2.nodalDisplacements[nId] ?? .zero
            dot12 += simd_dot(u1, u2)
            norm1 += simd_dot(u1, u1)
            norm2 += simd_dot(u2, u2)
        }

        let cosineSimilarity = abs(dot12) / (sqrt(norm1) * sqrt(norm2) + 1e-15)
        #expect(
            cosineSimilarity < 0.10,
            "Buckling modes 1 and 2 are not orthogonal: cosine similarity = \(cosineSimilarity)"
        )
    }

    // MARK: - 4. Error State and Boundary Validation

    @Test func testZeroLoadThrowsInvalidStudyConfiguration() {
        let (mesh, rootIds, _) = LinearStaticSolverTests.makeBeamMeshC3D4(nx: 4, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Zero Load", studyType: .linearBuckling)
        study.fixtures = [
            SimulationFixture(name: "FixedRoot", kind: .fixed)
        ]
        study.loads = []

        let rootSet = VolumeMeshSet(name: "FixedRoot", nodeIds: Array(rootIds), elementIds: [])
        var configuredMesh = mesh
        configuredMesh.sets = [rootSet]

        #expect(throws: CAEErrorCode.self) {
            _ = try LinearBucklingSolver.solve(study: study, mesh: configuredMesh)
        }
    }

    @Test func testUnconstrainedMeshThrowsInvalidStudyConfiguration() {
        let (mesh, _, tipIds) = LinearStaticSolverTests.makeBeamMeshC3D4(nx: 4, ny: 1, nz: 1)
        var study = SimulationStudy(name: "No Fixture", studyType: .linearBuckling)
        study.fixtures = []
        study.loads = [
            SimulationLoad(name: "LoadedTip", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]

        let tipSet = VolumeMeshSet(name: "LoadedTip", nodeIds: Array(tipIds), elementIds: [])
        var configuredMesh = mesh
        configuredMesh.sets = [tipSet]

        #expect(throws: CAEErrorCode.self) {
            _ = try LinearBucklingSolver.solve(study: study, mesh: configuredMesh)
        }
    }

    @Test func testEmptyMeshThrowsInvalidStudyConfiguration() {
        let emptyMesh = VolumeMesh(nodes: [], elements: [], surfaceTriangles: [])
        var study = SimulationStudy(name: "Empty Mesh", studyType: .linearBuckling)
        study.fixtures = [SimulationFixture(name: "Base", kind: .fixed)]
        study.loads = [SimulationLoad(name: "Force", kind: .force, magnitude: 100.0)]

        #expect(throws: CAEErrorCode.self) {
            _ = try LinearBucklingSolver.solve(study: study, mesh: emptyMesh)
        }
    }
}
