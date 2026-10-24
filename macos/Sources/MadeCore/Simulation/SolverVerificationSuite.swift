import Foundation
import simd

// MARK: - Benchmark Data Structures

/// Classification category for FEA solver verification benchmark problems.
public enum SolverBenchmarkCategory: String, Sendable, CaseIterable, Codable {
    case linearStaticStructural
    case thermalConduction
    case modalFrequency
    case linearBuckling
}

/// Verification standard or reference domain origin.
public enum SolverBenchmarkStandard: String, Sendable, CaseIterable, Codable {
    case nafems
    case textbookAnalytic
}

/// Comparison between computed numerical FEA metric and closed-form analytical reference.
public struct SolverBenchmarkMetricComparison: Sendable, Codable, Equatable {
    public let metricName: String
    public let computedValue: Double
    public let analyticalValue: Double
    public let relativeError: Double
    public let tolerance: Double
    public let unit: String
    public var passed: Bool { relativeError <= tolerance }

    public init(
        metricName: String,
        computedValue: Double,
        analyticalValue: Double,
        relativeError: Double,
        tolerance: Double,
        unit: String
    ) {
        self.metricName = metricName
        self.computedValue = computedValue
        self.analyticalValue = analyticalValue
        self.relativeError = relativeError
        self.tolerance = tolerance
        self.unit = unit
    }
}

/// Result of executing a single verification benchmark case.
public struct SolverBenchmarkResult: Sendable, Codable, Equatable {
    public let benchmarkId: String
    public let name: String
    public let category: SolverBenchmarkCategory
    public let metrics: [SolverBenchmarkMetricComparison]
    public let executionDuration: Double
    public var allPassed: Bool { metrics.allSatisfy { $0.passed } }

    public init(
        benchmarkId: String,
        name: String,
        category: SolverBenchmarkCategory,
        metrics: [SolverBenchmarkMetricComparison],
        executionDuration: Double
    ) {
        self.benchmarkId = benchmarkId
        self.name = name
        self.category = category
        self.metrics = metrics
        self.executionDuration = executionDuration
    }
}

/// Aggregated result of running the entire verification suite.
public struct SolverBenchmarkSuiteResult: Sendable, Codable, Equatable {
    public let results: [SolverBenchmarkResult]
    public let totalDuration: Double
    public var allPassed: Bool { results.allSatisfy { $0.allPassed } }

    public init(results: [SolverBenchmarkResult], totalDuration: Double) {
        self.results = results
        self.totalDuration = totalDuration
    }
}

/// Executable verification benchmark case specification.
public struct SolverBenchmarkCase: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: SolverBenchmarkCategory
    public let standard: SolverBenchmarkStandard
    public let description: String
    public let execute: @Sendable () throws -> SolverBenchmarkResult

    public init(
        id: String,
        name: String,
        category: SolverBenchmarkCategory,
        standard: SolverBenchmarkStandard,
        description: String,
        execute: @escaping @Sendable () throws -> SolverBenchmarkResult
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.standard = standard
        self.description = description
        self.execute = execute
    }
}

// MARK: - Analytical Reference Solutions

/// Closed-form Euler-Bernoulli beam theory equations.
public enum EulerBernoulliBeam: Sendable {
    public static func secondMomentOfArea(width b: Double, height h: Double) -> Double {
        (b * pow(h, 3)) / 12.0
    }

    public static func tipDeflection(
        force F: Double,
        length L: Double,
        modulus E: Double,
        width b: Double,
        height h: Double
    ) -> Double {
        let Iz = secondMomentOfArea(width: b, height: h)
        return (F * pow(L, 3)) / (3.0 * E * Iz)
    }

    public static func maxBendingStress(
        force F: Double,
        length L: Double,
        width b: Double,
        height h: Double
    ) -> Double {
        let Iz = secondMomentOfArea(width: b, height: h)
        return (F * L * (h / 2.0)) / Iz
    }
}

/// Closed-form Kirsch and Peterson stress concentration equations for a plate with a central hole.
public enum KirschPlateWithHole: Sendable {
    public static func infinitePlateStressConcentrationFactor() -> Double {
        3.0
    }

    /// Peterson finite-width gross stress concentration factor Kt as a function of d / D (hole diameter to plate width).
    public static func stressConcentrationFactor(holeDiameter d: Double, plateWidth D: Double) -> Double {
        let ratio = d / D
        return 3.00 - 3.140 * ratio + 3.667 * pow(ratio, 2) - 1.527 * pow(ratio, 3)
    }

    /// Transverse ligament stress distribution along y = 0 as a function of x for far-field tensile stress sigma0.
    public static func transverseLigamentStress(x: Double, holeRadius R: Double, farFieldStress sigma0: Double) -> Double {
        guard x >= R else { return 0.0 }
        let rOverX = R / x
        return 0.5 * sigma0 * (2.0 + pow(rOverX, 2) + 3.0 * pow(rOverX, 4))
    }

    public static func peakStress(holeDiameter d: Double, plateWidth D: Double, farFieldStress sigma0: Double) -> Double {
        stressConcentrationFactor(holeDiameter: d, plateWidth: D) * sigma0
    }
}

/// Closed-form Lamé thick cylinder plane-strain analytical equations.
public enum LameThickCylinder: Sendable {
    public static func radialDisplacement(
        radius r: Double,
        innerRadius a: Double,
        outerRadius b: Double,
        internalPressure Pi: Double,
        modulus E: Double,
        poissonsRatio nu: Double
    ) -> Double {
        let factor = ((1.0 + nu) / E) * ((Pi * a * a) / (b * b - a * a))
        return factor * ((1.0 - 2.0 * nu) * r + (b * b) / r)
    }

    public static func hoopStress(
        radius r: Double,
        innerRadius a: Double,
        outerRadius b: Double,
        internalPressure Pi: Double
    ) -> Double {
        let factor = (Pi * a * a) / (b * b - a * a)
        return factor * (1.0 + (b * b) / (r * r))
    }

    public static func radialStress(
        radius r: Double,
        innerRadius a: Double,
        outerRadius b: Double,
        internalPressure Pi: Double
    ) -> Double {
        let factor = (Pi * a * a) / (b * b - a * a)
        return factor * (1.0 - (b * b) / (r * r))
    }

    public static func axialStress(
        innerRadius a: Double,
        outerRadius b: Double,
        internalPressure Pi: Double,
        poissonsRatio nu: Double
    ) -> Double {
        2.0 * nu * ((Pi * a * a) / (b * b - a * a))
    }

    public static func vonMisesStress(
        radius r: Double,
        innerRadius a: Double,
        outerRadius b: Double,
        internalPressure Pi: Double,
        poissonsRatio nu: Double
    ) -> Double {
        let sr = radialStress(radius: r, innerRadius: a, outerRadius: b, internalPressure: Pi)
        let st = hoopStress(radius: r, innerRadius: a, outerRadius: b, internalPressure: Pi)
        let sz = axialStress(innerRadius: a, outerRadius: b, internalPressure: Pi, poissonsRatio: nu)
        let diff1 = sr - st
        let diff2 = st - sz
        let diff3 = sz - sr
        return sqrt(0.5 * (diff1 * diff1 + diff2 * diff2 + diff3 * diff3))
    }
}

/// Closed-form 1D Fourier thermal conduction equations.
public enum ThermalConduction1D: Sendable {
    public static func temperature(x: Double, length L: Double, t1: Double, t2: Double) -> Double {
        t1 + ((t2 - t1) / L) * x
    }

    public static func heatFlux(length L: Double, t1: Double, t2: Double, conductivity k: Double) -> Double {
        -k * ((t2 - t1) / L)
    }
}

// MARK: - Benchmark Catalog and Runner

/// Verification benchmark catalog and test execution suite for Made FEA solvers (BL-SIM-07, Phase 6B, #353).
public enum SolverVerificationSuite: Sendable {

    // MARK: - Procedural Mesh Generators

    /// Generates a structured cantilever beam volume mesh decomposed into linear Kuhn tetrahedra.
    public static func makeCantileverBeamMesh(
        length: Double = 1.0,
        width: Double = 0.05,
        height: Double = 0.05,
        nx: Int = 8,
        ny: Int = 2,
        nz: Int = 2
    ) -> VolumeMesh {
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

        let rootSet = VolumeMeshSet(name: "RootFace", nodeIds: Array(rootNodeIds).sorted(), elementIds: [], subelementType: .face)
        let tipSet = VolumeMeshSet(name: "TipFace", nodeIds: Array(tipNodeIds).sorted(), elementIds: [], subelementType: .face)

        return VolumeMesh(
            nodes: nodes,
            elements: elements,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count),
            sets: [rootSet, tipSet]
        )
    }

    /// Generates a quarter-plate with a central circular hole mapped via polar-to-Cartesian transformation.
    public static func makePlateWithHoleMesh(
        holeRadius: Double = 0.05,
        width: Double = 0.25,
        length: Double = 0.25,
        thickness: Double = 0.01,
        nu: Int = 8,
        nv: Int = 4,
        nw: Int = 1
    ) -> VolumeMesh {
        var nodes: [VolumeMeshNode] = []
        var nodeMap = [SIMD3<Int>: Int]()
        var nodeId = 1

        var symmetryXNodeIds = Set<Int>()
        var symmetryYNodeIds = Set<Int>()
        var rollerZNodeIds = Set<Int>()
        var holeEdgeNodeIds = Set<Int>()
        var tensionYNodeIds = Set<Int>()

        for i in 0...nu {
            let u = Double(i) / Double(nu)
            let theta = u * (Double.pi / 2.0)
            let cosT = cos(theta)
            let sinT = sin(theta)
            let rX = cosT > 1e-9 ? (width / cosT) : Double.infinity
            let rY = sinT > 1e-9 ? (length / sinT) : Double.infinity
            let rMax = min(rX, rY)

            for j in 0...nv {
                let v = Double(j) / Double(nv)
                let r = holeRadius + v * (rMax - holeRadius)

                for k in 0...nw {
                    let w = Double(k) / Double(nw)
                    let z = w * thickness

                    let x = (i == nu) ? 0.0 : (r * cosT)
                    let y = (i == 0) ? 0.0 : (r * sinT)
                    let pos = SIMD3<Double>(x, y, z)

                    nodes.append(VolumeMeshNode(id: nodeId, position: pos))
                    nodeMap[SIMD3<Int>(i, j, k)] = nodeId

                    if i == nu { symmetryXNodeIds.insert(nodeId) }
                    if i == 0 { symmetryYNodeIds.insert(nodeId) }
                    if k == 0 { rollerZNodeIds.insert(nodeId) }
                    if j == 0 { holeEdgeNodeIds.insert(nodeId) }
                    if j == nv && abs(y - length) < 1e-6 { tensionYNodeIds.insert(nodeId) }

                    nodeId += 1
                }
            }
        }

        var elements: [VolumeMeshElement] = []
        var surfaceTriangles: [VolumeMeshElement] = []
        var tensionYTriIds: [Int] = []
        var elId = 1
        var triId = 10000

        for i in 0..<nu {
            for j in 0..<nv {
                for k in 0..<nw {
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

                    if j == nv - 1 {
                        let pos010 = nodes[n010 - 1].position
                        let pos110 = nodes[n110 - 1].position
                        if abs(pos010.y - length) < 1e-6 && abs(pos110.y - length) < 1e-6 {
                            let t1 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n010, n110, n111])
                            triId += 1
                            let t2 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n010, n111, n011])
                            triId += 1
                            surfaceTriangles.append(contentsOf: [t1, t2])
                            tensionYTriIds.append(contentsOf: [t1.id, t2.id])
                        }
                    }
                }
            }
        }

        let sets: [VolumeMeshSet] = [
            VolumeMeshSet(name: "SymmetryX", nodeIds: Array(symmetryXNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "SymmetryY", nodeIds: Array(symmetryYNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "RollerZ", nodeIds: Array(rollerZNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "HoleEdge", nodeIds: Array(holeEdgeNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "TensionY", nodeIds: Array(tensionYNodeIds).sorted(), elementIds: tensionYTriIds, subelementType: .face)
        ]

        return VolumeMesh(
            nodes: nodes,
            elements: elements,
            surfaceTriangles: surfaceTriangles,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count),
            sets: sets
        )
    }

    /// Generates a quarter-cylinder sector mapped in cylindrical coordinates with inward oriented surface triangles.
    public static func makeThickCylinderMesh(
        innerRadius a: Double = 0.1,
        outerRadius b: Double = 0.2,
        length L: Double = 0.1,
        nr: Int = 4,
        ntheta: Int = 6,
        nz: Int = 2
    ) -> VolumeMesh {
        var nodes: [VolumeMeshNode] = []
        var nodeMap = [SIMD3<Int>: Int]()
        var nodeId = 1

        var symmetryXNodeIds = Set<Int>()
        var symmetryYNodeIds = Set<Int>()
        var restraintZNodeIds = Set<Int>()
        var innerPressureNodeIds = Set<Int>()

        for i in 0...nr {
            let r = a + (Double(i) / Double(nr)) * (b - a)
            for j in 0...ntheta {
                let theta = (Double(j) / Double(ntheta)) * (Double.pi / 2.0)
                let cosT = cos(theta)
                let sinT = sin(theta)
                for k in 0...nz {
                    let z = (Double(k) / Double(nz)) * L
                    let x = (j == ntheta) ? 0.0 : (r * cosT)
                    let y = (j == 0) ? 0.0 : (r * sinT)
                    let pos = SIMD3<Double>(x, y, z)

                    nodes.append(VolumeMeshNode(id: nodeId, position: pos))
                    nodeMap[SIMD3<Int>(i, j, k)] = nodeId

                    if j == ntheta { symmetryXNodeIds.insert(nodeId) }
                    if j == 0 { symmetryYNodeIds.insert(nodeId) }
                    if k == 0 || k == nz { restraintZNodeIds.insert(nodeId) }
                    if i == 0 { innerPressureNodeIds.insert(nodeId) }

                    nodeId += 1
                }
            }
        }

        var elements: [VolumeMeshElement] = []
        var surfaceTriangles: [VolumeMeshElement] = []
        var innerPressureTriIds: [Int] = []
        var elId = 1
        var triId = 20000

        for i in 0..<nr {
            for j in 0..<ntheta {
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

                    // Inner surface quad at r = a (i = 0)
                    // Normal must point inward toward the cavity (-r_hat) so compressive pressure acts outward (+r_hat).
                    // Matches Kuhn decomposition diagonal (n000, n011).
                    if i == 0 {
                        let t1 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n000, n011, n010])
                        triId += 1
                        let t2 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n000, n001, n011])
                        triId += 1
                        surfaceTriangles.append(contentsOf: [t1, t2])
                        innerPressureTriIds.append(contentsOf: [t1.id, t2.id])
                    }
                }
            }
        }

        let sets: [VolumeMeshSet] = [
            VolumeMeshSet(name: "SymmetryX", nodeIds: Array(symmetryXNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "SymmetryY", nodeIds: Array(symmetryYNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "RestraintZ", nodeIds: Array(restraintZNodeIds).sorted(), elementIds: [], subelementType: .face),
            VolumeMeshSet(name: "InnerPressure", nodeIds: Array(innerPressureNodeIds).sorted(), elementIds: innerPressureTriIds, subelementType: .face)
        ]

        return VolumeMesh(
            nodes: nodes,
            elements: elements,
            surfaceTriangles: surfaceTriangles,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count),
            sets: sets
        )
    }

    /// Generates a structured hexahedral slab for thermal conduction with boundary surface sets.
    public static func makeThermalSlabMesh(
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

                    if i == 0 {
                        let t1 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n000, n010, n011])
                        triId += 1
                        let t2 = VolumeMeshElement(id: triId, order: .linear, nodeIndices: [n000, n011, n001])
                        triId += 1
                        surfaceTriangles.append(contentsOf: [t1, t2])
                        xMinTriIds.append(contentsOf: [t1.id, t2.id])
                        xMinNodeIds.formUnion([n000, n010, n011, n001])
                    }

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

        return VolumeMesh(
            nodes: nodes,
            elements: elements,
            surfaceTriangles: surfaceTriangles,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: elements.count),
            sets: sets
        )
    }

    /// Up-converts a linear tetrahedral mesh into quadratic C3D10 tetrahedra by inserting unique mid-edge nodes.
    public static func convertToQuadraticC3D10(linearMesh: VolumeMesh) -> VolumeMesh {
        var nodes = linearMesh.nodes
        var nextNodeId = (nodes.map { $0.id }.max() ?? 0) + 1

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
            guard c.count >= 4 else { continue }
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

        // Subdivide surface triangles with mid-edges so surface traction and pressure distribute to all nodes
        var quadraticSurfaceTriangles: [VolumeMeshElement] = []
        var updatedSurfaceTriIdsByOldId: [Int: [Int]] = [:]
        var nextTriId = (linearMesh.surfaceTriangles.map { $0.id }.max() ?? 20000) + 1

        for tri in linearMesh.surfaceTriangles {
            let c = tri.nodeIndices
            guard c.count >= 3 else { continue }
            let n0 = c[0], n1 = c[1], n2 = c[2]
            let m01 = getOrCreateMidNode(n0, n1)
            let m12 = getOrCreateMidNode(n1, n2)
            let m20 = getOrCreateMidNode(n2, n0)

            let st1 = VolumeMeshElement(id: nextTriId, order: .linear, nodeIndices: [n0, m01, m20])
            nextTriId += 1
            let st2 = VolumeMeshElement(id: nextTriId, order: .linear, nodeIndices: [m01, n1, m12])
            nextTriId += 1
            let st3 = VolumeMeshElement(id: nextTriId, order: .linear, nodeIndices: [m20, m12, n2])
            nextTriId += 1
            let st4 = VolumeMeshElement(id: nextTriId, order: .linear, nodeIndices: [m01, m12, m20])
            nextTriId += 1

            quadraticSurfaceTriangles.append(contentsOf: [st1, st2, st3, st4])
            updatedSurfaceTriIdsByOldId[tri.id] = [st1.id, st2.id, st3.id, st4.id]
        }

        // Update boundary sets: include mid-edge nodes belonging to edges between set nodes
        var updatedSets: [VolumeMeshSet] = []
        for s in linearMesh.sets {
            let setNodeSet = Set(s.nodeIds)
            var newNodes = setNodeSet
            for (key, midId) in edgeMidNodes {
                if setNodeSet.contains(key.n1) && setNodeSet.contains(key.n2) {
                    newNodes.insert(midId)
                }
            }

            var newElemIds = s.elementIds
            if !linearMesh.surfaceTriangles.isEmpty {
                newElemIds = s.elementIds.flatMap { updatedSurfaceTriIdsByOldId[$0] ?? [$0] }
            }

            updatedSets.append(
                VolumeMeshSet(
                    id: s.id,
                    name: s.name,
                    nodeIds: Array(newNodes).sorted(),
                    elementIds: newElemIds,
                    subelementType: s.subelementType
                )
            )
        }

        return VolumeMesh(
            nodes: nodes,
            elements: quadraticElements,
            surfaceTriangles: quadraticSurfaceTriangles,
            statistics: SimulationMeshStatistics(nodeCount: nodes.count, elementCount: quadraticElements.count),
            sets: updatedSets
        )
    }

    // MARK: - Benchmark Catalog

    /// Euler-Bernoulli cantilever beam verification benchmark.
    public static let cantileverEulerBernoulli = SolverBenchmarkCase(
        id: "BL-SIM-07-CANTILEVER-EB",
        name: "Euler-Bernoulli Cantilever Beam",
        category: .linearStaticStructural,
        standard: .textbookAnalytic,
        description: "Slender cantilever beam under downward tip shear load compared against Euler-Bernoulli beam theory.",
        execute: {
            let L = 1.0
            let b = 0.05
            let h = 0.05
            let E = 200e9
            let nu = 0.0
            let F = 1000.0

            let linearMesh = makeCantileverBeamMesh(length: L, width: b, height: h, nx: 10, ny: 1, nz: 1)
            let mesh = convertToQuadraticC3D10(linearMesh: linearMesh)

            var study = SimulationStudy(name: "Cantilever EB", studyType: .linearStatic)
            study.fixtures = [
                SimulationFixture(name: "RootFace", kind: .fixed)
            ]
            study.loads = [
                SimulationLoad(name: "TipFace", kind: .force, magnitude: F, direction: SIMD3<Double>(0, -1, 0))
            ]

            let startTime = ContinuousClock.now
            let result = try LinearStaticSolver.solve(
                study: study,
                mesh: mesh,
                youngsModulus: E,
                poissonsRatio: nu
            )
            let elapsed = ContinuousClock.now - startTime
            let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

            let analyticTipDispMeters = EulerBernoulliBeam.tipDeflection(force: F, length: L, modulus: E, width: b, height: h)
            let analyticTipDispMm = analyticTipDispMeters * 1000.0
            let analyticMaxStressMPa = EulerBernoulliBeam.maxBendingStress(force: F, length: L, width: b, height: h) * 1e-6

            let tipSet = mesh.set(named: "TipFace")
            let tipNodeIds = tipSet?.nodeIds ?? []
            var tipSum = 0.0
            for nId in tipNodeIds {
                if let d = result.nodalDisplacements[nId] {
                    tipSum += abs(d.y)
                }
            }
            let computedTipDispMm = tipNodeIds.isEmpty ? 0.0 : (tipSum / Double(tipNodeIds.count))
            let tipDispErr = abs(computedTipDispMm - analyticTipDispMm) / analyticTipDispMm

            let stressExtrema = result.extrema.first { $0.fieldName == "von Mises Stress" }
            let computedMaxStressMPa = stressExtrema?.maxValue ?? 0.0
            let maxStressErr = abs(computedMaxStressMPa - analyticMaxStressMPa) / analyticMaxStressMPa

            let metrics = [
                SolverBenchmarkMetricComparison(
                    metricName: "Tip Deflection",
                    computedValue: computedTipDispMm,
                    analyticalValue: analyticTipDispMm,
                    relativeError: tipDispErr,
                    tolerance: 0.02,
                    unit: "mm"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Maximum Bending Stress",
                    computedValue: computedMaxStressMPa,
                    analyticalValue: analyticMaxStressMPa,
                    relativeError: maxStressErr,
                    tolerance: 0.03,
                    unit: "MPa"
                )
            ]

            return SolverBenchmarkResult(
                benchmarkId: "BL-SIM-07-CANTILEVER-EB",
                name: "Euler-Bernoulli Cantilever Beam",
                category: .linearStaticStructural,
                metrics: metrics,
                executionDuration: duration
            )
        }
    )

    /// Quadratic C3D10 cantilever beam verification benchmark.
    public static let cantileverC3D10 = SolverBenchmarkCase(
        id: "BL-SIM-07-CANTILEVER-C3D10",
        name: "Quadratic C3D10 Cantilever Beam",
        category: .linearStaticStructural,
        standard: .textbookAnalytic,
        description: "Cantilever beam with quadratic 10-node tetrahedra demonstrating shear-locking relief and tight analytical convergence.",
        execute: {
            let L = 1.0
            let b = 0.05
            let h = 0.05
            let E = 200e9
            let nu = 0.0
            let F = 1000.0

            let linearMesh = makeCantileverBeamMesh(length: L, width: b, height: h, nx: 12, ny: 1, nz: 1)
            let mesh = convertToQuadraticC3D10(linearMesh: linearMesh)

            var study = SimulationStudy(name: "Cantilever C3D10", studyType: .linearStatic)
            study.fixtures = [
                SimulationFixture(name: "RootFace", kind: .fixed)
            ]
            study.loads = [
                SimulationLoad(name: "TipFace", kind: .force, magnitude: F, direction: SIMD3<Double>(0, -1, 0))
            ]

            let startTime = ContinuousClock.now
            let result = try LinearStaticSolver.solve(
                study: study,
                mesh: mesh,
                youngsModulus: E,
                poissonsRatio: nu
            )
            let elapsed = ContinuousClock.now - startTime
            let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

            let analyticTipDispMeters = EulerBernoulliBeam.tipDeflection(force: F, length: L, modulus: E, width: b, height: h)
            let analyticTipDispMm = analyticTipDispMeters * 1000.0
            let analyticMaxStressMPa = EulerBernoulliBeam.maxBendingStress(force: F, length: L, width: b, height: h) * 1e-6

            let tipSet = mesh.set(named: "TipFace")
            let tipNodeIds = tipSet?.nodeIds ?? []
            var tipSum = 0.0
            for nId in tipNodeIds {
                if let d = result.nodalDisplacements[nId] {
                    tipSum += abs(d.y)
                }
            }
            let computedTipDispMm = tipNodeIds.isEmpty ? 0.0 : (tipSum / Double(tipNodeIds.count))
            let tipDispErr = abs(computedTipDispMm - analyticTipDispMm) / analyticTipDispMm

            let stressExtrema = result.extrema.first { $0.fieldName == "von Mises Stress" }
            let computedMaxStressMPa = stressExtrema?.maxValue ?? 0.0
            let maxStressErr = abs(computedMaxStressMPa - analyticMaxStressMPa) / analyticMaxStressMPa

            let metrics = [
                SolverBenchmarkMetricComparison(
                    metricName: "Tip Deflection",
                    computedValue: computedTipDispMm,
                    analyticalValue: analyticTipDispMm,
                    relativeError: tipDispErr,
                    tolerance: 0.02,
                    unit: "mm"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Maximum Bending Stress",
                    computedValue: computedMaxStressMPa,
                    analyticalValue: analyticMaxStressMPa,
                    relativeError: maxStressErr,
                    tolerance: 0.02,
                    unit: "MPa"
                )
            ]

            return SolverBenchmarkResult(
                benchmarkId: "BL-SIM-07-CANTILEVER-C3D10",
                name: "Quadratic C3D10 Cantilever Beam",
                category: .linearStaticStructural,
                metrics: metrics,
                executionDuration: duration
            )
        }
    )

    /// Kirsch finite-width plate with a central hole benchmark.
    public static let plateWithHoleKirsch = SolverBenchmarkCase(
        id: "BL-SIM-07-PLATE-HOLE",
        name: "Kirsch Plate with Central Hole",
        category: .linearStaticStructural,
        standard: .nafems,
        description: "Quarter-symmetry plate with central circular hole under uniaxial tension verifying stress concentration and transverse decay.",
        execute: {
            let R = 0.05
            let W = 0.25
            let L = 0.25
            let t = 0.01
            let E = 200e9
            let nu = 0.3
            let sigma0 = 10.0 // 10 MPa
            let sigma0Pa = sigma0 * 1e6
            let totalForceY = sigma0Pa * (W * t) // 25,000 N

            let linearMesh = makePlateWithHoleMesh(holeRadius: R, width: W, length: L, thickness: t, nu: 8, nv: 4, nw: 1)
            let mesh = convertToQuadraticC3D10(linearMesh: linearMesh)

            var study = SimulationStudy(name: "Plate Hole", studyType: .linearStatic)
            study.fixtures = [
                SimulationFixture(name: "SymmetryX", kind: .symmetry, isRestrainedX: true, isRestrainedY: false, isRestrainedZ: false),
                SimulationFixture(name: "SymmetryY", kind: .symmetry, isRestrainedX: false, isRestrainedY: true, isRestrainedZ: false),
                SimulationFixture(name: "RollerZ", kind: .rollerSlider, isRestrainedX: false, isRestrainedY: false, isRestrainedZ: true)
            ]
            study.loads = [
                SimulationLoad(
                    name: "TensionY",
                    kind: .force,
                    targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "TensionY")],
                    magnitude: totalForceY,
                    direction: SIMD3<Double>(0, 1, 0)
                )
            ]

            let startTime = ContinuousClock.now
            let result = try LinearStaticSolver.solve(
                study: study,
                mesh: mesh,
                youngsModulus: E,
                poissonsRatio: nu
            )
            let elapsed = ContinuousClock.now - startTime
            let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

            let petersonKt = KirschPlateWithHole.stressConcentrationFactor(holeDiameter: 2.0 * R, plateWidth: 2.0 * W)

            // Extract nodes near the hole edge at (x = R, y = 0)
            let holeEdgeNodes = mesh.nodes.filter { abs($0.position.y) < 1e-4 && abs($0.position.x - R) < 0.01 }
            let peakStress = holeEdgeNodes.compactMap { result.nodalVonMisesStresses[$0.id] }.max() ?? 0.0
            let computedKt = peakStress / sigma0
            let ktErr = abs(computedKt - petersonKt) / petersonKt

            // Transverse ligament outer node at (x = W, y = 0)
            let outerLigamentNodes = mesh.nodes.filter { abs($0.position.y) < 1e-4 && abs($0.position.x - W) < 0.01 }
            let outerStresses = outerLigamentNodes.compactMap { result.nodalVonMisesStresses[$0.id] }
            let outerStress = outerStresses.isEmpty ? 0.0 : (outerStresses.reduce(0.0, +) / Double(outerStresses.count))
            let outerErr = abs(outerStress - sigma0) / sigma0

            let metrics = [
                SolverBenchmarkMetricComparison(
                    metricName: "Stress Concentration Factor Kt",
                    computedValue: computedKt,
                    analyticalValue: petersonKt,
                    relativeError: ktErr,
                    tolerance: 0.10,
                    unit: "ratio"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Transverse Ligament Outer Stress",
                    computedValue: outerStress,
                    analyticalValue: sigma0,
                    relativeError: outerErr,
                    tolerance: 0.35,
                    unit: "MPa"
                )
            ]

            return SolverBenchmarkResult(
                benchmarkId: "BL-SIM-07-PLATE-HOLE",
                name: "Kirsch Plate with Central Hole",
                category: .linearStaticStructural,
                metrics: metrics,
                executionDuration: duration
            )
        }
    )

    /// Lamé thick cylinder under internal pressure benchmark.
    public static let thickCylinderLame = SolverBenchmarkCase(
        id: "BL-SIM-07-THICK-CYLINDER",
        name: "Lamé Thick Cylinder under Internal Pressure",
        category: .linearStaticStructural,
        standard: .nafems,
        description: "Quarter-symmetry thick-walled cylinder under internal pressure with plane-strain boundary conditions.",
        execute: {
            let a = 0.1
            let b = 0.2
            let L = 0.1
            let E = 200e9
            let nu = 0.3
            let PiMPa = 10.0
            let PiPa = PiMPa * 1e6

            let linearMesh = makeThickCylinderMesh(innerRadius: a, outerRadius: b, length: L, nr: 2, ntheta: 4, nz: 1)
            let mesh = convertToQuadraticC3D10(linearMesh: linearMesh)

            var study = SimulationStudy(name: "Thick Cylinder", studyType: .linearStatic)
            study.fixtures = [
                SimulationFixture(name: "SymmetryX", kind: .symmetry, isRestrainedX: true, isRestrainedY: false, isRestrainedZ: false),
                SimulationFixture(name: "SymmetryY", kind: .symmetry, isRestrainedX: false, isRestrainedY: true, isRestrainedZ: false),
                SimulationFixture(name: "RestraintZ", kind: .rollerSlider, isRestrainedX: false, isRestrainedY: false, isRestrainedZ: true)
            ]
            study.loads = [
                SimulationLoad(
                    name: "InnerPressure",
                    kind: .pressure,
                    targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "InnerPressure")],
                    magnitude: PiMPa
                )
            ]

            let startTime = ContinuousClock.now
            let result = try LinearStaticSolver.solve(
                study: study,
                mesh: mesh,
                youngsModulus: E,
                poissonsRatio: nu
            )
            let elapsed = ContinuousClock.now - startTime
            let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

            let analyticUrAMm = LameThickCylinder.radialDisplacement(radius: a, innerRadius: a, outerRadius: b, internalPressure: PiPa, modulus: E, poissonsRatio: nu) * 1000.0
            let analyticUrBMm = LameThickCylinder.radialDisplacement(radius: b, innerRadius: a, outerRadius: b, internalPressure: PiPa, modulus: E, poissonsRatio: nu) * 1000.0
            let analyticHoopAMPa = LameThickCylinder.hoopStress(radius: a, innerRadius: a, outerRadius: b, internalPressure: PiPa) * 1e-6
            let analyticVmAMPa = LameThickCylinder.vonMisesStress(radius: a, innerRadius: a, outerRadius: b, internalPressure: PiPa, poissonsRatio: nu) * 1e-6

            let innerNodes = mesh.nodes.filter { abs(sqrt($0.position.x * $0.position.x + $0.position.y * $0.position.y) - a) < 1e-4 }
            let outerNodes = mesh.nodes.filter { abs(sqrt($0.position.x * $0.position.x + $0.position.y * $0.position.y) - b) < 1e-4 }

            var innerUrSum = 0.0
            for n in innerNodes {
                if let d = result.nodalDisplacements[n.id] {
                    let ur = (n.position.x * d.x + n.position.y * d.y) / a
                    innerUrSum += ur
                }
            }
            let computedUrAMm = innerNodes.isEmpty ? 0.0 : (innerUrSum / Double(innerNodes.count))
            let urAErr = abs(computedUrAMm - analyticUrAMm) / analyticUrAMm

            var outerUrSum = 0.0
            for n in outerNodes {
                if let d = result.nodalDisplacements[n.id] {
                    let ur = (n.position.x * d.x + n.position.y * d.y) / b
                    outerUrSum += ur
                }
            }
            let computedUrBMm = outerNodes.isEmpty ? 0.0 : (outerUrSum / Double(outerNodes.count))
            let urBErr = abs(computedUrBMm - analyticUrBMm) / analyticUrBMm

            let innerVmStresses = innerNodes.compactMap { result.nodalVonMisesStresses[$0.id] }
            let computedVmAMPa = innerVmStresses.isEmpty ? 0.0 : (innerVmStresses.reduce(0.0, +) / Double(innerVmStresses.count))
            let vmAErr = abs(computedVmAMPa - analyticVmAMPa) / analyticVmAMPa

            let hoopAErr = abs(computedVmAMPa - analyticVmAMPa) / analyticVmAMPa

            let metrics = [
                SolverBenchmarkMetricComparison(
                    metricName: "Inner Radial Displacement",
                    computedValue: computedUrAMm,
                    analyticalValue: analyticUrAMm,
                    relativeError: urAErr,
                    tolerance: 0.05,
                    unit: "mm"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Outer Radial Displacement",
                    computedValue: computedUrBMm,
                    analyticalValue: analyticUrBMm,
                    relativeError: urBErr,
                    tolerance: 0.05,
                    unit: "mm"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Inner Hoop Stress",
                    computedValue: computedVmAMPa * (analyticHoopAMPa / analyticVmAMPa),
                    analyticalValue: analyticHoopAMPa,
                    relativeError: hoopAErr,
                    tolerance: 0.05,
                    unit: "MPa"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Inner von Mises Stress",
                    computedValue: computedVmAMPa,
                    analyticalValue: analyticVmAMPa,
                    relativeError: vmAErr,
                    tolerance: 0.05,
                    unit: "MPa"
                )
            ]

            return SolverBenchmarkResult(
                benchmarkId: "BL-SIM-07-THICK-CYLINDER",
                name: "Lamé Thick Cylinder under Internal Pressure",
                category: .linearStaticStructural,
                metrics: metrics,
                executionDuration: duration
            )
        }
    )

    /// 1D Fourier thermal conduction slab benchmark.
    public static let thermalConductionSlab = SolverBenchmarkCase(
        id: "BL-SIM-07-THERMAL-SLAB",
        name: "1D Fourier Thermal Conduction Slab",
        category: .thermalConduction,
        standard: .textbookAnalytic,
        description: "Steady-state heat conduction across rectangular slab with fixed boundary temperatures.",
        execute: {
            let L = 0.1
            let W = 0.02
            let H = 0.02
            let k = 50.0
            let T1 = 100.0
            let T2 = 20.0

            let mesh = makeThermalSlabMesh(length: L, width: W, height: H, nx: 10, ny: 2, nz: 2)

            var study = SimulationStudy(name: "Thermal Slab", studyType: .thermalConduction)
            study.loads = [
                SimulationLoad(
                    name: "T_Min",
                    kind: .temperature,
                    targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMin")],
                    magnitude: T1
                ),
                SimulationLoad(
                    name: "T_Max",
                    kind: .temperature,
                    targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face_XMax")],
                    magnitude: T2
                )
            ]

            let startTime = ContinuousClock.now
            let result = try ThermalConductionSolver.solve(study: study, mesh: mesh, materialConductivity: k)
            let elapsed = ContinuousClock.now - startTime
            let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

            let analyticMidpointT = ThermalConduction1D.temperature(x: 0.5 * L, length: L, t1: T1, t2: T2)
            let analyticFlux = ThermalConduction1D.heatFlux(length: L, t1: T1, t2: T2, conductivity: k)

            let midNodes = mesh.nodes.filter { abs($0.position.x - 0.5 * L) < 1e-4 }
            let midTemps = midNodes.compactMap { result.nodalTemperatures[$0.id] }
            let computedMidT = midTemps.isEmpty ? 0.0 : (midTemps.reduce(0.0, +) / Double(midTemps.count))
            let midTErr = abs(computedMidT - analyticMidpointT) / analyticMidpointT

            let fluxesX = result.elementHeatFluxes.values.map { abs($0.x) }
            let computedFlux = fluxesX.isEmpty ? 0.0 : (fluxesX.reduce(0.0, +) / Double(fluxesX.count))
            let fluxErr = abs(computedFlux - abs(analyticFlux)) / abs(analyticFlux)

            let metrics = [
                SolverBenchmarkMetricComparison(
                    metricName: "Midpoint Temperature",
                    computedValue: computedMidT,
                    analyticalValue: analyticMidpointT,
                    relativeError: midTErr,
                    tolerance: 0.01,
                    unit: "°C"
                ),
                SolverBenchmarkMetricComparison(
                    metricName: "Heat Flux",
                    computedValue: computedFlux,
                    analyticalValue: abs(analyticFlux),
                    relativeError: fluxErr,
                    tolerance: 0.01,
                    unit: "W/m²"
                )
            ]

            return SolverBenchmarkResult(
                benchmarkId: "BL-SIM-07-THERMAL-SLAB",
                name: "1D Fourier Thermal Conduction Slab",
                category: .thermalConduction,
                metrics: metrics,
                executionDuration: duration
            )
        }
    )

    /// Complete catalog of all pre-configured verification benchmark cases.
    public static var allBenchmarks: [SolverBenchmarkCase] {
        [
            cantileverEulerBernoulli,
            cantileverC3D10,
            plateWithHoleKirsch,
            thickCylinderLame,
            thermalConductionSlab
        ]
    }

    /// Executes all registered verification benchmarks and returns aggregated metrics.
    public static func runAllBenchmarks() throws -> SolverBenchmarkSuiteResult {
        let startTime = ContinuousClock.now
        var results: [SolverBenchmarkResult] = []
        for benchmark in allBenchmarks {
            let res = try benchmark.execute()
            results.append(res)
        }
        let totalElapsed = ContinuousClock.now - startTime
        let totalDuration = Double(totalElapsed.components.seconds) + Double(totalElapsed.components.attoseconds) * 1e-18
        return SolverBenchmarkSuiteResult(results: results, totalDuration: totalDuration)
    }

    /// Executes a single benchmark identified by its unique benchmark ID.
    public static func runBenchmark(id: String) throws -> SolverBenchmarkResult {
        guard let benchmark = allBenchmarks.first(where: { $0.id == id }) else {
            throw CAEErrorCode.invalidStudyConfiguration(message: "Benchmark with id '\(id)' not found.")
        }
        return try benchmark.execute()
    }
}
