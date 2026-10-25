import Foundation
import simd

/// Maps scalar field results (such as nodal temperatures) between CAE meshes (ADR-D5, BL-THM-04, #374).
public enum SimulationCouplingMapper: Sendable {

    /// Maps a source nodal temperature field to a target volume mesh.
    ///
    /// If all target node IDs exist in `sourceTemperatures`, performs direct $O(N)$ dictionary lookup.
    /// If target node IDs differ or partially match and `sourceMesh` is provided, maps target nodes
    /// to the spatially closest source node via Euclidean distance.
    /// Any unresolved target nodes receive `fallbackTemperature`.
    ///
    /// - Parameters:
    ///   - sourceTemperatures: Nodal temperature field from a completed thermal study (keyed by source node ID).
    ///   - sourceMesh: Discretized volume mesh of the source study, if available.
    ///   - targetMesh: Discretized volume mesh of the target structural study.
    ///   - fallbackTemperature: Baseline temperature applied when a node cannot be mapped (default 20.0 °C).
    /// - Returns: Nodal temperatures keyed by target mesh node ID.
    public static func mapNodalTemperatures(
        sourceTemperatures: [Int: Double],
        sourceMesh: VolumeMesh?,
        targetMesh: VolumeMesh,
        fallbackTemperature: Double = 20.0
    ) -> [Int: Double] {
        guard !targetMesh.nodes.isEmpty else { return [:] }
        guard !sourceTemperatures.isEmpty else {
            var fallback: [Int: Double] = [:]
            fallback.reserveCapacity(targetMesh.nodes.count)
            for node in targetMesh.nodes {
                fallback[node.id] = fallbackTemperature
            }
            return fallback
        }

        // Direct 1:1 Fast Path: Check if all target node IDs exist in sourceTemperatures
        let allTargetNodesPresent = targetMesh.nodes.allSatisfy { sourceTemperatures[$0.id] != nil }
        if allTargetNodesPresent {
            var directMap: [Int: Double] = [:]
            directMap.reserveCapacity(targetMesh.nodes.count)
            for node in targetMesh.nodes {
                directMap[node.id] = sourceTemperatures[node.id]!
            }
            return directMap
        }

        // Spatial nearest-neighbor fallback
        var result: [Int: Double] = [:]
        result.reserveCapacity(targetMesh.nodes.count)

        // Index source nodes that have temperature values
        let availableSourceNodes: [(id: Int, position: SIMD3<Double>, temperature: Double)]
        let sourceNodeById: [Int: VolumeMeshNode]
        if let sMesh = sourceMesh {
            let dict = Dictionary(uniqueKeysWithValues: sMesh.nodes.map { ($0.id, $0) })
            sourceNodeById = dict
            availableSourceNodes = sourceTemperatures.compactMap { (id, temp) in
                guard let node = dict[id] else { return nil }
                return (id: id, position: node.position, temperature: temp)
            }
        } else {
            sourceNodeById = [:]
            availableSourceNodes = []
        }

        for targetNode in targetMesh.nodes {
            // Direct ID match fast path if position is identical or sourceMesh not available
            if let directTemp = sourceTemperatures[targetNode.id] {
                if let sNode = sourceNodeById[targetNode.id] {
                    let distSq = simd_length_squared(sNode.position - targetNode.position)
                    if distSq < 1e-10 {
                        result[targetNode.id] = directTemp
                        continue
                    }
                } else if sourceMesh == nil {
                    result[targetNode.id] = directTemp
                    continue
                }
            }

            if !availableSourceNodes.isEmpty {
                var bestDistSq = Double.infinity
                var bestTemp = fallbackTemperature
                let targetPos = targetNode.position
                for sNode in availableSourceNodes {
                    let d = sNode.position - targetPos
                    let distSq = simd_length_squared(d)
                    if distSq < bestDistSq {
                        bestDistSq = distSq
                        bestTemp = sNode.temperature
                    }
                }
                result[targetNode.id] = bestTemp
            } else {
                result[targetNode.id] = sourceTemperatures[targetNode.id] ?? fallbackTemperature
            }
        }

        return result
    }
}
