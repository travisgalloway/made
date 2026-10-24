import Foundation
import simd

/// Generates standardized CalculiX `.inp` input decks for thermal and structural simulation studies (ADR-D5, BL-THM-01, #190).
public enum CalculiXDeckBuilder: Sendable {

    /// Constructs a complete CalculiX `.inp` deck specification from a simulation study and volume mesh.
    ///
    /// - Parameters:
    ///   - study: CAE simulation study containing materials, boundary conditions, and solver parameters.
    ///   - mesh: Discretized finite element volume mesh.
    /// - Returns: A `CAEDeck` containing the formatted deck and auxiliary files.
    public static func buildDeck(study: SimulationStudy, mesh: VolumeMesh) -> CAEDeck {
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
            lines.append("*ELASTIC")
            lines.append("210000.0, 0.3") // Standard steel MPa, Poisson ratio
        }

        lines.append("*SOLID SECTION, ELSET=EALL, MATERIAL=\(matName)")

        // Node and element sets
        let sets = mesh.sets.isEmpty ? MeshGeometryAssociator.associate(mesh: mesh, study: study) : mesh.sets
        var setByName: [String: VolumeMeshSet] = [:]
        for s in sets {
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

        } else {
            // Structural analysis
            lines.append("*STATIC")

            // Fixtures
            var hasBoundaryHeader = false
            for fixture in study.fixtures {
                if !hasBoundaryHeader {
                    lines.append("*BOUNDARY")
                    hasBoundaryHeader = true
                }
                let targetNodes = resolveFixtureNodeIds(for: fixture, setByName: setByName)
                let nodesToFix = targetNodes.isEmpty ? (mesh.nodes.prefix(3).map { $0.id }) : targetNodes
                for nId in nodesToFix {
                    if fixture.isRestrainedX && fixture.isRestrainedY && fixture.isRestrainedZ {
                        lines.append("\(nId), 1, 3, 0.0")
                    } else {
                        if fixture.isRestrainedX { lines.append("\(nId), 1, 1, 0.0") }
                        if fixture.isRestrainedY { lines.append("\(nId), 2, 2, 0.0") }
                        if fixture.isRestrainedZ { lines.append("\(nId), 3, 3, 0.0") }
                    }
                }
            }

            // Concentrated forces
            var hasCloadHeader = false
            for load in study.loads where load.kind == .force {
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
            }

            // Output requests for structural
            lines.append("*NODE FILE")
            lines.append("U")
            lines.append("*EL FILE")
            lines.append("S")
        }

        lines.append("*END STEP")

        let content = lines.joined(separator: "\n") + "\n"
        return CAEDeck(studyId: study.id, jobName: jobName, deckContent: content)
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
}
