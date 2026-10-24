import Foundation
import simd

/// Numerical solution results for linear static finite element analysis (ADR-D5, BL-FEA-01, #219).
public struct LinearStaticResult: Sendable, Codable, Equatable {
    public var nodalDisplacements: [Int: SIMD3<Double>]
    public var nodalVonMisesStresses: [Int: Double]
    public var elementVonMisesStresses: [Int: Double]
    public var extrema: [SimulationFieldExtrema]
    public var iterationCount: Int
    public var finalResidual: Double
    public var runtimeDuration: Double

    public init(
        nodalDisplacements: [Int: SIMD3<Double>],
        nodalVonMisesStresses: [Int: Double] = [:],
        elementVonMisesStresses: [Int: Double] = [:],
        extrema: [SimulationFieldExtrema] = [],
        iterationCount: Int = 0,
        finalResidual: Double = 0.0,
        runtimeDuration: Double = 0.0
    ) {
        self.nodalDisplacements = nodalDisplacements
        self.nodalVonMisesStresses = nodalVonMisesStresses
        self.elementVonMisesStresses = elementVonMisesStresses
        self.extrema = extrema
        self.iterationCount = iterationCount
        self.finalResidual = finalResidual
        self.runtimeDuration = runtimeDuration
    }
}

/// Pure-Swift finite element solver for 3D linear static structural analysis governed by $\nabla \cdot \boldsymbol{\sigma} + \mathbf{f} = \mathbf{0}$ (ADR-D5, BL-FEA-01, #219).
public enum LinearStaticSolver: Sendable {

    /// Solves linear static equilibrium $\mathbf{K} \mathbf{u} = \mathbf{F}$ for a given simulation study and volume mesh.
    ///
    /// - Parameters:
    ///   - study: CAE simulation study containing materials, boundary conditions, and solver controls.
    ///   - mesh: Discretized tetrahedral volume mesh (C3D4 or C3D10 elements).
    ///   - youngsModulus: Optional override for Young's modulus $E$ in Pascals ($\text{N/m}^2$).
    ///   - poissonsRatio: Optional override for Poisson's ratio $\nu$.
    ///   - lengthScaleToMeters: Multiplier converting mesh coordinate units to meters (default 1.0).
    /// - Returns: Computed nodal displacements, nodal/element von Mises stresses, and summary extrema.
    public static func solve(
        study: SimulationStudy,
        mesh: VolumeMesh,
        youngsModulus: Double? = nil,
        poissonsRatio: Double? = nil,
        lengthScaleToMeters: Double = 1.0
    ) throws -> LinearStaticResult {
        let startTime = ContinuousClock.now

        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            throw CAEErrorCode.invalidStudyConfiguration(message: "Mesh contains no nodes or elements.")
        }

        // 1. Resolve material elastic properties (Young's modulus E, Poisson's ratio nu, density rho, thermal expansion alpha)
        var E: Double
        var nu: Double
        var rho: Double = 7850.0 // Default structural steel density kg/m³
        var alpha: Double = 1.2e-5 // Default structural steel thermal expansion 1/K

        if let y = youngsModulus, let p = poissonsRatio {
            E = y
            nu = p
            if let matId = study.materials.first?.materialId,
               let mat = MaterialLibrary.standard.material(withId: matId) {
                if mat.densityKgPerM3 > 0 { rho = mat.densityKgPerM3 }
                if mat.thermalExpansionPerK > 0 { alpha = mat.thermalExpansionPerK }
            }
        } else {
            let matId = study.materials.first?.materialId
            let mat = matId.flatMap { MaterialLibrary.standard.material(withId: $0) }
            if let mat {
                E = youngsModulus ?? (mat.youngsModulusGPa * 1e9)
                nu = poissonsRatio ?? mat.poissonsRatioValue
                if mat.densityKgPerM3 > 0 { rho = mat.densityKgPerM3 }
                if mat.thermalExpansionPerK > 0 { alpha = mat.thermalExpansionPerK }
            } else {
                E = youngsModulus ?? 200e9 // 200 GPa
                nu = poissonsRatio ?? 0.3
            }
        }

        // Validate physical constraints
        guard E > 0.0, nu > -1.0, nu < 0.5 else {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Non-physical material properties: E=\(E) Pa, nu=\(nu). Structural analysis requires E > 0 and -1 < nu < 0.5."
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

        // Global stiffness matrix K (sparse rows) and force vector F
        var K: [[Int: Double]] = Array(repeating: [:], count: totalDOFs)
        var F = [Double](repeating: 0.0, count: totalDOFs)

        // 2. Assemble element stiffness matrices
        for element in mesh.elements {
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                assembleC3D10Stiffness(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    lambda: lambda,
                    mu: mu,
                    K: &K
                )
            } else if element.nodeIndices.count >= 4 {
                assembleC3D4Stiffness(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    lambda: lambda,
                    mu: mu,
                    K: &K
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

        let boundaryTriangles = getEffectiveBoundaryTriangles(mesh: mesh)

        // 4. Assemble Dirichlet constraints (fixtures)
        if study.fixtures.isEmpty {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Simulation study has no fixtures configured. Structural analysis requires boundary constraints to prevent rigid body motion."
            )
        }

        var dirichletDOFs: [Int: Double] = [:] // globalDOF -> prescribed displacement in meters
        var elasticDOFs: Set<Int> = []

        for fixture in study.fixtures {
            let matchedSet = (mesh.sets.first(where: { $0.name == fixture.name }))
                ?? setById[fixture.id]
                ?? fixture.targetReferences.compactMap({ setByName[$0.targetName] ?? setById[$0.targetId] }).first
                ?? fixture.groupNames.compactMap({ setByName[$0] }).first
                ?? setByName[fixture.name]

            let targetNodeIds = Set(matchedSet?.nodeIds ?? [])
            let nodeIdsToConstrain: [Int]
            if !targetNodeIds.isEmpty {
                nodeIdsToConstrain = Array(targetNodeIds)
            } else if fixture.targetReferences.isEmpty && fixture.groupNames.isEmpty {
                // If no target is named, default to boundary surface nodes
                nodeIdsToConstrain = Array(Set(boundaryTriangles.flatMap { $0.nodeIndices.prefix(3) }))
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
                        K[dof][dof] = (K[dof][dof] ?? 0.0) + kPerNode.x
                        elasticDOFs.insert(dof)
                    }
                    if fixture.isRestrainedY && kPerNode.y > 0 {
                        let dof = 3 * nodeIdx + 1
                        K[dof][dof] = (K[dof][dof] ?? 0.0) + kPerNode.y
                        elasticDOFs.insert(dof)
                    }
                    if fixture.isRestrainedZ && kPerNode.z > 0 {
                        let dof = 3 * nodeIdx + 2
                        K[dof][dof] = (K[dof][dof] ?? 0.0) + kPerNode.z
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

        // Ensure sufficient constraints to prevent rigid body modes (at least 6 DOFs constrained)
        let totalRestrainedDOFs = Set(dirichletDOFs.keys).union(elasticDOFs).count
        if totalRestrainedDOFs < 6 {
            throw CAEErrorCode.invalidStudyConfiguration(
                message: "Structural system is under-constrained (\(totalRestrainedDOFs) restrained DOFs; at least 6 required to prevent rigid body motion)."
            )
        }

        // 5. Assemble applied loads (force, pressure, gravity)
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
                    let tractionPa = load.direction * load.magnitude // N/m² (Pa)
                    let matchedTriangles = filterBoundaryTriangles(
                        triangles: boundaryTriangles,
                        targetElementIds: targetElementIds,
                        targetNodeIds: targetNodeIds,
                        hasExplicitTargets: !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                    )

                    if !matchedTriangles.isEmpty {
                        for tri in matchedTriangles {
                            let triIndices = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
                            guard triIndices.count == 3 else { continue }

                            let p0 = positions[triIndices[0]]
                            let p1 = positions[triIndices[1]]
                            let p2 = positions[triIndices[2]]

                            let cross = simd_cross(p1 - p0, p2 - p0)
                            let normalLength = simd_length(cross)
                            guard normalLength > 1e-15 else { continue }

                            let area = 0.5 * normalLength
                            let triForce = tractionPa * area
                            let nodalForce = triForce / 3.0

                            for nodeIdx in triIndices {
                                F[3 * nodeIdx + 0] += nodalForce.x
                                F[3 * nodeIdx + 1] += nodalForce.y
                                F[3 * nodeIdx + 2] += nodalForce.z
                            }
                        }
                    } else {
                        let nodesToUse: [Int]
                        if !targetNodeIds.isEmpty {
                            nodesToUse = Array(targetNodeIds)
                        } else if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                            nodesToUse = mesh.nodes.last.map { [$0.id] } ?? []
                        } else {
                            continue
                        }
                        guard !nodesToUse.isEmpty else { continue }
                        let totalForce = load.direction * load.magnitude
                        let forcePerNode = totalForce / Double(nodesToUse.count)
                        for nId in nodesToUse {
                            guard let nodeIdx = nodeIndexById[nId] else { continue }
                            F[3 * nodeIdx + 0] += forcePerNode.x
                            F[3 * nodeIdx + 1] += forcePerNode.y
                            F[3 * nodeIdx + 2] += forcePerNode.z
                        }
                    }
                } else {
                    let nodesToUse: [Int]
                    if !targetNodeIds.isEmpty {
                        nodesToUse = Array(targetNodeIds)
                    } else if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                        nodesToUse = mesh.nodes.last.map { [$0.id] } ?? []
                    } else {
                        continue
                    }

                    guard !nodesToUse.isEmpty else { continue }
                    let totalForce = load.direction * load.magnitude // Newtons
                    let forcePerNode = totalForce / Double(nodesToUse.count)

                    for nId in nodesToUse {
                        guard let nodeIdx = nodeIndexById[nId] else { continue }
                        F[3 * nodeIdx + 0] += forcePerNode.x
                        F[3 * nodeIdx + 1] += forcePerNode.y
                        F[3 * nodeIdx + 2] += forcePerNode.z
                    }
                }

            case .pressure:
                // Pressure in MPa converted to Pa (N/m²)
                let pressurePa = load.magnitude * 1e6
                guard abs(pressurePa) > 1e-15 else { continue }

                let matchedTriangles = filterBoundaryTriangles(
                    triangles: boundaryTriangles,
                    targetElementIds: targetElementIds,
                    targetNodeIds: targetNodeIds,
                    hasExplicitTargets: !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                )

                for tri in matchedTriangles {
                    let triIndices = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
                    guard triIndices.count == 3 else { continue }

                    let p0 = positions[triIndices[0]]
                    let p1 = positions[triIndices[1]]
                    let p2 = positions[triIndices[2]]

                    let cross = simd_cross(p1 - p0, p2 - p0)
                    let normalLength = simd_length(cross)
                    guard normalLength > 1e-15 else { continue }

                    let area = 0.5 * normalLength
                    let outwardNormal = cross / normalLength
                    // Compressive pressure acts inward: -n * p * area
                    let totalPressureForce = -outwardNormal * pressurePa * area
                    let nodalForce = totalPressureForce / 3.0

                    for nodeIdx in triIndices {
                        F[3 * nodeIdx + 0] += nodalForce.x
                        F[3 * nodeIdx + 1] += nodalForce.y
                        F[3 * nodeIdx + 2] += nodalForce.z
                    }
                }

            case .gravity:
                let accel = load.direction * load.magnitude // m/s²
                guard simd_length(accel) > 1e-15 else { continue }

                for element in mesh.elements {
                    let elIndices = element.nodeIndices.compactMap { nodeIndexById[$0] }
                    guard elIndices.count >= 4 else { continue }

                    let vol = computeTetrahedronVolume(el: element, positions: positions, nodeIndexById: nodeIndexById)
                    guard vol > 1e-15 else { continue }

                    let elMass = rho * vol
                    let totalGravityForce = accel * elMass
                    let count = Double(element.order == .quadratic && elIndices.count >= 10 ? 10 : 4)
                    let nodalForce = totalGravityForce / count

                    for i in 0..<Int(count) {
                        let nodeIdx = elIndices[i]
                        F[3 * nodeIdx + 0] += nodalForce.x
                        F[3 * nodeIdx + 1] += nodalForce.y
                        F[3 * nodeIdx + 2] += nodalForce.z
                    }
                }

            case .moment:
                let nodesToUse: [Int]
                if !targetNodeIds.isEmpty {
                    nodesToUse = Array(targetNodeIds)
                } else if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                    let boundary = filterBoundaryTriangles(
                        triangles: boundaryTriangles,
                        targetElementIds: targetElementIds,
                        targetNodeIds: targetNodeIds,
                        hasExplicitTargets: false
                    )
                    nodesToUse = Array(Set(boundary.flatMap { $0.nodeIndices }))
                } else {
                    continue
                }

                guard nodesToUse.count > 1 else { continue }
                let nodeIndices = nodesToUse.compactMap { nodeIndexById[$0] }
                guard nodeIndices.count > 1 else { continue }

                var rc = SIMD3<Double>.zero
                for idx in nodeIndices {
                    rc += positions[idx]
                }
                rc /= Double(nodeIndices.count)

                let momentVec = load.direction * load.magnitude
                guard simd_length(momentVec) > 1e-15 else { continue }

                var J0 = SIMD3<Double>.zero
                var J1 = SIMD3<Double>.zero
                var J2 = SIMD3<Double>.zero
                var drList = [SIMD3<Double>]()
                drList.reserveCapacity(nodeIndices.count)

                for idx in nodeIndices {
                    let dr = positions[idx] - rc
                    drList.append(dr)
                    let rSq = simd_dot(dr, dr)
                    J0 += SIMD3<Double>(rSq - dr.x * dr.x, -dr.x * dr.y, -dr.x * dr.z)
                    J1 += SIMD3<Double>(-dr.y * dr.x, rSq - dr.y * dr.y, -dr.y * dr.z)
                    J2 += SIMD3<Double>(-dr.z * dr.x, -dr.z * dr.y, rSq - dr.z * dr.z)
                }

                guard let Jinv = invert3x3((J0, J1, J2)) else { continue }
                let omega = multiply3x3(Jinv, momentVec)

                for (i, nodeIdx) in nodeIndices.enumerated() {
                    let Fi = simd_cross(omega, drList[i])
                    F[3 * nodeIdx + 0] += Fi.x
                    F[3 * nodeIdx + 1] += Fi.y
                    F[3 * nodeIdx + 2] += Fi.z
                }

            case .remoteLoad:
                let nodesToUse: [Int]
                if !targetNodeIds.isEmpty {
                    nodesToUse = Array(targetNodeIds)
                } else if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                    let boundary = filterBoundaryTriangles(
                        triangles: boundaryTriangles,
                        targetElementIds: targetElementIds,
                        targetNodeIds: targetNodeIds,
                        hasExplicitTargets: false
                    )
                    nodesToUse = Array(Set(boundary.flatMap { $0.nodeIndices }))
                } else {
                    continue
                }

                guard !nodesToUse.isEmpty else { continue }
                let nodeIndices = nodesToUse.compactMap { nodeIndexById[$0] }
                guard !nodeIndices.isEmpty else { continue }

                var rc = SIMD3<Double>.zero
                for idx in nodeIndices {
                    rc += positions[idx]
                }
                rc /= Double(nodeIndices.count)

                let remotePt = (load.remotePoint ?? rc) * lengthScaleToMeters
                let netForce = load.direction * load.magnitude // N
                let extMoment = load.remoteMoment ?? .zero // N·m

                let forcePerNode = netForce / Double(nodeIndices.count)
                for nodeIdx in nodeIndices {
                    F[3 * nodeIdx + 0] += forcePerNode.x
                    F[3 * nodeIdx + 1] += forcePerNode.y
                    F[3 * nodeIdx + 2] += forcePerNode.z
                }

                // Induced moment about centroid: M = M_ext + (rc - r_remote) x F
                let inducedMoment = extMoment + simd_cross(rc - remotePt, netForce)

                if simd_length(inducedMoment) > 1e-15 && nodeIndices.count > 1 {
                    var J0 = SIMD3<Double>.zero
                    var J1 = SIMD3<Double>.zero
                    var J2 = SIMD3<Double>.zero
                    var drList = [SIMD3<Double>]()
                    drList.reserveCapacity(nodeIndices.count)

                    for idx in nodeIndices {
                        let dr = positions[idx] - rc
                        drList.append(dr)
                        let rSq = simd_dot(dr, dr)
                        J0 += SIMD3<Double>(rSq - dr.x * dr.x, -dr.x * dr.y, -dr.x * dr.z)
                        J1 += SIMD3<Double>(-dr.y * dr.x, rSq - dr.y * dr.y, -dr.y * dr.z)
                        J2 += SIMD3<Double>(-dr.z * dr.x, -dr.z * dr.y, rSq - dr.z * dr.z)
                    }

                    if let Jinv = invert3x3((J0, J1, J2)) {
                        let omega = multiply3x3(Jinv, inducedMoment)
                        for (i, nodeIdx) in nodeIndices.enumerated() {
                            let Fi = simd_cross(omega, drList[i])
                            F[3 * nodeIdx + 0] += Fi.x
                            F[3 * nodeIdx + 1] += Fi.y
                            F[3 * nodeIdx + 2] += Fi.z
                        }
                    }
                }

            case .bearing:
                let dir = load.direction
                let netForceMag = load.magnitude
                guard abs(netForceMag) > 1e-15 else { continue }

                let matchedTriangles = filterBoundaryTriangles(
                    triangles: boundaryTriangles,
                    targetElementIds: targetElementIds,
                    targetNodeIds: targetNodeIds,
                    hasExplicitTargets: !load.targetReferences.isEmpty || !load.groupNames.isEmpty
                )

                var triangleData: [(indices: [Int], forceDir: SIMD3<Double>, weight: Double, area: Double)] = []
                var totalProjected = 0.0

                for tri in matchedTriangles {
                    let triIndices = tri.nodeIndices.prefix(3).compactMap { nodeIndexById[$0] }
                    guard triIndices.count == 3 else { continue }

                    let p0 = positions[triIndices[0]]
                    let p1 = positions[triIndices[1]]
                    let p2 = positions[triIndices[2]]

                    let cross = simd_cross(p1 - p0, p2 - p0)
                    let normalLength = simd_length(cross)
                    guard normalLength > 1e-15 else { continue }

                    let area = 0.5 * normalLength
                    let outwardNormal = cross / normalLength
                    let inwardNormal = -outwardNormal

                    // Compressive half-cosine traction: cos(theta) = max(0, -n · d)
                    let cosTheta = max(0.0, simd_dot(inwardNormal, dir))
                    if cosTheta > 1e-12 {
                        let unscaledTriForce = inwardNormal * (cosTheta * area)
                        let proj = simd_dot(unscaledTriForce, dir)
                        totalProjected += proj
                        triangleData.append((triIndices, inwardNormal, cosTheta, area))
                    }
                }

                if totalProjected > 1e-15 {
                    let scale = netForceMag / totalProjected
                    for item in triangleData {
                        let triForce = item.forceDir * (scale * item.weight * item.area)
                        let nodalForce = triForce / 3.0
                        for nodeIdx in item.indices {
                            F[3 * nodeIdx + 0] += nodalForce.x
                            F[3 * nodeIdx + 1] += nodalForce.y
                            F[3 * nodeIdx + 2] += nodalForce.z
                        }
                    }
                } else {
                    let nodesToUse: [Int] = !targetNodeIds.isEmpty ? Array(targetNodeIds) : (mesh.nodes.last.map { [$0.id] } ?? [])
                    guard !nodesToUse.isEmpty else { continue }
                    let forcePerNode = (dir * netForceMag) / Double(nodesToUse.count)
                    for nId in nodesToUse {
                        guard let nodeIdx = nodeIndexById[nId] else { continue }
                        F[3 * nodeIdx + 0] += forcePerNode.x
                        F[3 * nodeIdx + 1] += forcePerNode.y
                        F[3 * nodeIdx + 2] += forcePerNode.z
                    }
                }

            case .centrifugal:
                let omega = load.magnitude // rad/s
                let omegaSq = omega * omega
                guard omegaSq > 1e-15 else { continue }

                let axisLen = simd_length(load.direction)
                let axis = axisLen > 1e-6 ? load.direction / axisLen : SIMD3<Double>(0, 0, 1)
                let origin = (load.axisOrigin ?? .zero) * lengthScaleToMeters

                for element in mesh.elements {
                    if !targetElementIds.isEmpty && !targetElementIds.contains(element.id) {
                        continue
                    }

                    let elIndices = element.nodeIndices.compactMap { nodeIndexById[$0] }
                    guard elIndices.count >= 4 else { continue }

                    let vol = computeTetrahedronVolume(el: element, positions: positions, nodeIndexById: nodeIndexById)
                    guard vol > 1e-15 else { continue }

                    let count = Double(element.order == .quadratic && elIndices.count >= 10 ? 10 : 4)
                    let nodeMass = (rho * vol) / count

                    for i in 0..<Int(count) {
                        let nodeIdx = elIndices[i]
                        let r = positions[nodeIdx]
                        let dr = r - origin
                        let rPerp = dr - simd_dot(dr, axis) * axis
                        let aCentrif = omegaSq * rPerp
                        let Fi = nodeMass * aCentrif

                        F[3 * nodeIdx + 0] += Fi.x
                        F[3 * nodeIdx + 1] += Fi.y
                        F[3 * nodeIdx + 2] += Fi.z
                    }
                }

            case .thermalLoad, .temperature:
                let targetTemp = load.magnitude // °C
                let refTemp = load.referenceTemperature ?? 20.0 // °C
                let deltaT = targetTemp - refTemp
                guard abs(deltaT) > 1e-15 else { continue }

                let beta = (3.0 * lambda + 2.0 * mu) * alpha

                for element in mesh.elements {
                    if !targetElementIds.isEmpty && !targetElementIds.contains(element.id) {
                        continue
                    }

                    let elIndices = element.nodeIndices.compactMap { nodeIndexById[$0] }
                    guard elIndices.count >= 4 else { continue }

                    if element.order == .quadratic && elIndices.count >= 10 {
                        let p = elIndices.prefix(10).map { positions[$0] }
                        let alphaQuad = (5.0 - sqrt(5.0)) / 20.0
                        let betaQuad = (5.0 + 3.0 * sqrt(5.0)) / 20.0
                        let quadPoints: [(SIMD4<Double>, Double)] = [
                            (SIMD4<Double>(betaQuad, alphaQuad, alphaQuad, alphaQuad), 1.0 / 24.0),
                            (SIMD4<Double>(alphaQuad, betaQuad, alphaQuad, alphaQuad), 1.0 / 24.0),
                            (SIMD4<Double>(alphaQuad, alphaQuad, betaQuad, alphaQuad), 1.0 / 24.0),
                            (SIMD4<Double>(alphaQuad, alphaQuad, alphaQuad, betaQuad), 1.0 / 24.0)
                        ]

                        for (L, weight) in quadPoints {
                            let dNdL = evaluateC3D10LocalGradients(L: L)
                            var J = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero)
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
                            for a in 0..<10 {
                                let nodeIdx = elIndices[a]
                                let gradNa = multiply3x3(Jinv, dNdL[a])
                                let Fth = dOmega * (beta * deltaT) * gradNa
                                F[3 * nodeIdx + 0] += Fth.x
                                F[3 * nodeIdx + 1] += Fth.y
                                F[3 * nodeIdx + 2] += Fth.z
                            }
                        }
                    } else {
                        let p0 = positions[elIndices[0]]
                        let p1 = positions[elIndices[1]]
                        let p2 = positions[elIndices[2]]
                        let p3 = positions[elIndices[3]]

                        let C: [[Double]] = [
                            [1.0, p0.x, p0.y, p0.z],
                            [1.0, p1.x, p1.y, p1.z],
                            [1.0, p2.x, p2.y, p2.z],
                            [1.0, p3.x, p3.y, p3.z]
                        ]
                        guard let Cinv = invert4x4(C) else { continue }
                        let vol = computeTetrahedronVolume(el: element, positions: positions, nodeIndexById: nodeIndexById)
                        guard vol > 1e-15 else { continue }

                        for a in 0..<4 {
                            let nodeIdx = elIndices[a]
                            let gradNa = SIMD3<Double>(Cinv[1][a], Cinv[2][a], Cinv[3][a])
                            let Fth = vol * (beta * deltaT) * gradNa
                            F[3 * nodeIdx + 0] += Fth.x
                            F[3 * nodeIdx + 1] += Fth.y
                            F[3 * nodeIdx + 2] += Fth.z
                        }
                    }
                }

            default:
                break
            }
        }

        // 6. Apply symmetric Dirichlet elimination
        for (dIdx, dVal) in dirichletDOFs {
            for j in 0..<totalDOFs {
                if j != dIdx, let kjd = K[j][dIdx] {
                    F[j] -= kjd * dVal
                    K[j].removeValue(forKey: dIdx)
                }
            }
            K[dIdx].removeAll(keepingCapacity: true)
            K[dIdx][dIdx] = 1.0
            F[dIdx] = dVal
        }

        // 7. Solve linear system K * u = F using Jacobi-Preconditioned Conjugate Gradient (PCG)
        let maxIter = max(5000, study.solver.maxIterations * 50)
        let tol = 1e-7
        let (solutionU, iterations, finalRes) = solvePCG(
            K: K,
            b: F,
            dirichlet: dirichletDOFs,
            maxIterations: maxIter,
            tolerance: tol
        )

        // 8. Post-process displacements and von Mises stresses
        var nodalDisplacements: [Int: SIMD3<Double>] = [:]
        nodalDisplacements.reserveCapacity(nodeCount)

        var minMag = Double.infinity
        var maxMag = 0.0
        var minUx = Double.infinity
        var maxUx = -Double.infinity
        var minUy = Double.infinity
        var maxUy = -Double.infinity
        var minUz = Double.infinity
        var maxUz = -Double.infinity

        for (idx, nId) in nodeIds.enumerated() {
            // Convert displacement from meters to canonical millimeters
            let uxMm = solutionU[3 * idx + 0] * 1000.0
            let uyMm = solutionU[3 * idx + 1] * 1000.0
            let uzMm = solutionU[3 * idx + 2] * 1000.0
            let dispMm = SIMD3<Double>(uxMm, uyMm, uzMm)
            let mag = simd_length(dispMm)

            nodalDisplacements[nId] = dispMm

            minMag = min(minMag, mag)
            maxMag = max(maxMag, mag)
            minUx = min(minUx, uxMm)
            maxUx = max(maxUx, uxMm)
            minUy = min(minUy, uyMm)
            maxUy = max(maxUy, uyMm)
            minUz = min(minUz, uzMm)
            maxUz = max(maxUz, uzMm)
        }

        if minMag.isInfinite {
            minMag = 0.0; maxMag = 0.0
            minUx = 0.0; maxUx = 0.0
            minUy = 0.0; maxUy = 0.0
            minUz = 0.0; maxUz = 0.0
        }

        // 9. Recover Cauchy stresses and calculate element and nodal von Mises stresses (in MPa)
        var elementThermalStrain = [Int: Double]()
        for load in study.loads where load.kind == .thermalLoad || load.kind == .temperature {
            let targetTemp = load.magnitude
            let refTemp = load.referenceTemperature ?? 20.0
            let deltaT = targetTemp - refTemp
            let eth = alpha * deltaT

            let matchedSet = (mesh.sets.first(where: { $0.name == load.name }))
                ?? setById[load.id]
                ?? load.targetReferences.compactMap({ setByName[$0.targetName] ?? setById[$0.targetId] }).first
                ?? load.groupNames.compactMap({ setByName[$0] }).first
                ?? setByName[load.name]

            let targetElIds = Set(matchedSet?.elementIds ?? [])
            if targetElIds.isEmpty {
                for element in mesh.elements {
                    elementThermalStrain[element.id] = (elementThermalStrain[element.id] ?? 0.0) + eth
                }
            } else {
                for elId in targetElIds {
                    elementThermalStrain[elId] = (elementThermalStrain[elId] ?? 0.0) + eth
                }
            }
        }

        var elementVonMisesStresses: [Int: Double] = [:]
        elementVonMisesStresses.reserveCapacity(mesh.elements.count)

        var nodalStressAccumulator = [Int: (sum: Double, count: Int)](minimumCapacity: nodeCount)

        for element in mesh.elements {
            let eth = elementThermalStrain[element.id] ?? 0.0
            if element.order == .quadratic && element.nodeIndices.count >= 10 {
                let (elemStress, nodeStresses) = computeC3D10Stresses(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    nodalU: solutionU,
                    lambda: lambda,
                    mu: mu,
                    thermalStrain: eth
                )
                elementVonMisesStresses[element.id] = elemStress
                for (nId, s) in nodeStresses {
                    let cur = nodalStressAccumulator[nId] ?? (0.0, 0)
                    nodalStressAccumulator[nId] = (cur.sum + s, cur.count + 1)
                }
            } else if element.nodeIndices.count >= 4 {
                let elemStress = computeC3D4Stresses(
                    element: element,
                    positions: positions,
                    nodeIndexById: nodeIndexById,
                    nodalU: solutionU,
                    lambda: lambda,
                    mu: mu,
                    thermalStrain: eth
                )
                elementVonMisesStresses[element.id] = elemStress
                for nId in element.nodeIndices.prefix(4) {
                    let cur = nodalStressAccumulator[nId] ?? (0.0, 0)
                    nodalStressAccumulator[nId] = (cur.sum + elemStress, cur.count + 1)
                }
            }
        }

        var nodalVonMisesStresses: [Int: Double] = [:]
        nodalVonMisesStresses.reserveCapacity(nodeCount)

        var minStress = Double.infinity
        var maxStress = 0.0

        for nId in nodeIds {
            let smoothed: Double
            if let acc = nodalStressAccumulator[nId], acc.count > 0 {
                smoothed = acc.sum / Double(acc.count)
            } else {
                smoothed = 0.0
            }
            nodalVonMisesStresses[nId] = smoothed
            minStress = min(minStress, smoothed)
            maxStress = max(maxStress, smoothed)
        }

        if minStress.isInfinite {
            minStress = 0.0
            maxStress = 0.0
        }

        let extrema: [SimulationFieldExtrema] = [
            SimulationFieldExtrema(fieldName: "Displacement Magnitude", unitSymbol: "mm", minValue: minMag, maxValue: maxMag),
            SimulationFieldExtrema(fieldName: "Displacement X", unitSymbol: "mm", minValue: minUx, maxValue: maxUx),
            SimulationFieldExtrema(fieldName: "Displacement Y", unitSymbol: "mm", minValue: minUy, maxValue: maxUy),
            SimulationFieldExtrema(fieldName: "Displacement Z", unitSymbol: "mm", minValue: minUz, maxValue: maxUz),
            SimulationFieldExtrema(fieldName: "von Mises Stress", unitSymbol: "MPa", minValue: minStress, maxValue: maxStress)
        ]

        let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                      Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

        return LinearStaticResult(
            nodalDisplacements: nodalDisplacements,
            nodalVonMisesStresses: nodalVonMisesStresses,
            elementVonMisesStresses: elementVonMisesStresses,
            extrema: extrema,
            iterationCount: iterations,
            finalResidual: finalRes,
            runtimeDuration: elapsed
        )
    }

    // MARK: - Stiffness Assembly (C3D4 Linear Tetrahedra)

    private static func assembleC3D4Stiffness(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
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
        guard let Cinv = invert4x4(C) else { return }

        var gradN = [SIMD3<Double>](repeating: .zero, count: 4)
        for i in 0..<4 {
            gradN[i] = SIMD3<Double>(Cinv[1][i], Cinv[2][i], Cinv[3][i])
        }

        for a in 0..<4 {
            let rowNode = indices[a]
            let ga = gradN[a]
            for b in 0..<4 {
                let colNode = indices[b]
                let gb = gradN[b]
                let kab = computeNodalStiffnessBlock(ga: ga, gb: gb, lambda: lambda, mu: mu)

                add3x3Block(
                    K: &K,
                    rowNode: rowNode,
                    colNode: colNode,
                    block: kab,
                    weight: volume
                )
            }
        }
    }

    // MARK: - Stiffness Assembly (C3D10 Quadratic Tetrahedra)

    private static func assembleC3D10Stiffness(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
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
            let dNdL = evaluateC3D10LocalGradients(L: L)

            var J = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero)
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

            var gradN = [SIMD3<Double>](repeating: .zero, count: 10)
            for a in 0..<10 {
                gradN[a] = multiply3x3(Jinv, dNdL[a])
            }

            for a in 0..<10 {
                let rowNode = indices[a]
                let ga = gradN[a]
                for b in 0..<10 {
                    let colNode = indices[b]
                    let gb = gradN[b]
                    let kab = computeNodalStiffnessBlock(ga: ga, gb: gb, lambda: lambda, mu: mu)

                    add3x3Block(
                        K: &K,
                        rowNode: rowNode,
                        colNode: colNode,
                        block: kab,
                        weight: dOmega
                    )
                }
            }
        }
    }

    // MARK: - Stress Recovery

    private static func computeC3D4Stresses(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        nodalU: [Double],
        lambda: Double,
        mu: Double,
        thermalStrain: Double = 0.0
    ) -> Double {
        let indices = element.nodeIndices.prefix(4).compactMap { nodeIndexById[$0] }
        guard indices.count == 4 else { return 0.0 }

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
        guard let Cinv = invert4x4(C) else { return 0.0 }

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

        exx -= thermalStrain
        eyy -= thermalStrain
        ezz -= thermalStrain

        return evaluateVonMisesStress(exx: exx, eyy: eyy, ezz: ezz, exy: exy, eyz: eyz, ezx: ezx, lambda: lambda, mu: mu)
    }

    private static func computeC3D10Stresses(
        element: VolumeMeshElement,
        positions: [SIMD3<Double>],
        nodeIndexById: [Int: Int],
        nodalU: [Double],
        lambda: Double,
        mu: Double,
        thermalStrain: Double = 0.0
    ) -> (elementStress: Double, nodeStresses: [Int: Double]) {
        let indices = element.nodeIndices.prefix(10).compactMap { nodeIndexById[$0] }
        guard indices.count == 10 else { return (0.0, [:]) }

        let p = indices.map { positions[$0] }
        let elementNodeIds = Array(element.nodeIndices.prefix(10))

        // 1. Centroid stress
        let LCentroid = SIMD4<Double>(0.25, 0.25, 0.25, 0.25)
        let dNdLCentroid = evaluateC3D10LocalGradients(L: LCentroid)
        var JCentroid = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero)
        for a in 0..<10 {
            let g = dNdLCentroid[a]
            JCentroid.0 += g.x * p[a]
            JCentroid.1 += g.y * p[a]
            JCentroid.2 += g.z * p[a]
        }
        var elemStress = 0.0
        if let Jinv = invert3x3(JCentroid) {
            var gradN = [SIMD3<Double>](repeating: .zero, count: 10)
            for a in 0..<10 { gradN[a] = multiply3x3(Jinv, dNdLCentroid[a]) }

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
            exx -= thermalStrain
            eyy -= thermalStrain
            ezz -= thermalStrain
            elemStress = evaluateVonMisesStress(exx: exx, eyy: eyy, ezz: ezz, exy: exy, eyz: eyz, ezx: ezx, lambda: lambda, mu: mu)
        }

        // 2. Exact stresses at each of the 10 nodes
        let nodeCoords: [SIMD4<Double>] = [
            SIMD4<Double>(1.0, 0.0, 0.0, 0.0), // Node 0
            SIMD4<Double>(0.0, 1.0, 0.0, 0.0), // Node 1
            SIMD4<Double>(0.0, 0.0, 1.0, 0.0), // Node 2
            SIMD4<Double>(0.0, 0.0, 0.0, 1.0), // Node 3
            SIMD4<Double>(0.5, 0.5, 0.0, 0.0), // Node 4
            SIMD4<Double>(0.0, 0.5, 0.5, 0.0), // Node 5
            SIMD4<Double>(0.5, 0.0, 0.5, 0.0), // Node 6
            SIMD4<Double>(0.5, 0.0, 0.0, 0.5), // Node 7
            SIMD4<Double>(0.0, 0.5, 0.0, 0.5), // Node 8
            SIMD4<Double>(0.0, 0.0, 0.5, 0.5)  // Node 9
        ]

        var nodeStresses: [Int: Double] = [:]
        for k in 0..<10 {
            let Lk = nodeCoords[k]
            let dNdLk = evaluateC3D10LocalGradients(L: Lk)
            var Jk = (SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero)
            for a in 0..<10 {
                let g = dNdLk[a]
                Jk.0 += g.x * p[a]
                Jk.1 += g.y * p[a]
                Jk.2 += g.z * p[a]
            }
            guard let JinvK = invert3x3(Jk) else { continue }
            var gradNk = [SIMD3<Double>](repeating: .zero, count: 10)
            for a in 0..<10 { gradNk[a] = multiply3x3(JinvK, dNdLk[a]) }

            var exx = 0.0, eyy = 0.0, ezz = 0.0
            var exy = 0.0, eyz = 0.0, ezx = 0.0
            for a in 0..<10 {
                let nIdx = indices[a]
                let ux = nodalU[3 * nIdx + 0]
                let uy = nodalU[3 * nIdx + 1]
                let uz = nodalU[3 * nIdx + 2]
                let g = gradNk[a]
                exx += g.x * ux
                eyy += g.y * uy
                ezz += g.z * uz
                exy += 0.5 * (g.y * ux + g.x * uy)
                eyz += 0.5 * (g.z * uy + g.y * uz)
                ezx += 0.5 * (g.x * uz + g.z * ux)
            }
            exx -= thermalStrain
            eyy -= thermalStrain
            ezz -= thermalStrain
            let s = evaluateVonMisesStress(exx: exx, eyy: eyy, ezz: ezz, exy: exy, eyz: eyz, ezx: ezx, lambda: lambda, mu: mu)
            nodeStresses[elementNodeIds[k]] = s
        }

        return (elemStress, nodeStresses)
    }

    @inline(__always)
    private static func evaluateVonMisesStress(
        exx: Double, eyy: Double, ezz: Double,
        exy: Double, eyz: Double, ezx: Double,
        lambda: Double, mu: Double
    ) -> Double {
        let trE = exx + eyy + ezz
        let sxx = lambda * trE + 2.0 * mu * exx
        let syy = lambda * trE + 2.0 * mu * eyy
        let szz = lambda * trE + 2.0 * mu * ezz
        let sxy = 2.0 * mu * exy
        let syz = 2.0 * mu * eyz
        let szx = 2.0 * mu * ezx

        let diff1 = sxx - syy
        let diff2 = syy - szz
        let diff3 = szz - sxx
        let shearSq = sxy * sxy + syz * syz + szx * szx

        let vmSq = 0.5 * (diff1 * diff1 + diff2 * diff2 + diff3 * diff3) + 3.0 * shearSq
        let vmPa = sqrt(max(0.0, vmSq))
        return vmPa * 1e-6 // Return in MPa
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

        var invM = [Double](repeating: 1.0, count: n)
        for i in 0..<n {
            let diag = K[i][i] ?? 1.0
            invM[i] = abs(diag) > 1e-15 ? (1.0 / diag) : 1.0
        }

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

        var z = [Double](repeating: 0.0, count: n)
        for i in 0..<n { z[i] = invM[i] * r[i] }

        var p = z
        var gamma = 0.0
        for i in 0..<n { gamma += r[i] * z[i] }

        var iter = 0
        var currentRes = sqrt(rNormSq)

        while iter < maxIterations {
            iter += 1

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

    // MARK: - Mathematical Helpers

    @inline(__always)
    private static func computeNodalStiffnessBlock(
        ga: SIMD3<Double>,
        gb: SIMD3<Double>,
        lambda: Double,
        mu: Double
    ) -> (
        k00: Double, k01: Double, k02: Double,
        k10: Double, k11: Double, k12: Double,
        k20: Double, k21: Double, k22: Double
    ) {
        let k00 = (lambda + 2.0 * mu) * ga.x * gb.x + mu * (ga.y * gb.y + ga.z * gb.z)
        let k01 = lambda * ga.x * gb.y + mu * ga.y * gb.x
        let k02 = lambda * ga.x * gb.z + mu * ga.z * gb.x

        let k10 = lambda * ga.y * gb.x + mu * ga.x * gb.y
        let k11 = (lambda + 2.0 * mu) * ga.y * gb.y + mu * (ga.x * gb.x + ga.z * gb.z)
        let k12 = lambda * ga.y * gb.z + mu * ga.z * gb.y

        let k20 = lambda * ga.z * gb.x + mu * ga.x * gb.z
        let k21 = lambda * ga.z * gb.y + mu * ga.y * gb.z
        let k22 = (lambda + 2.0 * mu) * ga.z * gb.z + mu * (ga.x * gb.x + ga.y * gb.y)

        return (k00, k01, k02, k10, k11, k12, k20, k21, k22)
    }

    @inline(__always)
    private static func add3x3Block(
        K: inout [[Int: Double]],
        rowNode: Int,
        colNode: Int,
        block: (
            k00: Double, k01: Double, k02: Double,
            k10: Double, k11: Double, k12: Double,
            k20: Double, k21: Double, k22: Double
        ),
        weight: Double
    ) {
        let r0 = 3 * rowNode + 0
        let r1 = 3 * rowNode + 1
        let r2 = 3 * rowNode + 2

        let c0 = 3 * colNode + 0
        let c1 = 3 * colNode + 1
        let c2 = 3 * colNode + 2

        K[r0][c0, default: 0.0] += weight * block.k00
        K[r0][c1, default: 0.0] += weight * block.k01
        K[r0][c2, default: 0.0] += weight * block.k02

        K[r1][c0, default: 0.0] += weight * block.k10
        K[r1][c1, default: 0.0] += weight * block.k11
        K[r1][c2, default: 0.0] += weight * block.k12

        K[r2][c0, default: 0.0] += weight * block.k20
        K[r2][c1, default: 0.0] += weight * block.k21
        K[r2][c2, default: 0.0] += weight * block.k22
    }

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
