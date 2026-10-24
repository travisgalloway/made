import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ThermalConductionSolverTests {

    // MARK: - Mesh Generation Fixture

    /// Generates a structured hexahedral box decomposed into linear C3D4 tetrahedra with named boundary surface sets.
    static func makeSlabMesh(
        length: Double = 0.1,
        width: Double = 0.02,
        height: Double = 0.02,
        nx: Int = 10,
        ny: Int = 2,
        nz: Int = 2
    ) -> VolumeMesh {
        var nodes: [VolumeMeshNode] = []
        var nodeMap = [SIMD3<Int>: Int]()

        let dx = length / Double(nx)
        let dy = width / Double(ny)
        let dz = height / Double(nz)

        var nodeId = 1
        for i in 0...nx {
            for j in 0...ny {
                for k in 0...nz {
                    let pos = SIMD3<Double>(Double(i) * dx, Double(j) * dy, Double(k) * dz)
                    nodes.append(VolumeMeshNode(id: nodeId, position: pos))
                    nodeMap[SIMD3<Int>(i, j, k)] = nodeId
                    nodeId += 1
                }
            }
        }

        var elements: [VolumeMeshElement] = []
        var surfaceTriangles: [VolumeMeshElement] = []
        var elId = 1
        var triId = 10000

        var xMinTriIds: [Int] = []
        var xMaxTriIds: [Int] = []
        var xMinNodeIds = Set<Int>()
        var xMaxNodeIds = Set<Int>()

        // 6-tetrahedron Kuhn decomposition per hexahedral cell
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
                        [n000, n100, n101, n111],
                        [n000, n010, n110, n111],
                        [n000, n010, n011, n111],
                        [n000, n001, n101, n111],
                        [n000, n001, n011, n111]
                    ]

                    for conn in tets {
                        elements.append(VolumeMeshElement(id: elId, order: .linear, nodeIndices: conn))
                        elId += 1
                    }

                    // Boundary surface triangles at x = 0 (XMin)
                    if i == 0 {
                        let t1 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n000, n010, n011])
                        triId += 1
                        let t2 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n000, n011, n001])
                        triId += 1
                        surfaceTriangles.append(contentsOf: [t1, t2])
                        xMinTriIds.append(contentsOf: [t1.id, t2.id])
                        xMinNodeIds.formUnion([n000, n010, n011, n001])
                    }

                    // Boundary surface triangles at x = L (XMax)
                    if i == nx - 1 {
                        let t1 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n100, n110, n111])
                        triId += 1
                        let t2 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n100, n111, n101])
                        triId += 1
                        surfaceTriangles.append(contentsOf: [t1, t2])
                        xMaxTriIds.append(contentsOf: [t1.id, t2.id])
                        xMaxNodeIds.formUnion([n100, n110, n111, n101])
                    }
                }
            }
        }

        let sets: [VolumeMeshSet] = [
            VolumeMeshSet(name: "Face_XMin", nodeIds: xMinNodeIds.sorted(), elementIds: xMinTriIds, subelementType: .face),
            VolumeMeshSet(name: "Face_XMax", nodeIds: xMaxNodeIds.sorted(), elementIds: xMaxTriIds, subelementType: .face)
        ]

        let stats = SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count)
        return VolumeMesh(nodes: nodes, elements: elements, surfaceTriangles: surfaceTriangles, statistics: stats, sets: sets)
    }

    // MARK: - Analytic Verification Case 1: Two Fixed Temperatures

    @Test func testTwoFixedTemperaturesAnalyticVerification() throws {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Two Temps", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(
                name: "T_Min",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                magnitude: 100.0
            ),
            SimulationLoad(
                name: "T_Max",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                magnitude: 20.0
            )
        ]

        let result = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 50.0)

        // Verify temperature at all nodes matches T(x) = 100 - 800 * x within 0.1 °C (< 0.1% error)
        for node in mesh.nodes {
            let x = node.position.x
            let analyticT = 100.0 - 800.0 * x
            let numT = try #require(result.nodalTemperatures[node.id])
            #expect(abs(numT - analyticT) < 0.1, "Node at x=\(x): num=\(numT), analytic=\(analyticT)")
        }

        // Verify heat flux matches q_x = 40000 W/m² within 1%
        for (_, flux) in result.elementHeatFluxes {
            #expect(abs(flux.x - 40000.0) < 400.0, "Flux x=\(flux.x) expected 40000")
            #expect(abs(flux.y) < 1.0, "Flux y=\(flux.y) expected ~0")
            #expect(abs(flux.z) < 1.0, "Flux z=\(flux.z) expected ~0")
        }

        // Verify extrema
        let tempExtrema = try #require(result.extrema.first { $0.fieldName == "Temperature" })
        #expect(abs(tempExtrema.minValue - 20.0) < 0.1)
        #expect(abs(tempExtrema.maxValue - 100.0) < 0.1)

        let fluxExtrema = try #require(result.extrema.first { $0.fieldName == "Heat Flux" })
        #expect(abs(fluxExtrema.minValue - 40000.0) < 500.0)
        #expect(abs(fluxExtrema.maxValue - 40000.0) < 500.0)
    }

    // MARK: - Analytic Verification Case 2: Fixed Temperature + Convection

    @Test func testFixedTemperatureAndConvectionAnalyticVerification() throws {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Convection", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(
                name: "T_Min",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                magnitude: 100.0
            ),
            SimulationLoad(
                name: "Conv_Max",
                kind: .convection,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                magnitude: 100.0,
                ambientTemperature: 20.0
            )
        ]

        let result = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 50.0)

        // Analytic solution: T(L) = (T_0 + (h*L/k)*T_inf) / (1 + h*L/k)
        // h*L/k = (100 * 0.1) / 50 = 0.2
        // T(L) = (100 + 0.2 * 20) / (1 + 0.2) = 104 / 1.2 = 86.6667 °C
        let analyticTL = 86.666667

        let xMaxNodes = mesh.nodes.filter { abs($0.position.x - 0.1) < 1e-6 }
        #expect(!xMaxNodes.isEmpty)

        for node in xMaxNodes {
            let numT = try #require(result.nodalTemperatures[node.id])
            let relativeError = abs(numT - analyticTL) / analyticTL
            #expect(relativeError < 0.01, "T(L)=\(numT), expected \(analyticTL), relative error=\(relativeError)")
        }
    }

    // MARK: - Analytic Verification Case 3: Fixed Temperature + Surface Heat Flux

    @Test func testFixedTemperatureAndSurfaceHeatFluxAnalyticVerification() throws {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Flux", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(
                name: "Flux_Min",
                kind: .thermalFlux,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                magnitude: 1000.0
            ),
            SimulationLoad(
                name: "T_Max",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                magnitude: 20.0
            )
        ]

        let result = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 50.0)

        // Analytic solution: T(0) = T_L + (q * L) / k = 20.0 + (1000 * 0.1) / 50 = 22.0 °C
        let analyticT0 = 22.0

        let xMinNodes = mesh.nodes.filter { abs($0.position.x) < 1e-6 }
        #expect(!xMinNodes.isEmpty)

        for node in xMinNodes {
            let numT = try #require(result.nodalTemperatures[node.id])
            #expect(abs(numT - analyticT0) < 0.1, "T(0)=\(numT), expected \(analyticT0)")
        }
    }

    // MARK: - Analytic Verification Case 4: Fixed Temperature + Heat Power

    @Test func testFixedTemperatureAndHeatPowerAnalyticVerification() throws {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Power", studyType: .thermalConduction)
        study.loads = [
            // Face area A = 0.02 * 0.02 = 0.0004 m², Q = 4.0 W => q = 4.0 / 0.0004 = 10000 W/m²
            SimulationLoad(
                name: "Power_Min",
                kind: .heatPower,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                magnitude: 4.0
            ),
            SimulationLoad(
                name: "T_Max",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                magnitude: 20.0
            )
        ]

        let result = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 50.0)

        // Analytic solution: T(0) = 20 + (10000 * 0.1) / 50 = 40.0 °C
        let analyticT0 = 40.0

        let xMinNodes = mesh.nodes.filter { abs($0.position.x) < 1e-6 }
        #expect(!xMinNodes.isEmpty)

        for node in xMinNodes {
            let numT = try #require(result.nodalTemperatures[node.id])
            #expect(abs(numT - analyticT0) < 0.1, "T(0)=\(numT), expected \(analyticT0)")
        }
    }

    // MARK: - Case 5: Insulated Lateral Surfaces Zero Normal Heat Flux

    @Test func testInsulatedLateralSurfacesZeroHeatFlux() throws {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Insulated", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(
                name: "T_Min",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                magnitude: 100.0
            ),
            SimulationLoad(
                name: "T_Max",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                magnitude: 20.0
            )
        ]

        let result = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 50.0)

        for (_, flux) in result.elementHeatFluxes {
            #expect(abs(flux.y) < 0.1, "Lateral flux q_y should be zero, got \(flux.y)")
            #expect(abs(flux.z) < 0.1, "Lateral flux q_z should be zero, got \(flux.z)")
        }
    }

    // MARK: - Case 6: Conductivity Scaling

    @Test func testMaterialConductivityScaling() throws {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 10, ny: 2, nz: 2)
        var study = SimulationStudy(name: "Conductivity Scaling", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(
                name: "Flux_Min",
                kind: .thermalFlux,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                magnitude: 1000.0
            ),
            SimulationLoad(
                name: "T_Max",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                magnitude: 20.0
            )
        ]

        let res50 = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 50.0)
        let res100 = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: 100.0)

        let xMinNodes = mesh.nodes.filter { abs($0.position.x) < 1e-6 }
        let n0Id = try #require(xMinNodes.first?.id)

        let t50 = try #require(res50.nodalTemperatures[n0Id])
        let t100 = try #require(res100.nodalTemperatures[n0Id])

        // Delta T with k=50 is 2.0 °C (T0 = 22.0)
        // Delta T with k=100 is 1.0 °C (T0 = 21.0)
        #expect(abs(t50 - 22.0) < 0.1)
        #expect(abs(t100 - 21.0) < 0.1)
        #expect(abs((t50 - 20.0) - 2.0 * (t100 - 20.0)) < 0.05)
    }

    // MARK: - Case 7: Unconstrained Problem Throws Typed Error

    @Test func testUnconstrainedThermalSystemThrowsTypedError() {
        let mesh = Self.makeSlabMesh(length: 0.1, width: 0.02, height: 0.02, nx: 5, ny: 1, nz: 1)
        var study = SimulationStudy(name: "Unconstrained", studyType: .thermalConduction)
        // Only heat flux, no temperature or convection
        study.loads = [
            SimulationLoad(name: "Face_XMin", kind: .thermalFlux, magnitude: 500.0)
        ]

        #expect(throws: CAEErrorCode.self) {
            _ = try ThermalConductionSolver.solve(study: study, mesh: mesh)
        }
    }

    // MARK: - Case 8: Quadratic C3D10 Element Conduction

    @Test func testQuadraticC3D10ElementConduction() throws {
        // Single C3D10 tetrahedron with vertices at (0,0,0), (1,0,0), (0,1,0), (0,0,1)
        let v0 = SIMD3<Double>(0, 0, 0)
        let v1 = SIMD3<Double>(1, 0, 0)
        let v2 = SIMD3<Double>(0, 1, 0)
        let v3 = SIMD3<Double>(0, 0, 1)

        let m01 = (v0 + v1) * 0.5
        let m12 = (v1 + v2) * 0.5
        let m20 = (v2 + v0) * 0.5
        let m03 = (v0 + v3) * 0.5
        let m13 = (v1 + v3) * 0.5
        let m23 = (v2 + v3) * 0.5

        let positions = [v0, v1, v2, v3, m01, m12, m20, m03, m13, m23]
        var nodes: [VolumeMeshNode] = []
        for (i, p) in positions.enumerated() {
            nodes.append(VolumeMeshNode(id: i + 1, position: p))
        }

        let element = VolumeMeshElement(id: 1, order: .quadratic, nodeIndices: Array(1...10))
        let mesh = VolumeMesh(
            nodes: nodes,
            elements: [element],
            statistics: SimulationMeshStatistics(nodeCount: 10, elementCount: 1)
        )

        // Prescribe linear temperature T(x) = 100 - 80 * x on all boundary nodes
        var study = SimulationStudy(name: "C3D10", studyType: .thermalConduction)
        for node in nodes {
            let t = 100.0 - 80.0 * node.position.x
            study.loads.append(SimulationLoad(
                name: "Node_\(node.id)",
                kind: .temperature,
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Node_\(node.id)")],
                magnitude: t
            ))
        }

        // Create sets matching each load
        var sets: [VolumeMeshSet] = []
        for node in nodes {
            sets.append(VolumeMeshSet(name: "Node_\(node.id)", nodeIds: [node.id], elementIds: []))
        }
        var meshWithSets = mesh
        meshWithSets.sets = sets

        let result = try ThermalConductionSolver.solve(study: study, mesh: meshWithSets, materialConductivity: 50.0)

        for node in nodes {
            let expectedT = 100.0 - 80.0 * node.position.x
            let numT = try #require(result.nodalTemperatures[node.id])
            #expect(abs(numT - expectedT) < 1e-4)
        }

        let flux = try #require(result.elementHeatFluxes[1])
        // q = -k * grad(T) = -50 * (-80, 0, 0) = (4000, 0, 0)
        #expect(abs(flux.x - 4000.0) < 1.0)
        #expect(abs(flux.y) < 1.0)
        #expect(abs(flux.z) < 1.0)
    }
}
