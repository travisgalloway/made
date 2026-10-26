import Foundation
import simd

/// Pure topological graph traversal algorithms for candidate meshes (BL-SEL-09).
/// Respects LayeringTests by depending strictly on layer-neutral types (`CandidateMesh`, `MeshEdge`,
/// `EdgePolyline`, `FaceTriangleRange`, `SelectedSubElement`, `SolidId`, `SubelementType`, `TopologicalReference`).

/// Finds connected edges that form a smooth (tangent) continuation with the seed edge.
/// - Parameters:
///   - seedEdgeId: The edge ID to start from.
///   - mesh: The candidate mesh containing edge polylines.
///   - angularTolerance: Maximum angle in radians between tangent continuation vectors (default: 10 degrees).
/// - Returns: A set of `SelectedSubElement` representing the continuous tangent chain.
public func findTangentEdgeChain(
    seedEdgeId: Int,
    in mesh: CandidateMesh,
    angularTolerance: Float = .pi * 10.0 / 180.0
) -> Set<SelectedSubElement> {
    guard let seedPolyline = mesh.edgePolylines.first(where: { $0.edgeId == seedEdgeId }) else {
        return []
    }
    guard seedPolyline.points.count >= 2 else {
        return [SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: seedEdgeId, deterministicId: seedPolyline.deterministicId)]
    }

    let spatialEpsilon: Float = 1e-4
    let cosThreshold = cos(angularTolerance)

    struct EdgeEnd {
        let edgeId: Int
        let isStart: Bool
        let point: SIMD3<Float>
        let tangent: SIMD3<Float>
    }

    var edgeEnds: [EdgeEnd] = []
    for poly in mesh.edgePolylines where poly.points.count >= 2 {
        let pStart = poly.points.first!
        let pEnd = poly.points.last!
        let startDir = simd_normalize(poly.points[1] - pStart)
        let endDir = simd_normalize(poly.points[poly.points.count - 2] - pEnd)
        edgeEnds.append(EdgeEnd(edgeId: poly.edgeId, isStart: true, point: pStart, tangent: startDir))
        edgeEnds.append(EdgeEnd(edgeId: poly.edgeId, isStart: false, point: pEnd, tangent: endDir))
    }

    var chainEdgeIds: Set<Int> = [seedEdgeId]

    func traverseDirection(fromPoint: SIMD3<Float>, incomingTangentIntoVertex: SIMD3<Float>) {
        var currentPoint = fromPoint
        var currentIncomingTangent = incomingTangentIntoVertex

        while true {
            let candidates = edgeEnds.filter { end in
                !chainEdgeIds.contains(end.edgeId) &&
                simd_distance_squared(end.point, currentPoint) <= (spatialEpsilon * spatialEpsilon)
            }

            if candidates.isEmpty {
                break
            }

            var bestCandidate: EdgeEnd? = nil
            var bestScore: Float = -1.0

            for cand in candidates {
                let score = simd_dot(currentIncomingTangent, cand.tangent)
                if score >= cosThreshold && score > bestScore {
                    bestScore = score
                    bestCandidate = cand
                }
            }

            guard let nextEnd = bestCandidate,
                  let nextPoly = mesh.edgePolylines.first(where: { $0.edgeId == nextEnd.edgeId }),
                  nextPoly.points.count >= 2 else {
                break
            }

            chainEdgeIds.insert(nextEnd.edgeId)

            if nextEnd.isStart {
                currentPoint = nextPoly.points.last!
                currentIncomingTangent = simd_normalize(currentPoint - nextPoly.points[nextPoly.points.count - 2])
            } else {
                currentPoint = nextPoly.points.first!
                currentIncomingTangent = simd_normalize(currentPoint - nextPoly.points[1])
            }
        }
    }

    let pSeedStart = seedPolyline.points.first!
    let pSeedEnd = seedPolyline.points.last!

    // If seed is closed loop on itself, return immediately
    if simd_distance_squared(pSeedStart, pSeedEnd) <= (spatialEpsilon * spatialEpsilon) {
        return [SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: seedEdgeId, deterministicId: seedPolyline.deterministicId)]
    }

    let seedForwardDir = simd_normalize(pSeedEnd - seedPolyline.points[seedPolyline.points.count - 2])
    traverseDirection(fromPoint: pSeedEnd, incomingTangentIntoVertex: seedForwardDir)

    let seedBackwardDir = simd_normalize(pSeedStart - seedPolyline.points[1])
    traverseDirection(fromPoint: pSeedStart, incomingTangentIntoVertex: seedBackwardDir)

    let polyMap = Dictionary(uniqueKeysWithValues: mesh.edgePolylines.map { ($0.edgeId, $0) })
    return Set(chainEdgeIds.compactMap { id in
        guard let p = polyMap[id] else { return nil }
        return SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: id, deterministicId: p.deterministicId)
    })
}

/// Finds a closed loop of edges enclosing a face or manifold circuit starting from seedEdgeId.
/// - Parameters:
///   - seedEdgeId: The edge ID to start from.
///   - mesh: The candidate mesh containing edge polylines and face ranges.
/// - Returns: A set of `SelectedSubElement` representing the closed boundary loop.
public func findEdgeLoop(
    seedEdgeId: Int,
    in mesh: CandidateMesh
) -> Set<SelectedSubElement> {
    guard let seedPoly = mesh.edgePolylines.first(where: { $0.edgeId == seedEdgeId }) else {
        return []
    }
    guard seedPoly.points.count >= 2 else {
        return [SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: seedEdgeId, deterministicId: seedPoly.deterministicId)]
    }

    let spatialEpsilon: Float = 1e-4

    // If edge is itself a closed loop (e.g. cylinder circle cap)
    if simd_distance_squared(seedPoly.points.first!, seedPoly.points.last!) <= (spatialEpsilon * spatialEpsilon) {
        return [SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: seedEdgeId, deterministicId: seedPoly.deterministicId)]
    }

    func pointOnSegment(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        let ab = b - a
        let ap = p - a
        let abLenSq = simd_length_squared(ab)
        if abLenSq < 1e-8 { return simd_distance_squared(p, a) <= (spatialEpsilon * spatialEpsilon) }
        let t = simd_clamp(simd_dot(ap, ab) / abLenSq, 0.0, 1.0)
        let projection = a + t * ab
        return simd_distance_squared(p, projection) <= (spatialEpsilon * spatialEpsilon)
    }

    var candidateFaceLoops: [[Int]] = []

    for faceRange in mesh.faceRanges {
        guard !faceRange.triangleRange.isEmpty else { continue }
        var halfEdgeCounts: [MeshEdge: Int] = [:]
        for triIdx in faceRange.triangleRange {
            let base = triIdx * 3
            guard base + 2 < mesh.indices.count else { continue }
            let i0 = mesh.indices[base]
            let i1 = mesh.indices[base + 1]
            let i2 = mesh.indices[base + 2]
            halfEdgeCounts[MeshEdge(i0, i1), default: 0] += 1
            halfEdgeCounts[MeshEdge(i1, i2), default: 0] += 1
            halfEdgeCounts[MeshEdge(i2, i0), default: 0] += 1
        }

        let boundaryEdges = halfEdgeCounts.filter { $0.value == 1 }.map(\.key)
        guard !boundaryEdges.isEmpty else { continue }

        var faceEdgeIds: [Int] = []
        for poly in mesh.edgePolylines where poly.points.count >= 2 {
            let p0 = poly.points.first!
            let p1 = poly.points.last!
            let matchesBoundary = boundaryEdges.contains { edge in
                guard Int(edge.v0) < mesh.positions.count && Int(edge.v1) < mesh.positions.count else { return false }
                let v0 = mesh.positions[Int(edge.v0)]
                let v1 = mesh.positions[Int(edge.v1)]
                let d00 = simd_distance_squared(p0, v0)
                let d01 = simd_distance_squared(p0, v1)
                let d10 = simd_distance_squared(p1, v0)
                let d11 = simd_distance_squared(p1, v1)
                return (d00 <= spatialEpsilon * spatialEpsilon && d11 <= spatialEpsilon * spatialEpsilon) ||
                       (d01 <= spatialEpsilon * spatialEpsilon && d10 <= spatialEpsilon * spatialEpsilon) ||
                       (pointOnSegment(p0, v0, v1) && pointOnSegment(p1, v0, v1))
            }
            if matchesBoundary {
                faceEdgeIds.append(poly.edgeId)
            }
        }

        if faceEdgeIds.contains(seedEdgeId) && faceEdgeIds.count >= 3 {
            candidateFaceLoops.append(faceEdgeIds)
        }
    }

    if let bestFaceLoop = candidateFaceLoops.min(by: { $0.count < $1.count }) {
        let polyMap = Dictionary(uniqueKeysWithValues: mesh.edgePolylines.map { ($0.edgeId, $0) })
        return Set(bestFaceLoop.compactMap { id in
            guard let p = polyMap[id] else { return nil }
            return SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: id, deterministicId: p.deterministicId)
        })
    }

    // Fallback: Graph cycle search starting from seedPoly
    let target = seedPoly.points.first!
    var visitedEdges: Set<Int> = [seedEdgeId]
    var queue: [(currentPoint: SIMD3<Float>, path: [Int])] = [(seedPoly.points.last!, [seedEdgeId])]

    while !queue.isEmpty {
        let item = queue.removeFirst()
        if item.path.count > 1 && simd_distance_squared(item.currentPoint, target) <= (spatialEpsilon * spatialEpsilon) {
            let polyMap = Dictionary(uniqueKeysWithValues: mesh.edgePolylines.map { ($0.edgeId, $0) })
            return Set(item.path.compactMap { id in
                guard let p = polyMap[id] else { return nil }
                return SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: id, deterministicId: p.deterministicId)
            })
        }

        for poly in mesh.edgePolylines where !visitedEdges.contains(poly.edgeId) && poly.points.count >= 2 {
            let pStart = poly.points.first!
            let pEnd = poly.points.last!
            if simd_distance_squared(pStart, item.currentPoint) <= (spatialEpsilon * spatialEpsilon) {
                visitedEdges.insert(poly.edgeId)
                queue.append((pEnd, item.path + [poly.edgeId]))
            } else if simd_distance_squared(pEnd, item.currentPoint) <= (spatialEpsilon * spatialEpsilon) {
                visitedEdges.insert(poly.edgeId)
                queue.append((pStart, item.path + [poly.edgeId]))
            }
        }
    }

    return [SelectedSubElement(solidId: mesh.id, elementType: .edge, elementId: seedEdgeId, deterministicId: seedPoly.deterministicId)]
}

/// Finds connected faces whose surface normals match within angularTolerance (default: 10 degrees).
/// - Parameters:
///   - seedFaceId: The face ID to start from.
///   - mesh: The candidate mesh containing face ranges and triangle indices.
///   - angularTolerance: Maximum dihedral angle in radians (default: 10 degrees).
/// - Returns: A set of `SelectedSubElement` representing the coplanar/tangent face chain.
public func findTangentFaceChain(
    seedFaceId: Int,
    in mesh: CandidateMesh,
    angularTolerance: Float = .pi * 10.0 / 180.0
) -> Set<SelectedSubElement> {
    guard let seedFaceRange = mesh.faceRanges.first(where: { $0.faceId == seedFaceId }) else {
        return []
    }

    let cosThreshold = cos(angularTolerance)

    func computeFaceNormal(_ range: FaceTriangleRange) -> SIMD3<Float>? {
        var normalSum = SIMD3<Float>(0, 0, 0)
        for triIdx in range.triangleRange {
            let base = triIdx * 3
            guard base + 2 < mesh.indices.count else { continue }
            let i0 = Int(mesh.indices[base])
            let i1 = Int(mesh.indices[base + 1])
            let i2 = Int(mesh.indices[base + 2])
            guard i0 < mesh.positions.count && i1 < mesh.positions.count && i2 < mesh.positions.count else { continue }
            let p0 = mesh.positions[i0]
            let p1 = mesh.positions[i1]
            let p2 = mesh.positions[i2]
            let fn = simd_cross(p1 - p0, p2 - p0)
            normalSum += fn
        }
        let lenSq = simd_length_squared(normalSum)
        return lenSq > 1e-8 ? simd_normalize(normalSum) : nil
    }

    var faceNormals: [Int: SIMD3<Float>] = [:]
    for f in mesh.faceRanges {
        if let n = computeFaceNormal(f) {
            faceNormals[f.faceId] = n
        }
    }

    guard let _ = faceNormals[seedFaceId] else {
        return [SelectedSubElement(solidId: mesh.id, elementType: .face, elementId: seedFaceId, deterministicId: seedFaceRange.deterministicId)]
    }

    func quantize(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3<Int32>(
            Int32((p.x * 1000).rounded()),
            Int32((p.y * 1000).rounded()),
            Int32((p.z * 1000).rounded())
        )
    }

    struct QuantizedEdge: Hashable {
        let p0: SIMD3<Int32>
        let p1: SIMD3<Int32>
        init(_ a: SIMD3<Int32>, _ b: SIMD3<Int32>) {
            if a.x < b.x || (a.x == b.x && (a.y < b.y || (a.y == b.y && a.z < b.z))) {
                self.p0 = a; self.p1 = b
            } else {
                self.p0 = b; self.p1 = a
            }
        }
    }

    var edgeToFaces: [QuantizedEdge: Set<Int>] = [:]
    for f in mesh.faceRanges {
        for triIdx in f.triangleRange {
            let base = triIdx * 3
            guard base + 2 < mesh.indices.count else { continue }
            let i0 = Int(mesh.indices[base])
            let i1 = Int(mesh.indices[base + 1])
            let i2 = Int(mesh.indices[base + 2])
            guard i0 < mesh.positions.count && i1 < mesh.positions.count && i2 < mesh.positions.count else { continue }
            let q0 = quantize(mesh.positions[i0])
            let q1 = quantize(mesh.positions[i1])
            let q2 = quantize(mesh.positions[i2])
            if q0 != q1 { edgeToFaces[QuantizedEdge(q0, q1), default: []].insert(f.faceId) }
            if q1 != q2 { edgeToFaces[QuantizedEdge(q1, q2), default: []].insert(f.faceId) }
            if q2 != q0 { edgeToFaces[QuantizedEdge(q2, q0), default: []].insert(f.faceId) }
        }
    }

    var adjacency: [Int: Set<Int>] = [:]
    for (_, faces) in edgeToFaces where faces.count >= 2 {
        for f1 in faces {
            for f2 in faces where f1 != f2 {
                adjacency[f1, default: []].insert(f2)
            }
        }
    }

    var visitedFaceIds: Set<Int> = [seedFaceId]
    var queue: [Int] = [seedFaceId]

    while !queue.isEmpty {
        let curr = queue.removeFirst()
        guard let currNormal = faceNormals[curr] else { continue }
        for neighbor in adjacency[curr, default: []] where !visitedFaceIds.contains(neighbor) {
            guard let nNormal = faceNormals[neighbor] else { continue }
            if simd_dot(currNormal, nNormal) >= cosThreshold {
                visitedFaceIds.insert(neighbor)
                queue.append(neighbor)
            }
        }
    }

    let faceMap = Dictionary(uniqueKeysWithValues: mesh.faceRanges.map { ($0.faceId, $0) })
    return Set(visitedFaceIds.compactMap { id in
        guard let f = faceMap[id] else { return nil }
        return SelectedSubElement(solidId: mesh.id, elementType: .face, elementId: id, deterministicId: f.deterministicId)
    })
}

/// Queries face topological references generated by a feature and maps them to `SelectedSubElement` face items.
/// - Parameters:
///   - featureId: Optional feature UUID filter.
///   - generatedTopology: The feature's generated topology collection.
///   - candidateMesh: The candidate mesh to map against.
/// - Returns: A set of `SelectedSubElement` corresponding to the feature's faces.
public func findFeatureFaces(
    for featureId: UUID? = nil,
    in generatedTopology: [TopologicalReference],
    candidateMesh: CandidateMesh
) -> Set<SelectedSubElement> {
    let faceRefs = generatedTopology.filter { ref in
        ref.elementType == .face && (featureId == nil || ref.sourceFeatureId == featureId)
    }
    guard !faceRefs.isEmpty else { return [] }
    let refIds = Set(faceRefs.map(\.id))

    var result: Set<SelectedSubElement> = []
    for range in candidateMesh.faceRanges {
        if let detId = range.deterministicId, refIds.contains(detId) {
            result.insert(SelectedSubElement(
                solidId: candidateMesh.id,
                elementType: .face,
                elementId: range.faceId,
                deterministicId: detId
            ))
        }
    }

    if result.isEmpty && !candidateMesh.faceRanges.isEmpty {
        let sourceIndices = Set(faceRefs.compactMap { $0.historyPath.last?.sourceIndex })
        for range in candidateMesh.faceRanges {
            if sourceIndices.contains(range.faceId) || sourceIndices.isEmpty {
                result.insert(SelectedSubElement(
                    solidId: candidateMesh.id,
                    elementType: .face,
                    elementId: range.faceId,
                    deterministicId: nil
                ))
            }
        }
    }

    return result
}

/// Overload querying from dictionary generatedTopology storage.
public func findFeatureFaces(
    for featureId: UUID? = nil,
    in generatedTopology: [String: TopologicalReference],
    candidateMesh: CandidateMesh
) -> Set<SelectedSubElement> {
    findFeatureFaces(for: featureId, in: Array(generatedTopology.values), candidateMesh: candidateMesh)
}
