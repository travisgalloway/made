import Foundation
import simd

/// Numerical solution results for linear buckling finite element analysis (ADR-D5, BL-FEA-08, #226).
public struct LinearBucklingResult: Sendable, Codable, Equatable, Hashable {
    public var modes: [SimulationBucklingMode]
    public var extrema: [SimulationFieldExtrema]
    public var iterationCount: Int
    public var finalResidual: Double
    public var runtimeDuration: Double

    public init(
        modes: [SimulationBucklingMode] = [],
        extrema: [SimulationFieldExtrema] = [],
        iterationCount: Int = 0,
        finalResidual: Double = 0.0,
        runtimeDuration: Double = 0.0
    ) {
        self.modes = modes
        self.extrema = extrema
        self.iterationCount = iterationCount
        self.finalResidual = finalResidual
        self.runtimeDuration = runtimeDuration
    }
}

/// Pure-Swift finite element solver for linear elastic buckling analysis governed by $(\mathbf{K}_e + \lambda \mathbf{K}_\sigma) \boldsymbol{\phi} = \mathbf{0}$ (ADR-D5, BL-FEA-08, #226).
public enum LinearBucklingSolver: Sendable {

    /// Solves the linear buckling generalized eigenvalue problem for a given simulation study and volume mesh.
    ///
    /// - Parameters:
    ///   - study: CAE simulation study containing materials, boundary conditions, reference loads, and solver controls.
    ///   - mesh: Discretized tetrahedral volume mesh (C3D4 or C3D10 elements).
    ///   - youngsModulus: Optional override for Young's modulus $E$ in Pascals ($\text{N}/\text{m}^2$).
    ///   - poissonsRatio: Optional override for Poisson's ratio $\nu$.
    ///   - lengthScaleToMeters: Geometric length scale factor converting mesh coordinates to SI meters (default `1.0`).
    /// - Returns: `LinearBucklingResult` containing extracted buckling modes, field extrema, and solve statistics.
    public static func solve(
        study: SimulationStudy,
        mesh: VolumeMesh,
        youngsModulus: Double? = nil,
        poissonsRatio: Double? = nil,
        lengthScaleToMeters: Double = 1.0
    ) throws -> LinearBucklingResult {
        let startTime = ContinuousClock.now

        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            throw CAEErrorCode.invalidStudyConfiguration(message: "Mesh contains no nodes or elements.")
        }

        // 1. Resolve material elastic properties (Young's modulus E, Poisson's ratio nu, density rho)
        var E: Double
        var nu: Double
        var rho: Double = 7850.0

        if let y = youngsModulus, let p = poissonsRatio {
            E = y
            nu = p
            if let matId = study.materials.first?.materialId,
               let mat = MaterialLibrary.standard.material(withId: matId) {
                if mat.densityKgPerM3 > 0 { rho = mat.densityKgPerM3 }
            }
        } else {
            let matId = study.materials.first?.materialId
            let mat = matId.flatMap { MaterialLibrary.standard.material(withId: $0) }
            if let mat {
                E = youngsModulus ?? (mat.youngsModulusGPa * 1e9)
                nu = poissonsRatio ?? mat.poissonsRatioValue
                if mat.densityKgPerM3 > 0 { rho = mat.densityKgPerM3 }
            } else {
                E = youngsModulus ?? 200e9 // 200 GPa
                nu = poissonsRatio ?? 0.3
            }
        }

        guard E > 0.0, nu > -1.0, nu < 0.5 else {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Non-physical material properties: E=\(E) Pa, nu=\(nu). Buckling analysis requires E > 0 and -1 < nu < 0.5."
            )
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

        // Global elastic stiffness matrix K_e and reference load vector F_ref
        var Ke: [[Int: Double]] = Array(repeating: [:], count: totalDOFs)
        var Fref = [Double](repeating: 0.0, count: totalDOFs)

        // 2. Assemble small-displacement elastic stiffness matrix K_e
        for element in mesh.elements {
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                LinearStaticSolver.assembleC3D10Stiffness(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    lambda: lambda,
                    mu: mu,
                    K: &Ke
                )
            } else if element.nodeIndices.count >= 4 {
                LinearStaticSolver.assembleC3D4Stiffness(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    lambda: lambda,
                    mu: mu,
                    K: &Ke
                )
            }
        }

        // 3. Resolve geometry sets for fixtures and loads
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

        let boundaryTriangles = LinearStaticSolver.getEffectiveBoundaryTriangles(mesh: mesh)

        // 4. Assemble Dirichlet constraints (fixtures)
        if study.fixtures.isEmpty {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Simulation study has no fixtures configured. Structural analysis requires boundary constraints to prevent rigid body motion."
            )
        }

        var dirichletDOFs: [Int: Double] = [:]
        var elasticDOFs: Set<Int> = []

        for fixture in study.fixtures {
            let matchedSet = (mesh.sets.first(where: { $0.name == fixture.name }))
                ?? setById[fixture.id]
                ?? fixture.targetReferences.compactMap({ setByName[$0.targetName] ?? setById[$0.targetId] }).first
                ?? fixture.groupNames.compactMap({ setByName[$0] }).first
                ?? setByName[fixture.name]

            let hasExplicitTargets = !fixture.targetReferences.isEmpty || !fixture.groupNames.isEmpty
            let targetNodeIds = Set(matchedSet?.nodeIds ?? [])
            let nodeIdsToConstrain: [Int]
            if hasExplicitTargets && !targetNodeIds.isEmpty {
                nodeIdsToConstrain = Array(targetNodeIds)
            } else if !targetNodeIds.isEmpty && targetNodeIds.count < mesh.nodes.count {
                nodeIdsToConstrain = Array(targetNodeIds)
            } else if fixture.targetReferences.isEmpty && fixture.groupNames.isEmpty {
                let allBoundary = Array(Set(boundaryTriangles.flatMap { $0.nodeIndices.prefix(3) }))
                if allBoundary.count > 3, let firstTri = boundaryTriangles.first {
                    nodeIdsToConstrain = Array(firstTri.nodeIndices.prefix(3))
                } else {
                    nodeIdsToConstrain = allBoundary
                }
            } else {
                throw CAEErrorCode.invalidStudyConfiguration(
                    message: "Fixture '\(fixture.name)' targets geometry that could not be mapped to any mesh nodes."
                )
            }

            if fixture.kind == .elasticSupport {
                let kPerNode = fixture.elasticStiffness / Double(max(1, nodeIdsToConstrain.count))
                for nId in nodeIdsToConstrain {
                    guard let nodeIdx = nodeIndexById[nId] else { continue }
                    if fixture.isRestrainedX && kPerNode.x > 0 {
                        let dof = 3 * nodeIdx + 0
                        Ke[dof][dof] = (Ke[dof][dof] ?? 0.0) + kPerNode.x
                        elasticDOFs.insert(dof)
                    }
                    if fixture.isRestrainedY && kPerNode.y > 0 {
                        let dof = 3 * nodeIdx + 1
                        Ke[dof][dof] = (Ke[dof][dof] ?? 0.0) + kPerNode.y
                        elasticDOFs.insert(dof)
                    }
                    if fixture.isRestrainedZ && kPerNode.z > 0 {
                        let dof = 3 * nodeIdx + 2
                        Ke[dof][dof] = (Ke[dof][dof] ?? 0.0) + kPerNode.z
                        elasticDOFs.insert(dof)
                    }
                }
            } else {
                let dispMeters = fixture.kind == .prescribedDisplacement
                    ? (fixture.prescribedDisplacement * 0.001)
                    : SIMD3<Double>.zero

                for nId in nodeIdsToConstrain {
                    guard let nodeIdx = nodeIndexById[nId] else { continue }
                    switch fixture.kind {
                    case .fixed, .pinned:
                        dirichletDOFs[3 * nodeIdx + 0] = 0.0
                        dirichletDOFs[3 * nodeIdx + 1] = 0.0
                        dirichletDOFs[3 * nodeIdx + 2] = 0.0
                    case .rollerSlider, .symmetry:
                        if fixture.isRestrainedX { dirichletDOFs[3 * nodeIdx + 0] = 0.0 }
                        if fixture.isRestrainedY { dirichletDOFs[3 * nodeIdx + 1] = 0.0 }
                        if fixture.isRestrainedZ { dirichletDOFs[3 * nodeIdx + 2] = 0.0 }
                    case .prescribedDisplacement:
                        if fixture.isRestrainedX { dirichletDOFs[3 * nodeIdx + 0] = dispMeters.x }
                        if fixture.isRestrainedY { dirichletDOFs[3 * nodeIdx + 1] = dispMeters.y }
                        if fixture.isRestrainedZ { dirichletDOFs[3 * nodeIdx + 2] = dispMeters.z }
                    case .elasticSupport:
                        break
                    }
                }
            }
        }

        let totalRestrainedDOFs = Set(dirichletDOFs.keys).union(elasticDOFs).count
        if totalRestrainedDOFs < 6 {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Structural system is under-constrained (\(totalRestrainedDOFs) restrained DOFs; at least 6 required to prevent rigid body motion)."
            )
        }

        // 5. Assemble reference loads
        if study.loads.isEmpty {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Applied reference loads produce zero internal stress; linear buckling eigenvalues cannot be evaluated."
            )
        }

        for load in study.loads {
            let matchedSet = (mesh.sets.first(where: { $0.name == load.name }))
                ?? setById[load.id]
                ?? load.targetReferences.compactMap({ setByName[$0.targetName] ?? setById[$0.targetId] }).first
                ?? load.groupNames.compactMap({ setByName[$0] }).first
                ?? setByName[load.name]

            let targetNodeIds = Set(matchedSet?.nodeIds ?? [])
            let targetElementIds = Set(matchedSet?.elementIds ?? [])

            switch load.kind {
            case .force:
                if load.forceDistribution == .perUnitArea {
                    let tractionPa = load.direction * load.magnitude
                    for tri in boundaryTriangles {
                        if !targetElementIds.isEmpty && !targetElementIds.contains(tri.id) { continue }
                        let c = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
                        guard c.count == 3 else { continue }
                        let p0 = positions[c[0]], p1 = positions[c[1]], p2 = positions[c[2]]
                        let normal = simd_cross(p1 - p0, p2 - p0)
                        let area = simd_length(normal) * 0.5
                        guard area > 1e-15 else { continue }
                        let nodalForce = (tractionPa * area) / 3.0
                        for nodeIdx in c {
                            Fref[3 * nodeIdx + 0] += nodalForce.x
                            Fref[3 * nodeIdx + 1] += nodalForce.y
                            Fref[3 * nodeIdx + 2] += nodalForce.z
                        }
                    }
                } else {
                    let hasExplicitTargets = !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                    let nodesToUse: [Int]
                    if hasExplicitTargets && !targetNodeIds.isEmpty {
                        nodesToUse = Array(targetNodeIds)
                    } else if !targetNodeIds.isEmpty && targetNodeIds.count < mesh.nodes.count {
                        nodesToUse = Array(targetNodeIds)
                    } else {
                        let unconstrained = mesh.nodes.map { $0.id }.filter { nId in
                            guard let idx = nodeIndexById[nId] else { return false }
                            return dirichletDOFs[3 * idx] == nil || dirichletDOFs[3 * idx + 1] == nil || dirichletDOFs[3 * idx + 2] == nil
                        }
                        nodesToUse = !unconstrained.isEmpty ? unconstrained : (mesh.nodes.last.map { [$0.id] } ?? [])
                    }
                    guard !nodesToUse.isEmpty else { continue }
                    let forcePerNode = (load.direction * load.magnitude) / Double(nodesToUse.count)
                    for nId in nodesToUse {
                        guard let nodeIdx = nodeIndexById[nId] else { continue }
                        Fref[3 * nodeIdx + 0] += forcePerNode.x
                        Fref[3 * nodeIdx + 1] += forcePerNode.y
                        Fref[3 * nodeIdx + 2] += forcePerNode.z
                    }
                }

            case .pressure:
                let pPa = load.magnitude
                for tri in boundaryTriangles {
                    if !targetElementIds.isEmpty && !targetElementIds.contains(tri.id) { continue }
                    let c = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
                    guard c.count == 3 else { continue }
                    let p0 = positions[c[0]], p1 = positions[c[1]], p2 = positions[c[2]]
                    let rawNormal = simd_cross(p1 - p0, p2 - p0)
                    let area2 = simd_length(rawNormal)
                    guard area2 > 1e-15 else { continue }
                    let normal = rawNormal / area2
                    let area = area2 * 0.5
                    let nodalForce = (-normal * (pPa * area)) / 3.0
                    for nodeIdx in c {
                        Fref[3 * nodeIdx + 0] += nodalForce.x
                        Fref[3 * nodeIdx + 1] += nodalForce.y
                        Fref[3 * nodeIdx + 2] += nodalForce.z
                    }
                }

            case .gravity:
                let gVec = load.direction * load.magnitude
                for element in mesh.elements {
                    if !targetElementIds.isEmpty && !targetElementIds.contains(element.id) { continue }
                    let elIndices = element.nodeIndices.compactMap { nodeIndexById[$0] }
                    guard elIndices.count >= 4 else { continue }
                    let vol = LinearStaticSolver.computeTetrahedronVolume(el: element, positions: positions, nodeIndexById: nodeIndexById)
                    guard vol > 1e-15 else { continue }
                    let count = Double(element.order == .quadratic && elIndices.count >= 10 ? 10 : 4)
                    let nodeForce = (rho * vol * gVec) / count
                    for i in 0..<Int(count) {
                        let nodeIdx = elIndices[i]
                        Fref[3 * nodeIdx + 0] += nodeForce.x
                        Fref[3 * nodeIdx + 1] += nodeForce.y
                        Fref[3 * nodeIdx + 2] += nodeForce.z
                    }
                }

            default:
                break
            }
        }

        // 6. Pre-buckling static equilibrium solve: K_e u_0 = F_ref
        var KeElim = Ke
        var FrefElim = Fref

        for (dIdx, dVal) in dirichletDOFs {
            for j in 0..<totalDOFs {
                if j != dIdx, let kjd = KeElim[j][dIdx] {
                    FrefElim[j] -= kjd * dVal
                    KeElim[j].removeValue(forKey: dIdx)
                }
            }
            KeElim[dIdx].removeAll(keepingCapacity: true)
            KeElim[dIdx][dIdx] = 1.0
            FrefElim[dIdx] = dVal
        }

        let maxStaticIter = max(5000, study.solver.maxIterations * 50)
        let staticTol = 1e-9
        let (solutionU0, staticIterCount, _) = LinearStaticSolver.solvePCG(
            K: KeElim,
            b: FrefElim,
            dirichlet: dirichletDOFs,
            maxIterations: maxStaticIter,
            tolerance: staticTol
        )

        // 7. Recover pre-buckling stresses and assemble geometric stiffness matrix K_sigma
        var Ksigma: [[Int: Double]] = Array(repeating: [:], count: totalDOFs)
        var maxStressPa = 0.0

        for element in mesh.elements {
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                let indices = element.nodeIndices.prefix(10).compactMap { nodeIndexById[$0] }
                guard indices.count == 10 else { continue }
                let p = indices.map { positions[$0] }

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
                    let absDetJ = abs(detJ)
                    guard absDetJ > 1e-15, let Jinv = LinearStaticSolver.invert3x3(J) else { continue }
                    let dOmega = weight * absDetJ

                    var gradN = [SIMD3<Double>](repeating: .zero, count: 10)
                    for a in 0..<10 {
                        gradN[a] = LinearStaticSolver.multiply3x3(Jinv, dNdL[a])
                    }

                    var exx = 0.0, eyy = 0.0, ezz = 0.0
                    var exy = 0.0, eyz = 0.0, ezx = 0.0
                    for a in 0..<10 {
                        let nIdx = indices[a]
                        let ux = solutionU0[3 * nIdx + 0]
                        let uy = solutionU0[3 * nIdx + 1]
                        let uz = solutionU0[3 * nIdx + 2]
                        let g = gradN[a]
                        exx += g.x * ux
                        eyy += g.y * uy
                        ezz += g.z * uz
                        exy += 0.5 * (g.y * ux + g.x * uy)
                        eyz += 0.5 * (g.z * uy + g.y * uz)
                        ezx += 0.5 * (g.x * uz + g.z * ux)
                    }

                    let tr = exx + eyy + ezz
                    let sxx = lambda * tr + 2.0 * mu * exx
                    let syy = lambda * tr + 2.0 * mu * eyy
                    let szz = lambda * tr + 2.0 * mu * ezz
                    let sxy = 2.0 * mu * exy
                    let syz = 2.0 * mu * eyz
                    let szx = 2.0 * mu * ezx

                    maxStressPa = max(maxStressPa, max(abs(sxx), max(abs(syy), max(abs(szz), max(abs(sxy), max(abs(syz), abs(szx)))))))

                    for a in 0..<10 {
                        let rowNode = indices[a]
                        let ga = gradN[a]
                        for b in 0..<10 {
                            let colNode = indices[b]
                            let gb = gradN[b]
                            let tx = sxx * gb.x + sxy * gb.y + szx * gb.z
                            let ty = sxy * gb.x + syy * gb.y + syz * gb.z
                            let tz = szx * gb.x + syz * gb.y + szz * gb.z
                            let sab = dOmega * (ga.x * tx + ga.y * ty + ga.z * tz)

                            Ksigma[3 * rowNode + 0][3 * colNode + 0, default: 0.0] += sab
                            Ksigma[3 * rowNode + 1][3 * colNode + 1, default: 0.0] += sab
                            Ksigma[3 * rowNode + 2][3 * colNode + 2, default: 0.0] += sab
                        }
                    }
                }
            } else if element.nodeIndices.count >= 4 {
                let indices = element.nodeIndices.prefix(4).compactMap { nodeIndexById[$0] }
                guard indices.count == 4 else { continue }

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
                guard let Cinv = LinearStaticSolver.invert4x4(C) else { continue }
                let vol = LinearStaticSolver.computeTetrahedronVolume(el: element, positions: positions, nodeIndexById: nodeIndexById)
                guard vol > 1e-15 else { continue }

                var gradN = [SIMD3<Double>](repeating: .zero, count: 4)
                for i in 0..<4 {
                    gradN[i] = SIMD3<Double>(Cinv[1][i], Cinv[2][i], Cinv[3][i])
                }

                var exx = 0.0, eyy = 0.0, ezz = 0.0
                var exy = 0.0, eyz = 0.0, ezx = 0.0
                for a in 0..<4 {
                    let nIdx = indices[a]
                    let ux = solutionU0[3 * nIdx + 0]
                    let uy = solutionU0[3 * nIdx + 1]
                    let uz = solutionU0[3 * nIdx + 2]
                    let g = gradN[a]
                    exx += g.x * ux
                    eyy += g.y * uy
                    ezz += g.z * uz
                    exy += 0.5 * (g.y * ux + g.x * uy)
                    eyz += 0.5 * (g.z * uy + g.y * uz)
                    ezx += 0.5 * (g.x * uz + g.z * ux)
                }

                let tr = exx + eyy + ezz
                let sxx = lambda * tr + 2.0 * mu * exx
                let syy = lambda * tr + 2.0 * mu * eyy
                let szz = lambda * tr + 2.0 * mu * ezz
                let sxy = 2.0 * mu * exy
                let syz = 2.0 * mu * eyz
                let szx = 2.0 * mu * ezx

                maxStressPa = max(maxStressPa, max(abs(sxx), max(abs(syy), max(abs(szz), max(abs(sxy), max(abs(syz), abs(szx)))))))

                for a in 0..<4 {
                    let rowNode = indices[a]
                    let ga = gradN[a]
                    for b in 0..<4 {
                        let colNode = indices[b]
                        let gb = gradN[b]
                        let tx = sxx * gb.x + sxy * gb.y + szx * gb.z
                        let ty = sxy * gb.x + syy * gb.y + syz * gb.z
                        let tz = szx * gb.x + syz * gb.y + szz * gb.z
                        let sab = vol * (ga.x * tx + ga.y * ty + ga.z * tz)

                        Ksigma[3 * rowNode + 0][3 * colNode + 0, default: 0.0] += sab
                        Ksigma[3 * rowNode + 1][3 * colNode + 1, default: 0.0] += sab
                        Ksigma[3 * rowNode + 2][3 * colNode + 2, default: 0.0] += sab
                    }
                }
            }
        }

        // Validate stress state
        guard maxStressPa >= 1e-9 else {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Applied reference loads produce zero internal stress; linear buckling eigenvalues cannot be evaluated."
            )
        }

        // 8. Eliminate Dirichlet DOFs on K_sigma and construct B = -K_sigma
        for dIdx in dirichletDOFs.keys {
            Ksigma[dIdx].removeAll()
            for j in 0..<totalDOFs where j != dIdx {
                Ksigma[j].removeValue(forKey: dIdx)
            }
        }

        var B: [[Int: Double]] = Array(repeating: [:], count: totalDOFs)
        for i in 0..<totalDOFs {
            for (col, val) in Ksigma[i] {
                B[i][col] = -val
            }
        }

        // 9. Generalized eigensolver via inverse power iteration with Gram-Schmidt deflation
        let requestedModesCount = max(1, study.solver.bucklingModesCount)
        var computedModes: [[Double]] = []
        var computedLambdas: [Double] = []
        var totalEigenIterations = staticIterCount
        var lastResidual = 0.0

        var zeroDirichlet: [Int: Double] = [:]
        for dIdx in dirichletDOFs.keys {
            zeroDirichlet[dIdx] = 0.0
        }

        func deflateVector(_ vec: inout [Double], against modes: [[Double]]) {
            for mode in modes {
                var dot = 0.0
                for i in 0..<vec.count {
                    dot += vec[i] * mode[i]
                }
                for i in 0..<vec.count {
                    vec[i] -= dot * mode[i]
                }
            }
        }

        for m in 1...requestedModesCount {
            var v = [Double](repeating: 0.0, count: totalDOFs)
            for (idx, _) in mesh.nodes.enumerated() {
                let p = positions[idx]
                if m == 1 {
                    v[3 * idx + 1] = (p.x + 0.1) * (p.x + 0.1) + 0.1
                    v[3 * idx + 2] = 0.05 * (p.x + 0.1)
                } else if m == 2 {
                    v[3 * idx + 2] = (p.x + 0.1) * (p.x + 0.1) + 0.1
                    v[3 * idx + 1] = 0.05 * (p.x + 0.1)
                } else {
                    let phase = Double(m)
                    v[3 * idx + (m % 3)] = sin(phase * p.x) + cos(phase * p.y) + 0.1
                }
                v[3 * idx + 0] += 0.01 * sin(p.y + Double(m))
                v[3 * idx + 1] += 0.01 * cos(p.z + Double(m))
                v[3 * idx + 2] += 0.01 * sin(p.x + Double(m))
            }
            for dIdx in dirichletDOFs.keys {
                v[dIdx] = 0.0
            }
            deflateVector(&v, against: computedModes)
            var vNormSq = 0.0
            for val in v { vNormSq += val * val }
            let vNorm = sqrt(vNormSq)
            if vNorm > 1e-15 {
                for i in 0..<totalDOFs { v[i] /= vNorm }
            }

            var currentLambda = 0.0
            let maxIter = max(100, study.solver.maxIterations * 2)
            let tol = max(1e-7, study.solver.convergenceTolerance)

            for iter in 0..<maxIter {
                totalEigenIterations += 1

                var y = [Double](repeating: 0.0, count: totalDOFs)
                for i in 0..<totalDOFs {
                    var sum = 0.0
                    for (col, val) in B[i] {
                        sum += val * v[col]
                    }
                    y[i] = sum
                }

                let (wSol, _, res) = LinearStaticSolver.solvePCG(
                    K: KeElim,
                    b: y,
                    dirichlet: zeroDirichlet,
                    maxIterations: maxStaticIter,
                    tolerance: 1e-9
                )
                lastResidual = res
                var w = wSol

                deflateVector(&w, against: computedModes)

                var wNorm2 = 0.0
                for val in w { wNorm2 += val * val }
                let wNorm = sqrt(wNorm2)
                guard wNorm > 1e-30 else { break }

                var vNext = [Double](repeating: 0.0, count: totalDOFs)
                for i in 0..<totalDOFs { vNext[i] = w[i] / wNorm }

                // Rayleigh quotient lambda = (vNext^T Ke vNext) / (vNext^T B vNext)
                var num = 0.0
                var den = 0.0
                for i in 0..<totalDOFs {
                    var keRow = 0.0
                    for (col, val) in Ke[i] {
                        keRow += val * vNext[col]
                    }
                    num += vNext[i] * keRow

                    var bRow = 0.0
                    for (col, val) in B[i] {
                        bRow += val * vNext[col]
                    }
                    den += vNext[i] * bRow
                }

                let lambdaCandidate = abs(den) > 1e-20 ? (num / den) : 0.0
                let relDiff = abs(lambdaCandidate - currentLambda) / (abs(currentLambda) + 1e-10)
                currentLambda = lambdaCandidate
                v = vNext

                if iter > 2 && relDiff < tol {
                    break
                }
            }

            computedModes.append(v)
            computedLambdas.append(currentLambda)
        }

        // 10. Construct SimulationBucklingMode entities sorted by load factor
        struct CandidateMode {
            var loadFactor: Double
            var eigenvector: [Double]
        }
        var candidates: [CandidateMode] = []
        for i in 0..<computedModes.count {
            candidates.append(CandidateMode(loadFactor: computedLambdas[i], eigenvector: computedModes[i]))
        }
        candidates.sort { $0.loadFactor < $1.loadFactor }

        var resultModes: [SimulationBucklingMode] = []
        for (mIdx, cand) in candidates.enumerated() {
            var maxAmp = 0.0
            for (idx, _) in nodeIds.enumerated() {
                let ux = cand.eigenvector[3 * idx + 0]
                let uy = cand.eigenvector[3 * idx + 1]
                let uz = cand.eigenvector[3 * idx + 2]
                let amp = sqrt(ux * ux + uy * uy + uz * uz)
                maxAmp = max(maxAmp, amp)
            }
            let scale = maxAmp > 1e-15 ? (1.0 / maxAmp) : 1.0

            var dispMap: [Int: SIMD3<Double>] = [:]
            dispMap.reserveCapacity(nodeCount)
            for (idx, nId) in nodeIds.enumerated() {
                let ux = cand.eigenvector[3 * idx + 0] * scale
                let uy = cand.eigenvector[3 * idx + 1] * scale
                let uz = cand.eigenvector[3 * idx + 2] * scale
                dispMap[nId] = SIMD3<Double>(ux, uy, uz)
            }

            resultModes.append(
                SimulationBucklingMode(
                    modeNumber: mIdx + 1,
                    loadFactor: cand.loadFactor,
                    nodalDisplacements: dispMap
                )
            )
        }

        // 11. Extrema
        let lambdas = resultModes.map(\.loadFactor)
        let minLambda = lambdas.min() ?? 0.0
        let maxLambda = lambdas.max() ?? 0.0

        var extrema: [SimulationFieldExtrema] = [
            SimulationFieldExtrema(
                fieldName: "Buckling Load Factor",
                unitSymbol: "-",
                minValue: minLambda,
                maxValue: maxLambda
            )
        ]

        if let mode1 = resultModes.first {
            let mags = mode1.nodalDisplacements.values.map { simd_length($0) }
            let minDisp = mags.min() ?? 0.0
            let maxDisp = mags.max() ?? 0.0
            extrema.append(
                SimulationFieldExtrema(
                    fieldName: "Displacement Magnitude (Mode 1)",
                    unitSymbol: "mm",
                    minValue: minDisp,
                    maxValue: maxDisp
                )
            )
            extrema.append(
                SimulationFieldExtrema(
                    fieldName: "Displacement Magnitude",
                    unitSymbol: "mm",
                    minValue: minDisp,
                    maxValue: maxDisp
                )
            )
        }

        let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                      Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

        return LinearBucklingResult(
            modes: resultModes,
            extrema: extrema,
            iterationCount: totalEigenIterations,
            finalResidual: lastResidual,
            runtimeDuration: elapsed
        )
    }
}
