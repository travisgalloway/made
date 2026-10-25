import Foundation
import simd

/// Numerical evaluation engine for probing simulation result fields and raycasting volume meshes (BL-RES-04, #325).
public enum SimulationProbeEvaluator {

    /// Evaluates scalar result fields at a spatial query coordinate against a discretized volume mesh.
    ///
    /// - Parameters:
    ///   - position: Spatial 3D coordinate at which to sample the result field.
    ///   - mesh: Discretized volume mesh containing nodes and tetrahedral elements.
    ///   - study: Active simulation study containing physics configuration and contour settings.
    ///   - results: Completed simulation study results.
    ///   - fields: Cached or on-demand result fields (if loaded).
    ///   - name: Descriptive label for the probe point.
    ///   - kind: Whether the probe is a discrete point or part of a path sample.
    ///   - distanceAlongPath: Arc-length distance from the path start point if this is a path sample.
    /// - Returns: A populated `SimulationProbePoint` containing nearest node ID, element ID, and sampled scalar values.
    public static func evaluateProbe(
        at position: SIMD3<Double>,
        mesh: VolumeMesh,
        study: SimulationStudy,
        results: SimulationStudyResults,
        fields: SimulationResultFields?,
        name: String = "Probe",
        kind: SimulationProbeKind = .point,
        distanceAlongPath: Double? = nil
    ) -> SimulationProbePoint {
        guard !mesh.nodes.isEmpty else {
            return SimulationProbePoint(
                name: name,
                kind: kind,
                position: position,
                distanceAlongPath: distanceAlongPath,
                nodeId: nil,
                elementId: nil,
                fieldValues: [:]
            )
        }

        let isDeformed = study.contourSettings.isDeformed
        let scale = study.contourSettings.deformationScale
        let activeDisplacements = fields?.nodalDisplacements ?? results.nodalDisplacements

        var nodePositions: [Int: SIMD3<Double>] = [:]
        nodePositions.reserveCapacity(mesh.nodes.count)
        for node in mesh.nodes {
            var pos = node.position
            if isDeformed, let disp = activeDisplacements?[node.id] {
                pos += disp * scale
            }
            nodePositions[node.id] = pos
        }

        // 1. Find nearest node
        var nearestNodeId: Int? = nil
        var minNodeDistSq: Double = .greatestFiniteMagnitude
        for node in mesh.nodes {
            let pos = nodePositions[node.id] ?? node.position
            let distSq = simd_distance_squared(position, pos)
            if distSq < minNodeDistSq {
                minNodeDistSq = distSq
                nearestNodeId = node.id
            }
        }

        // 2. Find nearest element centroid
        var nearestElementId: Int? = nil
        var minElemDistSq: Double = .greatestFiniteMagnitude
        for element in mesh.elements {
            guard !element.nodeIndices.isEmpty else { continue }
            var centroid = SIMD3<Double>.zero
            var validCount = 0
            for nId in element.nodeIndices {
                if let p = nodePositions[nId] {
                    centroid += p
                    validCount += 1
                }
            }
            if validCount > 0 {
                centroid /= Double(validCount)
                let distSq = simd_distance_squared(position, centroid)
                if distSq < minElemDistSq {
                    minElemDistSq = distSq
                    nearestElementId = element.id
                }
            }
        }

        // 3. Extract scalar values for all field kinds
        var fieldValues: [SimulationResultFieldKind: Double] = [:]
        for fieldKind in SimulationResultFieldKind.allCases {
            let (nodal, element) = SimulationContourGenerator.extractScalars(
                field: fieldKind,
                study: study,
                results: results,
                fields: fields
            )
            if fieldKind.isNodal {
                if let nId = nearestNodeId, let val = nodal[nId] {
                    fieldValues[fieldKind] = val
                }
            } else {
                if let eId = nearestElementId, let val = element[eId] {
                    fieldValues[fieldKind] = val
                }
            }
        }

        return SimulationProbePoint(
            name: name,
            kind: kind,
            position: position,
            distanceAlongPath: distanceAlongPath,
            nodeId: nearestNodeId,
            elementId: nearestElementId,
            fieldValues: fieldValues
        )
    }

    /// Evaluates result values along a linear 3D segment between start and end coordinates with equidistant samples.
    ///
    /// - Parameters:
    ///   - start: Starting 3D coordinate of the path.
    ///   - end: Ending 3D coordinate of the path.
    ///   - sampleCount: Number of points to sample (clamped to >= 2).
    ///   - pathName: Name prefix for the path probe samples.
    ///   - mesh: Discretized volume mesh.
    ///   - study: Active simulation study.
    ///   - results: Simulation study results.
    ///   - fields: Simulation result fields.
    /// - Returns: An array of `SimulationProbePoint` objects representing equidistant samples along the path.
    public static func evaluatePath(
        start: SIMD3<Double>,
        end: SIMD3<Double>,
        sampleCount: Int,
        pathName: String = "Path",
        mesh: VolumeMesh,
        study: SimulationStudy,
        results: SimulationStudyResults,
        fields: SimulationResultFields?
    ) -> [SimulationProbePoint] {
        let count = max(2, sampleCount)
        let diff = end - start
        let totalDist = simd_length(diff)

        var points: [SimulationProbePoint] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let pos = start + diff * t
            let dist = totalDist * t
            let sampleName = "\(pathName) [\(i + 1)]"
            let probe = evaluateProbe(
                at: pos,
                mesh: mesh,
                study: study,
                results: results,
                fields: fields,
                name: sampleName,
                kind: .pathSample,
                distanceAlongPath: dist
            )
            points.append(probe)
        }

        return points
    }

    /// Performs Möller-Trumbore ray-triangle intersection against volume mesh boundary surface triangles.
    ///
    /// - Parameters:
    ///   - ray: World-space 3D ray.
    ///   - mesh: Volume mesh containing surface boundary triangles.
    ///   - isDeformed: Whether to test against deformed coordinates.
    ///   - deformationScale: Scale factor applied to nodal displacements.
    ///   - displacements: Active nodal displacement vectors.
    /// - Returns: Closest world-space intersection coordinate, or `nil` if the ray does not hit the mesh.
    public static func raycastVolumeMesh(
        ray: Ray3D,
        mesh: VolumeMesh,
        isDeformed: Bool = false,
        deformationScale: Double = 1.0,
        displacements: [Int: SIMD3<Double>]? = nil
    ) -> SIMD3<Double>? {
        guard !mesh.surfaceTriangles.isEmpty, !mesh.nodes.isEmpty else { return nil }

        var nodePositions: [Int: SIMD3<Double>] = [:]
        nodePositions.reserveCapacity(mesh.nodes.count)
        for node in mesh.nodes {
            var pos = node.position
            if isDeformed, let disp = displacements?[node.id] {
                pos += disp * deformationScale
            }
            nodePositions[node.id] = pos
        }

        let origin = SIMD3<Double>(Double(ray.origin.x), Double(ray.origin.y), Double(ray.origin.z))
        let dir = SIMD3<Double>(Double(ray.direction.x), Double(ray.direction.y), Double(ray.direction.z))
        let dirLen = simd_length(dir)
        guard dirLen > 1e-9 else { return nil }
        let d = dir / dirLen

        var closestT: Double = .greatestFiniteMagnitude
        var hitPoint: SIMD3<Double>? = nil

        for triangle in mesh.surfaceTriangles {
            guard triangle.nodeIndices.count >= 3 else { continue }
            let id0 = triangle.nodeIndices[0]
            let id1 = triangle.nodeIndices[1]
            let id2 = triangle.nodeIndices[2]

            guard let v0 = nodePositions[id0],
                  let v1 = nodePositions[id1],
                  let v2 = nodePositions[id2] else { continue }

            let e1 = v1 - v0
            let e2 = v2 - v0
            let pvec = simd_cross(d, e2)
            let det = simd_dot(e1, pvec)

            if abs(det) < 1e-9 { continue }
            let invDet = 1.0 / det

            let tvec = origin - v0
            let u = simd_dot(tvec, pvec) * invDet
            if u < 0.0 || u > 1.0 { continue }

            let qvec = simd_cross(tvec, e1)
            let v = simd_dot(d, qvec) * invDet
            if v < 0.0 || u + v > 1.0 { continue }

            let t = simd_dot(e2, qvec) * invDet
            if t > 1e-6 && t < closestT {
                closestT = t
                hitPoint = origin + d * t
            }
        }

        return hitPoint
    }
}
