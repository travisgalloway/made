import Foundation
import CoreGraphics
import simd

/// The directional mode of a marquee selection in the viewport.
public enum MarqueeMode: String, Sendable, Equatable {
    case window   // Left-to-right: only bodies fully enclosed are selected
    case crossing // Right-to-left: bodies intersecting or enclosed are selected
}

/// The geometric shape used for marquee multi-selection.
public enum SelectionShape: String, CaseIterable, Identifiable, Sendable, Codable {
    case box
    case lasso

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .box: return "Box Selection"
        case .lasso: return "Lasso Selection"
        }
    }
}

/// The active state of a viewport marquee drag.
public struct MarqueeState: Sendable, Equatable {
    public let shape: SelectionShape
    public let mode: MarqueeMode
    public let startPoint: CGPoint
    public let currentPoint: CGPoint
    public let points: [CGPoint]
    public let isExtend: Bool

    public init(
        shape: SelectionShape,
        mode: MarqueeMode,
        startPoint: CGPoint,
        currentPoint: CGPoint,
        points: [CGPoint] = [],
        isExtend: Bool = false
    ) {
        self.shape = shape
        self.mode = mode
        self.startPoint = startPoint
        self.currentPoint = currentPoint
        self.points = points.isEmpty ? [startPoint, currentPoint] : points
        self.isExtend = isExtend
    }

    /// The bounding rectangle for box selection in screen coordinates.
    public var screenRect: CGRect {
        let minX = min(startPoint.x, currentPoint.x)
        let maxX = max(startPoint.x, currentPoint.x)
        let minY = min(startPoint.y, currentPoint.y)
        let maxY = max(startPoint.y, currentPoint.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Tests whether a point lies inside a 2D polygon using the ray-crossing algorithm.
public func polygonContains(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let pi = polygon[i]
        let pj = polygon[j]
        if ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
            inside.toggle()
        }
        j = i
    }
    return inside
}

/// Tests whether two 2D line segments (p1-p2 and p3-p4) intersect.
public func segmentsIntersect(
    p1: SIMD2<Float>,
    p2: SIMD2<Float>,
    p3: SIMD2<Float>,
    p4: SIMD2<Float>
) -> Bool {
    if max(p1.x, p2.x) < min(p3.x, p4.x) || min(p1.x, p2.x) > max(p3.x, p4.x) ||
       max(p1.y, p2.y) < min(p3.y, p4.y) || min(p1.y, p2.y) > max(p3.y, p4.y) {
        return false
    }

    func ccw(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        (c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x)
    }

    let d1 = ccw(p1, p2, p3)
    let d2 = ccw(p1, p2, p4)
    let d3 = ccw(p3, p4, p1)
    let d4 = ccw(p3, p4, p2)

    if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
       ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
        return true
    }

    func onSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        p.x >= min(a.x, b.x) - 1e-4 && p.x <= max(a.x, b.x) + 1e-4 &&
        p.y >= min(a.y, b.y) - 1e-4 && p.y <= max(a.y, b.y) + 1e-4
    }

    if abs(d1) < 1e-5 && onSegment(p3, p1, p2) { return true }
    if abs(d2) < 1e-5 && onSegment(p4, p1, p2) { return true }
    if abs(d3) < 1e-5 && onSegment(p1, p3, p4) { return true }
    if abs(d4) < 1e-5 && onSegment(p2, p3, p4) { return true }

    return false
}

/// Tests whether a 2D point lies inside a triangle with vertices a, b, c.
public func pointInTriangle(p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>, c: SIMD2<Float>) -> Bool {
    func sign(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>) -> Float {
        (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
    }
    let d1 = sign(p, a, b)
    let d2 = sign(p, b, c)
    let d3 = sign(p, c, a)
    let hasNeg = (d1 < -1e-5) || (d2 < -1e-5) || (d3 < -1e-5)
    let hasPos = (d1 > 1e-5) || (d2 > 1e-5) || (d3 > 1e-5)
    return !(hasNeg && hasPos)
}

/// Evaluates marquee selection (box or lasso) against candidate meshes in the viewport.
/// - Parameters:
///   - marquee: The active marquee state with shape, mode, and screen-space coordinates.
///   - candidateMeshes: Candidate meshes representing visible solid bodies in the scene.
///   - viewportSize: Dimensions of the viewport in screen points.
///   - viewProjectionMatrix: Combined view-projection matrix for camera transformation.
///   - filter: Selection filter (bodies must be allowed for marquee selection).
/// - Returns: A set of SolidIds matching the marquee criteria.
public func evaluateMarqueeSelection(
    marquee: MarqueeState,
    candidateMeshes: [CandidateMesh],
    viewportSize: CGSize,
    viewProjectionMatrix: simd_float4x4,
    filter: SelectionFilter = .all
) -> Set<SolidId> {
    guard filter.allowsBodies else { return [] }
    guard viewportSize.width > 0 && viewportSize.height > 0 else { return [] }

    let boundaryPoints: [SIMD2<Float>]
    let boundarySegments: [(SIMD2<Float>, SIMD2<Float>)]
    let testCenterPoint: SIMD2<Float>

    switch marquee.shape {
    case .box:
        let r = marquee.screenRect
        guard r.width > 0 || r.height > 0 else { return [] }
        let c0 = SIMD2<Float>(Float(r.minX), Float(r.minY))
        let c1 = SIMD2<Float>(Float(r.maxX), Float(r.minY))
        let c2 = SIMD2<Float>(Float(r.maxX), Float(r.maxY))
        let c3 = SIMD2<Float>(Float(r.minX), Float(r.maxY))
        boundaryPoints = [c0, c1, c2, c3]
        boundarySegments = [(c0, c1), (c1, c2), (c2, c3), (c3, c0)]
        testCenterPoint = SIMD2<Float>(Float(r.midX), Float(r.midY))

    case .lasso:
        guard marquee.points.count >= 3 else { return [] }
        boundaryPoints = marquee.points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        var segs: [(SIMD2<Float>, SIMD2<Float>)] = []
        segs.reserveCapacity(boundaryPoints.count)
        for i in 0..<boundaryPoints.count {
            let next = (i + 1) % boundaryPoints.count
            segs.append((boundaryPoints[i], boundaryPoints[next]))
        }
        boundarySegments = segs
        let sum = boundaryPoints.reduce(SIMD2<Float>.zero, +)
        testCenterPoint = sum / Float(boundaryPoints.count)
    }

    func isInsideMarquee(_ pt: SIMD2<Float>) -> Bool {
        switch marquee.shape {
        case .box:
            let r = marquee.screenRect
            return Float(r.minX) <= pt.x && pt.x <= Float(r.maxX) &&
                   Float(r.minY) <= pt.y && pt.y <= Float(r.maxY)
        case .lasso:
            return polygonContains(point: pt, polygon: boundaryPoints)
        }
    }

    var selectedSolidIds = Set<SolidId>()

    for mesh in candidateMeshes {
        guard !mesh.positions.isEmpty else { continue }

        let worldMatrix = mesh.transform.matrix
        var projected: [SIMD2<Float>?] = []
        projected.reserveCapacity(mesh.positions.count)
        var validCount = 0

        for localPos in mesh.positions {
            let worldPos4 = worldMatrix * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1.0)
            let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
            if let screen = projectToScreen(point: worldPos, viewProjectionMatrix: viewProjectionMatrix, viewportSize: viewportSize) {
                projected.append(screen)
                validCount += 1
            } else {
                projected.append(nil)
            }
        }

        // Reject if no projected vertices in front of camera
        guard validCount > 0 else { continue }

        switch marquee.mode {
        case .window:
            // All vertices must project in front of camera and lie strictly inside marquee
            if validCount == mesh.positions.count {
                var allInside = true
                for p in projected {
                    guard let pt = p, isInsideMarquee(pt) else {
                        allInside = false
                        break
                    }
                }
                if allInside {
                    selectedSolidIds.insert(mesh.id)
                }
            }

        case .crossing:
            // 1. Any projected vertex inside marquee
            var matched = false
            for p in projected {
                if let pt = p, isInsideMarquee(pt) {
                    matched = true
                    break
                }
            }
            if matched {
                selectedSolidIds.insert(mesh.id)
                continue
            }

            // 2. Any projected edge intersects marquee boundary
            let edgesToTest: [(Int, Int)]
            if !mesh.edges.isEmpty {
                edgesToTest = mesh.edges.map { (Int($0.v0), Int($0.v1)) }
            } else if !mesh.indices.isEmpty {
                var triEdges: [(Int, Int)] = []
                triEdges.reserveCapacity(mesh.indices.count)
                for i in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                    let i0 = Int(mesh.indices[i])
                    let i1 = Int(mesh.indices[i + 1])
                    let i2 = Int(mesh.indices[i + 2])
                    triEdges.append((i0, i1))
                    triEdges.append((i1, i2))
                    triEdges.append((i2, i0))
                }
                edgesToTest = triEdges
            } else {
                edgesToTest = []
            }

            for (i0, i1) in edgesToTest {
                guard i0 < projected.count, i1 < projected.count,
                      let pA = projected[i0], let pB = projected[i1] else { continue }
                for (bA, bB) in boundarySegments {
                    if segmentsIntersect(p1: pA, p2: pB, p3: bA, p4: bB) {
                        matched = true
                        break
                    }
                }
                if matched { break }
            }

            if matched {
                selectedSolidIds.insert(mesh.id)
                continue
            }

            // 3. Screen boundary lies entirely inside a projected face
            if !mesh.indices.isEmpty {
                for i in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                    let i0 = Int(mesh.indices[i])
                    let i1 = Int(mesh.indices[i + 1])
                    let i2 = Int(mesh.indices[i + 2])
                    guard i0 < projected.count, i1 < projected.count, i2 < projected.count,
                          let t0 = projected[i0], let t1 = projected[i1], let t2 = projected[i2] else { continue }
                    if pointInTriangle(p: testCenterPoint, a: t0, b: t1, c: t2) {
                        matched = true
                        break
                    }
                }
            }

            if matched {
                selectedSolidIds.insert(mesh.id)
            }
        }
    }

    return selectedSolidIds
}

/// Evaluates marquee selection using separate view and projection matrices.
public func evaluateMarqueeSelection(
    marquee: MarqueeState,
    candidateMeshes: [CandidateMesh],
    viewportSize: CGSize,
    viewMatrix: simd_float4x4,
    projectionMatrix: simd_float4x4,
    filter: SelectionFilter = .all
) -> Set<SolidId> {
    evaluateMarqueeSelection(
        marquee: marquee,
        candidateMeshes: candidateMeshes,
        viewportSize: viewportSize,
        viewProjectionMatrix: projectionMatrix * viewMatrix,
        filter: filter
    )
}
