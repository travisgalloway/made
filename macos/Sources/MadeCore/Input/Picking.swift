import Foundation
import CoreGraphics
import simd

/// The result of a successful ray pick against candidate mesh geometry.
public struct PickResult: Sendable, Equatable {
    public let id: SolidId
    public let distance: Float
    public let hitPoint: SIMD3<Float>

    public init(id: SolidId, distance: Float, hitPoint: SIMD3<Float>) {
        self.id = id
        self.distance = distance
        self.hitPoint = hitPoint
    }
}

/// The result of picking an individual topological sub-element (face, edge, or vertex).
public struct SubElementPickResult: Sendable, Equatable {
    public let solidId: SolidId
    public let elementType: SubelementType
    public let elementId: Int
    public let deterministicId: UUID?
    public let distance: Float
    public let hitPoint: SIMD3<Float>

    public init(
        solidId: SolidId,
        elementType: SubelementType,
        elementId: Int,
        deterministicId: UUID? = nil,
        distance: Float,
        hitPoint: SIMD3<Float>
    ) {
        self.solidId = solidId
        self.elementType = elementType
        self.elementId = elementId
        self.deterministicId = deterministicId
        self.distance = distance
        self.hitPoint = hitPoint
    }
}

/// Evaluates raycast sub-element picking across candidate meshes with strict priority:
/// vertex > edge > face within tolerance, respecting occlusion from nearer surfaces.
public func pickSubElement(
    ray: Ray3D,
    candidateMeshes: [CandidateMesh],
    screenTolerancePx: Float = 8.0,
    viewportSize: CGSize = CGSize(width: 800, height: 600),
    viewMatrix: simd_float4x4? = nil,
    projectionMatrix: simd_float4x4? = nil
) -> SubElementPickResult? {
    let dirLen = simd_length(ray.direction)
    guard dirLen > 1e-6 else { return nil }
    let normDir = ray.direction / dirLen
    let worldRay = Ray3D(origin: ray.origin, direction: normDir)
    
    let aspect = Float(viewportSize.width) / Float(viewportSize.height)
    let vm = viewMatrix ?? {
        let up = abs(normDir.z) > 0.99 ? SIMD3<Float>(0, 1, 0) : Orientation.worldUp
        return Orientation.makeLookAt(eye: worldRay.origin, target: worldRay.origin + normDir * 10.0, up: up)
    }()
    let pm = projectionMatrix ?? Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)

    let vp = pm * vm
    let testPoint = worldRay.origin + normDir * 2.0
    guard let pointer = projectToScreen(point: testPoint, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
        return nil
    }

    struct CandidateHit {
        let solidId: SolidId
        let elementType: SubelementType
        let elementId: Int
        let deterministicId: UUID?
        let distance: Float
        let hitPoint: SIMD3<Float>
    }

    var vertexHits: [CandidateHit] = []
    var edgeHits: [CandidateHit] = []
    var faceHits: [CandidateHit] = []

    // 1. Check face intersections across candidate meshes
    for mesh in candidateMeshes {
        guard !mesh.positions.isEmpty else { continue }
        let modelMatrix = mesh.transform.matrix

        let triIndices: [UInt32]
        if !mesh.indices.isEmpty {
            triIndices = mesh.indices
        } else {
            triIndices = Array(0..<UInt32(mesh.positions.count))
        }

        let numTriangles = triIndices.count / 3
        for triIdx in 0..<numTriangles {
            let i0 = Int(triIndices[triIdx * 3])
            let i1 = Int(triIndices[triIdx * 3 + 1])
            let i2 = Int(triIndices[triIdx * 3 + 2])
            guard i0 < mesh.positions.count, i1 < mesh.positions.count, i2 < mesh.positions.count else { continue }

            let p0_4 = modelMatrix * SIMD4<Float>(mesh.positions[i0], 1.0)
            let p1_4 = modelMatrix * SIMD4<Float>(mesh.positions[i1], 1.0)
            let p2_4 = modelMatrix * SIMD4<Float>(mesh.positions[i2], 1.0)
            let v0 = SIMD3<Float>(p0_4.x, p0_4.y, p0_4.z)
            let v1 = SIMD3<Float>(p1_4.x, p1_4.y, p1_4.z)
            let v2 = SIMD3<Float>(p2_4.x, p2_4.y, p2_4.z)

            // Möller-Trumbore ray-triangle intersection
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let h = simd_cross(worldRay.direction, edge2)
            let a = simd_dot(edge1, h)
            if abs(a) < 1e-7 { continue }
            let f = 1.0 / a
            let s = worldRay.origin - v0
            let u = f * simd_dot(s, h)
            if u < 0.0 || u > 1.0 { continue }
            let q = simd_cross(s, edge1)
            let v = f * simd_dot(worldRay.direction, q)
            if v < 0.0 || u + v > 1.0 { continue }
            let t = f * simd_dot(edge2, q)
            if t > 1e-4 {
                let hitPt = worldRay.origin + worldRay.direction * t
                let faceRange = mesh.faceRanges.first(where: { $0.triangleRange.contains(triIdx) })
                let fid = faceRange?.faceId ?? 0
                let detId = faceRange?.deterministicId
                faceHits.append(CandidateHit(
                    solidId: mesh.id,
                    elementType: .face,
                    elementId: fid,
                    deterministicId: detId,
                    distance: t,
                    hitPoint: hitPt
                ))
            }
        }
    }

    faceHits.sort(by: { $0.distance < $1.distance })
    let minFaceT = faceHits.first?.distance
    let occlusionThreshold = minFaceT.map { $0 * 1.02 + 0.5 }

    // 2. Check vertex candidates
    for mesh in candidateMeshes {
        guard !mesh.positions.isEmpty else { continue }
        let modelMatrix = mesh.transform.matrix

        let vertices: [VertexPoint]
        if !mesh.vertexPoints.isEmpty {
            vertices = mesh.vertexPoints
        } else {
            var seen = Set<SIMD3<Float>>()
            var unique: [VertexPoint] = []
            for (idx, pos) in mesh.positions.enumerated() {
                if seen.insert(pos).inserted {
                    unique.append(VertexPoint(vertexId: idx, position: pos))
                }
            }
            vertices = unique
        }

        for vpItem in vertices {
            let world4 = modelMatrix * SIMD4<Float>(vpItem.position, 1.0)
            let worldPos = SIMD3<Float>(world4.x, world4.y, world4.z)

            guard let screenProj = projectToScreenWithW(point: worldPos, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                continue
            }

            let screenDist = simd_distance(pointer, screenProj.screen)
            guard screenDist <= screenTolerancePx else { continue }

            let t = simd_dot(worldPos - worldRay.origin, worldRay.direction)
            guard t > 0 else { continue }

            if let threshold = occlusionThreshold, t > threshold {
                continue
            }

            vertexHits.append(CandidateHit(
                solidId: mesh.id,
                elementType: .vertex,
                elementId: vpItem.vertexId,
                deterministicId: vpItem.deterministicId,
                distance: t,
                hitPoint: worldPos
            ))
        }
    }

    // 3. Check edge candidates
    for mesh in candidateMeshes {
        guard !mesh.positions.isEmpty else { continue }
        let modelMatrix = mesh.transform.matrix

        if !mesh.edgePolylines.isEmpty {
            for poly in mesh.edgePolylines {
                guard poly.points.count >= 2 else { continue }
                for i in 0..<(poly.points.count - 1) {
                    let a4 = modelMatrix * SIMD4<Float>(poly.points[i], 1.0)
                    let b4 = modelMatrix * SIMD4<Float>(poly.points[i + 1], 1.0)
                    let pA = SIMD3<Float>(a4.x, a4.y, a4.z)
                    let pB = SIMD3<Float>(b4.x, b4.y, b4.z)

                    guard let sA = projectToScreenWithW(point: pA, viewProjectionMatrix: vp, viewportSize: viewportSize),
                          let sB = projectToScreenWithW(point: pB, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                        continue
                    }

                    let (closestWorld, screenDist) = closestPointOnSegment(
                        p1: pA,
                        p2: pB,
                        s1: sA.screen,
                        s2: sB.screen,
                        screenPointer: pointer,
                        w1: sA.w,
                        w2: sB.w
                    )

                    guard screenDist <= screenTolerancePx else { continue }
                    let t = simd_dot(closestWorld - worldRay.origin, worldRay.direction)
                    guard t > 0 else { continue }

                    if let threshold = occlusionThreshold, t > threshold {
                        continue
                    }

                    edgeHits.append(CandidateHit(
                        solidId: mesh.id,
                        elementType: .edge,
                        elementId: poly.edgeId,
                        deterministicId: poly.deterministicId,
                        distance: t,
                        hitPoint: closestWorld
                    ))
                }
            }
        } else if !mesh.edges.isEmpty {
            for (edgeIdx, edge) in mesh.edges.enumerated() {
                let i0 = Int(edge.v0)
                let i1 = Int(edge.v1)
                guard i0 < mesh.positions.count, i1 < mesh.positions.count else { continue }

                let a4 = modelMatrix * SIMD4<Float>(mesh.positions[i0], 1.0)
                let b4 = modelMatrix * SIMD4<Float>(mesh.positions[i1], 1.0)
                let pA = SIMD3<Float>(a4.x, a4.y, a4.z)
                let pB = SIMD3<Float>(b4.x, b4.y, b4.z)

                guard let sA = projectToScreenWithW(point: pA, viewProjectionMatrix: vp, viewportSize: viewportSize),
                      let sB = projectToScreenWithW(point: pB, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                    continue
                }

                let (closestWorld, screenDist) = closestPointOnSegment(
                    p1: pA,
                    p2: pB,
                    s1: sA.screen,
                    s2: sB.screen,
                    screenPointer: pointer,
                    w1: sA.w,
                    w2: sB.w
                )

                guard screenDist <= screenTolerancePx else { continue }
                let t = simd_dot(closestWorld - worldRay.origin, worldRay.direction)
                guard t > 0 else { continue }

                if let threshold = occlusionThreshold, t > threshold {
                    continue
                }

                edgeHits.append(CandidateHit(
                    solidId: mesh.id,
                    elementType: .edge,
                    elementId: edgeIdx,
                    deterministicId: nil,
                    distance: t,
                    hitPoint: closestWorld
                ))
            }
        }
    }

    // 4. Resolve strictly: Vertex > Edge > Face.
    if !vertexHits.isEmpty {
        let best = vertexHits.min(by: { $0.distance < $1.distance })!
        return SubElementPickResult(
            solidId: best.solidId,
            elementType: best.elementType,
            elementId: best.elementId,
            deterministicId: best.deterministicId,
            distance: best.distance,
            hitPoint: best.hitPoint
        )
    }

    if !edgeHits.isEmpty {
        let best = edgeHits.min(by: { $0.distance < $1.distance })!
        return SubElementPickResult(
            solidId: best.solidId,
            elementType: best.elementType,
            elementId: best.elementId,
            deterministicId: best.deterministicId,
            distance: best.distance,
            hitPoint: best.hitPoint
        )
    }

    if let bestFace = faceHits.first {
        return SubElementPickResult(
            solidId: bestFace.solidId,
            elementType: bestFace.elementType,
            elementId: bestFace.elementId,
            deterministicId: bestFace.deterministicId,
            distance: bestFace.distance,
            hitPoint: bestFace.hitPoint
        )
    }

    return nil
}

/// Evaluates ray intersection against candidate mesh bounding boxes and returns the nearest hit.
public func pickSolid(ray: Ray3D, candidateMeshes: [CandidateMesh]) -> PickResult? {
    let dirLen = simd_length(ray.direction)
    guard dirLen > 1e-6 else { return nil }
    let normDir = ray.direction / dirLen
    let worldRay = Ray3D(origin: ray.origin, direction: normDir)

    var closestResult: PickResult? = nil

    for mesh in candidateMeshes {
        guard !mesh.positions.isEmpty else { continue }

        let matrix = mesh.transform.matrix
        guard abs(simd_determinant(matrix)) > 1e-8 else { continue }
        let invMatrix = simd_inverse(matrix)

        var localMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var localMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for pos in mesh.positions {
            localMin = simd_min(localMin, pos)
            localMax = simd_max(localMax, pos)
        }

        let origin4 = invMatrix * SIMD4<Float>(worldRay.origin, 1.0)
        guard abs(origin4.w) > 1e-8 else { continue }
        let localOrigin = SIMD3<Float>(origin4.x, origin4.y, origin4.z) / origin4.w

        let dir4 = invMatrix * SIMD4<Float>(worldRay.direction, 0.0)
        let localDir = SIMD3<Float>(dir4.x, dir4.y, dir4.z)

        var tMin: Float = -Float.greatestFiniteMagnitude
        var tMax: Float = Float.greatestFiniteMagnitude
        var misses = false

        for i in 0..<3 {
            let o = localOrigin[i]
            let d = localDir[i]
            let bMin = localMin[i]
            let bMax = localMax[i]

            if abs(d) < 1e-8 {
                if o < bMin || o > bMax {
                    misses = true
                    break
                }
            } else {
                var t1 = (bMin - o) / d
                var t2 = (bMax - o) / d
                if t1 > t2 {
                    swap(&t1, &t2)
                }
                tMin = max(tMin, t1)
                tMax = min(tMax, t2)
                if tMin > tMax {
                    misses = true
                    break
                }
            }
        }

        if misses || tMax < 0 { continue }
        let t = tMin >= 0 ? tMin : tMax
        guard t >= 0 else { continue }

        let hitPoint = worldRay.origin + worldRay.direction * t
        let hit = PickResult(id: mesh.id, distance: t, hitPoint: hitPoint)

        if let current = closestResult {
            if hit.distance < current.distance {
                closestResult = hit
            }
        } else {
            closestResult = hit
        }
    }

    return closestResult
}

/// Unprojects screen pointer coordinates to a world-space ray and picks the nearest solid.
public func pickSolidAtPointer(
    pointer: SIMD2<Float>,
    viewportSize: CGSize,
    viewMatrix: simd_float4x4,
    projectionMatrix: simd_float4x4,
    candidateMeshes: [CandidateMesh]
) -> SolidId? {
    guard let ray = screenPointToRay(
        screenPoint: pointer,
        viewportSize: viewportSize,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix
    ) else {
        return nil
    }
    return pickSolid(ray: ray, candidateMeshes: candidateMeshes)?.id
}

/// Resolves the 3D orbit pivot point by strict 4-tier precedence:
/// 1. Surface hit point under the cursor from visible scene geometry (`pickSolid`).
/// 2. Center/transform of the actively selected solid if cursor misses geometry.
/// 3. Ground plane intersection (`Ray3D.intersectPlaneZZero()`) if within view distance (<= maxGroundPlaneDistance).
/// 4. Current `fallbackTarget` (camera target).
public func resolveOrbitPivot(
    ray: Ray3D?,
    candidateMeshes: [CandidateMesh],
    selectedSolidCenter: SIMD3<Float>?,
    fallbackTarget: SIMD3<Float>,
    maxGroundPlaneDistance: Float = 1000.0
) -> SIMD3<Float> {
    if let ray, let hit = pickSolid(ray: ray, candidateMeshes: candidateMeshes) {
        return hit.hitPoint
    }
    if let selectedSolidCenter {
        return selectedSolidCenter
    }
    if let ray, let groundHit = ray.intersectPlaneZZero() {
        if simd_length(groundHit - ray.origin) <= maxGroundPlaneDistance {
            return groundHit
        }
    }
    return fallbackTarget
}
