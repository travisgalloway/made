import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct LinearStaticSolverTests {

    // MARK: - Helper Mesh Generators

    /// Generates a structured box decomposed into linear C3D4 tetrahedra (6 tets per hex cell).
    static func makeBeamMeshC3D4(
        length: Double = 1.0,
        width: Double = 0.05,
        height: Double = 0.05,
        nx: Int = 20,
        ny: Int = 2,
        nz: Int = 2
    ) -> (mesh: VolumeMesh, rootNodeIds: Set<Int>, tipNodeIds: Set<Int>) {
        var nodes: [VolumeMeshNode] = []
        var nodeMap = [SIMD3<Int>: Int]()

        let dx = length / Double(nx)
        let dy = width / Double(ny)
        let dz = height / Double(nz)

        var nodeId = 1
        var rootNodeIds = Set<Int>()
        var tipNodeIds = Set<Int>()

        for i in 0...nx {
            for j in 0...ny {
                for k in 0...nz {
                    let pos = SIMD3<Double>(Double(i) * dx, Double(j) * dy, Double(k) * dz)
                    nodes.append(VolumeMeshNode(id: nodeId, position: pos))
                    nodeMap[SIMD3<Int>(i, j, k)] = nodeId
                    if i == 0 { rootNodeIds.insert(nodeId) }
                    if i == nx { tipNodeIds.insert(nodeId) }
                    nodeId += 1
                }
            }
        }

        var elements: [VolumeMeshElement] = []
        var elId = 1

        for i in 0..<nx {
            for j in 0..<ny {
                for k in 0..<nz {
                    let n000 = nodeMap[SIMD3<Int>(i, j, k)]!
                    let n100 = nodeMap[SIMD3<Int>(i + 1, j, k)]!
                    let n010 = nodeMap[SIMD3<Int>(i, j + 1, k)]!
                    let n110 = nodeMap[SIMD3<Int>(i + 1, j + 1, k)]!
                    let n001 = nodeMap[SIMD3<Int>(i, j, k + 1)]!
                    let n101 = nodeMap[SIMD3<Int>(i + 1, j, k + 1)]!
                    let n011 = nodeMap[SIMD3<Int>(i, j + 1, k + 1)]!
                    let n111 = nodeMap[SIMD3<Int>(i + 1, j + 1, k + 1)]!

                    let tets: [[Int]] = [
                        [n000, n100, n110, n111],
                        [n000, n110, n010, n111],
                        [n000, n010, n011, n111],
                        [n000, n011, n001, n111],
                        [n000, n001, n101, n111],
                        [n000, n101, n100, n111]
                    ]

                    for t in tets {
                        elements.append(VolumeMeshElement(id: elId, order: .linear, nodeIndices: t))
                        elId += 1
                    }
                }
            }
        }

        let rootSet = VolumeMeshSet(name: "RootFace", nodeIds: Array(rootNodeIds), elementIds: [])
        let tipSet = VolumeMeshSet(name: "TipFace", nodeIds: Array(tipNodeIds), elementIds: [])

        let mesh = VolumeMesh(
            nodes: nodes,
            elements: elements,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count),
            sets: [rootSet, tipSet]
        )
        return (mesh, rootNodeIds, tipNodeIds)
    }

    /// Generates a structured box decomposed into quadratic C3D10 tetrahedra (10 nodes per tet).
    static func makeBeamMeshC3D10(
        length: Double = 1.0,
        width: Double = 0.05,
        height: Double = 0.05,
        nx: Int = 10,
        ny: Int = 2,
        nz: Int = 2
    ) -> (mesh: VolumeMesh, rootNodeIds: Set<Int>, tipNodeIds: Set<Int>) {
        let (linearMesh, _, _) = makeBeamMeshC3D4(length: length, width: width, height: height, nx: nx, ny: ny, nz: nz)

        var nodes = linearMesh.nodes
        var nextNodeId = nodes.count + 1

        struct EdgeKey: Hashable {
            let n1: Int, n2: Int
            init(_ a: Int, _ b: Int) {
                if a < b { self.n1 = a; self.n2 = b }
                else { self.n1 = b; self.n2 = a }
            }
        }

        var nodePositionsById: [Int: SIMD3<Double>] = [:]
        for n in nodes { nodePositionsById[n.id] = n.position }

        var edgeMidNodes: [EdgeKey: Int] = [:]

        func getOrCreateMidNode(_ a: Int, _ b: Int) -> Int {
            let key = EdgeKey(a, b)
            if let existing = edgeMidNodes[key] {
                return existing
            }
            let pA = nodePositionsById[a]!
            let pB = nodePositionsById[b]!
            let midPos = 0.5 * (pA + pB)
            let midId = nextNodeId
            nextNodeId += 1
            nodes.append(VolumeMeshNode(id: midId, position: midPos))
            nodePositionsById[midId] = midPos
            edgeMidNodes[key] = midId
            return midId
        }

        var quadraticElements: [VolumeMeshElement] = []
        for el in linearMesh.elements {
            let c = el.nodeIndices
            let n0 = c[0], n1 = c[1], n2 = c[2], n3 = c[3]
            // Standard C3D10 mid-edges: 0-1, 1-2, 2-0, 0-3, 1-3, 2-3
            let n4 = getOrCreateMidNode(n0, n1)
            let n5 = getOrCreateMidNode(n1, n2)
            let n6 = getOrCreateMidNode(n2, n0)
            let n7 = getOrCreateMidNode(n0, n3)
            let n8 = getOrCreateMidNode(n1, n3)
            let n9 = getOrCreateMidNode(n2, n3)

            let full10 = [n0, n1, n2, n3, n4, n5, n6, n7, n8, n9]
            quadraticElements.append(VolumeMeshElement(id: el.id, order: .quadratic, nodeIndices: full10))
        }

        var rootNodeIds = Set<Int>()
        var tipNodeIds = Set<Int>()
        for n in nodes {
            if abs(n.position.x) < 1e-9 { rootNodeIds.insert(n.id) }
            if abs(n.position.x - length) < 1e-9 { tipNodeIds.insert(n.id) }
        }

        let rootSet = VolumeMeshSet(name: "RootFace", nodeIds: Array(rootNodeIds), elementIds: [])
        let tipSet = VolumeMeshSet(name: "TipFace", nodeIds: Array(tipNodeIds), elementIds: [])

        let mesh = VolumeMesh(
            nodes: nodes,
            elements: quadraticElements,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: quadraticElements.count),
            sets: [rootSet, tipSet]
        )
        return (mesh, rootNodeIds, tipNodeIds)
    }

    /// Generates two touching box meshes decomposed into linear C3D4 tetrahedra touching at x = splitX.
    static func makeTwoBlockTouchingMeshC3D4(
        totalLength: Double = 1.0,
        splitX: Double = 0.5,
        width: Double = 0.05,
        height: Double = 0.05,
        nx1: Int = 10,
        nx2: Int = 10,
        ny: Int = 2,
        nz: Int = 2,
        gap: Double = 0.0
    ) -> (
        mesh: VolumeMesh,
        rootNodeIds: Set<Int>,
        tipNodeIds: Set<Int>,
        block1InterfaceNodeIds: Set<Int>,
        block2InterfaceNodeIds: Set<Int>
    ) {
        var nodes: [VolumeMeshNode] = []
        var elements: [VolumeMeshElement] = []
        var nodeId = 1
        var elId = 1

        var rootNodeIds = Set<Int>()
        var tipNodeIds = Set<Int>()
        var block1InterfaceNodeIds = Set<Int>()
        var block2InterfaceNodeIds = Set<Int>()

        let dy = width / Double(ny)
        let dz = height / Double(nz)

        // Block 1: x in [0, splitX]
        var nodeMap1 = [SIMD3<Int>: Int]()
        let dx1 = splitX / Double(nx1)
        for i in 0...nx1 {
            for j in 0...ny {
                for k in 0...nz {
                    let pos = SIMD3<Double>(Double(i) * dx1, Double(j) * dy, Double(k) * dz)
                    nodes.append(VolumeMeshNode(id: nodeId, position: pos))
                    nodeMap1[SIMD3<Int>(i, j, k)] = nodeId
                    if i == 0 { rootNodeIds.insert(nodeId) }
                    if i == nx1 { block1InterfaceNodeIds.insert(nodeId) }
                    nodeId += 1
                }
            }
        }
        for i in 0..<nx1 {
            for j in 0..<ny {
                for k in 0..<nz {
                    let n000 = nodeMap1[SIMD3<Int>(i, j, k)]!
                    let n100 = nodeMap1[SIMD3<Int>(i + 1, j, k)]!
                    let n010 = nodeMap1[SIMD3<Int>(i, j + 1, k)]!
                    let n110 = nodeMap1[SIMD3<Int>(i + 1, j + 1, k)]!
                    let n001 = nodeMap1[SIMD3<Int>(i, j, k + 1)]!
                    let n101 = nodeMap1[SIMD3<Int>(i + 1, j, k + 1)]!
                    let n011 = nodeMap1[SIMD3<Int>(i, j + 1, k + 1)]!
                    let n111 = nodeMap1[SIMD3<Int>(i + 1, j + 1, k + 1)]!

                    let tets: [[Int]] = [
                        [n000, n100, n110, n111],
                        [n000, n110, n010, n111],
                        [n000, n010, n011, n111],
                        [n000, n011, n001, n111],
                        [n000, n001, n101, n111],
                        [n000, n101, n100, n111]
                    ]
                    for t in tets {
                        elements.append(VolumeMeshElement(id: elId, order: .linear, nodeIndices: t))
                        elId += 1
                    }
                }
            }
        }

        // Block 2: x in [splitX + gap, totalLength + gap]
        var nodeMap2 = [SIMD3<Int>: Int]()
        let dx2 = (totalLength - splitX) / Double(nx2)
        for i in 0...nx2 {
            for j in 0...ny {
                for k in 0...nz {
                    let pos = SIMD3<Double>(splitX + gap + Double(i) * dx2, Double(j) * dy, Double(k) * dz)
                    nodes.append(VolumeMeshNode(id: nodeId, position: pos))
                    nodeMap2[SIMD3<Int>(i, j, k)] = nodeId
                    if i == 0 { block2InterfaceNodeIds.insert(nodeId) }
                    if i == nx2 { tipNodeIds.insert(nodeId) }
                    nodeId += 1
                }
            }
        }
        for i in 0..<nx2 {
            for j in 0..<ny {
                for k in 0..<nz {
                    let n000 = nodeMap2[SIMD3<Int>(i, j, k)]!
                    let n100 = nodeMap2[SIMD3<Int>(i + 1, j, k)]!
                    let n010 = nodeMap2[SIMD3<Int>(i, j + 1, k)]!
                    let n110 = nodeMap2[SIMD3<Int>(i + 1, j + 1, k)]!
                    let n001 = nodeMap2[SIMD3<Int>(i, j, k + 1)]!
                    let n101 = nodeMap2[SIMD3<Int>(i + 1, j, k + 1)]!
                    let n011 = nodeMap2[SIMD3<Int>(i, j + 1, k + 1)]!
                    let n111 = nodeMap2[SIMD3<Int>(i + 1, j + 1, k + 1)]!

                    let tets: [[Int]] = [
                        [n000, n100, n110, n111],
                        [n000, n110, n010, n111],
                        [n000, n010, n011, n111],
                        [n000, n011, n001, n111],
                        [n000, n001, n101, n111],
                        [n000, n101, n100, n111]
                    ]
                    for t in tets {
                        elements.append(VolumeMeshElement(id: elId, order: .linear, nodeIndices: t))
                        elId += 1
                    }
                }
            }
        }

        let rootSet = VolumeMeshSet(name: "RootFace", nodeIds: Array(rootNodeIds).sorted(), elementIds: [])
        let tipSet = VolumeMeshSet(name: "TipFace", nodeIds: Array(tipNodeIds).sorted(), elementIds: [])
        let b1Set = VolumeMeshSet(name: "Block1Interface", nodeIds: Array(block1InterfaceNodeIds).sorted(), elementIds: [])
        let b2Set = VolumeMeshSet(name: "Block2Interface", nodeIds: Array(block2InterfaceNodeIds).sorted(), elementIds: [])

        let mesh = VolumeMesh(
            nodes: nodes,
            elements: elements,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count),
            sets: [rootSet, tipSet, b1Set, b2Set]
        )

        return (mesh, rootNodeIds, tipNodeIds, block1InterfaceNodeIds, block2InterfaceNodeIds)
    }

    // MARK: - 1. Empty Mesh Error Handling

    @Test func testEmptyMeshThrowsError() {
        let emptyMesh = VolumeMesh(nodes: [], elements: [])
        let study = SimulationStudy(name: "Empty", studyType: .linearStatic)
        #expect(throws: CAEErrorCode.self) {
            try LinearStaticSolver.solve(study: study, mesh: emptyMesh)
        }
    }

    // MARK: - 2. Unconstrained Body Error Handling

    @Test func testUnconstrainedStructuralSystemThrowsError() {
        let (mesh, _, _) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.1, height: 0.1, nx: 2, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Unconstrained", studyType: .linearStatic)
        study.fixtures = [] // No fixtures
        #expect(throws: CAEErrorCode.self) {
            try LinearStaticSolver.solve(study: study, mesh: mesh)
        }
    }

    // MARK: - 3. Prescribed Displacement Boundary Condition

    @Test func testPrescribedDisplacementBoundaryCondition() throws {
        let (mesh, rootIds, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.1, height: 0.1, nx: 4, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Prescribed Disp", studyType: .linearStatic)
        let prescribed = SIMD3<Double>(2.5, -1.0, 0.5) // mm

        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed),
            SimulationFixture(
                name: "TipFace",
                kind: .prescribedDisplacement,
                prescribedDisplacement: prescribed,
                isRestrainedX: true,
                isRestrainedY: true,
                isRestrainedZ: true
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.3
        )

        // Verify root nodes have zero displacement
        for rId in rootIds {
            let d = try #require(result.nodalDisplacements[rId])
            #expect(abs(d.x) < 1e-6)
            #expect(abs(d.y) < 1e-6)
            #expect(abs(d.z) < 1e-6)
        }

        // Verify tip nodes have prescribed displacement in mm
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(abs(d.x - prescribed.x) < 1e-4)
            #expect(abs(d.y - prescribed.y) < 1e-4)
            #expect(abs(d.z - prescribed.z) < 1e-4)
        }
    }

    // MARK: - 4. Axial Tension Bar Analytic Verification

    @Test func testTensionBarAnalyticVerification() throws {
        let L = 1.0 // 1 meter
        let b = 0.05 // 50 mm
        let h = 0.05 // 50 mm
        let A = b * h // 0.0025 m²
        let E = 200e9 // 200 GPa
        let nu = 0.0 // Zero Poisson ratio for pure 1D uniaxial strain
        let Fx = 10000.0 // 10 kN tensile force

        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: L, width: b, height: h, nx: 10, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Tension Bar", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: Fx, direction: SIMD3<Double>(1, 0, 0))
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        // Analytical elongation: deltaL = F * L / (E * A) in meters
        let analyticDeltaLMeters = (Fx * L) / (E * A)
        let analyticDeltaLMm = analyticDeltaLMeters * 1000.0 // mm
        // Analytical stress: sigma = F / A in Pa, converted to MPa
        let analyticSigmaMPa = (Fx / A) * 1e-6

        // Check tip displacement
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            let errDisp = abs(d.x - analyticDeltaLMm) / analyticDeltaLMm
            #expect(errDisp < 0.01, "Axial displacement error \(errDisp * 100)% exceeds 1%")
            #expect(abs(d.y) < 1e-4)
            #expect(abs(d.z) < 1e-4)
        }

        // Check average stress throughout the bar matches within 1%
        let avgStress = result.elementVonMisesStresses.values.reduce(0.0, +) / Double(result.elementVonMisesStresses.count)
        let errAvgStress = abs(avgStress - analyticSigmaMPa) / analyticSigmaMPa
        #expect(errAvgStress < 0.01, "Axial average stress error \(errAvgStress * 100)% exceeds 1%")

        let stressExtrema = try #require(result.extrema.first { $0.fieldName == "von Mises Stress" })
        let errStress = abs(stressExtrema.maxValue - analyticSigmaMPa) / analyticSigmaMPa
        #expect(errStress < 0.05, "Axial peak stress error \(errStress * 100)% exceeds 5%")
    }

    // MARK: - 5. Cantilever Beam Benchmark (Euler-Bernoulli Verification)

    @Test func testCantileverBeamAnalyticVerification() throws {
        let L = 1.0 // 1 meter
        let b = 0.05 // 50 mm
        let h = 0.05 // 50 mm
        let E = 200e9 // 200 GPa
        let nu = 0.0 // Uncoupled bending benchmark
        let F = 1000.0 // 1000 N downward tip force
        let Iz = (b * pow(h, 3)) / 12.0 // Second moment of area: 5.208333e-7 m^4

        // Euler-Bernoulli analytical tip deflection: v = F * L^3 / (3 * E * Iz)
        let analyticTipDispMeters = (F * pow(L, 3)) / (3.0 * E * Iz)
        let analyticTipDispMm = analyticTipDispMeters * 1000.0 // 3.20 mm
        // Euler-Bernoulli analytical max bending stress: sigma = M * c / Iz = F * L * (h/2) / Iz
        let analyticMaxStressMPa = ((F * L * (h / 2.0)) / Iz) * 1e-6 // 48.0 MPa

        let (mesh, _, tipIds) = Self.makeBeamMeshC3D10(length: L, width: b, height: h, nx: 12, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Cantilever Beam", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: F, direction: SIMD3<Double>(0, -1, 0))
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        // Average tip downward displacement
        var sumTipY = 0.0
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            sumTipY += abs(d.y)
        }
        let avgTipDispMm = sumTipY / Double(tipIds.count)
        let tipError = abs(avgTipDispMm - analyticTipDispMm) / analyticTipDispMm

        // Tip deflection matches Euler-Bernoulli beam theory within 2%
        #expect(tipError < 0.02, "Tip deflection error \(tipError * 100)% exceeds 2% (computed \(avgTipDispMm) mm vs analytic \(analyticTipDispMm) mm)")

        // Maximum bending stress matches Euler-Bernoulli beam theory within 2%
        let stressExtrema = try #require(result.extrema.first { $0.fieldName == "von Mises Stress" })
        let stressError = abs(stressExtrema.maxValue - analyticMaxStressMPa) / analyticMaxStressMPa
        #expect(stressError < 0.02, "Max stress error \(stressError * 100)% exceeds 2% (computed \(stressExtrema.maxValue) MPa vs analytic \(analyticMaxStressMPa) MPa)")
    }

    // MARK: - 6. Cantilever Beam Benchmark (C3D10 Quadratic Tetrahedra)

    @Test func testQuadraticC3D10CantileverBeamVerification() throws {
        let L = 1.0 // 1 meter
        let b = 0.05 // 50 mm
        let h = 0.05 // 50 mm
        let E = 200e9 // 200 GPa
        let nu = 0.0 // Uncoupled bending benchmark
        let F = 1000.0 // 1000 N downward tip force
        let Iz = (b * pow(h, 3)) / 12.0 // 5.208333e-7 m^4

        let analyticTipDispMeters = (F * pow(L, 3)) / (3.0 * E * Iz)
        let analyticTipDispMm = analyticTipDispMeters * 1000.0 // 3.20 mm
        let analyticMaxStressMPa = ((F * L * (h / 2.0)) / Iz) * 1e-6 // 48.0 MPa

        let (mesh, _, tipIds) = Self.makeBeamMeshC3D10(length: L, width: b, height: h, nx: 12, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Cantilever C3D10", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: F, direction: SIMD3<Double>(0, -1, 0))
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        var sumTipY = 0.0
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            sumTipY += abs(d.y)
        }
        let avgTipDispMm = sumTipY / Double(tipIds.count)
        let tipError = abs(avgTipDispMm - analyticTipDispMm) / analyticTipDispMm

        #expect(tipError < 0.02, "C3D10 tip deflection error \(tipError * 100)% exceeds 2% (computed \(avgTipDispMm) mm vs analytic \(analyticTipDispMm) mm)")

        let stressExtrema = try #require(result.extrema.first { $0.fieldName == "von Mises Stress" })
        let stressError = abs(stressExtrema.maxValue - analyticMaxStressMPa) / analyticMaxStressMPa
        #expect(stressError < 0.02, "C3D10 max stress error \(stressError * 100)% exceeds 2% (computed \(stressExtrema.maxValue) MPa vs analytic \(analyticMaxStressMPa) MPa)")
    }

    // MARK: - 7. Elastic Support Boundary Condition Analytic Verification

    @Test func testElasticSupportBoundaryCondition() throws {
        let L = 1.0 // 1 meter
        let b = 0.05 // 50 mm
        let h = 0.05 // 50 mm
        let A = b * h // 0.0025 m²
        let E = 200e9 // 200 GPa
        let nu = 0.0 // Zero Poisson ratio for pure uniaxial response
        let Fx = 10000.0 // 10 kN tensile force
        let Kspring = 1e7 // 10^7 N/m total spring foundation stiffness

        let (mesh, rootIds, tipIds) = Self.makeBeamMeshC3D4(length: L, width: b, height: h, nx: 10, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Elastic Foundation Bar", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(
                name: "RootFace",
                kind: .elasticSupport,
                isRestrainedX: true,
                isRestrainedY: true,
                isRestrainedZ: true,
                elasticStiffness: SIMD3<Double>(Kspring, Kspring, Kspring)
            )
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: Fx, direction: SIMD3<Double>(1, 0, 0))
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        // Analytical root displacement: delta_root = F / K = 10000 / 1e7 = 0.001 m = 1.0 mm
        let analyticRootDispMm = (Fx / Kspring) * 1000.0 // 1.0 mm
        // Analytical tip displacement: delta_tip = delta_root + (F * L) / (E * A) = 1.0 mm + 0.02 mm = 1.02 mm
        let barStretchMm = ((Fx * L) / (E * A)) * 1000.0 // 0.02 mm
        let analyticTipDispMm = analyticRootDispMm + barStretchMm // 1.02 mm

        // Verify root displacement
        var sumRootX = 0.0
        for rId in rootIds {
            let d = try #require(result.nodalDisplacements[rId])
            sumRootX += d.x
            #expect(abs(d.y) < 0.01)
            #expect(abs(d.z) < 0.01)
        }
        let avgRootX = sumRootX / Double(rootIds.count)
        let rootError = abs(avgRootX - analyticRootDispMm) / analyticRootDispMm
        #expect(rootError < 0.01, "Elastic root displacement error \(rootError * 100)% exceeds 1% (computed \(avgRootX) mm vs analytic \(analyticRootDispMm) mm)")

        // Verify tip displacement
        var sumTipX = 0.0
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            sumTipX += d.x
            #expect(abs(d.y) < 0.01)
            #expect(abs(d.z) < 0.01)
        }
        let avgTipX = sumTipX / Double(tipIds.count)
        let tipError = abs(avgTipX - analyticTipDispMm) / analyticTipDispMm
        #expect(tipError < 0.01, "Elastic tip displacement error \(tipError * 100)% exceeds 1% (computed \(avgTipX) mm vs analytic \(analyticTipDispMm) mm)")
    }

    // MARK: - 8. Pinned Boundary Condition

    @Test func testPinnedBoundaryCondition() throws {
        let (mesh, rootIds, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 8, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Pinned Beam", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .pinned)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: 500.0, direction: SIMD3<Double>(0, -1, 0))
        ]

        let result = try LinearStaticSolver.solve(study: study, mesh: mesh)

        // Pinned root enforces Ux = Uy = Uz = 0
        for rId in rootIds {
            let d = try #require(result.nodalDisplacements[rId])
            #expect(abs(d.x) < 1e-6)
            #expect(abs(d.y) < 1e-6)
            #expect(abs(d.z) < 1e-6)
        }

        // Tip deflects downwards
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.y < -0.01)
        }
    }

    // MARK: - 9. Roller Slider Boundary Condition

    @Test func testRollerSliderBoundaryCondition() throws {
        let (mesh, rootIds, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 8, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Roller Slider Test", studyType: .linearStatic)
        // Root face allows Y and Z expansion but fixes axial X = 0
        study.fixtures = [
            SimulationFixture(
                name: "RootFace",
                kind: .rollerSlider,
                isRestrainedX: true,
                isRestrainedY: true,
                isRestrainedZ: true
            )
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: 5000.0, direction: SIMD3<Double>(1, 0, 0))
        ]

        let result = try LinearStaticSolver.solve(study: study, mesh: mesh)

        for rId in rootIds {
            let d = try #require(result.nodalDisplacements[rId])
            #expect(abs(d.x) < 1e-6)
        }
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.x > 0.005)
        }
    }

    // MARK: - 10. Symmetry Boundary Condition

    @Test func testSymmetryBoundaryCondition() throws {
        let (mesh, rootIds, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 8, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Symmetry Test", studyType: .linearStatic)
        // Symmetry condition on RootFace (normal = X, Ux = 0)
        // Combine with elastic lateral support to prevent rigid body motion in Y/Z
        study.fixtures = [
            SimulationFixture(
                name: "RootFace",
                kind: .symmetry,
                isRestrainedX: true,
                isRestrainedY: false,
                isRestrainedZ: false
            ),
            SimulationFixture(
                name: "RootFace",
                kind: .elasticSupport,
                isRestrainedX: false,
                isRestrainedY: true,
                isRestrainedZ: true,
                elasticStiffness: SIMD3<Double>(0, 1e7, 1e7)
            )
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: 5000.0, direction: SIMD3<Double>(1, 0, 0))
        ]

        let result = try LinearStaticSolver.solve(study: study, mesh: mesh)

        for rId in rootIds {
            let d = try #require(result.nodalDisplacements[rId])
            #expect(abs(d.x) < 1e-6)
        }
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.x > 0.001)
        }
    }

    // MARK: - 11. Mixed Elastic and Dirichlet Constraints

    @Test func testMixedElasticAndDirichletConstraints() throws {
        let (mesh, rootIds, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 8, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Mixed Constraints", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed),
            SimulationFixture(
                name: "TipFace",
                kind: .elasticSupport,
                isRestrainedX: false,
                isRestrainedY: true,
                isRestrainedZ: false,
                elasticStiffness: SIMD3<Double>(0, 1e5, 0)
            )
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]

        let result = try LinearStaticSolver.solve(study: study, mesh: mesh)

        for rId in rootIds {
            let d = try #require(result.nodalDisplacements[rId])
            #expect(abs(d.x) < 1e-6)
            #expect(abs(d.y) < 1e-6)
            #expect(abs(d.z) < 1e-6)
        }

        // Tip deflection is restrained by elastic foundation
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.y < 0.0)
        }
    }

    // MARK: - 12. Edge Cases and Error States

    @Test func testUnderConstrainedThrowsInvalidStudyConfiguration() {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))
        let el = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4])
        let singleNodeSet = VolumeMeshSet(name: "OneNode", nodeIds: [1], elementIds: [])
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [el], sets: [singleNodeSet])

        var study = SimulationStudy(name: "UnderConstrained", studyType: .linearStatic)
        // Only 1 node constrained in X, Y, Z -> 3 DOFs < 6 DOFs
        study.fixtures = [
            SimulationFixture(name: "OneNode", kind: .fixed)
        ]

        #expect(throws: CAEErrorCode.self) {
            try LinearStaticSolver.solve(study: study, mesh: mesh)
        }
    }

    @Test func testUnmappedTargetGeometryThrowsError() {
        let (mesh, _, _) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.1, height: 0.1, nx: 2, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Missing Target", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "NonExistentFace", kind: .fixed, groupNames: ["NonExistentFace"])
        ]

        #expect(throws: CAEErrorCode.self) {
            try LinearStaticSolver.solve(study: study, mesh: mesh)
        }
    }

    // MARK: - 13. BL-FEA-03 Structural Loads (#221)

    @Test func testForcePerUnitAreaDistribution() throws {
        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Traction Beam", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(
                name: "TipFace",
                kind: .force,
                magnitude: 400_000.0, // Pa (N/m²)
                direction: SIMD3<Double>(0, -1, 0),
                forceDistribution: .perUnitArea
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.3
        )

        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.y < 0.0) // Deflects downwards
        }
        #expect(result.iterationCount > 0)
    }

    @Test func testMomentCoupleTwistAndEquilibrium() throws {
        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Twisting Moment", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(
                name: "TipFace",
                kind: .moment,
                magnitude: 200.0, // N·m torque about X axis
                direction: SIMD3<Double>(1, 0, 0)
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.3
        )

        // Nodes on opposite sides of centroid should have opposite transverse displacements (torque couple)
        var posDisplacements = 0
        var negDisplacements = 0
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            if d.y > 1e-6 { posDisplacements += 1 }
            if d.y < -1e-6 { negDisplacements += 1 }
        }
        #expect(posDisplacements > 0)
        #expect(negDisplacements > 0)
        #expect(result.iterationCount > 0)
    }

    @Test func testRemoteLoadTransfer() throws {
        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Remote Load Beam", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        // Remote point at x=1.0, y=0.5 (offset +0.475m above tip centroid in Y), pushing downwards in Y
        study.loads = [
            SimulationLoad(
                name: "TipFace",
                kind: .remoteLoad,
                magnitude: 500.0,
                direction: SIMD3<Double>(0, -1, 0),
                remotePoint: SIMD3<Double>(1.0, 0.5, 0.025)
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.3
        )

        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.y < 0.0)
        }
        #expect(result.iterationCount > 0)
    }

    @Test func testBearingContactCompressiveLoad() throws {
        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Bearing Contact", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(
                name: "TipFace",
                kind: .bearing,
                magnitude: 1000.0,
                direction: SIMD3<Double>(1, 0, 0) // Tension/bearing along X
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.3
        )

        // The beam should extend in +X
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.x > 0.0)
        }
        #expect(result.iterationCount > 0)
    }

    @Test func testCentrifugalBodyAcceleration() throws {
        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Spinning Beam", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        // Spin about Z axis at origin with omega = 50 rad/s
        study.loads = [
            SimulationLoad(
                name: "Spin",
                kind: .centrifugal,
                magnitude: 50.0,
                direction: SIMD3<Double>(0, 0, 1),
                axisOrigin: SIMD3<Double>(0, 0, 0)
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.3
        )

        // Centrifugal body force accelerates outward in +X away from rotation axis
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(d.x > 0.0)
        }
        #expect(result.iterationCount > 0)
    }

    @Test func testThermalExpansionCantileverBeam() throws {
        let length = 1.0
        let (mesh, _, tipIds) = Self.makeBeamMeshC3D4(length: length, width: 0.05, height: 0.05, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Thermal Cantilever", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        let alpha = 1.2e-5 // 1/K
        let deltaT = 50.0  // °C
        study.loads = [
            SimulationLoad(
                name: "ThermalStep",
                kind: .thermalLoad,
                magnitude: 70.0,
                referenceTemperature: 20.0
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: 200e9,
            poissonsRatio: 0.0
        )

        // Expected free thermal expansion in X with nu=0: Delta L = alpha * Delta T * L
        let expectedDeltaL_mm = (alpha * deltaT * length) * 1000.0 // mm
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            #expect(abs(d.x - expectedDeltaL_mm) < 0.05 * expectedDeltaL_mm)
        }
        #expect(result.iterationCount > 0)
    }

    @Test func testDegenerateLoadsAndZeroDelta() throws {
        let (mesh, _, _) = Self.makeBeamMeshC3D4(length: 1.0, width: 0.05, height: 0.05, nx: 2, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Degenerate Edge Cases", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "RootFace", kind: .fixed)]
        study.loads = [
            // Thermal load with zero delta
            SimulationLoad(name: "ZeroDeltaThermal", kind: .thermalLoad, magnitude: 20.0, referenceTemperature: 20.0),
            // Centrifugal with zero omega
            SimulationLoad(name: "ZeroOmegaCentrif", kind: .centrifugal, magnitude: 0.0)
        ]

        let result = try LinearStaticSolver.solve(study: study, mesh: mesh, youngsModulus: 200e9, poissonsRatio: 0.3)
        for (_, disp) in result.nodalDisplacements {
            #expect(simd_length(disp) < 1e-6)
        }
    }

    // MARK: - 11. Multi-body Bonded Contact Verification (BL-FEA-04, #222)

    @Test func testMultiBodyBondedContactCantileverTension() throws {
        let L = 1.0 // 1.0 meter total
        let b = 0.05 // 50 mm
        let h = 0.05 // 50 mm
        let A = b * h // 0.0025 m²
        let E = 200e9 // 200 GPa
        let nu = 0.0 // Zero Poisson ratio for pure uniaxial strain
        let Fx = 1000.0 // 1000 N tensile force

        let (mesh, _, tipIds, b1Interface, b2Interface) = Self.makeTwoBlockTouchingMeshC3D4(
            totalLength: L,
            splitX: 0.5,
            width: b,
            height: h,
            nx1: 10,
            nx2: 10,
            ny: 2,
            nz: 2
        )

        var study = SimulationStudy(name: "Bonded Two-Block Tension", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: Fx, direction: SIMD3<Double>(1, 0, 0))
        ]
        study.connections = [
            SimulationConnection(
                name: "InterfaceBond",
                kind: .bonded,
                sourceReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Block1Interface")],
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Block2Interface")],
                stiffness: 1e11
            )
        ]

        let result = try LinearStaticSolver.solve(
            study: study,
            mesh: mesh,
            youngsModulus: E,
            poissonsRatio: nu
        )

        // Analytical elongation deltaL = F * L / (E * A) in mm
        let analyticDeltaLMm = ((Fx * L) / (E * A)) * 1000.0

        // 1. Tip displacement matches analytical extension within 2% error
        for tId in tipIds {
            let d = try #require(result.nodalDisplacements[tId])
            let errDisp = abs(d.x - analyticDeltaLMm) / analyticDeltaLMm
            #expect(errDisp < 0.02, "Axial displacement error \(errDisp * 100)% exceeds 2%")
            #expect(abs(d.y) < 1e-4)
            #expect(abs(d.z) < 1e-4)
        }

        // 2. Relative displacement between paired interface nodes is negligible (< 1e-4 mm)
        let pairs = MeshGeometryAssociator.findBondedNodePairs(
            sourceNodeIds: Array(b1Interface),
            targetNodeIds: Array(b2Interface),
            mesh: mesh
        )
        #expect(!pairs.isEmpty)
        for pair in pairs {
            let dS = try #require(result.nodalDisplacements[pair.sourceNodeId])
            let dT = try #require(result.nodalDisplacements[pair.targetNodeId])
            let relativeDisp = simd_length(dS - dT)
            #expect(relativeDisp < 1e-4, "Relative separation at interface node pair exceeds 1e-4 mm: \(relativeDisp)")
        }
    }

    @Test func testDisjointBodiesOutsideToleranceThrowsError() throws {
        let (mesh, _, _, _, _) = Self.makeTwoBlockTouchingMeshC3D4(
            totalLength: 1.0,
            splitX: 0.5,
            width: 0.05,
            height: 0.05,
            gap: 0.1 // 100 mm gap between blocks
        )

        var study = SimulationStudy(name: "Disjoint Blocks", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "RootFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "TipFace", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(1, 0, 0))
        ]
        study.connections = [
            SimulationConnection(
                name: "InterfaceBond",
                kind: .bonded,
                sourceReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Block1Interface")],
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Block2Interface")],
                searchTolerance: 0.001 // 1 mm tolerance, but gap is 100 mm
            )
        ]

        #expect(throws: CAEErrorCode.self) {
            try LinearStaticSolver.solve(
                study: study,
                mesh: mesh,
                youngsModulus: 200e9,
                poissonsRatio: 0.0
            )
        }
    }
}
