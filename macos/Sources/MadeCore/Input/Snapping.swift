import Foundation
import simd

public enum SnapKind: String, Sendable, Equatable, Comparable {
    case vertex
    case edge
    case grid
    
    // Priority order: vertex > edge > grid
    private var priority: Int {
        switch self {
        case .vertex: return 0
        case .edge: return 1
        case .grid: return 2
        }
    }
    
    public static func < (lhs: SnapKind, rhs: SnapKind) -> Bool {
        return lhs.priority < rhs.priority
    }
}

public struct SnapResult: Sendable, Equatable {
    public let kind: SnapKind
    public let point: SIMD3<Float>
    
    public init(kind: SnapKind, point: SIMD3<Float>) {
        self.kind = kind
        self.point = point
    }
}

public struct SnapCandidate: Sendable, Equatable {
    public let kind: SnapKind
    public let point: SIMD3<Float>
    public let screenDistancePx: Float
    
    public init(kind: SnapKind, point: SIMD3<Float>, screenDistancePx: Float) {
        self.kind = kind
        self.point = point
        self.screenDistancePx = screenDistancePx
    }
}

public let defaultGridSpacing: Float = 10.0
public let defaultSnapTolerancePx: Float = 20.0

/// Grid snap: quantizes point's X and Y to the nearest multiple of spacing, leaving Z untouched.
/// Operates on the XY ground plane (Z = 0) per the Z-up convention.
public func snapToGrid(_ point: SIMD3<Float>, spacing: Float = defaultGridSpacing) -> SIMD3<Float> {
    guard spacing > 0 else { return point }
    let sx = (point.x / spacing).rounded() * spacing
    let sy = (point.y / spacing).rounded() * spacing
    let cleanX = (sx == 0) ? 0 : sx
    let cleanY = (sy == 0) ? 0 : sy
    return SIMD3<Float>(cleanX, cleanY, point.z)
}

/// Distance between two 2D screen coordinates.
public func screenPixelDistance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    return simd_distance(a, b)
}

/// Evaluates candidates according to Invariant 9:
/// Priority is strictly vertex > edge > grid. Within the highest-priority kind present,
/// the candidate with the minimum screenDistancePx inside tolerancePx is chosen.
public func resolveSnap(candidates: [SnapCandidate], tolerancePx: Float = defaultSnapTolerancePx) -> SnapResult? {
    let kinds: [SnapKind] = [.vertex, .edge, .grid]
    
    for kind in kinds {
        var best: SnapCandidate? = nil
        for candidate in candidates {
            guard candidate.kind == kind else { continue }
            guard candidate.screenDistancePx <= tolerancePx else { continue }
            
            if let currentBest = best {
                if candidate.screenDistancePx < currentBest.screenDistancePx {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        
        if let winner = best {
            return SnapResult(kind: winner.kind, point: winner.point)
        }
    }
    
    return nil
}

/// Represents an undirected edge between two vertex indices in a mesh.
public struct MeshEdge: Hashable, Sendable {
    public let v0: UInt32
    public let v1: UInt32
    
    public init(_ a: UInt32, _ b: UInt32) {
        if a < b {
            self.v0 = a
            self.v1 = b
        } else {
            self.v0 = b
            self.v1 = a
        }
    }
}

/// A CPU-side representation of a solid mesh for candidate snap generation.
public struct CandidateMesh: Sendable {
    public let id: SolidId
    public let positions: [SIMD3<Float>]
    public let edges: [MeshEdge]
    public var transform: Transform
    public let indices: [UInt32]
    public let faceRanges: [FaceTriangleRange]
    public let edgePolylines: [EdgePolyline]
    public let vertexPoints: [VertexPoint]
    
    public init(
        id: SolidId,
        positions: [SIMD3<Float>],
        edges: [MeshEdge],
        transform: Transform = .identity,
        indices: [UInt32] = [],
        faceRanges: [FaceTriangleRange] = [],
        edgePolylines: [EdgePolyline] = [],
        vertexPoints: [VertexPoint] = []
    ) {
        self.id = id
        self.positions = positions
        self.edges = edges
        self.transform = transform
        self.indices = indices
        self.faceRanges = faceRanges
        self.edgePolylines = edgePolylines
        self.vertexPoints = vertexPoints
    }
    
    public init(
        id: SolidId,
        rawPositions: [Float],
        indices: [UInt32],
        transform: Transform = .identity,
        faceRanges: [FaceTriangleRange] = [],
        edgePolylines: [EdgePolyline] = [],
        vertexPoints: [VertexPoint] = []
    ) {
        self.id = id
        var pts: [SIMD3<Float>] = []
        pts.reserveCapacity(rawPositions.count / 3)
        for i in stride(from: 0, to: rawPositions.count, by: 3) {
            if i + 2 < rawPositions.count {
                pts.append(SIMD3<Float>(rawPositions[i], rawPositions[i+1], rawPositions[i+2]))
            }
        }
        self.positions = pts
        
        var edgeSet = Set<MeshEdge>()
        for i in stride(from: 0, to: indices.count, by: 3) {
            if i + 2 < indices.count {
                edgeSet.insert(MeshEdge(indices[i], indices[i+1]))
                edgeSet.insert(MeshEdge(indices[i+1], indices[i+2]))
                edgeSet.insert(MeshEdge(indices[i+2], indices[i]))
            }
        }
        self.edges = Array(edgeSet)
        self.transform = transform
        self.indices = indices
        self.faceRanges = faceRanges
        self.edgePolylines = edgePolylines
        self.vertexPoints = vertexPoints
    }
    
    public init(id: SolidId, payload: MeshPayload, transform: Transform = .identity) {
        self.init(
            id: id,
            rawPositions: Array(payload.positions),
            indices: Array(payload.indices),
            transform: transform,
            faceRanges: payload.faceRanges,
            edgePolylines: payload.edgePolylines,
            vertexPoints: payload.vertexPoints
        )
    }
    
    /// Computes the world-space normal for the specified face ID, applying the mesh transform.
    public func faceNormal(forFaceId faceId: Int) -> SIMD3<Float>? {
        let range: Range<Int>?
        if let fr = faceRanges.first(where: { $0.faceId == faceId }) {
            range = fr.triangleRange
        } else if faceRanges.isEmpty && indices.count >= 3 {
            range = 0..<(indices.count / 3)
        } else {
            range = nil
        }
        guard let triRange = range, !triRange.isEmpty else { return nil }
        
        for t in triRange {
            let i0 = Int(t * 3)
            guard i0 + 2 < indices.count else { continue }
            let idx0 = Int(indices[i0])
            let idx1 = Int(indices[i0 + 1])
            let idx2 = Int(indices[i0 + 2])
            guard idx0 < positions.count && idx1 < positions.count && idx2 < positions.count else { continue }
            let p0 = positions[idx0]
            let p1 = positions[idx1]
            let p2 = positions[idx2]
            let localNormal = simd_cross(p1 - p0, p2 - p0)
            let len = simd_length(localNormal)
            guard len > 1e-6 else { continue }
            let normalizedLocal = localNormal / len
            let worldNormal = transform.normalMatrix * normalizedLocal
            let worldLen = simd_length(worldNormal)
            guard worldLen > 1e-6 else { continue }
            return worldNormal / worldLen
        }
        return nil
    }

    /// Computes the world-space centroid for the specified face ID, applying the mesh transform.
    public func faceCentroid(forFaceId faceId: Int) -> SIMD3<Float>? {
        let range: Range<Int>?
        if let fr = faceRanges.first(where: { $0.faceId == faceId }) {
            range = fr.triangleRange
        } else if faceRanges.isEmpty && indices.count >= 3 {
            range = 0..<(indices.count / 3)
        } else {
            range = nil
        }
        guard let triRange = range, !triRange.isEmpty else { return nil }
        
        var sum = SIMD3<Float>.zero
        var count: Int = 0
        for t in triRange {
            let i0 = Int(t * 3)
            guard i0 + 2 < indices.count else { continue }
            let idx0 = Int(indices[i0])
            let idx1 = Int(indices[i0 + 1])
            let idx2 = Int(indices[i0 + 2])
            guard idx0 < positions.count && idx1 < positions.count && idx2 < positions.count else { continue }
            sum += positions[idx0] + positions[idx1] + positions[idx2]
            count += 3
        }
        guard count > 0 else { return nil }
        let localCentroid = sum / Float(count)
        return transform.transformPoint(localCentroid)
    }
}

public struct ScreenProjection: Sendable {
    public let screen: SIMD2<Float>
    public let w: Float
    
    public init(screen: SIMD2<Float>, w: Float) {
        self.screen = screen
        self.w = w
    }
}

/// Projects a 3D world-space point to 2D screen coordinates along with clip.w.
public func projectToScreenWithW(
    point: SIMD3<Float>,
    viewProjectionMatrix: simd_float4x4,
    viewportSize: CGSize
) -> ScreenProjection? {
    let clip = viewProjectionMatrix * SIMD4<Float>(point.x, point.y, point.z, 1.0)
    guard clip.w > 1e-6 else { return nil }
    
    let ndcX = clip.x / clip.w
    let ndcY = clip.y / clip.w
    let ndcZ = clip.z / clip.w
    
    guard ndcZ >= 0.0 && ndcZ <= 1.0 else { return nil }
    
    let width = Float(viewportSize.width)
    let height = Float(viewportSize.height)
    guard width > 0 && height > 0 else { return nil }
    
    let screenX = (ndcX + 1.0) * 0.5 * width
    let screenY = (ndcY + 1.0) * 0.5 * height
    return ScreenProjection(screen: SIMD2<Float>(screenX, screenY), w: clip.w)
}

/// Projects a 3D world-space point to 2D screen coordinates.
/// Returns nil if the point is behind the camera near plane or outside [0, 1] depth.
public func projectToScreen(
    point: SIMD3<Float>,
    viewProjectionMatrix: simd_float4x4,
    viewportSize: CGSize
) -> SIMD2<Float>? {
    return projectToScreenWithW(point: point, viewProjectionMatrix: viewProjectionMatrix, viewportSize: viewportSize)?.screen
}

/// A 3D ray in world space.
public struct Ray3D: Sendable, Equatable {
    public let origin: SIMD3<Float>
    public let direction: SIMD3<Float>
    
    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = direction
    }
    
    /// Intersects ray with the Z = 0 ground plane.
    /// Returns nil if ray is parallel to the ground or intersection is behind the ray origin.
    public func intersectPlaneZZero() -> SIMD3<Float>? {
        guard abs(direction.z) > 1e-6 else { return nil }
        let t = -origin.z / direction.z
        guard t > 0 else { return nil }
        return origin + direction * t
    }
}

/// Unprojects a 2D screen coordinate to a 3D world-space ray.
public func screenPointToRay(
    screenPoint: SIMD2<Float>,
    viewportSize: CGSize,
    viewMatrix: simd_float4x4,
    projectionMatrix: simd_float4x4
) -> Ray3D? {
    let width = Float(viewportSize.width)
    let height = Float(viewportSize.height)
    guard width > 0 && height > 0 else { return nil }
    
    let ndcX = (screenPoint.x / width) * 2.0 - 1.0
    let ndcY = (screenPoint.y / height) * 2.0 - 1.0
    
    let invVP = simd_inverse(projectionMatrix * viewMatrix)
    
    let nearClip = SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
    let farClip = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)
    
    let nearWorld4 = invVP * nearClip
    let farWorld4 = invVP * farClip
    
    guard abs(nearWorld4.w) > 1e-6, abs(farWorld4.w) > 1e-6 else { return nil }
    
    let nearWorld = SIMD3<Float>(nearWorld4.x, nearWorld4.y, nearWorld4.z) / nearWorld4.w
    let farWorld = SIMD3<Float>(farWorld4.x, farWorld4.y, farWorld4.z) / farWorld4.w
    
    let dir = farWorld - nearWorld
    let len = simd_length(dir)
    guard len > 1e-6 else { return nil }
    
    return Ray3D(origin: nearWorld, direction: dir / len)
}

/// Finds the closest 3D point on segment [p1, p2] based on proximity to screenPointer in screen space.
/// Optional w1 and w2 provide perspective-correct interpolation.
public func closestPointOnSegment(
    p1: SIMD3<Float>,
    p2: SIMD3<Float>,
    s1: SIMD2<Float>,
    s2: SIMD2<Float>,
    screenPointer: SIMD2<Float>,
    w1: Float? = nil,
    w2: Float? = nil
) -> (worldPoint: SIMD3<Float>, screenDistancePx: Float) {
    let sDiff = s2 - s1
    let lenSq = simd_length_squared(sDiff)
    let t: Float
    if lenSq < 1e-6 {
        t = 0.0
    } else {
        let dot = simd_dot(screenPointer - s1, sDiff)
        t = min(max(dot / lenSq, 0.0), 1.0)
    }
    
    let u: Float
    if let w1 = w1, let w2 = w2, w1 > 1e-6, w2 > 1e-6 {
        let denom = (1.0 - t) * w2 + t * w1
        if denom > 1e-6 {
            u = (t * w1) / denom
        } else {
            u = t
        }
    } else {
        u = t
    }
    
    let worldPoint = p1 + (p2 - p1) * u
    let screenPoint = s1 + sDiff * t
    let dist = simd_distance(screenPointer, screenPoint)
    return (worldPoint, dist)
}

/// Generates vertex, edge, and grid snap candidates.
public struct SnapCandidateGenerator: Sendable {
    public static func generateCandidates(
        meshes: [CandidateMesh],
        pointer: SIMD2<Float>,
        viewportSize: CGSize,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        gridSpacing: Float = defaultGridSpacing,
        tolerancePx: Float = defaultSnapTolerancePx
    ) -> [SnapCandidate] {
        var candidates: [SnapCandidate] = []
        let vp = projectionMatrix * viewMatrix
        
        // 1. Vertex candidates from meshes
        for mesh in meshes {
            let worldPositions = mesh.positions.map { mesh.transform.transformPoint($0) }
            
            for worldPos in worldPositions {
                guard let screenPos = projectToScreen(point: worldPos, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                    continue
                }
                let dist = simd_distance(pointer, screenPos)
                if dist <= tolerancePx {
                    candidates.append(SnapCandidate(kind: .vertex, point: worldPos, screenDistancePx: dist))
                }
            }
            
            // 2. Edge candidates from meshes
            for edge in mesh.edges {
                guard Int(edge.v0) < worldPositions.count && Int(edge.v1) < worldPositions.count else { continue }
                let p1 = worldPositions[Int(edge.v0)]
                let p2 = worldPositions[Int(edge.v1)]
                
                guard let proj1 = projectToScreenWithW(point: p1, viewProjectionMatrix: vp, viewportSize: viewportSize),
                      let proj2 = projectToScreenWithW(point: p2, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                    continue
                }
                
                let (closestWorld, dist) = closestPointOnSegment(
                    p1: p1, p2: p2,
                    s1: proj1.screen, s2: proj2.screen,
                    screenPointer: pointer,
                    w1: proj1.w, w2: proj2.w
                )
                if dist <= tolerancePx {
                    candidates.append(SnapCandidate(kind: .edge, point: closestWorld, screenDistancePx: dist))
                }
            }
        }
        
        // 3. Grid candidates on Z = 0 plane
        if let ray = screenPointToRay(screenPoint: pointer, viewportSize: viewportSize, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix) {
            if let groundPoint = ray.intersectPlaneZZero() {
                let snappedGrid = snapToGrid(groundPoint, spacing: gridSpacing)
                if let screenGrid = projectToScreen(point: snappedGrid, viewProjectionMatrix: vp, viewportSize: viewportSize) {
                    let dist = simd_distance(pointer, screenGrid)
                    if dist <= tolerancePx {
                        candidates.append(SnapCandidate(kind: .grid, point: snappedGrid, screenDistancePx: dist))
                    }
                }
            }
        }
        
        return candidates
    }
}

/// Resolves the winning snap candidate at pointer coordinates.
public func resolveSnapAtPointer(
    meshes: [CandidateMesh],
    pointer: SIMD2<Float>,
    viewportSize: CGSize,
    viewMatrix: simd_float4x4,
    projectionMatrix: simd_float4x4,
    gridSpacing: Float = defaultGridSpacing,
    tolerancePx: Float = defaultSnapTolerancePx
) -> SnapResult? {
    let candidates = SnapCandidateGenerator.generateCandidates(
        meshes: meshes,
        pointer: pointer,
        viewportSize: viewportSize,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
        gridSpacing: gridSpacing,
        tolerancePx: tolerancePx
    )
    return resolveSnap(candidates: candidates, tolerancePx: tolerancePx)
}
