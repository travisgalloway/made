import Foundation
import simd

/// Axis-aligned bounding box defined by minimum and maximum extents in 3D space.
public struct AxisAlignedBoundingBox: Sendable, Equatable, Codable {
    public let min: SIMD3<Double>
    public let max: SIMD3<Double>

    public init(min: SIMD3<Double>, max: SIMD3<Double>) {
        self.min = min
        self.max = max
    }

    public var size: SIMD3<Double> {
        SIMD3<Double>(
            Swift.max(0.0, max.x - min.x),
            Swift.max(0.0, max.y - min.y),
            Swift.max(0.0, max.z - min.z)
        )
    }

    public var center: SIMD3<Double> {
        (min + max) * 0.5
    }

    public var volume: Double {
        let s = size
        return s.x * s.y * s.z
    }

    public func toDictionary() -> [String: Any] {
        [
            "min": [min.x, min.y, min.z],
            "max": [max.x, max.y, max.z],
            "size": [size.x, size.y, size.z],
            "volume": volume
        ]
    }
}

/// Oriented bounding box defined by center, three orthonormal basis axes, and extents.
public struct OrientedBoundingBox: Sendable, Equatable, Codable {
    public let center: SIMD3<Double>
    public let axes: [SIMD3<Double>]
    public let size: SIMD3<Double>

    public init(center: SIMD3<Double>, axes: [SIMD3<Double>], size: SIMD3<Double>) {
        self.center = center
        self.axes = axes
        self.size = SIMD3<Double>(
            Swift.max(0.0, size.x),
            Swift.max(0.0, size.y),
            Swift.max(0.0, size.z)
        )
    }

    public var volume: Double {
        size.x * size.y * size.z
    }

    public var sortedDimensions: SIMD3<Double> {
        let sorted = [size.x, size.y, size.z].sorted()
        return SIMD3<Double>(sorted[0], sorted[1], sorted[2])
    }

    public func toDictionary() -> [String: Any] {
        [
            "center": [center.x, center.y, center.z],
            "axes": axes.map { [$0.x, $0.y, $0.z] },
            "size": [size.x, size.y, size.z],
            "volume": volume
        ]
    }
}

/// Calculates axis-aligned and optimal oriented bounding boxes for 3D meshes and point sets.
public enum BoundingBoxCalculator {

    private struct Point2D: Equatable {
        let x: Double
        let y: Double
    }

    /// Computes axis-aligned and optimal oriented bounding boxes for the given points.
    public static func boxes(
        for points: [SIMD3<Double>],
        triangleNormals: [SIMD3<Double>] = [],
        additionalOrientations: [[SIMD3<Double>]] = []
    ) -> (axisAligned: AxisAlignedBoundingBox, oriented: OrientedBoundingBox)? {
        guard !points.isEmpty else { return nil }

        // 1. Axis-Aligned Bounding Box (AABB)
        var minP = points[0]
        var maxP = points[0]
        var sum = SIMD3<Double>(0, 0, 0)
        for p in points {
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
            sum += p
        }
        let aabb = AxisAlignedBoundingBox(min: minP, max: maxP)

        // 2. Centroid-relative coordinates for numerical stability
        let n = Double(points.count)
        let c0 = sum / n
        let q = points.map { $0 - c0 }

        // 3. Assemble candidate orientation frames
        var candidateBases: [[SIMD3<Double>]] = [
            [SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1)]
        ]

        for basis in additionalOrientations {
            if let ortho = orthonormalize(basis) {
                candidateBases.append(ortho)
            }
        }

        // PCA frame via sample covariance matrix and Jacobi eigenvalue diagonalization
        if points.count >= 3 {
            var cov = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
            for pt in q {
                cov[0][0] += pt.x * pt.x
                cov[0][1] += pt.x * pt.y
                cov[0][2] += pt.x * pt.z
                cov[1][1] += pt.y * pt.y
                cov[1][2] += pt.y * pt.z
                cov[2][2] += pt.z * pt.z
            }
            cov[1][0] = cov[0][1]
            cov[2][0] = cov[0][2]
            cov[2][1] = cov[1][2]
            for r in 0..<3 {
                for c in 0..<3 {
                    cov[r][c] /= n
                }
            }
            let pcaBasis = jacobiEigenvectors(matrix: cov)
            candidateBases.append(pcaBasis)
        }

        // Normal-aligned frames and 2D rotating calipers
        var candidateNormals: [SIMD3<Double>] = []

        for normal in triangleNormals {
            let len = simd_length(normal)
            guard len > 1e-9 else { continue }
            let unitN = normal / len
            if !candidateNormals.contains(where: { abs(simd_dot($0, unitN)) > 0.9999 }) {
                candidateNormals.append(unitN)
                if candidateNormals.count >= 64 { break }
            }
        }

        if points.count <= 64 && candidateNormals.isEmpty {
            for i in 0..<points.count {
                for j in (i + 1)..<points.count {
                    let diff = points[j] - points[i]
                    let len = simd_length(diff)
                    guard len > 1e-6 else { continue }
                    let dir = diff / len
                    if !candidateNormals.contains(where: { abs(simd_dot($0, dir)) > 0.9999 }) {
                        candidateNormals.append(dir)
                        if candidateNormals.count >= 32 { break }
                    }
                }
                if candidateNormals.count >= 32 { break }
            }
        }

        for normal in candidateNormals {
            let ref: SIMD3<Double> = abs(normal.x) < 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ex = simd_normalize(ref - simd_dot(ref, normal) * normal)
            let ey = simd_normalize(simd_cross(normal, ex))

            let projected2D = q.map { Point2D(x: simd_dot($0, ex), y: simd_dot($0, ey)) }
            let (u2D, v2D) = minimumBoundingRectangle2D(for: projected2D)

            let u0 = simd_normalize(u2D.x * ex + u2D.y * ey)
            let u1 = simd_normalize(v2D.x * ex + v2D.y * ey)
            var u2 = simd_cross(u0, u1)
            let lenU2 = simd_length(u2)
            if lenU2 > 1e-9 {
                u2 /= lenU2
                candidateBases.append([u0, u1, u2])
            }
        }

        // 4. Evaluate all candidate frames and choose the minimum-volume box
        var bestBasis: [SIMD3<Double>] = candidateBases[0]
        var bestSize = SIMD3<Double>(0, 0, 0)
        var bestCenterLocal = SIMD3<Double>(0, 0, 0)
        var bestScore = Double.greatestFiniteMagnitude

        for basis in candidateBases {
            let u0 = basis[0]
            let u1 = basis[1]
            let u2 = basis[2]

            var min0 = Double.greatestFiniteMagnitude, max0 = -Double.greatestFiniteMagnitude
            var min1 = Double.greatestFiniteMagnitude, max1 = -Double.greatestFiniteMagnitude
            var min2 = Double.greatestFiniteMagnitude, max2 = -Double.greatestFiniteMagnitude

            for pt in q {
                let s0 = simd_dot(pt, u0)
                let s1 = simd_dot(pt, u1)
                let s2 = simd_dot(pt, u2)
                min0 = Swift.min(min0, s0); max0 = Swift.max(max0, s0)
                min1 = Swift.min(min1, s1); max1 = Swift.max(max1, s1)
                min2 = Swift.min(min2, s2); max2 = Swift.max(max2, s2)
            }

            let ext0 = Swift.max(0.0, max0 - min0)
            let ext1 = Swift.max(0.0, max1 - min1)
            let ext2 = Swift.max(0.0, max2 - min2)
            let vol = ext0 * ext1 * ext2
            let surfArea = 2.0 * (ext0 * ext1 + ext1 * ext2 + ext2 * ext0)
            let score = vol > 1e-9 ? vol : (surfArea * 1e-9)

            if score < bestScore {
                bestScore = score
                bestBasis = basis
                bestSize = SIMD3<Double>(ext0, ext1, ext2)
                bestCenterLocal = ((min0 + max0) * 0.5) * u0 +
                                  ((min1 + max1) * 0.5) * u1 +
                                  ((min2 + max2) * 0.5) * u2
            }
        }

        let bestCenterWorld = c0 + bestCenterLocal
        let obb = OrientedBoundingBox(
            center: bestCenterWorld,
            axes: bestBasis,
            size: bestSize
        )

        return (axisAligned: aabb, oriented: obb)
    }

    /// Computes bounding boxes for a candidate mesh, transforming vertices to world space with Double precision.
    public static func boxes(for mesh: CandidateMesh) -> (axisAligned: AxisAlignedBoundingBox, oriented: OrientedBoundingBox)? {
        guard !mesh.positions.isEmpty else { return nil }

        let transform = mesh.transform
        let rot = transform.rotation
        let qxyz = SIMD3<Double>(Double(rot.imag.x), Double(rot.imag.y), Double(rot.imag.z))
        let qw = Double(rot.real)
        let qlen = sqrt(qxyz.x * qxyz.x + qxyz.y * qxyz.y + qxyz.z * qxyz.z + qw * qw)
        let normQxyz = qlen > 1e-12 ? qxyz / qlen : SIMD3<Double>(0, 0, 0)
        let normQw = qlen > 1e-12 ? qw / qlen : 1.0

        let scale = SIMD3<Double>(Double(transform.scale.x), Double(transform.scale.y), Double(transform.scale.z))
        let pos = SIMD3<Double>(Double(transform.position.x), Double(transform.position.y), Double(transform.position.z))

        @inline(__always)
        func rotateVectorDouble(_ v: SIMD3<Double>) -> SIMD3<Double> {
            let t = simd_cross(normQxyz, v) + normQw * v
            return v + 2.0 * simd_cross(normQxyz, t)
        }

        @inline(__always)
        func transformPointDouble(_ p: SIMD3<Float>) -> SIMD3<Double> {
            let v = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z)) * scale
            return rotateVectorDouble(v) + pos
        }

        let worldPoints = mesh.positions.map { transformPointDouble($0) }

        var normals: [SIMD3<Double>] = []
        if mesh.indices.count >= 3 {
            normals.reserveCapacity(mesh.indices.count / 3)
            for i in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                let i0 = Int(mesh.indices[i])
                let i1 = Int(mesh.indices[i + 1])
                let i2 = Int(mesh.indices[i + 2])
                guard i0 < worldPoints.count, i1 < worldPoints.count, i2 < worldPoints.count else { continue }
                let p0 = worldPoints[i0]
                let p1 = worldPoints[i1]
                let p2 = worldPoints[i2]
                let cross = simd_cross(p1 - p0, p2 - p0)
                let len = simd_length(cross)
                if len > 1e-9 {
                    normals.append(cross / len)
                }
            }
        }

        let localX = simd_normalize(rotateVectorDouble(SIMD3<Double>(1, 0, 0)))
        let localY = simd_normalize(rotateVectorDouble(SIMD3<Double>(0, 1, 0)))
        let localZ = simd_normalize(rotateVectorDouble(SIMD3<Double>(0, 0, 1)))
        let transformOrientation = [localX, localY, localZ]

        return boxes(
            for: worldPoints,
            triangleNormals: normals,
            additionalOrientations: [transformOrientation]
        )
    }

    /// Computes bounding boxes for a solid ID in the document, resolving from candidate meshes or geometry generators.
    @MainActor
    public static func boxes(
        for solidId: SolidId,
        in document: DocumentModel,
        candidateMeshes: [CandidateMesh]
    ) -> (axisAligned: AxisAlignedBoundingBox, oriented: OrientedBoundingBox)? {
        if let match = candidateMeshes.first(where: { $0.id == solidId }) {
            return boxes(for: match)
        }
        if let resolved = MeasureTool.resolveMesh(for: solidId, in: document, candidateMeshes: candidateMeshes) {
            return boxes(for: resolved)
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func orthonormalize(_ basis: [SIMD3<Double>]) -> [SIMD3<Double>]? {
        guard basis.count == 3 else { return nil }
        var v0 = basis[0]
        let l0 = simd_length(v0)
        guard l0 > 1e-9 else { return nil }
        v0 /= l0

        var v1 = basis[1] - simd_dot(basis[1], v0) * v0
        let l1 = simd_length(v1)
        guard l1 > 1e-9 else { return nil }
        v1 /= l1

        var v2 = simd_cross(v0, v1)
        let l2 = simd_length(v2)
        guard l2 > 1e-9 else { return nil }
        v2 /= l2

        return [v0, v1, v2]
    }

    private static func jacobiEigenvectors(matrix: [[Double]]) -> [SIMD3<Double>] {
        var a = matrix
        var v: [[Double]] = [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
        ]

        let maxSweeps = 50
        let epsilon = 1e-12

        for _ in 0..<maxSweeps {
            var maxOffDiag = 0.0
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    maxOffDiag = Swift.max(maxOffDiag, abs(a[i][j]))
                }
            }
            if maxOffDiag < epsilon { break }

            for p in 0..<2 {
                for q in (p + 1)..<3 {
                    let apq = a[p][q]
                    if abs(apq) < epsilon { continue }

                    let app = a[p][p]
                    let aqq = a[q][q]
                    let diff = aqq - app

                    let t: Double
                    if abs(diff) > epsilon {
                        let tau = diff / (2.0 * apq)
                        if tau >= 0 {
                            t = 1.0 / (tau + sqrt(1.0 + tau * tau))
                        } else {
                            t = -1.0 / (-tau + sqrt(1.0 + tau * tau))
                        }
                    } else {
                        t = (apq > 0) ? 1.0 : -1.0
                    }

                    let c = 1.0 / sqrt(1.0 + t * t)
                    let s = t * c
                    let tauRot = s / (1.0 + c)

                    a[p][q] = 0.0
                    a[q][p] = 0.0
                    a[p][p] = app - t * apq
                    a[q][q] = aqq + t * apq

                    for r in 0..<3 {
                        if r != p && r != q {
                            let arp = a[r][p]
                            let arq = a[r][q]
                            a[r][p] = arp - s * (arq + tauRot * arp)
                            a[p][r] = a[r][p]
                            a[r][q] = arq + s * (arp - tauRot * arq)
                            a[q][r] = a[r][q]
                        }
                    }

                    for r in 0..<3 {
                        let vrp = v[r][p]
                        let vrq = v[r][q]
                        v[r][p] = vrp - s * (vrq + tauRot * vrp)
                        v[r][q] = vrq + s * (vrp - tauRot * vrq)
                    }
                }
            }
        }

        var v0 = SIMD3<Double>(v[0][0], v[1][0], v[2][0])
        var v1 = SIMD3<Double>(v[0][1], v[1][1], v[2][1])
        let l0 = simd_length(v0)
        let l1 = simd_length(v1)
        if l0 > epsilon { v0 /= l0 } else { v0 = SIMD3<Double>(1, 0, 0) }
        if l1 > epsilon { v1 /= l1 } else { v1 = SIMD3<Double>(0, 1, 0) }
        var v2 = simd_cross(v0, v1)
        let l2 = simd_length(v2)
        if l2 > epsilon {
            v2 /= l2
        } else {
            v2 = SIMD3<Double>(0, 0, 1)
        }
        v1 = simd_normalize(simd_cross(v2, v0))
        return [v0, v1, v2]
    }

    private static func crossProduct2D(_ o: Point2D, _ a: Point2D, _ b: Point2D) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private static func convexHull2D(for points: [Point2D]) -> [Point2D] {
        let sorted = points.sorted {
            if abs($0.x - $1.x) > 1e-9 { return $0.x < $1.x }
            return $0.y < $1.y
        }
        var unique: [Point2D] = []
        for pt in sorted {
            if let last = unique.last, abs(last.x - pt.x) < 1e-9 && abs(last.y - pt.y) < 1e-9 {
                continue
            }
            unique.append(pt)
        }
        guard unique.count >= 3 else { return unique }

        var lower: [Point2D] = []
        for p in unique {
            while lower.count >= 2 && crossProduct2D(lower[lower.count - 2], lower[lower.count - 1], p) <= 1e-9 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [Point2D] = []
        for p in unique.reversed() {
            while upper.count >= 2 && crossProduct2D(upper[upper.count - 2], upper[upper.count - 1], p) <= 1e-9 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func minimumBoundingRectangle2D(for points: [Point2D]) -> (Point2D, Point2D) {
        let hull = convexHull2D(for: points)
        guard hull.count >= 2 else {
            return (Point2D(x: 1, y: 0), Point2D(x: 0, y: 1))
        }

        var bestArea = Double.greatestFiniteMagnitude
        var bestU = Point2D(x: 1, y: 0)
        var bestV = Point2D(x: 0, y: 1)

        for k in 0..<hull.count {
            let p1 = hull[k]
            let p2 = hull[(k + 1) % hull.count]
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = hypot(dx, dy)
            guard len > 1e-9 else { continue }

            let ux = dx / len
            let uy = dy / len
            let vx = -uy
            let vy = ux

            var minU = Double.greatestFiniteMagnitude, maxU = -Double.greatestFiniteMagnitude
            var minV = Double.greatestFiniteMagnitude, maxV = -Double.greatestFiniteMagnitude

            for pt in hull {
                let su = pt.x * ux + pt.y * uy
                let sv = pt.x * vx + pt.y * vy
                minU = Swift.min(minU, su); maxU = Swift.max(maxU, su)
                minV = Swift.min(minV, sv); maxV = Swift.max(maxV, sv)
            }

            let area = Swift.max(0.0, maxU - minU) * Swift.max(0.0, maxV - minV)
            if area < bestArea {
                bestArea = area
                bestU = Point2D(x: ux, y: uy)
                bestV = Point2D(x: vx, y: vy)
            }
        }

        return (bestU, bestV)
    }
}
