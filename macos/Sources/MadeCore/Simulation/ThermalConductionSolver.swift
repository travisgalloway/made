import Foundation
import simd

/// Numerical solution results for steady-state thermal conduction (ADR-D5, BL-THM-01, #190).
public struct ThermalConductionResult: Sendable, Codable, Equatable {
    public var nodalTemperatures: [Int: Double]
    public var elementHeatFluxes: [Int: SIMD3<Double>]
    public var extrema: [SimulationFieldExtrema]
    public var iterationCount: Int
    public var finalResidual: Double
    public var runtimeDuration: Double

    public init(
        nodalTemperatures: [Int: Double],
        elementHeatFluxes: [Int: SIMD3<Double>] = [:],
        extrema: [SimulationFieldExtrema] = [],
        iterationCount: Int = 0,
        finalResidual: Double = 0.0,
        runtimeDuration: Double = 0.0
    ) {
        self.nodalTemperatures = nodalTemperatures
        self.elementHeatFluxes = elementHeatFluxes
        self.extrema = extrema
        self.iterationCount = iterationCount
        self.finalResidual = finalResidual
        self.runtimeDuration = runtimeDuration
    }
}

/// Pure-Swift finite element solver for 3D steady-state thermal conduction governed by $-\nabla \cdot (k \nabla T) = Q$ (ADR-D5, BL-THM-01, #190).
public enum ThermalConductionSolver: Sendable {

    /// Solves steady-state thermal conduction for a given simulation study and volume mesh.
    ///
    /// - Parameters:
    ///   - study: CAE simulation study containing materials, boundary conditions, and solver controls.
    ///   - mesh: Discretized tetrahedral volume mesh.
    ///   - materialConductivity: Thermal conductivity $k$ in $\text{W}/(\text{m}\cdot\text{K})$ (default 50.0 for structural steel).
    ///   - lengthScaleToMeters: Coordinate multiplier converting mesh positions to meters (default 1.0).
    /// - Returns: Computed nodal temperatures, heat fluxes, and summary extrema.
    public static func solve(
        study: SimulationStudy,
        mesh: VolumeMesh,
        materialConductivity: Double = 50.0,
        lengthScaleToMeters: Double = 1.0
    ) throws -> ThermalConductionResult {
        let startTime = ContinuousClock.now

        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            throw CAEErrorCode.invalidStudyConfiguration(message: "Mesh contains no nodes or elements.")
        }

        let k = materialConductivity > 0 ? materialConductivity : 50.0
        let nodeCount = mesh.nodes.count

        // Build node ID to zero-based matrix index mapping
        var nodeIndexById = [Int: Int](minimumCapacity: nodeCount)
        var nodeIds = [Int](repeating: 0, count: nodeCount)
        var positions = [SIMD3<Double>](repeating: .zero, count: nodeCount)

        for (idx, node) in mesh.nodes.enumerated() {
            nodeIndexById[node.id] = idx
            nodeIds[idx] = node.id
            positions[idx] = node.position * lengthScaleToMeters
        }

        // Global sparse matrix A = K + Kc stored as row dictionaries: K[row][col]
        var K: [[Int: Double]] = Array(repeating: [:], count: nodeCount)
        var F = [Double](repeating: 0.0, count: nodeCount)

        // 1. Assemble element conductance matrices
        for element in mesh.elements {
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                assembleC3D10Conductance(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    conductivity: k,
                    K: &K
                )
            } else if element.nodeIndices.count >= 4 {
                assembleC3D4Conductance(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    conductivity: k,
                    K: &K
                )
            }
        }

        // 2. Resolve geometry sets for fixtures and loads
        let associatedSets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        var setByName: [String: VolumeMeshSet] = [:]
        var setById: [UUID: VolumeMeshSet] = [:]
        for s in associatedSets {
            setByName[s.name] = s
            setById[s.id] = s
        }
        for s in mesh.sets {
            setByName[s.name] = s
            setById[s.id] = s
        }

        let boundaryTriangles = getEffectiveBoundaryTriangles(mesh: mesh)

        // Track boundary conditions to enforce uniqueness and check unconstrained state
        var dirichletNodes: [Int: Double] = [:] // matrixIndex -> prescribed temperature
        var hasRobinCondition = false

        // 3. Assemble boundary conditions and applied loads
        for load in study.loads {
            let matchedSet = (mesh.sets.first(where: { $0.name == load.name }))
                ?? setById[load.id]
                ?? load.targetReferences.compactMap({ setByName[$0.targetName] ?? setById[$0.targetId] }).first
                ?? load.groupNames.compactMap({ setByName[$0] }).first
                ?? setByName[load.name]
            let targetNodeIds = Set(matchedSet?.nodeIds ?? [])
            let targetElementIds = Set(matchedSet?.elementIds ?? [])

            switch load.kind {
            case .temperature:
                let prescribedT = load.magnitude
                if !targetNodeIds.isEmpty {
                    for nId in targetNodeIds {
                        if let idx = nodeIndexById[nId] {
                            dirichletNodes[idx] = prescribedT
                        }
                    }
                } else if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                    // Fallback: all boundary surface nodes
                    for tri in boundaryTriangles {
                        for nId in tri.nodeIndices {
                            if let idx = nodeIndexById[nId] {
                                dirichletNodes[idx] = prescribedT
                            }
                        }
                    }
                }

            case .convection:
                let h = load.magnitude
                let tInf = load.ambientTemperature ?? 20.0
                guard h > 0 else { continue }

                let matchedTriangles = filterBoundaryTriangles(
                    triangles: boundaryTriangles,
                    targetElementIds: targetElementIds,
                    targetNodeIds: targetNodeIds,
                    hasExplicitTargets: !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                )

                if !matchedTriangles.isEmpty {
                    hasRobinCondition = true
                    for tri in matchedTriangles {
                        assembleRobinTriangle(
                            tri: tri,
                            positions: positions,
                            nodeIndexById: nodeIndexById,
                            h: h,
                            tInf: tInf,
                            K: &K,
                            F: &F
                        )
                    }
                }

            case .thermalFlux:
                let q = load.magnitude
                let matchedTriangles = filterBoundaryTriangles(
                    triangles: boundaryTriangles,
                    targetElementIds: targetElementIds,
                    targetNodeIds: targetNodeIds,
                    hasExplicitTargets: !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                )

                for tri in matchedTriangles {
                    assembleFluxTriangle(
                        tri: tri,
                        positions: positions,
                        nodeIndexById: nodeIndexById,
                        flux: q,
                        F: &F
                    )
                }

            case .heatPower:
                let totalPower = load.magnitude
                let matchedTriangles = filterBoundaryTriangles(
                    triangles: boundaryTriangles,
                    targetElementIds: targetElementIds,
                    targetNodeIds: targetNodeIds,
                    hasExplicitTargets: !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                )

                if !matchedTriangles.isEmpty {
                    var totalArea = 0.0
                    for tri in matchedTriangles {
                        totalArea += computeTriangleArea(tri: tri, positions: positions, nodeIndexById: nodeIndexById)
                    }
                    if totalArea > 1e-12 {
                        let equivalentFlux = totalPower / totalArea
                        for tri in matchedTriangles {
                            assembleFluxTriangle(
                                tri: tri,
                                positions: positions,
                                nodeIndexById: nodeIndexById,
                                flux: equivalentFlux,
                                F: &F
                            )
                        }
                    }
                } else {
                    // Volumetric heat power distributed across volume elements
                    var totalVolume = 0.0
                    for el in mesh.elements {
                        totalVolume += computeTetrahedronVolume(el: el, positions: positions, nodeIndexById: nodeIndexById)
                    }
                    if totalVolume > 1e-12 {
                        let qv = totalPower / totalVolume
                        for el in mesh.elements {
                            let v = computeTetrahedronVolume(el: el, positions: positions, nodeIndexById: nodeIndexById)
                            let nodalShare = (qv * v) / Double(el.nodeIndices.count)
                            for nId in el.nodeIndices {
                                if let idx = nodeIndexById[nId] {
                                    F[idx] += nodalShare
                                }
                            }
                        }
                    }
                }

            case .force, .pressure, .gravity:
                break
            }
        }

        // Validate that thermal problem is constrained
        guard !dirichletNodes.isEmpty || hasRobinCondition else {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Thermal problem is unconstrained; at least one temperature or convection boundary condition is required."
            )
        }

        // 4. Enforce Dirichlet boundary conditions via row and column elimination
        for (dIdx, tVal) in dirichletNodes {
            // For every other row j, subtract K[j][dIdx] * tVal from F[j], then remove column entry
            for j in 0..<nodeCount where j != dIdx {
                if let kjd = K[j][dIdx] {
                    F[j] -= kjd * tVal
                    K[j].removeValue(forKey: dIdx)
                }
            }
            // Clear row dIdx
            K[dIdx].removeAll(keepingCapacity: true)
            K[dIdx][dIdx] = 1.0
            F[dIdx] = tVal
        }

        // 5. Solve linear system K * T = F using Preconditioned Conjugate Gradient (PCG)
        let maxIter = max(1000, study.solver.maxIterations)
        let tol = 1e-7
        let (solutionT, iterations, finalRes) = solvePCG(K: K, b: F, dirichlet: dirichletNodes, maxIterations: maxIter, tolerance: tol)

        // 6. Post-process element heat flux vectors q = -k * grad(T)
        var elementHeatFluxes: [Int: SIMD3<Double>] = [:]
        elementHeatFluxes.reserveCapacity(mesh.elements.count)
        var minFlux = Double.infinity
        var maxFlux = 0.0

        for element in mesh.elements {
            let flux: SIMD3<Double>
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                flux = computeC3D10HeatFlux(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    nodalT: solutionT,
                    k: k
                )
            } else if element.nodeIndices.count >= 4 {
                flux = computeC3D4HeatFlux(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    nodalT: solutionT,
                    k: k
                )
            } else {
                flux = .zero
            }

            elementHeatFluxes[element.id] = flux
            let mag = simd_length(flux)
            minFlux = min(minFlux, mag)
            maxFlux = max(maxFlux, mag)
        }

        if minFlux.isInfinite { minFlux = 0.0 }

        // Map solution back to node IDs
        var nodalTemperatures: [Int: Double] = [:]
        nodalTemperatures.reserveCapacity(nodeCount)
        var minT = Double.infinity
        var maxT = -Double.infinity

        for (idx, nId) in nodeIds.enumerated() {
            let t = solutionT[idx]
            nodalTemperatures[nId] = t
            minT = min(minT, t)
            maxT = max(maxT, t)
        }

        if minT.isInfinite { minT = 0.0; maxT = 0.0 }

        let extrema: [SimulationFieldExtrema] = [
            SimulationFieldExtrema(fieldName: "Temperature", unitSymbol: "°C", minValue: minT, maxValue: maxT),
            SimulationFieldExtrema(fieldName: "Heat Flux", unitSymbol: "W/m²", minValue: minFlux, maxValue: maxFlux)
        ]

        let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                      Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

        return ThermalConductionResult(
            nodalTemperatures: nodalTemperatures,
            elementHeatFluxes: elementHeatFluxes,
            extrema: extrema,
            iterationCount: iterations,
            finalResidual: finalRes,
            runtimeDuration: elapsed
        )
    }

    // MARK: - Conductance Assembly (C3D4 Linear Tetrahedra)

    private static func assembleC3D4Conductance(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        conductivity k: Double,
        K: inout [[Int: Double]]
    ) {
        let indices = element.nodeIndices.prefix(4).compactMap { nodeIndexById[$0] }
        guard indices.count == 4 else { return }

        let p0 = positions[indices[0]]
        let p1 = positions[indices[1]]
        let p2 = positions[indices[2]]
        let p3 = positions[indices[3]]

        let v10 = p1 - p0
        let v20 = p2 - p0
        let v30 = p3 - p0
        let det6 = simd_dot(simd_cross(v10, v20), v30)
        let volume = abs(det6) / 6.0
        guard volume > 1e-15 else { return }

        // Coordinate matrix C
        let C: [[Double]] = [
            [1.0, p0.x, p0.y, p0.z],
            [1.0, p1.x, p1.y, p1.z],
            [1.0, p2.x, p2.y, p2.z],
            [1.0, p3.x, p3.y, p3.z]
        ]

        guard let Cinv = invert4x4(C) else { return }

        // Gradients of shape functions: column i of Cinv gives [a_i, b_i, c_i, d_i]
        var gradN = [SIMD3<Double>](repeating: .zero, count: 4)
        for i in 0..<4 {
            gradN[i] = SIMD3<Double>(Cinv[1][i], Cinv[2][i], Cinv[3][i])
        }

        // Element stiffness entries: K_ij = volume * k * (gradN_i . gradN_j)
        for i in 0..<4 {
            let row = indices[i]
            for j in 0..<4 {
                let col = indices[j]
                let entry = volume * k * simd_dot(gradN[i], gradN[j])
                K[row][col, default: 0.0] += entry
            }
        }
    }

    // MARK: - Conductance Assembly (C3D10 Quadratic Tetrahedra)

    private static func assembleC3D10Conductance(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        conductivity k: Double,
        K: inout [[Int: Double]]
    ) {
        let indices = element.nodeIndices.prefix(10).compactMap { nodeIndexById[$0] }
        guard indices.count == 10 else { return }

        let p = indices.map { positions[$0] }

        // 4-point Gauss quadrature on tetrahedra
        let alpha = (5.0 - sqrt(5.0)) / 20.0
        let beta = (5.0 + 3.0 * sqrt(5.0)) / 20.0
        let quadPoints: [(SIMD4<Double>, Double)] = [
            (SIMD4<Double>(beta, alpha, alpha, alpha), 1.0 / 24.0),
            (SIMD4<Double>(alpha, beta, alpha, alpha), 1.0 / 24.0),
            (SIMD4<Double>(alpha, alpha, beta, alpha), 1.0 / 24.0),
            (SIMD4<Double>(alpha, alpha, alpha, beta), 1.0 / 24.0)
        ]

        for (L, weight) in quadPoints {
            let dNdL = evaluateC3D10LocalGradients(L: L)

            // Compute Jacobian J = dN/dL_i * p_a
            var J = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero) // 3 rows
            for a in 0..<10 {
                let grad = dNdL[a]
                J.0 += grad.x * p[a]
                J.1 += grad.y * p[a]
                J.2 += grad.z * p[a]
            }

            let detJ = simd_dot(simd_cross(J.0, J.1), J.2)
            let absDetJ = abs(detJ)
            guard absDetJ > 1e-15, let Jinv = invert3x3(J) else { continue }

            let dOmega = weight * absDetJ

            // Physical gradients gradN_a = Jinv * dNdL_a
            var gradN = [SIMD3<Double>](repeating: .zero, count: 10)
            for a in 0..<10 {
                gradN[a] = multiply3x3(Jinv, dNdL[a])
            }

            for i in 0..<10 {
                let row = indices[i]
                for j in 0..<10 {
                    let col = indices[j]
                    let entry = dOmega * k * simd_dot(gradN[i], gradN[j])
                    K[row][col, default: 0.0] += entry
                }
            }
        }
    }

    // MARK: - Boundary Condition Assembly

    private static func assembleRobinTriangle(
        tri: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        h: Double,
        tInf: Double,
        K: inout [[Int: Double]],
        F: inout [Double]
    ) {
        let indices = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
        guard indices.count == 3 else { return }

        let p0 = positions[indices[0]]
        let p1 = positions[indices[1]]
        let p2 = positions[indices[2]]
        let area = 0.5 * simd_length(simd_cross(p1 - p0, p2 - p0))
        guard area > 1e-15 else { return }

        // Robin matrix Kc = (h * A / 12) * [2 1 1; 1 2 1; 1 1 2]
        let factor = (h * area) / 12.0
        let loadShare = (h * tInf * area) / 3.0

        for i in 0..<3 {
            let row = indices[i]
            F[row] += loadShare
            for j in 0..<3 {
                let col = indices[j]
                let entry = (i == j) ? (2.0 * factor) : factor
                K[row][col, default: 0.0] += entry
            }
        }
    }

    private static func assembleFluxTriangle(
        tri: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        flux q: Double,
        F: inout [Double]
    ) {
        let indices = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
        guard indices.count == 3 else { return }

        let p0 = positions[indices[0]]
        let p1 = positions[indices[1]]
        let p2 = positions[indices[2]]
        let area = 0.5 * simd_length(simd_cross(p1 - p0, p2 - p0))
        guard area > 1e-15 else { return }

        let loadShare = (q * area) / 3.0
        for i in 0..<3 {
            F[indices[i]] += loadShare
        }
    }

    // MARK: - Post-Processing (Heat Flux Vectors)

    private static func computeC3D4HeatFlux(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        nodalT: [Double],
        k: Double
    ) -> SIMD3<Double> {
        let indices = element.nodeIndices.prefix(4).compactMap { nodeIndexById[$0] }
        guard indices.count == 4 else { return .zero }

        let p0 = positions[indices[0]]
        let p1 = positions[indices[1]]
        let p2 = positions[indices[2]]
        let p3 = positions[indices[3]]

        let C: [[Double]] = [
            [1.0, p0.x, p0.y, p0.z],
            [1.0, p1.x, p1.y, p1.z],
            [1.0, p2.x, p2.y, p2.z],
            [1.0, p3.x, p3.y, p3.z]
        ]

        guard let Cinv = invert4x4(C) else { return .zero }

        var gradT = SIMD3<Double>.zero
        for i in 0..<4 {
            let gradN = SIMD3<Double>(Cinv[1][i], Cinv[2][i], Cinv[3][i])
            gradT += nodalT[indices[i]] * gradN
        }

        return -k * gradT
    }

    private static func computeC3D10HeatFlux(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        nodalT: [Double],
        k: Double
    ) -> SIMD3<Double> {
        let indices = element.nodeIndices.prefix(10).compactMap { nodeIndexById[$0] }
        guard indices.count == 10 else { return .zero }

        let p = indices.map { positions[$0] }
        let centroidL = SIMD4<Double>(0.25, 0.25, 0.25, 0.25)
        let dNdL = evaluateC3D10LocalGradients(L: centroidL)

        var J = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero)
        for a in 0..<10 {
            J.0 += dNdL[a].x * p[a]
            J.1 += dNdL[a].y * p[a]
            J.2 += dNdL[a].z * p[a]
        }

        guard let Jinv = invert3x3(J) else { return .zero }

        var gradT = SIMD3<Double>.zero
        for a in 0..<10 {
            let gradN = multiply3x3(Jinv, dNdL[a])
            gradT += nodalT[indices[a]] * gradN
        }

        return -k * gradT
    }

    // MARK: - Linear Solver (Preconditioned Conjugate Gradient)

    private static func solvePCG(
        K: [[Int: Double]],
        b: [Double],
        dirichlet: [Int: Double],
        maxIterations: Int,
        tolerance: Double
    ) -> (x: [Double], iterations: Int, finalResidual: Double) {
        let n = b.count
        var x = [Double](repeating: 0.0, count: n)
        for (idx, val) in dirichlet {
            x[idx] = val
        }

        // Jacobi preconditioner: invM[i] = 1 / K_ii
        var invM = [Double](repeating: 1.0, count: n)
        for i in 0..<n {
            let diag = K[i][i] ?? 1.0
            invM[i] = abs(diag) > 1e-15 ? (1.0 / diag) : 1.0
        }

        // r = b - K * x
        var r = b
        for i in 0..<n {
            var sum = 0.0
            for (col, val) in K[i] {
                sum += val * x[col]
            }
            r[i] -= sum
        }

        var rNormSq = 0.0
        for val in r { rNormSq += val * val }
        let initNorm = max(sqrt(rNormSq), 1e-12)

        if sqrt(rNormSq) / initNorm < tolerance {
            return (x, 0, sqrt(rNormSq))
        }

        // z = M^-1 * r
        var z = [Double](repeating: 0.0, count: n)
        for i in 0..<n { z[i] = invM[i] * r[i] }

        var p = z
        var gamma = 0.0
        for i in 0..<n { gamma += r[i] * z[i] }

        var iter = 0
        var currentRes = sqrt(rNormSq)

        while iter < maxIterations {
            iter += 1

            // q = K * p
            var q = [Double](repeating: 0.0, count: n)
            for i in 0..<n {
                var sum = 0.0
                for (col, val) in K[i] {
                    sum += val * p[col]
                }
                q[i] = sum
            }

            var pDotQ = 0.0
            for i in 0..<n { pDotQ += p[i] * q[i] }
            if abs(pDotQ) < 1e-30 { break }

            let alpha = gamma / pDotQ

            for i in 0..<n {
                x[i] += alpha * p[i]
                r[i] -= alpha * q[i]
            }

            var rNorm2 = 0.0
            for val in r { rNorm2 += val * val }
            currentRes = sqrt(rNorm2)

            if currentRes / initNorm < tolerance {
                break
            }

            for i in 0..<n { z[i] = invM[i] * r[i] }

            var gammaNew = 0.0
            for i in 0..<n { gammaNew += r[i] * z[i] }

            let beta = gammaNew / gamma
            gamma = gammaNew

            for i in 0..<n {
                p[i] = z[i] + beta * p[i]
            }
        }

        return (x, iter, currentRes)
    }

    // MARK: - Geometry & Quadrature Helpers

    private static func evaluateC3D10LocalGradients(L: SIMD4<Double>) -> [SIMD3<Double>] {
        let L1 = L.x, L2 = L.y, L3 = L.z, L4 = L.w
        var grad = [SIMD3<Double>](repeating: .zero, count: 10)

        // Corner nodes
        grad[0] = SIMD3<Double>(4.0 * L1 - 1.0, 0.0, 0.0)
        grad[1] = SIMD3<Double>(0.0, 4.0 * L2 - 1.0, 0.0)
        grad[2] = SIMD3<Double>(0.0, 0.0, 4.0 * L3 - 1.0)
        grad[3] = SIMD3<Double>(1.0 - 4.0 * L4, 1.0 - 4.0 * L4, 1.0 - 4.0 * L4)

        // Mid-side nodes
        grad[4] = SIMD3<Double>(4.0 * L2, 4.0 * L1, 0.0)
        grad[5] = SIMD3<Double>(0.0, 4.0 * L3, 4.0 * L2)
        grad[6] = SIMD3<Double>(4.0 * L3, 0.0, 4.0 * L1)
        grad[7] = SIMD3<Double>(4.0 * (L4 - L1), -4.0 * L1, -4.0 * L1)
        grad[8] = SIMD3<Double>(-4.0 * L2, 4.0 * (L4 - L2), -4.0 * L2)
        grad[9] = SIMD3<Double>(-4.0 * L3, -4.0 * L3, 4.0 * (L4 - L3))

        return grad
    }

    private static func computeTriangleArea(
        tri: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int]
    ) -> Double {
        let indices = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
        guard indices.count == 3 else { return 0.0 }
        let p0 = positions[indices[0]]
        let p1 = positions[indices[1]]
        let p2 = positions[indices[2]]
        return 0.5 * simd_length(simd_cross(p1 - p0, p2 - p0))
    }

    private static func computeTetrahedronVolume(
        el: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int]
    ) -> Double {
        let indices = el.nodeIndices.prefix(4).compactMap { nodeIndexById[$0] }
        guard indices.count == 4 else { return 0.0 }
        let p0 = positions[indices[0]]
        let p1 = positions[indices[1]]
        let p2 = positions[indices[2]]
        let p3 = positions[indices[3]]
        let det = simd_dot(simd_cross(p1 - p0, p2 - p0), p3 - p0)
        return abs(det) / 6.0
    }

    private static func getEffectiveBoundaryTriangles(mesh: VolumeMesh) -> [VolumeMeshElement] {
        if !mesh.surfaceTriangles.isEmpty {
            return mesh.surfaceTriangles
        }

        // Reconstruct boundary faces from tetrahedra
        struct FaceKey: Hashable {
            let n0: Int, n1: Int, n2: Int
            init(_ a: Int, _ b: Int, _ c: Int) {
                let s = [a, b, c].sorted()
                self.n0 = s[0]
                self.n1 = s[1]
                self.n2 = s[2]
            }
        }

        var faceOccurrences: [FaceKey: (count: Int, nodes: [Int], order: MeshElementOrder)] = [:]

        for tet in mesh.elements {
            guard tet.nodeIndices.count >= 4 else { continue }
            let corners = Array(tet.nodeIndices.prefix(4))
            let faces: [[Int]] = [
                [corners[0], corners[1], corners[2]],
                [corners[0], corners[1], corners[3]],
                [corners[1], corners[2], corners[3]],
                [corners[0], corners[2], corners[3]]
            ]

            for f in faces {
                let key = FaceKey(f[0], f[1], f[2])
                if let existing = faceOccurrences[key] {
                    faceOccurrences[key] = (existing.count + 1, existing.nodes, existing.order)
                } else {
                    faceOccurrences[key] = (1, f, tet.order)
                }
            }
        }

        var boundary: [VolumeMeshElement] = []
        var nextId = (mesh.elements.map { $0.id }.max() ?? 0) + 1
        for (_, entry) in faceOccurrences where entry.count == 1 {
            boundary.append(VolumeMeshElement(id: nextId, order: entry.order, nodeIndices: entry.nodes))
            nextId += 1
        }

        return boundary
    }

    private static func filterBoundaryTriangles(
        triangles: [VolumeMeshElement],
        targetElementIds: Set<Int>,
        targetNodeIds: Set<Int>,
        hasExplicitTargets: Bool
    ) -> [VolumeMeshElement] {
        if !hasExplicitTargets {
            return triangles
        }
        return triangles.filter { tri in
            if targetElementIds.contains(tri.id) { return true }
            let triCorners = Set(tri.nodeIndices.prefix(3))
            return !triCorners.isEmpty && triCorners.isSubset(of: targetNodeIds)
        }
    }

    // MARK: - Matrix Inversion Helpers

    private static func invert4x4(_ m: [[Double]]) -> [[Double]]? {
        var a = m
        var inv = [[Double]](repeating: [Double](repeating: 0.0, count: 4), count: 4)
        for i in 0..<4 { inv[i][i] = 1.0 }

        for col in 0..<4 {
            var pivotRow = col
            var maxVal = abs(a[col][col])
            for row in (col + 1)..<4 {
                let val = abs(a[row][col])
                if val > maxVal {
                    maxVal = val
                    pivotRow = row
                }
            }
            if maxVal < 1e-15 { return nil }
            if pivotRow != col {
                a.swapAt(col, pivotRow)
                inv.swapAt(col, pivotRow)
            }
            let pivot = a[col][col]
            for j in 0..<4 {
                a[col][j] /= pivot
                inv[col][j] /= pivot
            }
            for row in 0..<4 {
                if row != col {
                    let factor = a[row][col]
                    if abs(factor) > 1e-15 {
                        for j in 0..<4 {
                            a[row][j] -= factor * a[col][j]
                            inv[row][j] -= factor * inv[col][j]
                        }
                    }
                }
            }
        }
        return inv
    }

    private static func invert3x3(_ J: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)? {
        let r0 = J.0, r1 = J.1, r2 = J.2
        let det = simd_dot(simd_cross(r0, r1), r2)
        guard abs(det) > 1e-15 else { return nil }
        let invDet = 1.0 / det

        let c0 = simd_cross(r1, r2) * invDet
        let c1 = simd_cross(r2, r0) * invDet
        let c2 = simd_cross(r0, r1) * invDet

        // Return rows of Jinv = [c0, c1, c2]^T
        return (
            SIMD3<Double>(c0.x, c1.x, c2.x),
            SIMD3<Double>(c0.y, c1.y, c2.y),
            SIMD3<Double>(c0.z, c1.z, c2.z)
        )
    }

    private static func multiply3x3(_ M: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>), _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            simd_dot(M.0, v),
            simd_dot(M.1, v),
            simd_dot(M.2, v)
        )
    }
}
