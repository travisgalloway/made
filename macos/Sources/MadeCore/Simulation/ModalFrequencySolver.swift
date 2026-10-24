import Foundation
import simd

/// Numerical solution results for modal natural frequency analysis (ADR-D5, BL-FEA-07, #225).
public struct ModalFrequencyResult: Sendable, Codable, Equatable {
    public var modeShapes: [SimulationModeShape]
    public var extrema: [SimulationFieldExtrema]
    public var iterationCount: Int
    public var finalResidual: Double
    public var runtimeDuration: Double

    public init(
        modeShapes: [SimulationModeShape] = [],
        extrema: [SimulationFieldExtrema] = [],
        iterationCount: Int = 0,
        finalResidual: Double = 0.0,
        runtimeDuration: Double = 0.0
    ) {
        self.modeShapes = modeShapes
        self.extrema = extrema
        self.iterationCount = iterationCount
        self.finalResidual = finalResidual
        self.runtimeDuration = runtimeDuration
    }
}

/// Pure-Swift finite element generalized eigensolver for 3D natural frequency and mode shape analysis
/// governed by $(\mathbf{K} + \mathbf{K}_\sigma)\boldsymbol{\phi} = \omega^2 \mathbf{M} \boldsymbol{\phi}$ (ADR-D5, BL-FEA-07, #225).
public enum ModalFrequencySolver: Sendable {

    /// Solves the generalized eigenvalue problem to extract natural frequencies and mode shapes.
    ///
    /// - Parameters:
    ///   - study: CAE simulation study containing fixtures, materials, and solver configuration.
    ///   - mesh: Discretized tetrahedral volume mesh (C3D4 or C3D10 elements).
    ///   - youngsModulus: Optional override for Young's modulus $E$ in Pascals ($\text{N/m}^2$).
    ///   - poissonsRatio: Optional override for Poisson's ratio $\nu$.
    ///   - density: Optional override for mass density $\rho$ in $\text{kg/m}^3$.
    ///   - lengthScaleToMeters: Multiplier converting mesh coordinate units to meters (default 1.0).
    /// - Returns: Computed natural frequencies, mode shapes, and field extrema.
    public static func solve(
        study: SimulationStudy,
        mesh: VolumeMesh,
        youngsModulus: Double? = nil,
        poissonsRatio: Double? = nil,
        density: Double? = nil,
        lengthScaleToMeters: Double = 1.0
    ) throws -> ModalFrequencyResult {
        let startTime = ContinuousClock.now

        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            throw CAEErrorCode.invalidStudyConfiguration(message: "Mesh contains no nodes or elements.")
        }

        if study.fixtures.isEmpty {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Modal frequency analysis requires at least one fixture boundary condition to prevent unconstrained motion."
            )
        }

        // 1. Resolve isotropic material properties
        var E: Double
        var nu: Double
        var rho: Double = 7850.0 // Default structural steel density kg/m³

        if let y = youngsModulus, let p = poissonsRatio {
            E = y
            nu = p
            if let d = density, d > 0 {
                rho = d
            } else if let matId = study.materials.first?.materialId,
                      let mat = MaterialLibrary.standard.material(withId: matId),
                      mat.densityKgPerM3 > 0 {
                rho = mat.densityKgPerM3
            }
        } else {
            let matId = study.materials.first?.materialId
            let mat = matId.flatMap { MaterialLibrary.standard.material(withId: $0) }
            if let mat {
                E = youngsModulus ?? (mat.youngsModulusGPa * 1e9)
                nu = poissonsRatio ?? mat.poissonsRatioValue
                if let d = density, d > 0 {
                    rho = d
                } else if mat.densityKgPerM3 > 0 {
                    rho = mat.densityKgPerM3
                }
            } else {
                E = youngsModulus ?? 200e9
                nu = poissonsRatio ?? 0.3
                if let d = density, d > 0 {
                    rho = d
                }
            }
        }

        guard E > 0.0, nu > -1.0, nu < 0.5 else {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Non-physical material properties: E=\(E) Pa, nu=\(nu). Analysis requires E > 0 and -1 < nu < 0.5."
            )
        }

        // Prevent zero or negative mass density
        if rho <= 0.0 {
            rho = 7850.0
        }

        let lambda = (E * nu) / ((1.0 + nu) * (1.0 - 2.0 * nu))
        let mu = E / (2.0 * (1.0 + nu))

        let nodeCount = mesh.nodes.count
        let totalDOFs = 3 * nodeCount

        var nodeIndexById = [Int: Int](minimumCapacity: nodeCount)
        var nodeIds = [Int](repeating: 0, count: nodeCount)
        var positions = [SIMD3<Double>](repeating: .zero, count: nodeCount)

        for (idx, node) in mesh.nodes.enumerated() {
            nodeIndexById[node.id] = idx
            nodeIds[idx] = node.id
            positions[idx] = node.position * lengthScaleToMeters
        }

        // 2. Assemble global elastic stiffness matrix K
        var K: [[Int: Double]] = Array(repeating: [:], count: totalDOFs)

        for element in mesh.elements {
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                LinearStaticSolver.assembleC3D10Stiffness(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    lambda: lambda,
                    mu: mu,
                    K: &K
                )
            } else if element.nodeIndices.count >= 4 {
                LinearStaticSolver.assembleC3D4Stiffness(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    lambda: lambda,
                    mu: mu,
                    K: &K
                )
            }
        }

        // 3. Assemble lumped mass matrix M (diagonal array)
        var M = [Double](repeating: 0.0, count: totalDOFs)
        var nodalMass = [Double](repeating: 0.0, count: nodeCount)

        for element in mesh.elements {
            let volume = LinearStaticSolver.computeTetrahedronVolume(
                el: element,
                positions: positions,
                nodeIndexById: nodeIndexById
            )
            guard volume > 1e-15 else { continue }
            let elMass = rho * volume

            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                let nodeLump = elMass / 10.0
                let indices = element.nodeIndices.prefix(10).compactMap { nodeIndexById[$0] }
                for nIdx in indices {
                    nodalMass[nIdx] += nodeLump
                }
            } else if element.nodeIndices.count >= 4 {
                let nodeLump = elMass / 4.0
                let indices = element.nodeIndices.prefix(4).compactMap { nodeIndexById[$0] }
                for nIdx in indices {
                    nodalMass[nIdx] += nodeLump
                }
            }
        }

        for i in 0..<nodeCount {
            let m = nodalMass[i]
            M[3 * i + 0] = m
            M[3 * i + 1] = m
            M[3 * i + 2] = m
        }

        // 4. Optional Prestress: Evaluate initial static equilibrium and add geometric stiffness K_sigma
        if study.solver.isPrestressEnabled && !study.loads.isEmpty {
            let staticResult = try LinearStaticSolver.solve(
                study: study,
                mesh: mesh,
                youngsModulus: E,
                poissonsRatio: nu,
                lengthScaleToMeters: lengthScaleToMeters
            )

            // Convert static nodal displacements from mm to meters
            var nodalUMeters = [Double](repeating: 0.0, count: totalDOFs)
            for (nId, dispMm) in staticResult.nodalDisplacements {
                guard let nIdx = nodeIndexById[nId] else { continue }
                nodalUMeters[3 * nIdx + 0] = dispMm.x * 0.001
                nodalUMeters[3 * nIdx + 1] = dispMm.y * 0.001
                nodalUMeters[3 * nIdx + 2] = dispMm.z * 0.001
            }

            // Assemble geometric stiffness K_sigma
            for element in mesh.elements {
                if element.order == .quadratic && element.nodeIndices.count >= 10 {
                    assembleC3D10GeometricStiffness(
                        element: element,
                        positions: positions,
                        nodeIndexById: nodeIndexById,
                        nodalU: nodalUMeters,
                        lambda: lambda,
                        mu: mu,
                        K: &K
                    )
                } else if element.nodeIndices.count >= 4 {
                    assembleC3D4GeometricStiffness(
                        element: element,
                        positions: positions,
                        nodeIndexById: nodeIndexById,
                        nodalU: nodalUMeters,
                        lambda: lambda,
                        mu: mu,
                        K: &K
                    )
                }
            }
        }

        // 5. Resolve geometry sets for fixtures
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

        var dirichletDOFs = Set<Int>()

        for fixture in study.fixtures {
            let matchedSet = (mesh.sets.first(where: { $0.name == fixture.name }))
                ?? setById[fixture.id]
                ?? fixture.targetReferences.compactMap({ setByName[$0.targetName] ?? setById[$0.targetId] }).first
                ?? fixture.groupNames.compactMap({ setByName[$0] }).first
                ?? setByName[fixture.name]

            let targetNodeIds = Set(matchedSet?.nodeIds ?? [])
            let nodeIdsToConstrain: [Int]
            if !targetNodeIds.isEmpty && !(fixture.targetReferences.isEmpty && fixture.groupNames.isEmpty && targetNodeIds.count >= mesh.nodes.count) {
                nodeIdsToConstrain = Array(targetNodeIds)
            } else if fixture.targetReferences.isEmpty && fixture.groupNames.isEmpty {
                // If no target is named, constrain the first boundary surface triangle to prevent rigid body motion while leaving remaining volume nodes free for modal vibration
                if let firstTri = mesh.surfaceTriangles.first, firstTri.nodeIndices.prefix(3).count < mesh.nodes.count {
                    nodeIdsToConstrain = Array(firstTri.nodeIndices.prefix(3))
                } else {
                    nodeIdsToConstrain = Array(mesh.nodes.prefix(max(1, mesh.nodes.count - 1)).map(\.id))
                }
            } else {
                throw CAEErrorCode.invalidStudyConfiguration(
                    message: "Fixture '\(fixture.name)' targets geometry that could not be mapped to any mesh nodes."
                )
            }

            for nId in nodeIdsToConstrain {
                guard let nodeIdx = nodeIndexById[nId] else { continue }
                switch fixture.kind {
                case .fixed, .pinned:
                    dirichletDOFs.insert(3 * nodeIdx + 0)
                    dirichletDOFs.insert(3 * nodeIdx + 1)
                    dirichletDOFs.insert(3 * nodeIdx + 2)
                case .rollerSlider, .symmetry, .prescribedDisplacement:
                    if fixture.isRestrainedX { dirichletDOFs.insert(3 * nodeIdx + 0) }
                    if fixture.isRestrainedY { dirichletDOFs.insert(3 * nodeIdx + 1) }
                    if fixture.isRestrainedZ { dirichletDOFs.insert(3 * nodeIdx + 2) }
                case .elasticSupport:
                    let kPerNode = fixture.elasticStiffness / Double(max(1, nodeIdsToConstrain.count))
                    if fixture.isRestrainedX && kPerNode.x > 0 {
                        let dof = 3 * nodeIdx + 0
                        K[dof][dof] = (K[dof][dof] ?? 0.0) + kPerNode.x
                    }
                    if fixture.isRestrainedY && kPerNode.y > 0 {
                        let dof = 3 * nodeIdx + 1
                        K[dof][dof] = (K[dof][dof] ?? 0.0) + kPerNode.y
                    }
                    if fixture.isRestrainedZ && kPerNode.z > 0 {
                        let dof = 3 * nodeIdx + 2
                        K[dof][dof] = (K[dof][dof] ?? 0.0) + kPerNode.z
                    }
                }
            }
        }

        if dirichletDOFs.isEmpty {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Modal frequency analysis requires fixed degrees of freedom to prevent rigid body motion."
            )
        }

        // Apply symmetric Dirichlet elimination on K and zero Dirichlet entries in M
        for dIdx in dirichletDOFs {
            K[dIdx].removeAll(keepingCapacity: true)
            K[dIdx][dIdx] = 1.0
            M[dIdx] = 0.0
        }
        for i in 0..<totalDOFs where !dirichletDOFs.contains(i) {
            for col in K[i].keys where dirichletDOFs.contains(col) {
                K[i].removeValue(forKey: col)
            }
        }

        // 6. Clamp requested mode count to available free degrees of freedom
        let freeDOFCount = totalDOFs - dirichletDOFs.count
        guard freeDOFCount > 0 else {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "No free degrees of freedom available for modal eigenvalue solution."
            )
        }

        let requestedModeCount = max(1, study.solver.modeCount)
        let modeCountToExtract = min(requestedModeCount, freeDOFCount)

        // 7. Deflated Inverse Power Iteration with Jacobi-PCG and M-Orthogonalization
        var modeVectors: [[Double]] = []
        var naturalFrequenciesHz: [Double] = []
        var totalIterations = 0
        var finalResidual = 0.0

        var dirichletDict: [Int: Double] = [:]
        dirichletDict.reserveCapacity(dirichletDOFs.count)
        for d in dirichletDOFs {
            dirichletDict[d] = 0.0
        }

        let maxPowerIterations = 50
        let pcgMaxIter = max(2000, study.solver.maxIterations * 40)
        let pcgTol = 1e-5

        for m in 0..<modeCountToExtract {
            // Seed trial vector deterministically
            var v = [Double](repeating: 0.0, count: totalDOFs)
            var seed = UInt64(0x9E3779B97F4A7C15 &+ UInt64(m) &* 0xBF58476D1CE4E5B9)

            for i in 0..<totalDOFs where !dirichletDOFs.contains(i) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let randVal = (Double(seed >> 33) / Double(1 << 31)) - 0.5
                let spatialMod = Double(i % 7) * 0.1
                v[i] = randVal + spatialMod
            }

            // Project v against previously converged modes
            for phi in modeVectors {
                let alpha = dotM(phi, v, M: M)
                for i in 0..<totalDOFs {
                    v[i] -= alpha * phi[i]
                }
            }

            var normVM = sqrt(dotM(v, v, M: M))
            if normVM < 1e-15 {
                // Fallback deterministic perturbation if vector collapsed
                for i in 0..<totalDOFs where !dirichletDOFs.contains(i) {
                    v[i] = 1.0 + Double(i % 13) * 0.05
                }
                for phi in modeVectors {
                    let alpha = dotM(phi, v, M: M)
                    for i in 0..<totalDOFs {
                        v[i] -= alpha * phi[i]
                    }
                }
                normVM = sqrt(dotM(v, v, M: M))
            }

            if normVM > 1e-15 {
                let invNorm = 1.0 / normVM
                for i in 0..<totalDOFs { v[i] *= invNorm }
            }

            var lambdaCurrent = 0.0
            var lambdaPrev = Double.infinity

            for iter in 1...maxPowerIterations {
                totalIterations += 1

                // Form right-hand side b = M * v
                var b = [Double](repeating: 0.0, count: totalDOFs)
                for i in 0..<totalDOFs {
                    b[i] = M[i] * v[i]
                }

                // Solve K * w = b using Jacobi-PCG
                let (w, _, res) = LinearStaticSolver.solvePCG(
                    K: K,
                    b: b,
                    dirichlet: dirichletDict,
                    maxIterations: pcgMaxIter,
                    tolerance: pcgTol
                )
                finalResidual = res

                var wVec = w
                for d in dirichletDOFs {
                    wVec[d] = 0.0
                }

                // Modified Gram-Schmidt twice for numerical stability
                for phi in modeVectors {
                    for _ in 0..<2 {
                        let alpha = dotM(phi, wVec, M: M)
                        for i in 0..<totalDOFs {
                            wVec[i] -= alpha * phi[i]
                        }
                    }
                }

                let wMw = dotM(wVec, wVec, M: M)
                guard wMw > 1e-30 else { break }

                let wMv = dotM(wVec, v, M: M)
                lambdaCurrent = wMv / wMw

                let normW = sqrt(wMw)
                let invNormW = 1.0 / normW
                for i in 0..<totalDOFs {
                    v[i] = wVec[i] * invNormW
                }

                let relDelta = abs(lambdaCurrent - lambdaPrev) / max(abs(lambdaCurrent), 1e-6)
                lambdaPrev = lambdaCurrent

                if relDelta < 1e-6 && iter >= 3 {
                    break
                }
            }

            modeVectors.append(v)

            // Clamp non-positive eigenvalues to 0.0 Hz (e.g. compressive buckling limit)
            let freqHz = lambdaCurrent > 0.0 ? (sqrt(lambdaCurrent) / (2.0 * .pi)) : 0.0
            naturalFrequenciesHz.append(freqHz)
        }

        // 8. Build SimulationModeShape structs with unit-peak normalized nodal displacements
        var modeShapes: [SimulationModeShape] = []
        modeShapes.reserveCapacity(modeVectors.count)

        for (mIdx, v) in modeVectors.enumerated() {
            var peakMag = 0.0
            var rawDisplacements = [Int: SIMD3<Double>](minimumCapacity: nodeCount)

            for (idx, nId) in nodeIds.enumerated() {
                let disp = SIMD3<Double>(v[3 * idx + 0], v[3 * idx + 1], v[3 * idx + 2])
                let mag = simd_length(disp)
                peakMag = max(peakMag, mag)
                rawDisplacements[nId] = disp
            }

            let normFactor = peakMag > 1e-15 ? (1.0 / peakMag) : 1.0
            var normalizedDisplacements = [Int: SIMD3<Double>](minimumCapacity: nodeCount)
            for (nId, disp) in rawDisplacements {
                normalizedDisplacements[nId] = disp * normFactor
            }

            let modeShape = SimulationModeShape(
                modeNumber: mIdx + 1,
                frequencyHz: naturalFrequenciesHz[mIdx],
                nodalDisplacements: normalizedDisplacements
            )
            modeShapes.append(modeShape)
        }

        // Sort mode shapes monotonically by natural frequency
        modeShapes.sort { $0.frequencyHz < $1.frequencyHz }
        for i in 0..<modeShapes.count {
            modeShapes[i].modeNumber = i + 1
        }

        // 9. Assemble summary field extrema
        var extrema: [SimulationFieldExtrema] = []
        if let firstMode = modeShapes.first, let lastMode = modeShapes.last {
            extrema.append(
                SimulationFieldExtrema(
                    fieldName: "Natural Frequency",
                    unitSymbol: "Hz",
                    minValue: firstMode.frequencyHz,
                    maxValue: lastMode.frequencyHz
                )
            )
            extrema.append(
                SimulationFieldExtrema(
                    fieldName: "Mode 1 Displacement",
                    unitSymbol: "mm",
                    minValue: 0.0,
                    maxValue: 1.0
                )
            )
        }

        let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                      Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

        return ModalFrequencyResult(
            modeShapes: modeShapes,
            extrema: extrema,
            iterationCount: totalIterations,
            finalResidual: finalResidual,
            runtimeDuration: elapsed
        )
    }

    // MARK: - Internal Helpers

    @inline(__always)
    private static func dotM(_ u: [Double], _ v: [Double], M: [Double]) -> Double {
        var sum = 0.0
        let count = u.count
        for i in 0..<count {
            sum += u[i] * M[i] * v[i]
        }
        return sum
    }

    // MARK: - Geometric Stiffness Assembly (C3D4 Linear Tetrahedra)

    private static func assembleC3D4GeometricStiffness(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        nodalU: [Double],
        lambda: Double,
        mu: Double,
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

        let C: [[Double]] = [
            [1.0, p0.x, p0.y, p0.z],
            [1.0, p1.x, p1.y, p1.z],
            [1.0, p2.x, p2.y, p2.z],
            [1.0, p3.x, p3.y, p3.z]
        ]
        guard let Cinv = LinearStaticSolver.invert4x4(C) else { return }

        var gradN = [SIMD3<Double>](repeating: .zero, count: 4)
        for i in 0..<4 {
            gradN[i] = SIMD3<Double>(Cinv[1][i], Cinv[2][i], Cinv[3][i])
        }

        var exx = 0.0, eyy = 0.0, ezz = 0.0
        var exy = 0.0, eyz = 0.0, ezx = 0.0

        for a in 0..<4 {
            let nIdx = indices[a]
            let ux = nodalU[3 * nIdx + 0]
            let uy = nodalU[3 * nIdx + 1]
            let uz = nodalU[3 * nIdx + 2]
            let g = gradN[a]

            exx += g.x * ux
            eyy += g.y * uy
            ezz += g.z * uz
            exy += 0.5 * (g.y * ux + g.x * uy)
            eyz += 0.5 * (g.z * uy + g.y * uz)
            ezx += 0.5 * (g.x * uz + g.z * ux)
        }

        let trace = exx + eyy + ezz
        let sxx = lambda * trace + 2.0 * mu * exx
        let syy = lambda * trace + 2.0 * mu * eyy
        let szz = lambda * trace + 2.0 * mu * ezz
        let sxy = 2.0 * mu * exy
        let syz = 2.0 * mu * eyz
        let szx = 2.0 * mu * ezx

        // Node pairs geometric stiffness: K_sigma,ab = volume * (gradN_a^T * sigma * gradN_b) * I_3x3
        for a in 0..<4 {
            let rowNode = indices[a]
            let ga = gradN[a]
            for b in 0..<4 {
                let colNode = indices[b]
                let gb = gradN[b]

                let sigX = sxx * gb.x + sxy * gb.y + szx * gb.z
                let sigY = sxy * gb.x + syy * gb.y + syz * gb.z
                let sigZ = szx * gb.x + syz * gb.y + szz * gb.z
                let sab = volume * (ga.x * sigX + ga.y * sigY + ga.z * sigZ)

                for k in 0..<3 {
                    let r = 3 * rowNode + k
                    let c = 3 * colNode + k
                    K[r][c, default: 0.0] += sab
                }
            }
        }
    }

    // MARK: - Geometric Stiffness Assembly (C3D10 Quadratic Tetrahedra)

    private static func assembleC3D10GeometricStiffness(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        nodalU: [Double],
        lambda: Double,
        mu: Double,
        K: inout [[Int: Double]]
    ) {
        let indices = element.nodeIndices.prefix(10).compactMap { nodeIndexById[$0] }
        guard indices.count == 10 else { return }

        let p = indices.map { positions[$0] }

        // 4-point symmetric Gauss quadrature on tetrahedra
        let alpha = (5.0 - sqrt(5.0)) / 20.0
        let beta = (5.0 + 3.0 * sqrt(5.0)) / 20.0
        let quadPoints: [(SIMD4<Double>, Double)] = [
            (SIMD4<Double>(beta, alpha, alpha, alpha), 1.0 / 24.0),
            (SIMD4<Double>(alpha, beta, alpha, alpha), 1.0 / 24.0),
            (SIMD4<Double>(alpha, alpha, beta, alpha), 1.0 / 24.0),
            (SIMD4<Double>(alpha, alpha, alpha, beta), 1.0 / 24.0)
        ]

        for (L, weight) in quadPoints {
            let dNdL = LinearStaticSolver.evaluateC3D10LocalGradients(L: L)

            var J = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero)
            for a in 0..<10 {
                let grad = dNdL[a]
                J.0 += grad.x * p[a]
                J.1 += grad.y * p[a]
                J.2 += grad.z * p[a]
            }

            let detJ = simd_dot(simd_cross(J.0, J.1), J.2)
            guard detJ > 1e-15, let Jinv = LinearStaticSolver.invert3x3(J) else { continue }

            var gradN = [SIMD3<Double>](repeating: .zero, count: 10)
            for a in 0..<10 {
                gradN[a] = LinearStaticSolver.multiply3x3(Jinv, dNdL[a])
            }

            var exx = 0.0, eyy = 0.0, ezz = 0.0
            var exy = 0.0, eyz = 0.0, ezx = 0.0

            for a in 0..<10 {
                let nIdx = indices[a]
                let ux = nodalU[3 * nIdx + 0]
                let uy = nodalU[3 * nIdx + 1]
                let uz = nodalU[3 * nIdx + 2]
                let g = gradN[a]

                exx += g.x * ux
                eyy += g.y * uy
                ezz += g.z * uz
                exy += 0.5 * (g.y * ux + g.x * uy)
                eyz += 0.5 * (g.z * uy + g.y * uz)
                ezx += 0.5 * (g.x * uz + g.z * ux)
            }

            let trace = exx + eyy + ezz
            let sxx = lambda * trace + 2.0 * mu * exx
            let syy = lambda * trace + 2.0 * mu * eyy
            let szz = lambda * trace + 2.0 * mu * ezz
            let sxy = 2.0 * mu * exy
            let syz = 2.0 * mu * eyz
            let szx = 2.0 * mu * ezx

            let dOmega = weight * detJ

            for a in 0..<10 {
                let rowNode = indices[a]
                let ga = gradN[a]
                for b in 0..<10 {
                    let colNode = indices[b]
                    let gb = gradN[b]

                    let sigX = sxx * gb.x + sxy * gb.y + szx * gb.z
                    let sigY = sxy * gb.x + syy * gb.y + syz * gb.z
                    let sigZ = szx * gb.x + syz * gb.y + szz * gb.z
                    let sab = dOmega * (ga.x * sigX + ga.y * sigY + ga.z * sigZ)

                    for k in 0..<3 {
                        let r = 3 * rowNode + k
                        let c = 3 * colNode + k
                        K[r][c, default: 0.0] += sab
                    }
                }
            }
        }
    }
}
