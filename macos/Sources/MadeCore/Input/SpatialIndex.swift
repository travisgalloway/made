import Foundation
import CoreGraphics
import simd

// MARK: - Axis-Aligned Bounding Box (AABB)

/// Axis-aligned bounding box in 3D space.
public struct AABB: Sendable, Equatable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public init(point: SIMD3<Float>) {
        self.min = point
        self.max = point
    }

    public init(points: [SIMD3<Float>]) {
        guard let first = points.first else {
            self.min = .zero
            self.max = .zero
            return
        }
        var lo = first
        var hi = first
        for p in points.dropFirst() {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        self.min = lo
        self.max = hi
    }

    public var center: SIMD3<Float> {
        (min + max) * 0.5
    }

    public var extents: SIMD3<Float> {
        max - min
    }

    public var corners: [SIMD3<Float>] {
        [
            SIMD3<Float>(min.x, min.y, min.z),
            SIMD3<Float>(max.x, min.y, min.z),
            SIMD3<Float>(min.x, max.y, min.z),
            SIMD3<Float>(max.x, max.y, min.z),
            SIMD3<Float>(min.x, min.y, max.z),
            SIMD3<Float>(max.x, min.y, max.z),
            SIMD3<Float>(min.x, max.y, max.z),
            SIMD3<Float>(max.x, max.y, max.z)
        ]
    }

    public mutating func union(with point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    public mutating func union(with other: AABB) {
        min = simd_min(min, other.min)
        max = simd_max(max, other.max)
    }

    public func unioned(with other: AABB) -> AABB {
        AABB(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }

    public func intersects(other: AABB) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x &&
        min.y <= other.max.y && max.y >= other.min.y &&
        min.z <= other.max.z && max.z >= other.min.z
    }

    public func intersects(ray: Ray3D, minT: Float = 1e-4, maxT: Float = .greatestFiniteMagnitude) -> (hit: Bool, t: Float) {
        var t0 = minT
        var t1 = maxT
        for i in 0..<3 {
            let dir = ray.direction[i]
            let invD = 1.0 / (abs(dir) > 1e-8 ? dir : (dir >= 0 ? 1e-8 : -1e-8))
            var tNear = (min[i] - ray.origin[i]) * invD
            var tFar = (max[i] - ray.origin[i]) * invD
            if tNear > tFar { swap(&tNear, &tFar) }
            t0 = Swift.max(t0, tNear)
            t1 = Swift.min(t1, tFar)
            if t0 > t1 { return (false, 0) }
        }
        return (true, t0)
    }

    @inline(__always)
    public func projectedScreenBounds(viewProjectionMatrix: simd_float4x4, viewportSize: CGSize) -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        let width = Float(viewportSize.width)
        let height = Float(viewportSize.height)
        guard width > 0 && height > 0 else { return nil }

        var sMin = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var sMax = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        var inFrontCount = 0

        let x0 = min.x, x1 = max.x
        let y0 = min.y, y1 = max.y
        let z0 = min.z, z1 = max.z

        for i in 0..<8 {
            let cx = (i & 1 == 0) ? x0 : x1
            let cy = (i & 2 == 0) ? y0 : y1
            let cz = (i & 4 == 0) ? z0 : z1

            let clip = viewProjectionMatrix * SIMD4<Float>(cx, cy, cz, 1.0)
            if clip.w > 1e-4 {
                inFrontCount += 1
                let invW = 1.0 / clip.w
                let ndcX = clip.x * invW
                let ndcY = clip.y * invW
                let sx = (ndcX + 1.0) * 0.5 * width
                let sy = (ndcY + 1.0) * 0.5 * height
                sMin = simd_min(sMin, SIMD2<Float>(sx, sy))
                sMax = simd_max(sMax, SIMD2<Float>(sx, sy))
            }
        }

        if inFrontCount == 0 { return nil }
        if inFrontCount < 8 {
            sMin = simd_min(sMin, SIMD2<Float>(0, 0))
            sMax = simd_max(sMax, SIMD2<Float>(width, height))
        }
        return (sMin, sMax)
    }

    public func squaredDistance(to point: SIMD3<Float>) -> Float {
        let clamped = simd_clamp(point, min, max)
        return simd_distance_squared(point, clamped)
    }

    public func distance(to point: SIMD3<Float>) -> Float {
        sqrt(squaredDistance(to: point))
    }

    public func squaredDistance(to other: AABB) -> Float {
        var distSq: Float = 0
        for i in 0..<3 {
            if max[i] < other.min[i] {
                let d = other.min[i] - max[i]
                distSq += d * d
            } else if other.max[i] < min[i] {
                let d = min[i] - other.max[i]
                distSq += d * d
            }
        }
        return distSq
    }

    public func distance(to other: AABB) -> Float {
        sqrt(squaredDistance(to: other))
    }

    public func transformed(by matrix: simd_float4x4) -> AABB {
        var newLo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var newHi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for c in corners {
            let p4 = matrix * SIMD4<Float>(c.x, c.y, c.z, 1.0)
            let p = SIMD3<Float>(p4.x, p4.y, p4.z)
            newLo = simd_min(newLo, p)
            newHi = simd_max(newHi, p)
        }
        return AABB(min: newLo, max: newHi)
    }
}

// MARK: - Frustum Volume

/// 6-plane frustum volume for accelerated screen-space and picking queries against BVH AABBs.
public struct FrustumVolume: Sendable {
    public let p0: SIMD4<Float>
    public let p1: SIMD4<Float>
    public let p2: SIMD4<Float>
    public let p3: SIMD4<Float>
    public let p4: SIMD4<Float>
    public let p5: SIMD4<Float>
    public let pCamera: SIMD4<Float>

    public init(modelViewProj: simd_float4x4, ndcMin: SIMD2<Float>, ndcMax: SIMD2<Float>) {
        let row0 = SIMD4<Float>(modelViewProj.columns.0.x, modelViewProj.columns.1.x, modelViewProj.columns.2.x, modelViewProj.columns.3.x)
        let row1 = SIMD4<Float>(modelViewProj.columns.0.y, modelViewProj.columns.1.y, modelViewProj.columns.2.y, modelViewProj.columns.3.y)
        let row2 = SIMD4<Float>(modelViewProj.columns.0.z, modelViewProj.columns.1.z, modelViewProj.columns.2.z, modelViewProj.columns.3.z)
        let row3 = SIMD4<Float>(modelViewProj.columns.0.w, modelViewProj.columns.1.w, modelViewProj.columns.2.w, modelViewProj.columns.3.w)

        self.p0 = row0 - ndcMin.x * row3
        self.p1 = ndcMax.x * row3 - row0
        self.p2 = row1 - ndcMin.y * row3
        self.p3 = ndcMax.y * row3 - row1
        self.p4 = row2
        self.p5 = row3 - row2
        self.pCamera = row3
    }

    @inline(__always)
    public func intersects(aabb: AABB) -> Bool {
        if !testPlane(p0, min: aabb.min, max: aabb.max) { return false }
        if !testPlane(p1, min: aabb.min, max: aabb.max) { return false }
        if !testPlane(p2, min: aabb.min, max: aabb.max) { return false }
        if !testPlane(p3, min: aabb.min, max: aabb.max) { return false }
        if !testPlane(pCamera, min: aabb.min, max: aabb.max) { return false }
        if !testPlane(p4, min: aabb.min, max: aabb.max) { return false }
        if !testPlane(p5, min: aabb.min, max: aabb.max) { return false }
        return true
    }

    @inline(__always)
    private func testPlane(_ p: SIMD4<Float>, min: SIMD3<Float>, max: SIMD3<Float>) -> Bool {
        let px = p.x >= 0 ? max.x : min.x
        let py = p.y >= 0 ? max.y : min.y
        let pz = p.z >= 0 ? max.z : min.z
        return (p.x * px + p.y * py + p.z * pz + p.w) >= 0
    }
}

// MARK: - Flat BVH Node

/// Cache-coherent flat tree node for contiguous array-based hierarchical bounding volume traversal.
public struct FlatBVHNode: Sendable {
    public var bounds: AABB
    public var leftOrPrimitiveIndex: Int32
    public var primitiveCount: Int32
    public var rightChildIndex: Int32

    public var isLeaf: Bool { primitiveCount > 0 }

    public init(bounds: AABB, leftOrPrimitiveIndex: Int32, primitiveCount: Int32, rightChildIndex: Int32) {
        self.bounds = bounds
        self.leftOrPrimitiveIndex = leftOrPrimitiveIndex
        self.primitiveCount = primitiveCount
        self.rightChildIndex = rightChildIndex
    }
}

// MARK: - Primitives

public protocol BVHPrimitive: Sendable {
    var bounds: AABB { get }
    var centroid: SIMD3<Float> { get }
}

public struct BVHTriangle: Sendable, BVHPrimitive {
    public let v0: SIMD3<Float>
    public let v1: SIMD3<Float>
    public let v2: SIMD3<Float>
    public let triIndex: Int
    public let faceId: Int
    public let deterministicId: UUID?
    public let bounds: AABB
    public let centroid: SIMD3<Float>

    public init(v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, triIndex: Int, faceId: Int, deterministicId: UUID? = nil) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
        self.triIndex = triIndex
        self.faceId = faceId
        self.deterministicId = deterministicId
        var b = AABB(point: v0)
        b.union(with: v1)
        b.union(with: v2)
        self.bounds = b
        self.centroid = (v0 + v1 + v2) / 3.0
    }
}

public struct BVHEdge: Sendable, BVHPrimitive {
    public let p0: SIMD3<Float>
    public let p1: SIMD3<Float>
    public let edgeId: Int
    public let deterministicId: UUID?
    public let bounds: AABB
    public let centroid: SIMD3<Float>

    public init(p0: SIMD3<Float>, p1: SIMD3<Float>, edgeId: Int, deterministicId: UUID? = nil) {
        self.p0 = p0
        self.p1 = p1
        self.edgeId = edgeId
        self.deterministicId = deterministicId
        var b = AABB(point: p0)
        b.union(with: p1)
        self.bounds = b
        self.centroid = (p0 + p1) * 0.5
    }
}

public struct BVHVertex: Sendable, BVHPrimitive {
    public let position: SIMD3<Float>
    public let vertexId: Int
    public let deterministicId: UUID?
    public let bounds: AABB
    public let centroid: SIMD3<Float>

    public init(position: SIMD3<Float>, vertexId: Int, deterministicId: UUID? = nil) {
        self.position = position
        self.vertexId = vertexId
        self.deterministicId = deterministicId
        self.bounds = AABB(point: position)
        self.centroid = position
    }
}

// MARK: - BVH Tree Builder Helper

private func buildFlatBVH<P: BVHPrimitive>(
    primitives: inout [P],
    maxLeafPrimitives: Int = 4
) -> [FlatBVHNode] {
    guard !primitives.isEmpty else { return [] }
    var nodes: [FlatBVHNode] = []
    nodes.reserveCapacity(Swift.max(1, primitives.count * 2))

    func buildRecursive(start: Int, count: Int) -> Int32 {
        let nodeIndex = Int32(nodes.count)
        nodes.append(FlatBVHNode(
            bounds: AABB(min: .zero, max: .zero),
            leftOrPrimitiveIndex: 0,
            primitiveCount: 0,
            rightChildIndex: -1
        ))

        var totalBounds = primitives[start].bounds
        var centroidBounds = AABB(point: primitives[start].centroid)
        for i in (start + 1)..<(start + count) {
            totalBounds.union(with: primitives[i].bounds)
            centroidBounds.union(with: primitives[i].centroid)
        }

        if count <= maxLeafPrimitives {
            nodes[Int(nodeIndex)] = FlatBVHNode(
                bounds: totalBounds,
                leftOrPrimitiveIndex: Int32(start),
                primitiveCount: Int32(count),
                rightChildIndex: -1
            )
            return nodeIndex
        }

        let ext = centroidBounds.extents
        var axis = 0
        if ext.y > ext.x && ext.y >= ext.z {
            axis = 1
        } else if ext.z > ext.x && ext.z > ext.y {
            axis = 2
        }

        let mid = start + count / 2
        primitives[start..<(start + count)].sort { a, b in
            a.centroid[axis] < b.centroid[axis]
        }

        let left = buildRecursive(start: start, count: mid - start)
        let right = buildRecursive(start: mid, count: start + count - mid)

        nodes[Int(nodeIndex)] = FlatBVHNode(
            bounds: totalBounds,
            leftOrPrimitiveIndex: left,
            primitiveCount: 0,
            rightChildIndex: right
        )
        return nodeIndex
    }

    _ = buildRecursive(start: 0, count: primitives.count)
    return nodes
}

// MARK: - SubElementCandidateHit

public struct SubElementCandidateHit: Sendable, Equatable {
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

// MARK: - TriangleBVH

public struct TriangleRaycastHit: Sendable, Equatable {
    public let hitPoint: SIMD3<Float>
    public let distance: Float
    public let triIndex: Int
    public let faceId: Int
    public let deterministicId: UUID?

    public init(hitPoint: SIMD3<Float>, distance: Float, triIndex: Int, faceId: Int, deterministicId: UUID? = nil) {
        self.hitPoint = hitPoint
        self.distance = distance
        self.triIndex = triIndex
        self.faceId = faceId
        self.deterministicId = deterministicId
    }
}

public struct TriangleBVH: Sendable {
    public let nodes: [FlatBVHNode]
    public let primitives: [BVHTriangle]

    public init(primitives: [BVHTriangle], maxLeafPrimitives: Int = 4) {
        var mutablePrimitives = primitives
        self.nodes = buildFlatBVH(primitives: &mutablePrimitives, maxLeafPrimitives: maxLeafPrimitives)
        self.primitives = mutablePrimitives
    }

    public func raycast(ray: Ray3D, minT: Float = 1e-4, maxT: Float = .greatestFiniteMagnitude) -> TriangleRaycastHit? {
        guard !nodes.isEmpty else { return nil }

        var stack = [Int32](repeating: 0, count: 64)
        var stackPtr = 0
        stack[0] = 0
        var closestHit: TriangleRaycastHit? = nil
        var currentMaxT = maxT

        while stackPtr >= 0 {
            let nodeIdx = Int(stack[stackPtr])
            stackPtr -= 1

            let node = nodes[nodeIdx]
            let (hitBox, tBox) = node.bounds.intersects(ray: ray, minT: minT, maxT: currentMaxT)
            if !hitBox || tBox >= currentMaxT { continue }

            if node.isLeaf {
                let start = Int(node.leftOrPrimitiveIndex)
                let count = Int(node.primitiveCount)
                for i in start..<(start + count) {
                    let tri = primitives[i]
                    let edge1 = tri.v1 - tri.v0
                    let edge2 = tri.v2 - tri.v0
                    let h = simd_cross(ray.direction, edge2)
                    let a = simd_dot(edge1, h)
                    if abs(a) < 1e-7 { continue }
                    let f = 1.0 / a
                    let s = ray.origin - tri.v0
                    let u = f * simd_dot(s, h)
                    if u < 0.0 || u > 1.0 { continue }
                    let q = simd_cross(s, edge1)
                    let v = f * simd_dot(ray.direction, q)
                    if v < 0.0 || u + v > 1.0 { continue }
                    let t = f * simd_dot(edge2, q)
                    if t >= minT && t < currentMaxT {
                        currentMaxT = t
                        let hitPt = ray.origin + ray.direction * t
                        closestHit = TriangleRaycastHit(
                            hitPoint: hitPt,
                            distance: t,
                            triIndex: tri.triIndex,
                            faceId: tri.faceId,
                            deterministicId: tri.deterministicId
                        )
                    }
                }
            } else {
                let leftIdx = node.leftOrPrimitiveIndex
                let rightIdx = node.rightChildIndex
                let (hitLeft, tLeft) = nodes[Int(leftIdx)].bounds.intersects(ray: ray, minT: minT, maxT: currentMaxT)
                let (hitRight, tRight) = nodes[Int(rightIdx)].bounds.intersects(ray: ray, minT: minT, maxT: currentMaxT)

                if hitLeft && hitRight {
                    if tLeft < tRight {
                        stackPtr += 1; stack[stackPtr] = rightIdx
                        stackPtr += 1; stack[stackPtr] = leftIdx
                    } else {
                        stackPtr += 1; stack[stackPtr] = leftIdx
                        stackPtr += 1; stack[stackPtr] = rightIdx
                    }
                } else if hitLeft {
                    stackPtr += 1; stack[stackPtr] = leftIdx
                } else if hitRight {
                    stackPtr += 1; stack[stackPtr] = rightIdx
                }
            }
        }
        return closestHit
    }

    public func closestPoint(
        to point: SIMD3<Float>,
        maxDistance: Float = .greatestFiniteMagnitude
    ) -> (point: SIMD3<Float>, distance: Float, normal: SIMD3<Float>?, triIndex: Int, faceId: Int)? {
        guard !nodes.isEmpty else { return nil }

        var stack = [Int32](repeating: 0, count: 64)
        var stackPtr = 0
        stack[0] = 0

        var bestDistSq = maxDistance * maxDistance
        var bestPoint: SIMD3<Float>? = nil
        var bestNormal: SIMD3<Float>? = nil
        var bestTriIndex: Int = 0
        var bestFaceId: Int = 0

        while stackPtr >= 0 {
            let nodeIdx = Int(stack[stackPtr])
            stackPtr -= 1

            let node = nodes[nodeIdx]
            let boxDistSq = node.bounds.squaredDistance(to: point)
            if boxDistSq >= bestDistSq { continue }

            if node.isLeaf {
                let start = Int(node.leftOrPrimitiveIndex)
                let count = Int(node.primitiveCount)
                for i in start..<(start + count) {
                    let tri = primitives[i]
                    let pt = closestPointOnTriangle(p: point, a: tri.v0, b: tri.v1, c: tri.v2)
                    let dSq = simd_distance_squared(point, pt)
                    if dSq < bestDistSq {
                        bestDistSq = dSq
                        bestPoint = pt
                        bestTriIndex = tri.triIndex
                        bestFaceId = tri.faceId
                        let normal = simd_cross(tri.v1 - tri.v0, tri.v2 - tri.v0)
                        let len = simd_length(normal)
                        bestNormal = len > 1e-6 ? (normal / len) : nil
                    }
                }
            } else {
                let leftIdx = node.leftOrPrimitiveIndex
                let rightIdx = node.rightChildIndex
                let dLeftSq = nodes[Int(leftIdx)].bounds.squaredDistance(to: point)
                let dRightSq = nodes[Int(rightIdx)].bounds.squaredDistance(to: point)

                if dLeftSq < dRightSq {
                    if dRightSq < bestDistSq { stackPtr += 1; stack[stackPtr] = rightIdx }
                    if dLeftSq < bestDistSq { stackPtr += 1; stack[stackPtr] = leftIdx }
                } else {
                    if dLeftSq < bestDistSq { stackPtr += 1; stack[stackPtr] = leftIdx }
                    if dRightSq < bestDistSq { stackPtr += 1; stack[stackPtr] = rightIdx }
                }
            }
        }

        guard let pt = bestPoint else { return nil }
        return (point: pt, distance: sqrt(bestDistSq), normal: bestNormal, triIndex: bestTriIndex, faceId: bestFaceId)
    }
}

// MARK: - EdgeBVH

public struct EdgeBVH: Sendable {
    public let nodes: [FlatBVHNode]
    public let primitives: [BVHEdge]

    public init(primitives: [BVHEdge], maxLeafPrimitives: Int = 4) {
        var mutablePrimitives = primitives
        self.nodes = buildFlatBVH(primitives: &mutablePrimitives, maxLeafPrimitives: maxLeafPrimitives)
        self.primitives = mutablePrimitives
    }

    public func querySnapCandidates(
        pointer: SIMD2<Float>,
        tolerancePx: Float,
        vp: simd_float4x4,
        viewportSize: CGSize,
        transform: Transform
    ) -> [SnapCandidate] {
        var candidates: [SnapCandidate] = []
        candidates.reserveCapacity(256)
        querySnapCandidates(
            pointer: pointer,
            tolerancePx: tolerancePx,
            vp: vp,
            viewportSize: viewportSize,
            transform: transform,
            into: &candidates
        )
        return candidates
    }

    public func querySnapCandidates(
        pointer: SIMD2<Float>,
        tolerancePx: Float,
        vp: simd_float4x4,
        viewportSize: CGSize,
        transform: Transform,
        into candidates: inout [SnapCandidate]
    ) {
        guard !nodes.isEmpty else { return }
        let width = Float(viewportSize.width)
        let height = Float(viewportSize.height)
        guard width > 0 && height > 0 else { return }

        let modelViewProj = vp * transform.matrix
        let pMin = pointer - SIMD2<Float>(tolerancePx, tolerancePx)
        let pMax = pointer + SIMD2<Float>(tolerancePx, tolerancePx)

        let ndcMinX = (pMin.x / width) * 2.0 - 1.0
        let ndcMaxX = (pMax.x / width) * 2.0 - 1.0
        let ndcMinY = (pMin.y / height) * 2.0 - 1.0
        let ndcMaxY = (pMax.y / height) * 2.0 - 1.0

        let frustum = FrustumVolume(
            modelViewProj: modelViewProj,
            ndcMin: SIMD2<Float>(ndcMinX, ndcMinY),
            ndcMax: SIMD2<Float>(ndcMaxX, ndcMaxY)
        )

        let halfW = width * 0.5
        let halfH = height * 0.5
        let tolSq = tolerancePx * tolerancePx
        let isIdentity = (transform == .identity)

        guard frustum.intersects(aabb: nodes[0].bounds) else { return }

        let initialCount = candidates.count

        nodes.withUnsafeBufferPointer { nodeBuf in
            primitives.withUnsafeBufferPointer { primBuf in
                withUnsafeTemporaryAllocation(of: Int32.self, capacity: 64) { stack in
                    var stackPtr = 0
                    stack[0] = 0

                    while stackPtr >= 0 {
                        if candidates.count - initialCount >= 64 { break }

                        let nodeIdx = Int(stack[stackPtr])
                        stackPtr -= 1

                        let node = nodeBuf[nodeIdx]

                        if node.isLeaf {
                            let start = Int(node.leftOrPrimitiveIndex)
                            let count = Int(node.primitiveCount)
                            for i in start..<(start + count) {
                                let edge = primBuf[i]
                                let c1 = modelViewProj * SIMD4<Float>(edge.p0, 1.0)
                                let c2 = modelViewProj * SIMD4<Float>(edge.p1, 1.0)
                                guard c1.w > 1e-6 && c2.w > 1e-6 else { continue }
                                let invW1 = 1.0 / c1.w
                                let invW2 = 1.0 / c2.w

                                let ndcX1 = c1.x * invW1
                                let ndcX2 = c2.x * invW2
                                if (ndcX1 < ndcMinX && ndcX2 < ndcMinX) || (ndcX1 > ndcMaxX && ndcX2 > ndcMaxX) {
                                    continue
                                }

                                let ndcY1 = c1.y * invW1
                                let ndcY2 = c2.y * invW2
                                if (ndcY1 < ndcMinY && ndcY2 < ndcMinY) || (ndcY1 > ndcMaxY && ndcY2 > ndcMaxY) {
                                    continue
                                }

                                let s1 = SIMD2<Float>((ndcX1 + 1.0) * halfW, (ndcY1 + 1.0) * halfH)
                                let s2 = SIMD2<Float>((ndcX2 + 1.0) * halfW, (ndcY2 + 1.0) * halfH)

                                let sDiff = s2 - s1
                                let lenSq = simd_length_squared(sDiff)
                                let t: Float
                                if lenSq < 1e-6 {
                                    t = 0.0
                                } else {
                                    let dot = simd_dot(pointer - s1, sDiff)
                                    t = min(max(dot / lenSq, 0.0), 1.0)
                                }

                                let sProj = s1 + sDiff * t
                                let diff = pointer - sProj
                                let distSq = simd_length_squared(diff)
                                if distSq <= tolSq {
                                    let screenDist = sqrt(distSq)
                                    let denom = (1.0 - t) * c2.w + t * c1.w
                                    let u: Float = (denom > 1e-6) ? ((t * c1.w) / denom) : t
                                    let localHit = edge.p0 + (edge.p1 - edge.p0) * u
                                    let worldPoint = isIdentity ? localHit : transform.transformPoint(localHit)
                                    candidates.append(SnapCandidate(kind: .edge, point: worldPoint, screenDistancePx: screenDist))
                                    if candidates.count - initialCount >= 64 { break }
                                }
                            }
                        } else {
                            let left = node.leftOrPrimitiveIndex
                            let right = node.rightChildIndex
                            if frustum.intersects(aabb: nodeBuf[Int(left)].bounds) {
                                stackPtr += 1; stack[stackPtr] = left
                            }
                            if frustum.intersects(aabb: nodeBuf[Int(right)].bounds) {
                                stackPtr += 1; stack[stackPtr] = right
                            }
                        }
                    }
                }
            }
        }

        let addedCount = candidates.count - initialCount
        if addedCount > 1 {
            candidates[initialCount...].sort { $0.screenDistancePx < $1.screenDistancePx }
        }
    }

    public func queryPickCandidates(
        pointer: SIMD2<Float>,
        screenTolerancePx: Float,
        vp: simd_float4x4,
        viewportSize: CGSize,
        worldRay: Ray3D,
        occlusionThreshold: Float?,
        transform: Transform,
        solidId: SolidId
    ) -> [SubElementCandidateHit] {
        guard !nodes.isEmpty else { return [] }
        let width = Float(viewportSize.width)
        let height = Float(viewportSize.height)
        guard width > 0 && height > 0 else { return [] }

        let modelViewProj = vp * transform.matrix
        let pMin = pointer - SIMD2<Float>(screenTolerancePx, screenTolerancePx)
        let pMax = pointer + SIMD2<Float>(screenTolerancePx, screenTolerancePx)

        let ndcMinX = (pMin.x / width) * 2.0 - 1.0
        let ndcMaxX = (pMax.x / width) * 2.0 - 1.0
        let ndcMinY = (pMin.y / height) * 2.0 - 1.0
        let ndcMaxY = (pMax.y / height) * 2.0 - 1.0

        let frustum = FrustumVolume(
            modelViewProj: modelViewProj,
            ndcMin: SIMD2<Float>(ndcMinX, ndcMinY),
            ndcMax: SIMD2<Float>(ndcMaxX, ndcMaxY)
        )

        var stack = [Int32](repeating: 0, count: 64)
        var stackPtr = 0
        stack[0] = 0
        var hits: [SubElementCandidateHit] = []

        while stackPtr >= 0 {
            let nodeIdx = Int(stack[stackPtr])
            stackPtr -= 1

            let node = nodes[nodeIdx]
            guard frustum.intersects(aabb: node.bounds) else {
                continue
            }

            if node.isLeaf {
                let start = Int(node.leftOrPrimitiveIndex)
                let count = Int(node.primitiveCount)
                for i in start..<(start + count) {
                    let edge = primitives[i]
                    let pA = transform.transformPoint(edge.p0)
                    let pB = transform.transformPoint(edge.p1)
                    guard let sA = projectToScreenWithW(point: pA, viewProjectionMatrix: vp, viewportSize: viewportSize),
                          let sB = projectToScreenWithW(point: pB, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                        continue
                    }
                    let (closestWorld, screenDist) = closestPointOnSegment(
                        p1: pA, p2: pB,
                        s1: sA.screen, s2: sB.screen,
                        screenPointer: pointer,
                        w1: sA.w, w2: sB.w
                    )
                    guard screenDist <= screenTolerancePx else { continue }
                    let t = simd_dot(closestWorld - worldRay.origin, worldRay.direction)
                    guard t > 0 else { continue }
                    if let threshold = occlusionThreshold, t > threshold { continue }
                    hits.append(SubElementCandidateHit(
                        solidId: solidId,
                        elementType: .edge,
                        elementId: edge.edgeId,
                        deterministicId: edge.deterministicId,
                        distance: t,
                        hitPoint: closestWorld
                    ))
                }
            } else {
                stackPtr += 1; stack[stackPtr] = node.leftOrPrimitiveIndex
                stackPtr += 1; stack[stackPtr] = node.rightChildIndex
            }
        }
        return hits
    }
}

// MARK: - VertexBVH

public struct VertexBVH: Sendable {
    public let nodes: [FlatBVHNode]
    public let primitives: [BVHVertex]

    public init(primitives: [BVHVertex], maxLeafPrimitives: Int = 4) {
        var mutablePrimitives = primitives
        self.nodes = buildFlatBVH(primitives: &mutablePrimitives, maxLeafPrimitives: maxLeafPrimitives)
        self.primitives = mutablePrimitives
    }

    public func querySnapCandidates(
        pointer: SIMD2<Float>,
        tolerancePx: Float,
        vp: simd_float4x4,
        viewportSize: CGSize,
        transform: Transform
    ) -> [SnapCandidate] {
        var candidates: [SnapCandidate] = []
        candidates.reserveCapacity(128)
        querySnapCandidates(
            pointer: pointer,
            tolerancePx: tolerancePx,
            vp: vp,
            viewportSize: viewportSize,
            transform: transform,
            into: &candidates
        )
        return candidates
    }

    public func querySnapCandidates(
        pointer: SIMD2<Float>,
        tolerancePx: Float,
        vp: simd_float4x4,
        viewportSize: CGSize,
        transform: Transform,
        into candidates: inout [SnapCandidate]
    ) {
        guard !nodes.isEmpty else { return }
        let width = Float(viewportSize.width)
        let height = Float(viewportSize.height)
        guard width > 0 && height > 0 else { return }

        let modelViewProj = vp * transform.matrix
        let pMin = pointer - SIMD2<Float>(tolerancePx, tolerancePx)
        let pMax = pointer + SIMD2<Float>(tolerancePx, tolerancePx)

        let ndcMinX = (pMin.x / width) * 2.0 - 1.0
        let ndcMaxX = (pMax.x / width) * 2.0 - 1.0
        let ndcMinY = (pMin.y / height) * 2.0 - 1.0
        let ndcMaxY = (pMax.y / height) * 2.0 - 1.0

        let frustum = FrustumVolume(
            modelViewProj: modelViewProj,
            ndcMin: SIMD2<Float>(ndcMinX, ndcMinY),
            ndcMax: SIMD2<Float>(ndcMaxX, ndcMaxY)
        )

        let halfW = width * 0.5
        let halfH = height * 0.5
        let tolSq = tolerancePx * tolerancePx
        let isIdentity = (transform == .identity)

        guard frustum.intersects(aabb: nodes[0].bounds) else { return }

        let initialCount = candidates.count
        var candidateDepths: [Float] = []
        candidateDepths.reserveCapacity(64)

        nodes.withUnsafeBufferPointer { nodeBuf in
            primitives.withUnsafeBufferPointer { primBuf in
                withUnsafeTemporaryAllocation(of: Int32.self, capacity: 64) { stack in
                    var stackPtr = 0
                    stack[0] = 0

                    while stackPtr >= 0 {
                        if candidates.count - initialCount >= 64 { break }

                        let nodeIdx = Int(stack[stackPtr])
                        stackPtr -= 1

                        let node = nodeBuf[nodeIdx]

                        if node.isLeaf {
                            let start = Int(node.leftOrPrimitiveIndex)
                            let count = Int(node.primitiveCount)
                            for i in start..<(start + count) {
                                let v = primBuf[i]
                                let c = modelViewProj * SIMD4<Float>(v.position, 1.0)
                                guard c.w > 1e-6 else { continue }
                                let invW = 1.0 / c.w
                                let ndcZ = c.z * invW
                                guard ndcZ >= 0.0 && ndcZ <= 1.0 else { continue }
                                let sx = (c.x * invW + 1.0) * halfW
                                let sy = (c.y * invW + 1.0) * halfH
                                let screenPos = SIMD2<Float>(sx, sy)
                                let diff = pointer - screenPos
                                let distSq = simd_length_squared(diff)
                                if distSq <= tolSq {
                                    let worldPos = isIdentity ? v.position : transform.transformPoint(v.position)
                                    candidates.append(SnapCandidate(kind: .vertex, point: worldPos, screenDistancePx: sqrt(distSq)))
                                    candidateDepths.append(ndcZ)
                                    if candidates.count - initialCount >= 64 { break }
                                }
                            }
                        } else {
                            let left = node.leftOrPrimitiveIndex
                            let right = node.rightChildIndex
                            if frustum.intersects(aabb: nodeBuf[Int(left)].bounds) {
                                stackPtr += 1; stack[stackPtr] = left
                            }
                            if frustum.intersects(aabb: nodeBuf[Int(right)].bounds) {
                                stackPtr += 1; stack[stackPtr] = right
                            }
                        }
                    }
                }
            }
        }

        let addedCount = candidates.count - initialCount
        if addedCount > 1 {
            let sortedSubIndices = (0..<addedCount).sorted {
                let dA = candidates[initialCount + $0].screenDistancePx
                let dB = candidates[initialCount + $1].screenDistancePx
                if abs(dA - dB) > 1e-4 {
                    return dA < dB
                }
                return candidateDepths[$0] < candidateDepths[$1]
            }
            let original = Array(candidates[initialCount...])
            for (i, sortedIdx) in sortedSubIndices.enumerated() {
                candidates[initialCount + i] = original[sortedIdx]
            }
        }
    }

    public func queryPickCandidates(
        pointer: SIMD2<Float>,
        screenTolerancePx: Float,
        vp: simd_float4x4,
        viewportSize: CGSize,
        worldRay: Ray3D,
        occlusionThreshold: Float?,
        transform: Transform,
        solidId: SolidId
    ) -> [SubElementCandidateHit] {
        guard !nodes.isEmpty else { return [] }
        let width = Float(viewportSize.width)
        let height = Float(viewportSize.height)
        guard width > 0 && height > 0 else { return [] }

        let modelViewProj = vp * transform.matrix
        let pMin = pointer - SIMD2<Float>(screenTolerancePx, screenTolerancePx)
        let pMax = pointer + SIMD2<Float>(screenTolerancePx, screenTolerancePx)

        let ndcMinX = (pMin.x / width) * 2.0 - 1.0
        let ndcMaxX = (pMax.x / width) * 2.0 - 1.0
        let ndcMinY = (pMin.y / height) * 2.0 - 1.0
        let ndcMaxY = (pMax.y / height) * 2.0 - 1.0

        let frustum = FrustumVolume(
            modelViewProj: modelViewProj,
            ndcMin: SIMD2<Float>(ndcMinX, ndcMinY),
            ndcMax: SIMD2<Float>(ndcMaxX, ndcMaxY)
        )

        var stack = [Int32](repeating: 0, count: 64)
        var stackPtr = 0
        stack[0] = 0
        var hits: [SubElementCandidateHit] = []

        while stackPtr >= 0 {
            let nodeIdx = Int(stack[stackPtr])
            stackPtr -= 1

            let node = nodes[nodeIdx]
            guard frustum.intersects(aabb: node.bounds) else {
                continue
            }

            if node.isLeaf {
                let start = Int(node.leftOrPrimitiveIndex)
                let count = Int(node.primitiveCount)
                for i in start..<(start + count) {
                    let v = primitives[i]
                    let worldPos = transform.transformPoint(v.position)
                    guard let screenProj = projectToScreenWithW(point: worldPos, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                        continue
                    }
                    let screenDist = simd_distance(pointer, screenProj.screen)
                    guard screenDist <= screenTolerancePx else { continue }
                    let t = simd_dot(worldPos - worldRay.origin, worldRay.direction)
                    guard t > 0 else { continue }
                    if let threshold = occlusionThreshold, t > threshold { continue }
                    hits.append(SubElementCandidateHit(
                        solidId: solidId,
                        elementType: .vertex,
                        elementId: v.vertexId,
                        deterministicId: v.deterministicId,
                        distance: t,
                        hitPoint: worldPos
                    ))
                }
            } else {
                stackPtr += 1; stack[stackPtr] = node.leftOrPrimitiveIndex
                stackPtr += 1; stack[stackPtr] = node.rightChildIndex
            }
        }
        return hits
    }
}

// MARK: - BodySpatialIndex

/// Incremental spatial index composing AABB bounds, TriangleBVH, EdgeBVH, and VertexBVH.
public final class BodySpatialIndex: Sendable {
    public let bounds: AABB
    public let triangleBVH: TriangleBVH
    public let edgeBVH: EdgeBVH
    public let vertexBVH: VertexBVH

    public init(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        faceRanges: [FaceTriangleRange] = [],
        edges: [MeshEdge] = [],
        edgePolylines: [EdgePolyline] = [],
        vertexPoints: [VertexPoint] = []
    ) {
        if positions.isEmpty {
            self.bounds = AABB(min: .zero, max: .zero)
            self.triangleBVH = TriangleBVH(primitives: [])
            self.edgeBVH = EdgeBVH(primitives: [])
            self.vertexBVH = VertexBVH(primitives: [])
            return
        }

        var rootBounds = AABB(point: positions[0])
        for p in positions.dropFirst() {
            rootBounds.union(with: p)
        }
        self.bounds = rootBounds

        // 1. Build triangles
        var triangles: [BVHTriangle] = []
        let triIndices: [UInt32]
        if !indices.isEmpty {
            triIndices = indices
        } else {
            triIndices = Array(0..<UInt32(positions.count))
        }
        let numTriangles = triIndices.count / 3
        triangles.reserveCapacity(numTriangles)

        for triIdx in 0..<numTriangles {
            let i0 = Int(triIndices[triIdx * 3])
            let i1 = Int(triIndices[triIdx * 3 + 1])
            let i2 = Int(triIndices[triIdx * 3 + 2])
            guard i0 < positions.count && i1 < positions.count && i2 < positions.count else { continue }
            let v0 = positions[i0]
            let v1 = positions[i1]
            let v2 = positions[i2]
            let faceRange = faceRanges.first(where: { $0.triangleRange.contains(triIdx) })
            let faceId = faceRange?.faceId ?? 0
            let detId = faceRange?.deterministicId
            triangles.append(BVHTriangle(
                v0: v0, v1: v1, v2: v2,
                triIndex: triIdx,
                faceId: faceId,
                deterministicId: detId
            ))
        }
        self.triangleBVH = TriangleBVH(primitives: triangles)

        // 2. Build edges
        var bvhEdges: [BVHEdge] = []
        if !edgePolylines.isEmpty {
            for poly in edgePolylines {
                let pts = poly.points
                guard pts.count >= 2 else { continue }
                for i in 0..<(pts.count - 1) {
                    bvhEdges.append(BVHEdge(
                        p0: pts[i],
                        p1: pts[i + 1],
                        edgeId: poly.edgeId,
                        deterministicId: poly.deterministicId
                    ))
                }
            }
        } else if !edges.isEmpty {
            bvhEdges.reserveCapacity(edges.count)
            for (idx, e) in edges.enumerated() {
                let i0 = Int(e.v0)
                let i1 = Int(e.v1)
                guard i0 < positions.count && i1 < positions.count else { continue }
                bvhEdges.append(BVHEdge(
                    p0: positions[i0],
                    p1: positions[i1],
                    edgeId: idx,
                    deterministicId: nil
                ))
            }
        }
        self.edgeBVH = EdgeBVH(primitives: bvhEdges)

        // 3. Build vertices
        var bvhVertices: [BVHVertex] = []
        if !vertexPoints.isEmpty {
            bvhVertices.reserveCapacity(vertexPoints.count)
            for vp in vertexPoints {
                bvhVertices.append(BVHVertex(
                    position: vp.position,
                    vertexId: vp.vertexId,
                    deterministicId: vp.deterministicId
                ))
            }
        } else {
            bvhVertices.reserveCapacity(positions.count)
            for (idx, p) in positions.enumerated() {
                bvhVertices.append(BVHVertex(
                    position: p,
                    vertexId: idx,
                    deterministicId: nil
                ))
            }
        }
        self.vertexBVH = VertexBVH(primitives: bvhVertices)
    }
}

// MARK: - Geometric Queries & Triangle Utilities

/// Finds the closest point on a 3D triangle (a, b, c) to point p.
public func closestPointOnTriangle(p: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> SIMD3<Float> {
    let ab = b - a
    let ac = c - a
    let ap = p - a
    let d1 = simd_dot(ab, ap)
    let d2 = simd_dot(ac, ap)
    if d1 <= 0 && d2 <= 0 { return a }

    let bp = p - b
    let d3 = simd_dot(ab, bp)
    let d4 = simd_dot(ac, bp)
    if d3 >= 0 && d4 <= d3 { return b }

    let vc = d1 * d4 - d3 * d2
    if vc <= 0 && d1 >= 0 && d3 <= 0 {
        let v = d1 / (d1 - d3)
        return a + v * ab
    }

    let cp = p - c
    let d5 = simd_dot(ab, cp)
    let d6 = simd_dot(ac, cp)
    if d6 >= 0 && d5 <= d6 { return c }

    let vb = d5 * d2 - d1 * d6
    if vb <= 0 && d2 >= 0 && d6 <= 0 {
        let w = d2 / (d2 - d6)
        return a + w * ac
    }

    let va = d3 * d6 - d5 * d4
    if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
        let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return b + w * (c - b)
    }

    let denom = 1.0 / (va + vb + vc)
    let v = vb * denom
    let w = vc * denom
    return a + ab * v + ac * w
}

/// Computes the minimum distance between two 3D segments [p0, p1] and [q0, q1].
public func distanceBetweenSegments(
    p0: SIMD3<Float>, p1: SIMD3<Float>,
    q0: SIMD3<Float>, q1: SIMD3<Float>
) -> Float {
    let u = p1 - p0
    let v = q1 - q0
    let w0 = p0 - q0
    let a = simd_dot(u, u)
    let b = simd_dot(u, v)
    let c = simd_dot(v, v)
    let d = simd_dot(u, w0)
    let e = simd_dot(v, w0)
    let D = a * c - b * b

    var sc: Float
    var sN: Float
    var sD: Float = D
    var tc: Float
    var tN: Float
    var tD: Float = D

    if D < 1e-8 {
        sN = 0.0
        sD = 1.0
        tN = e
        tD = c
    } else {
        sN = (b * e - c * d)
        tN = (a * e - b * d)
        if sN < 0.0 {
            sN = 0.0
            tN = e
            tD = c
        } else if sN > sD {
            sN = sD
            tN = e + b
            tD = c
        }
    }

    if tN < 0.0 {
        tN = 0.0
        if -d < 0.0 {
            sN = 0.0
        } else if -d > a {
            sN = sD
        } else {
            sN = -d
            sD = a
        }
    } else if tN > tD {
        tN = tD
        if (-d + b) < 0.0 {
            sN = 0.0
        } else if (-d + b) > a {
            sN = sD
        } else {
            sN = (-d + b)
            sD = a
        }
    }

    sc = (abs(sN) < 1e-8 ? 0.0 : sN / sD)
    tc = (abs(tN) < 1e-8 ? 0.0 : tN / tD)

    let dP = w0 + (sc * u) - (tc * v)
    return simd_length(dP)
}

/// Evaluates Tomas Möller's 3D triangle-triangle intersection test.
public func trianglesIntersect(
    v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>,
    u0: SIMD3<Float>, u1: SIMD3<Float>, u2: SIMD3<Float>
) -> Bool {
    let e1 = u1 - u0
    let e2 = u2 - u0
    let n2 = simd_cross(e1, e2)
    let lenN2 = simd_length(n2)
    guard lenN2 > 1e-7 else { return false }
    let normN2 = n2 / lenN2
    let d2 = -simd_dot(normN2, u0)

    var dv0 = simd_dot(normN2, v0) + d2
    var dv1 = simd_dot(normN2, v1) + d2
    var dv2 = simd_dot(normN2, v2) + d2
    if abs(dv0) < 1e-5 { dv0 = 0 }
    if abs(dv1) < 1e-5 { dv1 = 0 }
    if abs(dv2) < 1e-5 { dv2 = 0 }

    if (dv0 > 0 && dv1 > 0 && dv2 > 0) || (dv0 < 0 && dv1 < 0 && dv2 < 0) {
        return false
    }

    let f1 = v1 - v0
    let f2 = v2 - v0
    let n1 = simd_cross(f1, f2)
    let lenN1 = simd_length(n1)
    guard lenN1 > 1e-7 else { return false }
    let normN1 = n1 / lenN1
    let d1 = -simd_dot(normN1, v0)

    var du0 = simd_dot(normN1, u0) + d1
    var du1 = simd_dot(normN1, u1) + d1
    var du2 = simd_dot(normN1, u2) + d1
    if abs(du0) < 1e-5 { du0 = 0 }
    if abs(du1) < 1e-5 { du1 = 0 }
    if abs(du2) < 1e-5 { du2 = 0 }

    if (du0 > 0 && du1 > 0 && du2 > 0) || (du0 < 0 && du1 < 0 && du2 < 0) {
        return false
    }

    let d = simd_cross(normN1, normN2)
    let lenD = simd_length(d)
    if lenD < 1e-5 {
        // Coplanar triangles: test 2D projection
        return coplanarTrianglesIntersect(v0: v0, v1: v1, v2: v2, u0: u0, u1: u1, u2: u2, normal: normN1)
    }

    let dir = d / lenD

    func getInterval(p0: Float, p1: Float, p2: Float, d0: Float, d1: Float, d2: Float) -> (min: Float, max: Float)? {
        if (d0 > 0 && d1 <= 0 && d2 <= 0) || (d0 < 0 && d1 >= 0 && d2 >= 0) {
            let tA = p0 + (p1 - p0) * (d0 / (d0 - d1))
            let tB = p0 + (p2 - p0) * (d0 / (d0 - d2))
            return (Swift.min(tA, tB), Swift.max(tA, tB))
        } else if (d1 > 0 && d0 <= 0 && d2 <= 0) || (d1 < 0 && d0 >= 0 && d2 >= 0) {
            let tA = p1 + (p0 - p1) * (d1 / (d1 - d0))
            let tB = p1 + (p2 - p1) * (d1 / (d1 - d2))
            return (Swift.min(tA, tB), Swift.max(tA, tB))
        } else if (d2 > 0 && d0 <= 0 && d1 <= 0) || (d2 < 0 && d0 >= 0 && d1 >= 0) {
            let tA = p2 + (p0 - p2) * (d2 / (d2 - d0))
            let tB = p2 + (p1 - p2) * (d2 / (d2 - d1))
            return (Swift.min(tA, tB), Swift.max(tA, tB))
        } else {
            var pts: [Float] = []
            if abs(d0) < 1e-5 { pts.append(p0) }
            if abs(d1) < 1e-5 { pts.append(p1) }
            if abs(d2) < 1e-5 { pts.append(p2) }
            if pts.count >= 2 {
                return (Swift.min(pts[0], pts[1]), Swift.max(pts[0], pts[1]))
            } else if pts.count == 1 {
                return (pts[0], pts[0])
            }
            return nil
        }
    }

    let pv0 = simd_dot(dir, v0)
    let pv1 = simd_dot(dir, v1)
    let pv2 = simd_dot(dir, v2)
    guard let isect1 = getInterval(p0: pv0, p1: pv1, p2: pv2, d0: dv0, d1: dv1, d2: dv2) else {
        return false
    }

    let pu0 = simd_dot(dir, u0)
    let pu1 = simd_dot(dir, u1)
    let pu2 = simd_dot(dir, u2)
    guard let isect2 = getInterval(p0: pu0, p1: pu1, p2: pu2, d0: du0, d1: du1, d2: du2) else {
        return false
    }

    return Swift.max(isect1.min, isect2.min) <= Swift.min(isect1.max, isect2.max) + 1e-5
}

private func coplanarTrianglesIntersect(
    v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>,
    u0: SIMD3<Float>, u1: SIMD3<Float>, u2: SIMD3<Float>,
    normal: SIMD3<Float>
) -> Bool {
    let absN = abs(normal)
    func project2D(_ p: SIMD3<Float>) -> SIMD2<Float> {
        if absN.z >= absN.x && absN.z >= absN.y {
            return SIMD2<Float>(p.x, p.y)
        } else if absN.x >= absN.y && absN.x >= absN.z {
            return SIMD2<Float>(p.y, p.z)
        } else {
            return SIMD2<Float>(p.x, p.z)
        }
    }

    let a0 = project2D(v0), a1 = project2D(v1), a2 = project2D(v2)
    let b0 = project2D(u0), b1 = project2D(u1), b2 = project2D(u2)

    func segIntersect(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ q1: SIMD2<Float>, _ q2: SIMD2<Float>) -> Bool {
        func ccw(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d1 = ccw(p1, p2, q1)
        let d2 = ccw(p1, p2, q2)
        let d3 = ccw(q1, q2, p1)
        let d4 = ccw(q1, q2, p2)
        if ((d1 > 1e-5 && d2 < -1e-5) || (d1 < -1e-5 && d2 > 1e-5)) &&
           ((d3 > 1e-5 && d4 < -1e-5) || (d3 < -1e-5 && d4 > 1e-5)) {
            return true
        }
        return false
    }

    let edgesA = [(a0, a1), (a1, a2), (a2, a0)]
    let edgesB = [(b0, b1), (b1, b2), (b2, b0)]
    for (ea1, ea2) in edgesA {
        for (eb1, eb2) in edgesB {
            if segIntersect(ea1, ea2, eb1, eb2) { return true }
        }
    }

    func pointInTri(_ p: SIMD2<Float>, _ t0: SIMD2<Float>, _ t1: SIMD2<Float>, _ t2: SIMD2<Float>) -> Bool {
        let d1 = (p.x - t1.x) * (t0.y - t1.y) - (t0.x - t1.x) * (p.y - t1.y)
        let d2 = (p.x - t2.x) * (t1.y - t2.y) - (t1.x - t2.x) * (p.y - t2.y)
        let d3 = (p.x - t0.x) * (t2.y - t0.y) - (t2.x - t0.x) * (p.y - t0.y)
        let hasNeg = (d1 < -1e-5) || (d2 < -1e-5) || (d3 < -1e-5)
        let hasPos = (d1 > 1e-5) || (d2 > 1e-5) || (d3 > 1e-5)
        return !(hasNeg && hasPos)
    }

    if pointInTri(b0, a0, a1, a2) || pointInTri(b1, a0, a1, a2) || pointInTri(b2, a0, a1, a2) { return true }
    if pointInTri(a0, b0, b1, b2) || pointInTri(a1, b0, b1, b2) || pointInTri(a2, b0, b1, b2) { return true }
    return false
}

/// Computes the exact minimum distance between two 3D triangles.
public func distanceBetweenTriangles(
    v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>,
    u0: SIMD3<Float>, u1: SIMD3<Float>, u2: SIMD3<Float>
) -> Float {
    if trianglesIntersect(v0: v0, v1: v1, v2: v2, u0: u0, u1: u1, u2: u2) {
        return 0.0
    }

    var minDist: Float = .greatestFiniteMagnitude

    // Vertices of V to triangle U
    let pV = [v0, v1, v2]
    for p in pV {
        let pt = closestPointOnTriangle(p: p, a: u0, b: u1, c: u2)
        minDist = Swift.min(minDist, simd_distance(p, pt))
    }

    // Vertices of U to triangle V
    let pU = [u0, u1, u2]
    for p in pU {
        let pt = closestPointOnTriangle(p: p, a: v0, b: v1, c: v2)
        minDist = Swift.min(minDist, simd_distance(p, pt))
    }

    // Edges of V to edges of U
    let edgesV = [(v0, v1), (v1, v2), (v2, v0)]
    let edgesU = [(u0, u1), (u1, u2), (u2, u0)]
    for (ea0, ea1) in edgesV {
        for (eb0, eb1) in edgesU {
            let d = distanceBetweenSegments(p0: ea0, p1: ea1, q0: eb0, q1: eb1)
            minDist = Swift.min(minDist, d)
        }
    }

    return minDist
}

// MARK: - Interference Query API

/// Evaluates whether two candidate meshes collide in 3D world space using hierarchical BVH-BVH traversal.
public func checkInterference(meshA: CandidateMesh, meshB: CandidateMesh) -> Bool {
    guard let indexA = meshA.spatialIndex, let indexB = meshB.spatialIndex else { return false }
    guard !meshA.positions.isEmpty && !meshB.positions.isEmpty else { return false }

    let matA = meshA.transform.matrix
    let matB = meshB.transform.matrix
    let worldA = indexA.bounds.transformed(by: matA)
    let worldB = indexB.bounds.transformed(by: matB)
    guard worldA.intersects(other: worldB) else { return false }

    var stack: [(Int32, Int32)] = [(0, 0)]
    stack.reserveCapacity(128)

    while let (nodeAIdx, nodeBIdx) = stack.popLast() {
        let nodeA = indexA.triangleBVH.nodes[Int(nodeAIdx)]
        let nodeB = indexB.triangleBVH.nodes[Int(nodeBIdx)]

        let bA = nodeA.bounds.transformed(by: matA)
        let bB = nodeB.bounds.transformed(by: matB)
        guard bA.intersects(other: bB) else { continue }

        if nodeA.isLeaf && nodeB.isLeaf {
            let startA = Int(nodeA.leftOrPrimitiveIndex)
            let countA = Int(nodeA.primitiveCount)
            let startB = Int(nodeB.leftOrPrimitiveIndex)
            let countB = Int(nodeB.primitiveCount)

            for i in startA..<(startA + countA) {
                let triA = indexA.triangleBVH.primitives[i]
                let a0 = meshA.transform.transformPoint(triA.v0)
                let a1 = meshA.transform.transformPoint(triA.v1)
                let a2 = meshA.transform.transformPoint(triA.v2)

                for j in startB..<(startB + countB) {
                    let triB = indexB.triangleBVH.primitives[j]
                    let b0 = meshB.transform.transformPoint(triB.v0)
                    let b1 = meshB.transform.transformPoint(triB.v1)
                    let b2 = meshB.transform.transformPoint(triB.v2)

                    if trianglesIntersect(v0: a0, v1: a1, v2: a2, u0: b0, u1: b1, u2: b2) {
                        return true
                    }
                }
            }
        } else if nodeA.isLeaf {
            stack.append((nodeAIdx, nodeB.leftOrPrimitiveIndex))
            stack.append((nodeAIdx, nodeB.rightChildIndex))
        } else if nodeB.isLeaf {
            stack.append((nodeA.leftOrPrimitiveIndex, nodeBIdx))
            stack.append((nodeA.rightChildIndex, nodeBIdx))
        } else {
            let extA = simd_length(nodeA.bounds.extents)
            let extB = simd_length(nodeB.bounds.extents)
            if extA >= extB {
                stack.append((nodeA.leftOrPrimitiveIndex, nodeBIdx))
                stack.append((nodeA.rightChildIndex, nodeBIdx))
            } else {
                stack.append((nodeAIdx, nodeB.leftOrPrimitiveIndex))
                stack.append((nodeAIdx, nodeB.rightChildIndex))
            }
        }
    }
    return false
}

/// Identifies all interfering face index pairs between two candidate meshes.
public func findInterference(meshA: CandidateMesh, meshB: CandidateMesh) -> [(Int, Int)] {
    guard let indexA = meshA.spatialIndex, let indexB = meshB.spatialIndex else { return [] }
    guard !meshA.positions.isEmpty && !meshB.positions.isEmpty else { return [] }

    let matA = meshA.transform.matrix
    let matB = meshB.transform.matrix
    let worldA = indexA.bounds.transformed(by: matA)
    let worldB = indexB.bounds.transformed(by: matB)
    guard worldA.intersects(other: worldB) else { return [] }

    var stack: [(Int32, Int32)] = [(0, 0)]
    stack.reserveCapacity(128)
    var collidingPairs = Set<[Int]>()

    while let (nodeAIdx, nodeBIdx) = stack.popLast() {
        let nodeA = indexA.triangleBVH.nodes[Int(nodeAIdx)]
        let nodeB = indexB.triangleBVH.nodes[Int(nodeBIdx)]

        let bA = nodeA.bounds.transformed(by: matA)
        let bB = nodeB.bounds.transformed(by: matB)
        guard bA.intersects(other: bB) else { continue }

        if nodeA.isLeaf && nodeB.isLeaf {
            let startA = Int(nodeA.leftOrPrimitiveIndex)
            let countA = Int(nodeA.primitiveCount)
            let startB = Int(nodeB.leftOrPrimitiveIndex)
            let countB = Int(nodeB.primitiveCount)

            for i in startA..<(startA + countA) {
                let triA = indexA.triangleBVH.primitives[i]
                let a0 = meshA.transform.transformPoint(triA.v0)
                let a1 = meshA.transform.transformPoint(triA.v1)
                let a2 = meshA.transform.transformPoint(triA.v2)

                for j in startB..<(startB + countB) {
                    let triB = indexB.triangleBVH.primitives[j]
                    let b0 = meshB.transform.transformPoint(triB.v0)
                    let b1 = meshB.transform.transformPoint(triB.v1)
                    let b2 = meshB.transform.transformPoint(triB.v2)

                    if trianglesIntersect(v0: a0, v1: a1, v2: a2, u0: b0, u1: b1, u2: b2) {
                        collidingPairs.insert([triA.faceId, triB.faceId])
                    }
                }
            }
        } else if nodeA.isLeaf {
            stack.append((nodeAIdx, nodeB.leftOrPrimitiveIndex))
            stack.append((nodeAIdx, nodeB.rightChildIndex))
        } else if nodeB.isLeaf {
            stack.append((nodeA.leftOrPrimitiveIndex, nodeBIdx))
            stack.append((nodeA.rightChildIndex, nodeBIdx))
        } else {
            let extA = simd_length(nodeA.bounds.extents)
            let extB = simd_length(nodeB.bounds.extents)
            if extA >= extB {
                stack.append((nodeA.leftOrPrimitiveIndex, nodeBIdx))
                stack.append((nodeA.rightChildIndex, nodeBIdx))
            } else {
                stack.append((nodeAIdx, nodeB.leftOrPrimitiveIndex))
                stack.append((nodeAIdx, nodeB.rightChildIndex))
            }
        }
    }
    return collidingPairs.map { ($0[0], $0[1]) }
}

// MARK: - Measurement Query API

public struct ClosestPointResult: Sendable, Equatable {
    public let point: SIMD3<Float>
    public let distance: Float
    public let normal: SIMD3<Float>?
    public let faceId: Int?

    public init(point: SIMD3<Float>, distance: Float, normal: SIMD3<Float>? = nil, faceId: Int? = nil) {
        self.point = point
        self.distance = distance
        self.normal = normal
        self.faceId = faceId
    }
}

/// Computes the closest point on a candidate mesh surface to a 3D world-space query point.
public func closestPointOnMesh(to worldPoint: SIMD3<Float>, in mesh: CandidateMesh) -> ClosestPointResult? {
    guard let spatialIndex = mesh.spatialIndex, !mesh.positions.isEmpty else { return nil }
    guard abs(simd_determinant(mesh.transform.matrix)) > 1e-8 else { return nil }

    let invMatrix = simd_inverse(mesh.transform.matrix)
    let p4 = invMatrix * SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)
    let localPoint = SIMD3<Float>(p4.x, p4.y, p4.z)

    guard let localResult = spatialIndex.triangleBVH.closestPoint(to: localPoint) else { return nil }

    let worldPointHit = mesh.transform.transformPoint(localResult.point)
    let worldDist = simd_distance(worldPoint, worldPointHit)
    let worldNormal: SIMD3<Float>?
    if let ln = localResult.normal {
        let wn = mesh.transform.normalMatrix * ln
        let len = simd_length(wn)
        worldNormal = len > 1e-6 ? (wn / len) : nil
    } else {
        worldNormal = nil
    }

    return ClosestPointResult(
        point: worldPointHit,
        distance: worldDist,
        normal: worldNormal,
        faceId: localResult.faceId
    )
}

/// Computes the exact minimum Euclidean distance between two candidate meshes.
public func distanceBetweenMeshes(_ meshA: CandidateMesh, _ meshB: CandidateMesh) -> Float {
    guard let indexA = meshA.spatialIndex, let indexB = meshB.spatialIndex else {
        return .greatestFiniteMagnitude
    }
    guard !meshA.positions.isEmpty && !meshB.positions.isEmpty else {
        return .greatestFiniteMagnitude
    }

    if checkInterference(meshA: meshA, meshB: meshB) {
        return 0.0
    }

    let matA = meshA.transform.matrix
    let matB = meshB.transform.matrix
    var minDist = Float.greatestFiniteMagnitude

    var stack: [(Int32, Int32)] = [(0, 0)]
    stack.reserveCapacity(128)

    while let (nodeAIdx, nodeBIdx) = stack.popLast() {
        let nodeA = indexA.triangleBVH.nodes[Int(nodeAIdx)]
        let nodeB = indexB.triangleBVH.nodes[Int(nodeBIdx)]

        let worldBoundsA = nodeA.bounds.transformed(by: matA)
        let worldBoundsB = nodeB.bounds.transformed(by: matB)

        let boxDist = worldBoundsA.distance(to: worldBoundsB)
        if boxDist >= minDist { continue }

        if nodeA.isLeaf && nodeB.isLeaf {
            let startA = Int(nodeA.leftOrPrimitiveIndex)
            let countA = Int(nodeA.primitiveCount)
            let startB = Int(nodeB.leftOrPrimitiveIndex)
            let countB = Int(nodeB.primitiveCount)

            for i in startA..<(startA + countA) {
                let triA = indexA.triangleBVH.primitives[i]
                let a0 = meshA.transform.transformPoint(triA.v0)
                let a1 = meshA.transform.transformPoint(triA.v1)
                let a2 = meshA.transform.transformPoint(triA.v2)

                for j in startB..<(startB + countB) {
                    let triB = indexB.triangleBVH.primitives[j]
                    let b0 = meshB.transform.transformPoint(triB.v0)
                    let b1 = meshB.transform.transformPoint(triB.v1)
                    let b2 = meshB.transform.transformPoint(triB.v2)

                    let d = distanceBetweenTriangles(v0: a0, v1: a1, v2: a2, u0: b0, u1: b1, u2: b2)
                    if d < minDist {
                        minDist = d
                        if minDist < 1e-5 { return 0.0 }
                    }
                }
            }
        } else if nodeA.isLeaf {
            stack.append((nodeAIdx, nodeB.leftOrPrimitiveIndex))
            stack.append((nodeAIdx, nodeB.rightChildIndex))
        } else if nodeB.isLeaf {
            stack.append((nodeA.leftOrPrimitiveIndex, nodeBIdx))
            stack.append((nodeA.rightChildIndex, nodeBIdx))
        } else {
            let extA = simd_length(nodeA.bounds.extents)
            let extB = simd_length(nodeB.bounds.extents)
            if extA >= extB {
                stack.append((nodeA.leftOrPrimitiveIndex, nodeBIdx))
                stack.append((nodeA.rightChildIndex, nodeBIdx))
            } else {
                stack.append((nodeAIdx, nodeB.leftOrPrimitiveIndex))
                stack.append((nodeAIdx, nodeB.rightChildIndex))
            }
        }
    }

    return minDist
}
