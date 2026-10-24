import Foundation
import simd

/// Deterministic CAD geometry to finite element mesh set associator (ADR-D5 §4, ADR-D3, #189).
public enum MeshGeometryAssociator {

    /// Associates finite element volume mesh nodes and elements to simulation study fixtures, loads, and geometry groups.
    public static func associate(
        mesh: VolumeMesh,
        study: SimulationStudy
    ) -> [VolumeMeshSet] {
        var resultSets: [VolumeMeshSet] = []

        // Preserve pre-existing physical sets from mesh
        for s in mesh.sets {
            resultSets.append(s)
        }

        // Associate geometry groups
        for group in study.groups {
            var groupElementIds = Set<Int>()
            var groupNodeIds = Set<Int>()
            for ref in group.targetReferences {
                let res = associate(reference: ref, mesh: mesh)
                groupElementIds.formUnion(res.elementIds)
                groupNodeIds.formUnion(res.nodeIds)
            }
            let set = VolumeMeshSet(
                id: group.id,
                name: group.name,
                nodeIds: groupNodeIds.sorted(),
                elementIds: groupElementIds.sorted(),
                subelementType: group.subelementType ?? .face
            )
            if let idx = resultSets.firstIndex(where: { $0.name == set.name }) {
                resultSets[idx] = set
            } else {
                resultSets.append(set)
            }
        }

        // Associate fixtures
        for fixture in study.fixtures {
            let set: VolumeMeshSet
            if fixture.targetReferences.isEmpty && fixture.groupNames.isEmpty {
                // Fallback: all boundary surfaces
                let boundaryTriangles = getBoundaryTriangles(mesh: mesh)
                let elIds = boundaryTriangles.map { $0.id }.sorted()
                let nIds = Array(Set(boundaryTriangles.flatMap { $0.nodeIndices })).sorted()
                set = VolumeMeshSet(
                    id: fixture.id,
                    name: fixture.name,
                    nodeIds: nIds,
                    elementIds: elIds,
                    subelementType: .face
                )
            } else {
                var fElementIds = Set<Int>()
                var fNodeIds = Set<Int>()
                for ref in fixture.targetReferences {
                    let res = associate(reference: ref, mesh: mesh)
                    fElementIds.formUnion(res.elementIds)
                    fNodeIds.formUnion(res.nodeIds)
                }
                for gName in fixture.groupNames {
                    if let grp = study.groups.first(where: { $0.name == gName }) {
                        for ref in grp.targetReferences {
                            let res = associate(reference: ref, mesh: mesh)
                            fElementIds.formUnion(res.elementIds)
                            fNodeIds.formUnion(res.nodeIds)
                        }
                    } else if let existing = resultSets.first(where: { $0.name == gName }) {
                        fElementIds.formUnion(existing.elementIds)
                        fNodeIds.formUnion(existing.nodeIds)
                    }
                }
                set = VolumeMeshSet(
                    id: fixture.id,
                    name: fixture.name,
                    nodeIds: fNodeIds.sorted(),
                    elementIds: fElementIds.sorted(),
                    subelementType: .face
                )
            }
            if let idx = resultSets.firstIndex(where: { $0.name == set.name }) {
                resultSets[idx] = set
            } else {
                resultSets.append(set)
            }
        }

        // Associate loads
        for load in study.loads {
            let set: VolumeMeshSet
            if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                if load.kind == .gravity || load.kind == .centrifugal || load.kind == .thermalLoad || load.kind == .temperature {
                    // Fallback: all volume elements and all nodes
                    let elIds = mesh.elements.map { $0.id }.sorted()
                    let nIds = mesh.nodes.map { $0.id }.sorted()
                    set = VolumeMeshSet(
                        id: load.id,
                        name: load.name,
                        nodeIds: nIds,
                        elementIds: elIds,
                        subelementType: nil
                    )
                } else {
                    // Fallback: all boundary surfaces
                    let boundaryTriangles = getBoundaryTriangles(mesh: mesh)
                    let elIds = boundaryTriangles.map { $0.id }.sorted()
                    let nIds = Array(Set(boundaryTriangles.flatMap { $0.nodeIndices })).sorted()
                    set = VolumeMeshSet(
                        id: load.id,
                        name: load.name,
                        nodeIds: nIds,
                        elementIds: elIds,
                        subelementType: .face
                    )
                }
            } else {
                var lElementIds = Set<Int>()
                var lNodeIds = Set<Int>()
                for ref in load.targetReferences {
                    let res = associate(reference: ref, mesh: mesh)
                    lElementIds.formUnion(res.elementIds)
                    lNodeIds.formUnion(res.nodeIds)
                }
                for gName in load.groupNames {
                    if let grp = study.groups.first(where: { $0.name == gName }) {
                        for ref in grp.targetReferences {
                            let res = associate(reference: ref, mesh: mesh)
                            lElementIds.formUnion(res.elementIds)
                            lNodeIds.formUnion(res.nodeIds)
                        }
                    } else if let existing = resultSets.first(where: { $0.name == gName }) {
                        lElementIds.formUnion(existing.elementIds)
                        lNodeIds.formUnion(existing.nodeIds)
                    }
                }
                let isBodyLoad = load.kind == .gravity || load.kind == .centrifugal || load.kind == .thermalLoad || load.kind == .temperature
                set = VolumeMeshSet(
                    id: load.id,
                    name: load.name,
                    nodeIds: lNodeIds.sorted(),
                    elementIds: lElementIds.sorted(),
                    subelementType: isBodyLoad ? nil : .face
                )
            }
            if let idx = resultSets.firstIndex(where: { $0.name == set.name }) {
                resultSets[idx] = set
            } else {
                resultSets.append(set)
            }
        }

        return resultSets
    }

    /// Associates an individual geometry reference to finite element node and element indices.
    public static func associate(
        reference: SimulationGeometryReference,
        mesh: VolumeMesh
    ) -> (nodeIds: [Int], elementIds: [Int]) {
        guard !mesh.nodes.isEmpty else { return ([], []) }

        // If targetName matches an existing physical or named set, return its members
        if let existing = mesh.set(named: reference.targetName) {
            return (existing.nodeIds, existing.elementIds)
        }

        // Check if reference explicitly targets solid body
        let lowerName = reference.targetName.lowercased()
        if reference.subelementType == nil && (lowerName.contains("body") || lowerName.contains("solid")) {
            return (mesh.nodes.map { $0.id }.sorted(), mesh.elements.map { $0.id }.sorted())
        }

        let nodeMap = Dictionary(uniqueKeysWithValues: mesh.nodes.map { ($0.id, $0.position) })

        // Compute mesh bounds
        var minPos = SIMD3<Double>(repeating: .infinity)
        var maxPos = SIMD3<Double>(repeating: -.infinity)
        for node in mesh.nodes {
            minPos = simd_min(minPos, node.position)
            maxPos = simd_max(maxPos, node.position)
        }
        let extents = maxPos - minPos
        let maxDim = max(max(extents.x, extents.y), extents.z)
        let tolerance = max(1e-4, maxDim * 0.005)

        // Determine face canonical label or normal specification
        let label = (reference.topologicalReference?.historyPath.last?.label ?? reference.targetName).lowercased()
        let canonicalKind = CanonicalFaceKind(from: label)

        let disambiguatorNormal = reference.topologicalReference?.disambiguator?.normal.map { SIMD3<Double>($0) }
        let disambiguatorCentroid = reference.topologicalReference?.disambiguator?.centroid.map { SIMD3<Double>($0) }

        // Edge association
        if reference.subelementType == .edge || label.hasPrefix("edge:") {
            if let centroid = disambiguatorCentroid {
                let matchedNodes = mesh.nodes.filter { simd_distance($0.position, centroid) <= tolerance * 2.0 }.map { $0.id }
                return (matchedNodes.sorted(), [])
            }
            return ([], [])
        }

        // Vertex association
        if reference.subelementType == .vertex || label.hasPrefix("vertex:") {
            if let centroid = disambiguatorCentroid {
                let matchedNodes = mesh.nodes.filter { simd_distance($0.position, centroid) <= tolerance * 2.0 }.map { $0.id }
                return (matchedNodes.sorted(), [])
            }
            return ([], [])
        }

        // Face association: evaluate boundary surface triangles
        let surfaceTriangles = getBoundaryTriangles(mesh: mesh)
        var matchedElementIds: [Int] = []
        var matchedNodeIds = Set<Int>()

        for tri in surfaceTriangles {
            guard tri.nodeIndices.count >= 3,
                  let p0 = nodeMap[tri.nodeIndices[0]],
                  let p1 = nodeMap[tri.nodeIndices[1]],
                  let p2 = nodeMap[tri.nodeIndices[2]] else {
                continue
            }

            let v01 = p1 - p0
            let v02 = p2 - p0
            let cross = simd_cross(v01, v02)
            let len = simd_length(cross)
            guard len > 1e-12 else { continue }
            let triNormal = cross / len

            let triCentroid = (p0 + p1 + p2) / 3.0
            let triNodes = tri.nodeIndices.compactMap { nodeMap[$0] }

            var isMatch = false

            if let canonical = canonicalKind {
                let targetNormal = canonical.normal
                let targetCoord: Double
                switch canonical {
                case .top: targetCoord = maxPos.z
                case .bottom: targetCoord = minPos.z
                case .front: targetCoord = minPos.y
                case .back: targetCoord = maxPos.y
                case .right: targetCoord = maxPos.x
                case .left: targetCoord = minPos.x
                }

                // Check normal alignment (accounting for outward orientation or reversed winding)
                let dotProd = simd_dot(triNormal, targetNormal)
                let normalAligned = dotProd >= 0.95 || abs(dotProd) >= 0.95

                if normalAligned {
                    // Check that all triangle nodes lie on the canonical coordinate plane within tolerance
                    let coordsMatch = triNodes.allSatisfy { p in
                        switch canonical {
                        case .top, .bottom:
                            return abs(p.z - targetCoord) <= tolerance
                        case .front, .back:
                            return abs(p.y - targetCoord) <= tolerance
                        case .right, .left:
                            return abs(p.x - targetCoord) <= tolerance
                        }
                    }
                    if coordsMatch {
                        isMatch = true
                    }
                }
            } else if let targetN = disambiguatorNormal {
                let normN = simd_normalize(targetN)
                let dotProd = simd_dot(triNormal, normN)
                let effN: SIMD3<Double>?
                if dotProd >= 0.95 {
                    effN = triNormal
                } else if simd_dot(-triNormal, normN) >= 0.95 {
                    effN = -triNormal
                } else {
                    effN = nil
                }

                if let effN, simd_dot(effN, normN) >= 0.95 {
                    if let c = disambiguatorCentroid {
                        let expectedD = simd_dot(normN, c)
                        let dist = abs(simd_dot(normN, triCentroid) - expectedD)
                        if dist <= tolerance {
                            isMatch = true
                        }
                    } else {
                        isMatch = true
                    }
                }
            }

            if isMatch {
                matchedElementIds.append(tri.id)
                matchedNodeIds.formUnion(tri.nodeIndices)
            }
        }

        return (matchedNodeIds.sorted(), matchedElementIds.sorted())
    }

    /// Returns boundary surface triangles, either directly from mesh.surfaceTriangles or reconstructed from tetrahedra.
    private static func getBoundaryTriangles(mesh: VolumeMesh) -> [VolumeMeshElement] {
        if !mesh.surfaceTriangles.isEmpty {
            return mesh.surfaceTriangles
        }

        // Reconstruct boundary faces from tetrahedra
        var faceCount: [CanonicalFaceKey: (elementId: Int, order: MeshElementOrder, nodeIndices: [Int])] = [:]
        for tet in mesh.elements {
            guard tet.nodeIndices.count >= 4 else { continue }
            let corners = Array(tet.nodeIndices.prefix(4))
            let tetFaces: [[Int]]
            if tet.order == .quadratic && tet.nodeIndices.count >= 10 {
                // C3D10 10-node tetrahedron faces with quadratic mid-side nodes
                tetFaces = [
                    [corners[0], corners[1], corners[2], tet.nodeIndices[4], tet.nodeIndices[5], tet.nodeIndices[6]],
                    [corners[0], corners[1], corners[3], tet.nodeIndices[4], tet.nodeIndices[8], tet.nodeIndices[7]],
                    [corners[1], corners[2], corners[3], tet.nodeIndices[5], tet.nodeIndices[9], tet.nodeIndices[8]],
                    [corners[0], corners[2], corners[3], tet.nodeIndices[6], tet.nodeIndices[9], tet.nodeIndices[7]]
                ]
            } else {
                // C3D4 4-node linear tetrahedron faces
                tetFaces = [
                    [corners[0], corners[1], corners[2]],
                    [corners[0], corners[1], corners[3]],
                    [corners[1], corners[2], corners[3]],
                    [corners[0], corners[2], corners[3]]
                ]
            }

            for fNodes in tetFaces {
                let key = CanonicalFaceKey(nodes: Array(fNodes.prefix(3)))
                if faceCount[key] != nil {
                    faceCount[key] = nil // Shared interior face
                } else {
                    faceCount[key] = (tet.id, tet.order, fNodes)
                }
            }
        }

        var reconstructed: [VolumeMeshElement] = []
        var nextId = (mesh.elements.map { $0.id }.max() ?? 0) + 1
        for (_, entry) in faceCount {
            reconstructed.append(VolumeMeshElement(
                id: nextId,
                order: entry.order,
                nodeIndices: entry.nodeIndices,
                tag: 0
            ))
            nextId += 1
        }
        return reconstructed
    }

    private struct CanonicalFaceKey: Hashable {
        let n0: Int
        let n1: Int
        let n2: Int

        init(nodes: [Int]) {
            let sorted = nodes.sorted()
            n0 = sorted[0]
            n1 = sorted[1]
            n2 = sorted[2]
        }
    }

    private enum CanonicalFaceKind {
        case top
        case bottom
        case front
        case back
        case right
        case left

        init?(from label: String) {
            let lower = label.lowercased()
            if lower == "face:top" || lower == "top" || lower.hasPrefix("top_") || lower.hasSuffix("_top") {
                self = .top
            } else if lower == "face:bottom" || lower == "bottom" || lower.hasPrefix("bottom_") || lower.hasSuffix("_bottom") {
                self = .bottom
            } else if lower == "face:front" || lower == "front" || lower.hasPrefix("front_") || lower.hasSuffix("_front") {
                self = .front
            } else if lower == "face:back" || lower == "back" || lower.hasPrefix("back_") || lower.hasSuffix("_back") {
                self = .back
            } else if lower == "face:right" || lower == "right" || lower.hasPrefix("right_") || lower.hasSuffix("_right") {
                self = .right
            } else if lower == "face:left" || lower == "left" || lower.hasPrefix("left_") || lower.hasSuffix("_left") {
                self = .left
            } else {
                return nil
            }
        }

        var normal: SIMD3<Double> {
            switch self {
            case .top: return SIMD3<Double>(0, 0, 1)
            case .bottom: return SIMD3<Double>(0, 0, -1)
            case .front: return SIMD3<Double>(0, -1, 0)
            case .back: return SIMD3<Double>(0, 1, 0)
            case .right: return SIMD3<Double>(1, 0, 0)
            case .left: return SIMD3<Double>(-1, 0, 0)
            }
        }
    }
}
