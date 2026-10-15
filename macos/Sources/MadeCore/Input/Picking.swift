import Foundation
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
