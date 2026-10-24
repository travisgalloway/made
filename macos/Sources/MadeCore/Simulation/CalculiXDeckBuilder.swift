import Foundation
import simd

/// Generates standardized CalculiX `.inp` input decks for thermal and structural simulation studies (ADR-D5, BL-THM-01, #190).
public enum CalculiXDeckBuilder: Sendable {

    /// Constructs a complete CalculiX `.inp` deck specification from a simulation study and volume mesh.
    ///
    /// - Parameters:
    ///   - study: CAE simulation study containing materials, boundary conditions, and solver parameters.
    ///   - mesh: Discretized finite element volume mesh.
    public static func buildDeck(
        study: SimulationStudy,
        mesh: VolumeMesh,
        nodalTemperatures: [Int: Double]? = nil
    ) -> CAEDeck {
        let cleanId = study.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let jobName = "study_\(cleanId)"

        var lines: [String] = []

        // Heading
        lines.append("*HEADING")
        lines.append("CalculiX FEA Simulation Study - \(study.name)")

        // Nodes
        lines.append("*NODE, NSET=NALL")
        for node in mesh.nodes {
            lines.append(String(format: "%d, %.6f, %.6f, %.6f", node.id, node.position.x, node.position.y, node.position.z))
        }

        // Elements
        let isQuadratic = mesh.elements.contains { $0.order == .quadratic && $0.nodeIndices.count >= 10 }
        let elementType = isQuadratic ? "C3D10" : "C3D4"
        lines.append("*ELEMENT, TYPE=\(elementType), ELSET=EALL")
        for el in mesh.elements {
            let conn = el.nodeIndices.map(String.init).joined(separator: ", ")
            lines.append("\(el.id), \(conn)")
        }

        // Material definition
        let matRaw = study.materials.first?.materialId ?? "STEEL"
        let matName = matRaw.uppercased().replacingOccurrences(of: "-", with: "_")
        lines.append("*MATERIAL, NAME=\(matName)")

        if study.studyType == .thermalConduction {
            lines.append("*CONDUCTIVITY")
            lines.append("50.0") // Standard structural steel W/(m·K)
        } else {
            if let mat = MaterialLibrary.standard.material(withId: matRaw) {
                let eMPa = mat.youngsModulusGPa * 1000.0
                let nu = mat.poissonsRatioValue
                lines.append("*ELASTIC")
                lines.append(String(format: "%.1f, %.4f", eMPa, nu))
                if mat.densityKgPerM3 > 0 {
                    lines.append("*DENSITY")
                    lines.append(String(format: "%.4e", mat.densityKgPerM3))
                } else if study.studyType == .modalFrequency {
                    lines.append("*DENSITY")
                    lines.append(String(format: "%.4e", 7850.0))
                }
                if mat.thermalExpansionPerK > 0 {
                    lines.append("*EXPANSION")
                    lines.append(String(format: "%.4e", mat.thermalExpansionPerK))
                }
            } else {
                lines.append("*ELASTIC")
                lines.append("210000.0, 0.3") // Standard steel MPa, Poisson ratio
                if study.studyType == .modalFrequency {
                    lines.append("*DENSITY")
                    lines.append(String(format: "%.4e", 7850.0))
                }
                lines.append("*EXPANSION")
                lines.append("1.2000e-05")
            }
        }

        lines.append("*SOLID SECTION, ELSET=EALL, MATERIAL=\(matName)")

        // Node and element sets
        let associatedSets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        let sets = mesh.sets.isEmpty ? associatedSets : mesh.sets
        var setByName: [String: VolumeMeshSet] = [:]
        for s in mesh.sets {
            setByName[s.name] = s
        }
        for s in associatedSets {
            if setByName[s.name] == nil {
                setByName[s.name] = s
            }
        }
        for s in sets {
            // Exclude connection sets from generic output so they are formatted cleanly with *TIE below
            if study.connections.contains(where: { s.name == "\($0.name)_Source" || s.name == "\($0.name)_Target" }) {
                continue
            }
            setByName[s.name] = s
            let sanitized = s.name.uppercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
            if !s.nodeIds.isEmpty {
                lines.append("*NSET, NSET=\(sanitized)")
                for chunk in stride(from: 0, to: s.nodeIds.count, by: 16) {
                    let end = min(chunk + 16, s.nodeIds.count)
                    let chunkStr = s.nodeIds[chunk..<end].map(String.init).joined(separator: ", ")
                    lines.append(chunkStr)
                }
            }
            if !s.elementIds.isEmpty {
                lines.append("*ELSET, ELSET=\(sanitized)")
                for chunk in stride(from: 0, to: s.elementIds.count, by: 16) {
                    let end = min(chunk + 16, s.elementIds.count)
                    let chunkStr = s.elementIds[chunk..<end].map(String.init).joined(separator: ", ")
                    lines.append(chunkStr)
                }
            }
        }

        // Elastic support spring elements (grounded SPRING1 elements before *STEP)
        if study.studyType != .thermalConduction {
            var springElemId = mesh.elements.map(\.id).max() ?? 0
            for fixture in study.fixtures where fixture.kind == .elasticSupport {
                let targetNodes = resolveFixtureNodeIds(for: fixture, setByName: setByName)
                let nodesToUse = targetNodes.isEmpty ? (mesh.nodes.prefix(3).map(\.id)) : targetNodes
                guard !nodesToUse.isEmpty else { continue }
                let axes: [(Int, Bool, Double)] = [
                    (1, fixture.isRestrainedX, fixture.elasticStiffness.x),
                    (2, fixture.isRestrainedY, fixture.elasticStiffness.y),
                    (3, fixture.isRestrainedZ, fixture.elasticStiffness.z)
                ]
                for (axis, isRestrained, stiffnessVal) in axes where isRestrained && stiffnessVal > 0 {
                    let kPerNodeMm = (stiffnessVal / Double(nodesToUse.count)) * 0.001
                    for nId in nodesToUse {
                        springElemId += 1
                        let elsetName = "ESPRING_\(springElemId)_\(axis)"
                        lines.append("*ELEMENT, TYPE=SPRING1, ELSET=\(elsetName)")
                        lines.append("\(springElemId), \(nId)")
                        lines.append("*SPRING, ELSET=\(elsetName)")
                        lines.append("\(axis)")
                        lines.append(String(format: "%.4f", kPerNodeMm))
                    }
                }
            }
        }

        // Bonded contact connections (*TIE before *STEP) (BL-FEA-04, #222)
        if study.studyType != .thermalConduction {
            for connection in study.connections where connection.kind == .bonded {
                let sanitized = connection.name.uppercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "-", with: "_")

                let sourceNodes = resolveConnectionSourceNodeIds(for: connection, setByName: setByName)
                let targetNodes = resolveConnectionTargetNodeIds(for: connection, setByName: setByName)

                let sourceNset = "\(sanitized)_SOURCE"
                let targetNset = "\(sanitized)_TARGET"

                if !sourceNodes.isEmpty {
                    lines.append("*NSET, NSET=\(sourceNset)")
                    for chunk in stride(from: 0, to: sourceNodes.count, by: 16) {
                        let end = min(chunk + 16, sourceNodes.count)
                        let chunkStr = sourceNodes[chunk..<end].map(String.init).joined(separator: ", ")
                        lines.append(chunkStr)
                    }
                }

                if !targetNodes.isEmpty {
                    lines.append("*NSET, NSET=\(targetNset)")
                    for chunk in stride(from: 0, to: targetNodes.count, by: 16) {
                        let end = min(chunk + 16, targetNodes.count)
                        let chunkStr = targetNodes[chunk..<end].map(String.init).joined(separator: ", ")
                        lines.append(chunkStr)
                    }
                }

                let tol: Double
                if let st = connection.searchTolerance, st > 0 {
                    tol = st
                } else {
                    var minPos = SIMD3<Double>(repeating: .infinity)
                    var maxPos = SIMD3<Double>(repeating: -.infinity)
                    for node in mesh.nodes {
                        minPos = simd_min(minPos, node.position)
                        maxPos = simd_max(maxPos, node.position)
                    }
                    let extents = maxPos - minPos
                    let maxDim = max(max(extents.x, extents.y), extents.z)
                    tol = max(1e-4, maxDim * 0.005)
                }
                let toleranceStr = String(format: "%.4f", tol)

                lines.append("*SURFACE, NAME=SURF_\(sanitized)_SOURCE, TYPE=NODE")
                lines.append(sourceNset)
                lines.append("*SURFACE, NAME=SURF_\(sanitized)_TARGET, TYPE=NODE")
                lines.append(targetNset)

                lines.append("*TIE, NAME=\(sanitized)_TIE, POSITION TOLERANCE=\(toleranceStr)")
                lines.append("SURF_\(sanitized)_SOURCE, SURF_\(sanitized)_TARGET")
            }
        }

        // Initial conditions for structural thermal loads
        if study.studyType != .thermalConduction {
            let refTemp = study.thermalReferenceTemperature ?? 20.0
            if (nodalTemperatures != nil && !nodalTemperatures!.isEmpty) || study.thermalStudyId != nil {
                lines.append("*INITIAL CONDITIONS, TYPE=TEMPERATURE")
                lines.append(String(format: "NALL, %.4f", refTemp))
            } else {
                let thermalLoads = study.loads.filter { $0.kind == .thermalLoad || $0.kind == .temperature }
                if !thermalLoads.isEmpty {
                    let ref = thermalLoads.first?.referenceTemperature ?? refTemp
                    lines.append("*INITIAL CONDITIONS, TYPE=TEMPERATURE")
                    lines.append(String(format: "NALL, %.4f", ref))
                }
            }
        }

        // Analysis step
        lines.append("*STEP")

        if study.studyType == .thermalConduction {
            lines.append("*HEAT TRANSFER, STEADY STATE")

            // Boundary conditions (DOF 11 for temperature)
            var hasBoundaryHeader = false
            for load in study.loads where load.kind == .temperature {
                if !hasBoundaryHeader {
                    lines.append("*BOUNDARY")
                    hasBoundaryHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                if !targetNodes.isEmpty {
                    for nId in targetNodes {
                        lines.append(String(format: "%d, 11, 11, %.4f", nId, load.magnitude))
                    }
                } else if let firstNode = mesh.nodes.first {
                    lines.append(String(format: "%d, 11, 11, %.4f", firstNode.id, load.magnitude))
                }
            }

            // Convection films
            var hasFilmHeader = false
            for load in study.loads where load.kind == .convection {
                if !hasFilmHeader {
                    lines.append("*FILM")
                    hasFilmHeader = true
                }
                let h = load.magnitude
                let tInf = load.ambientTemperature ?? 20.0
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                if !targetNodes.isEmpty {
                    for nId in targetNodes {
                        lines.append(String(format: "%d, 11, %.4f, %.4f", nId, tInf, h))
                    }
                } else if let lastNode = mesh.nodes.last {
                    lines.append(String(format: "%d, 11, %.4f, %.4f", lastNode.id, tInf, h))
                }
            }

            // Distributed surface heat flux
            var hasDfluxHeader = false
            for load in study.loads where load.kind == .thermalFlux {
                if !hasDfluxHeader {
                    lines.append("*DFLUX")
                    hasDfluxHeader = true
                }
                let q = load.magnitude
                let targetElements = resolveElementIds(for: load, setByName: setByName)
                if !targetElements.isEmpty {
                    for elId in targetElements {
                        lines.append(String(format: "%d, S1, %.4f", elId, q))
                    }
                } else if let firstEl = mesh.elements.first {
                    lines.append(String(format: "%d, S1, %.4f", firstEl.id, q))
                }
            }

            // Concentrated nodal heat power
            var hasCfluxHeader = false
            for load in study.loads where load.kind == .heatPower {
                if !hasCfluxHeader {
                    lines.append("*CFLUX")
                    hasCfluxHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                let nodesToUse = targetNodes.isEmpty ? (mesh.nodes.first.map { [$0.id] } ?? []) : targetNodes
                let powerPerNode = nodesToUse.isEmpty ? load.magnitude : (load.magnitude / Double(nodesToUse.count))
                for nId in nodesToUse {
                    lines.append(String(format: "%d, 11, %.4f", nId, powerPerNode))
                }
            }

            // Output requests for thermal
            lines.append("*NODE FILE")
            lines.append("NT")
            lines.append("*EL FILE")
            lines.append("HFL")

        } else if study.studyType == .modalFrequency {
            if study.solver.isPrestressEnabled && !study.loads.isEmpty {
                // Step 1: Static preload step
                lines.append("*STATIC")
                emitBoundaryCards(study: study, mesh: mesh, setByName: setByName, lines: &lines)
                emitStructuralLoadCards(study: study, mesh: mesh, setByName: setByName, nodalTemperatures: nodalTemperatures, lines: &lines)
                lines.append("*END STEP")

                // Step 2: Frequency perturbation extraction step
                lines.append("*STEP, PERTURBATION")
                lines.append("*FREQUENCY")
                lines.append("\(study.solver.modeCount)")
                emitBoundaryCards(study: study, mesh: mesh, setByName: setByName, lines: &lines)
                lines.append("*NODE FILE")
                lines.append("U")
            } else {
                lines.append("*FREQUENCY")
                lines.append("\(study.solver.modeCount)")
                emitBoundaryCards(study: study, mesh: mesh, setByName: setByName, lines: &lines)
                lines.append("*NODE FILE")
                lines.append("U")
            }
        } else {
            // Structural analysis or linear buckling
            if study.studyType == .linearBuckling {
                lines.append("*BUCKLE")
                lines.append("\(max(1, study.solver.bucklingModesCount))")
            } else {
                lines.append("*STATIC")
            }
            emitBoundaryCards(study: study, mesh: mesh, setByName: setByName, lines: &lines)
            emitStructuralLoadCards(study: study, mesh: mesh, setByName: setByName, nodalTemperatures: nodalTemperatures, lines: &lines)

            // Output requests for structural / buckling
            lines.append("*NODE FILE")
            lines.append("U")
            if study.studyType != .linearBuckling {
                lines.append("*EL FILE")
                lines.append("S")
            }
        }

        lines.append("*END STEP")

        let content = lines.joined(separator: "\n") + "\n"
        return CAEDeck(studyId: study.id, jobName: jobName, deckContent: content)
    }

    private static func emitBoundaryCards(
        study: SimulationStudy,
        mesh: VolumeMesh,
        setByName: [String: VolumeMeshSet],
        lines: inout [String]
    ) {
        var hasBoundaryHeader = false
        for fixture in study.fixtures where fixture.kind != .elasticSupport {
            if !hasBoundaryHeader {
                lines.append("*BOUNDARY")
                hasBoundaryHeader = true
            }
            let targetNodes = resolveFixtureNodeIds(for: fixture, setByName: setByName)
            let nodesToFix = targetNodes.isEmpty ? (mesh.nodes.prefix(3).map(\.id)) : targetNodes
            for nId in nodesToFix {
                switch fixture.kind {
                case .fixed, .pinned:
                    lines.append("\(nId), 1, 3, 0.0")
                case .rollerSlider, .symmetry:
                    if fixture.isRestrainedX && fixture.isRestrainedY && fixture.isRestrainedZ {
                        lines.append("\(nId), 1, 3, 0.0")
                    } else {
                        if fixture.isRestrainedX { lines.append("\(nId), 1, 1, 0.0") }
                        if fixture.isRestrainedY { lines.append("\(nId), 2, 2, 0.0") }
                        if fixture.isRestrainedZ { lines.append("\(nId), 3, 3, 0.0") }
                    }
                case .prescribedDisplacement:
                    if fixture.isRestrainedX { lines.append(String(format: "%d, 1, 1, %.4f", nId, fixture.prescribedDisplacement.x)) }
                    if fixture.isRestrainedY { lines.append(String(format: "%d, 2, 2, %.4f", nId, fixture.prescribedDisplacement.y)) }
                    if fixture.isRestrainedZ { lines.append(String(format: "%d, 3, 3, %.4f", nId, fixture.prescribedDisplacement.z)) }
                case .elasticSupport:
                    break
                }
            }
        }
    }

    private static func emitStructuralLoadCards(
        study: SimulationStudy,
        mesh: VolumeMesh,
        setByName: [String: VolumeMeshSet],
        nodalTemperatures: [Int: Double]? = nil,
        lines: inout [String]
    ) {
        // Concentrated and equivalent nodal forces (*CLOAD)
        var hasCloadHeader = false
        for load in study.loads {
            switch load.kind {
            case .force:
                if !hasCloadHeader {
                    lines.append("*CLOAD")
                    hasCloadHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                let nodesToUse = targetNodes.isEmpty ? (mesh.nodes.last.map { [$0.id] } ?? []) : targetNodes
                let share = nodesToUse.isEmpty ? 1.0 : (1.0 / Double(nodesToUse.count))
                let forceVec = load.direction * load.magnitude * share
                for nId in nodesToUse {
                    if abs(forceVec.x) > 1e-6 { lines.append(String(format: "%d, 1, %.4f", nId, forceVec.x)) }
                    if abs(forceVec.y) > 1e-6 { lines.append(String(format: "%d, 2, %.4f", nId, forceVec.y)) }
                    if abs(forceVec.z) > 1e-6 { lines.append(String(format: "%d, 3, %.4f", nId, forceVec.z)) }
                }

            case .moment:
                if !hasCloadHeader {
                    lines.append("*CLOAD")
                    hasCloadHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                let nodesToUse = targetNodes.isEmpty ? (mesh.nodes.map(\.id)) : targetNodes
                guard nodesToUse.count > 1 else { continue }
                let nodePositions = Dictionary(uniqueKeysWithValues: mesh.nodes.map { ($0.id, $0.position) })
                var rc = SIMD3<Double>.zero
                for nId in nodesToUse {
                    rc += nodePositions[nId] ?? .zero
                }
                rc /= Double(nodesToUse.count)
                let momentVec = load.direction * load.magnitude
                guard simd_length(momentVec) > 1e-15 else { continue }

                var J0 = SIMD3<Double>.zero, J1 = SIMD3<Double>.zero, J2 = SIMD3<Double>.zero
                var drList = [(id: Int, dr: SIMD3<Double>)]()
                for nId in nodesToUse {
                    let dr = (nodePositions[nId] ?? .zero) - rc
                    drList.append((nId, dr))
                    let rSq = simd_dot(dr, dr)
                    J0 += SIMD3<Double>(rSq - dr.x * dr.x, -dr.x * dr.y, -dr.x * dr.z)
                    J1 += SIMD3<Double>(-dr.y * dr.x, rSq - dr.y * dr.y, -dr.y * dr.z)
                    J2 += SIMD3<Double>(-dr.z * dr.x, -dr.z * dr.y, rSq - dr.z * dr.z)
                }
                guard let Jinv = invert3x3Matrix((J0, J1, J2)) else { continue }
                let omega = multiply3x3Vector(Jinv, momentVec)
                for item in drList {
                    let Fi = simd_cross(omega, item.dr)
                    if abs(Fi.x) > 1e-6 { lines.append(String(format: "%d, 1, %.4f", item.id, Fi.x)) }
                    if abs(Fi.y) > 1e-6 { lines.append(String(format: "%d, 2, %.4f", item.id, Fi.y)) }
                    if abs(Fi.z) > 1e-6 { lines.append(String(format: "%d, 3, %.4f", item.id, Fi.z)) }
                }

            case .remoteLoad:
                if !hasCloadHeader {
                    lines.append("*CLOAD")
                    hasCloadHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                let nodesToUse = targetNodes.isEmpty ? (mesh.nodes.map(\.id)) : targetNodes
                guard !nodesToUse.isEmpty else { continue }
                let nodePositions = Dictionary(uniqueKeysWithValues: mesh.nodes.map { ($0.id, $0.position) })
                var rc = SIMD3<Double>.zero
                for nId in nodesToUse {
                    rc += nodePositions[nId] ?? .zero
                }
                rc /= Double(nodesToUse.count)

                let remotePt = load.remotePoint ?? rc
                let netForce = load.direction * load.magnitude
                let extMoment = load.remoteMoment ?? .zero
                let share = 1.0 / Double(nodesToUse.count)
                let transForce = netForce * share
                let inducedMoment = extMoment + simd_cross(rc - remotePt, netForce)

                var rotForces = [Int: SIMD3<Double>]()
                if simd_length(inducedMoment) > 1e-15 && nodesToUse.count > 1 {
                    var J0 = SIMD3<Double>.zero, J1 = SIMD3<Double>.zero, J2 = SIMD3<Double>.zero
                    var drList = [(id: Int, dr: SIMD3<Double>)]()
                    for nId in nodesToUse {
                        let dr = (nodePositions[nId] ?? .zero) - rc
                        drList.append((nId, dr))
                        let rSq = simd_dot(dr, dr)
                        J0 += SIMD3<Double>(rSq - dr.x * dr.x, -dr.x * dr.y, -dr.x * dr.z)
                        J1 += SIMD3<Double>(-dr.y * dr.x, rSq - dr.y * dr.y, -dr.y * dr.z)
                        J2 += SIMD3<Double>(-dr.z * dr.x, -dr.z * dr.y, rSq - dr.z * dr.z)
                    }
                    if let Jinv = invert3x3Matrix((J0, J1, J2)) {
                        let omega = multiply3x3Vector(Jinv, inducedMoment)
                        for item in drList {
                            rotForces[item.id] = simd_cross(omega, item.dr)
                        }
                    }
                }

                for nId in nodesToUse {
                    let totalFi = transForce + (rotForces[nId] ?? .zero)
                    if abs(totalFi.x) > 1e-6 { lines.append(String(format: "%d, 1, %.4f", nId, totalFi.x)) }
                    if abs(totalFi.y) > 1e-6 { lines.append(String(format: "%d, 2, %.4f", nId, totalFi.y)) }
                    if abs(totalFi.z) > 1e-6 { lines.append(String(format: "%d, 3, %.4f", nId, totalFi.z)) }
                }

            case .bearing:
                if !hasCloadHeader {
                    lines.append("*CLOAD")
                    hasCloadHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                let nodesToUse = targetNodes.isEmpty ? (mesh.nodes.map(\.id)) : targetNodes
                guard !nodesToUse.isEmpty else { continue }
                let dir = load.direction
                let netForceMag = load.magnitude
                let share = 1.0 / Double(nodesToUse.count)
                let forceVec = dir * netForceMag * share
                for nId in nodesToUse {
                    if abs(forceVec.x) > 1e-6 { lines.append(String(format: "%d, 1, %.4f", nId, forceVec.x)) }
                    if abs(forceVec.y) > 1e-6 { lines.append(String(format: "%d, 2, %.4f", nId, forceVec.y)) }
                    if abs(forceVec.z) > 1e-6 { lines.append(String(format: "%d, 3, %.4f", nId, forceVec.z)) }
                }

            default:
                break
            }
        }

        // Distributed loads (*DLOAD for pressure, gravity, centrifugal)
        var hasDloadHeader = false
        for load in study.loads {
            if load.kind == .pressure {
                if !hasDloadHeader {
                    lines.append("*DLOAD")
                    hasDloadHeader = true
                }
                let targetElements = resolveElementIds(for: load, setByName: setByName)
                let elementsToUse = targetElements.isEmpty ? (mesh.elements.first.map { [$0.id] } ?? []) : targetElements
                for elId in elementsToUse {
                    lines.append(String(format: "%d, P1, %.4f", elId, load.magnitude))
                }
            } else if load.kind == .gravity {
                if !hasDloadHeader {
                    lines.append("*DLOAD")
                    hasDloadHeader = true
                }
                let dir = load.direction
                lines.append(String(format: "EALL, GRAV, %.4f, %.4f, %.4f, %.4f", load.magnitude, dir.x, dir.y, dir.z))
            } else if load.kind == .centrifugal {
                if !hasDloadHeader {
                    lines.append("*DLOAD")
                    hasDloadHeader = true
                }
                let omega = load.magnitude
                let omegaSq = omega * omega
                let axisLen = simd_length(load.direction)
                let axis = axisLen > 1e-6 ? load.direction / axisLen : SIMD3<Double>(0, 0, 1)
                let p1 = load.axisOrigin ?? .zero
                let p2 = p1 + axis
                lines.append(String(format: "EALL, CENTRIF, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f", omegaSq, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z))
            }
        }

        // Structural temperature loads (*TEMPERATURE)
        if let nodalTemperatures, !nodalTemperatures.isEmpty {
            lines.append("*TEMPERATURE")
            for node in mesh.nodes.sorted(by: { $0.id < $1.id }) {
                if let temp = nodalTemperatures[node.id] {
                    lines.append(String(format: "%d, %.4f", node.id, temp))
                }
            }
        } else {
            var hasTempHeader = false
            for load in study.loads where load.kind == .thermalLoad || load.kind == .temperature {
                if !hasTempHeader {
                    lines.append("*TEMPERATURE")
                    hasTempHeader = true
                }
                let targetNodes = resolveNodeIds(for: load, setByName: setByName)
                if !targetNodes.isEmpty {
                    for nId in targetNodes {
                        lines.append(String(format: "%d, %.4f", nId, load.magnitude))
                    }
                } else {
                    lines.append(String(format: "NALL, %.4f", load.magnitude))
                }
            }
        }
    }

    private static func resolveNodeIds(for load: SimulationLoad, setByName: [String: VolumeMeshSet]) -> [Int] {
        setByName[load.name]?.nodeIds
            ?? load.groupNames.compactMap({ setByName[$0]?.nodeIds }).first
            ?? load.targetReferences.compactMap({ setByName[$0.targetName]?.nodeIds }).first
            ?? []
    }

    private static func resolveElementIds(for load: SimulationLoad, setByName: [String: VolumeMeshSet]) -> [Int] {
        setByName[load.name]?.elementIds
            ?? load.groupNames.compactMap({ setByName[$0]?.elementIds }).first
            ?? load.targetReferences.compactMap({ setByName[$0.targetName]?.elementIds }).first
            ?? []
    }

    private static func resolveFixtureNodeIds(for fixture: SimulationFixture, setByName: [String: VolumeMeshSet]) -> [Int] {
        setByName[fixture.name]?.nodeIds
            ?? fixture.groupNames.compactMap({ setByName[$0]?.nodeIds }).first
            ?? fixture.targetReferences.compactMap({ setByName[$0.targetName]?.nodeIds }).first
            ?? []
    }

    private static func resolveConnectionSourceNodeIds(for connection: SimulationConnection, setByName: [String: VolumeMeshSet]) -> [Int] {
        if let explicit = setByName["\(connection.name)_Source"]?.nodeIds, !explicit.isEmpty {
            return explicit
        }
        for g in connection.sourceGroupNames {
            if let s = setByName[g]?.nodeIds, !s.isEmpty { return s }
        }
        for ref in connection.sourceReferences {
            if let s = setByName[ref.targetName]?.nodeIds, !s.isEmpty { return s }
        }
        return []
    }

    private static func resolveConnectionTargetNodeIds(for connection: SimulationConnection, setByName: [String: VolumeMeshSet]) -> [Int] {
        if let explicit = setByName["\(connection.name)_Target"]?.nodeIds, !explicit.isEmpty {
            return explicit
        }
        for g in connection.targetGroupNames {
            if let s = setByName[g]?.nodeIds, !s.isEmpty { return s }
        }
        for ref in connection.targetReferences {
            if let s = setByName[ref.targetName]?.nodeIds, !s.isEmpty { return s }
        }
        return []
    }

    private static func invert3x3Matrix(_ J: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)? {
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

    private static func multiply3x3Vector(_ M: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>), _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            simd_dot(M.0, v),
            simd_dot(M.1, v),
            simd_dot(M.2, v)
        )
    }
}
