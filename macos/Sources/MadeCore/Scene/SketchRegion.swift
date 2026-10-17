import Foundation
import simd

/// A detected 2D planar region bounded by an outer loop and zero or more inner loops (holes).
public struct SketchRegion: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var outerLoop: [SIMD2<Float>]
    public var innerLoops: [[SIMD2<Float>]]
    public var area: Float
    public var centroid: SIMD2<Float>

    public init(
        id: UUID = UUID(),
        outerLoop: [SIMD2<Float>],
        innerLoops: [[SIMD2<Float>]] = [],
        area: Float,
        centroid: SIMD2<Float>
    ) {
        self.id = id
        self.outerLoop = outerLoop
        self.innerLoops = innerLoops
        self.area = area
        self.centroid = centroid
    }

    /// Converts this region into a `SketchProfile` suitable for extrusion.
    public func toProfile(plane: SketchPlane = .xy) -> SketchProfile {
        SketchProfile(plane: plane, points: outerLoop, holes: innerLoops)
    }

    /// Hit-tests whether a 2D point lies within this region (inside outer boundary and strictly outside all inner holes).
    public func contains(point: SIMD2<Float>) -> Bool {
        guard Self.pointInPolygon(point: point, polygon: outerLoop) else {
            return false
        }
        for hole in innerLoops {
            if Self.pointInPolygon(point: point, polygon: hole) {
                return false
            }
        }
        return true
    }

    /// Standard ray-casting point-in-polygon test, including points on or very close to the polygon boundary.
    public static func pointInPolygon(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]

            // Boundary edge distance check
            if pointToSegmentDistance(point, a: pi, b: pj) < 1e-4 {
                return true
            }

            if ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static func pointToSegmentDistance(_ p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> Float {
        let ab = b - a
        let lenSq = simd_length_squared(ab)
        if lenSq < 1e-8 { return simd_distance(p, a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / lenSq))
        let proj = a + t * ab
        return simd_distance(p, proj)
    }
}

// MARK: - Planar Arrangement Region Detection Engine

public enum SketchRegionDetector {
    public static let snappingTolerance: Double = 1e-3
    public static let minTolerance: Double = 1e-5

    /// Canonical vertex registry snapping coincident endpoints and intersections within `snappingTolerance`.
    final class VertexRegistry {
        var vertices: [SIMD2<Double>] = []
        let tolerance: Double

        init(tolerance: Double = SketchRegionDetector.snappingTolerance) {
            self.tolerance = tolerance
        }

        func getOrCreateVertex(_ pt: SIMD2<Double>) -> Int {
            for (i, v) in vertices.enumerated() {
                if hypot(v.x - pt.x, v.y - pt.y) <= tolerance {
                    return i
                }
            }
            let idx = vertices.count
            vertices.append(pt)
            return idx
        }
    }

    /// Atomic curve segment connecting two canonical vertices.
    struct AtomicCurve {
        enum Kind {
            case line
            case arc(center: SIMD2<Double>, radius: Double, clockwise: Bool)
        }
        let fromVertex: Int
        let toVertex: Int
        let kind: Kind

        var fromPoint: SIMD2<Double> { _registry.vertices[fromVertex] }
        var toPoint: SIMD2<Double> { _registry.vertices[toVertex] }
        private unowned let _registry: VertexRegistry

        init(fromVertex: Int, toVertex: Int, kind: Kind, registry: VertexRegistry) {
            self.fromVertex = fromVertex
            self.toVertex = toVertex
            self.kind = kind
            self._registry = registry
        }
    }

    /// Directed half-edge for face cycle traversal.
    struct DirectedHalfEdge {
        let id: Int
        let twinId: Int
        let fromVertex: Int
        let toVertex: Int
        let departureTangent: SIMD2<Double>
        let departureAngle: Double
        let curve: AtomicCurve
        let isReversed: Bool
    }

    /// Intermediate closed loop representation.
    struct ClosedLoop {
        let points: [SIMD2<Float>]
        let area: Float
        let centroid: SIMD2<Float>
        let bbox: (minX: Float, minY: Float, maxX: Float, maxY: Float)
    }

    /// Detects all closed planar regions and holes from sketch entities.
    public static func detectRegions(from entities: [SketchEntity]) throws -> [SketchRegion] {
        guard !entities.isEmpty else { return [] }

        for entity in entities {
            try SketchProfileBuilder.validateEntity(entity)
        }

        let registry = VertexRegistry(tolerance: snappingTolerance)

        // 1. Collect all intersections among entities
        var lineIntersections: [UUID: [SIMD2<Double>]] = [:]
        var arcIntersections: [UUID: [SIMD2<Double>]] = [:]
        var circleIntersections: [UUID: [SIMD2<Double>]] = [:]

        for e in entities {
            switch e.kind {
            case "line": lineIntersections[e.id] = []
            case "arc": arcIntersections[e.id] = []
            case "circle": circleIntersections[e.id] = []
            default: break
            }
        }

        let n = entities.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                let e1 = entities[i]
                let e2 = entities[j]
                let pts = findIntersections(e1, e2)
                for p in pts {
                    if lineIntersections[e1.id] != nil { lineIntersections[e1.id]?.append(p) }
                    if arcIntersections[e1.id] != nil { arcIntersections[e1.id]?.append(p) }
                    if circleIntersections[e1.id] != nil { circleIntersections[e1.id]?.append(p) }

                    if lineIntersections[e2.id] != nil { lineIntersections[e2.id]?.append(p) }
                    if arcIntersections[e2.id] != nil { arcIntersections[e2.id]?.append(p) }
                    if circleIntersections[e2.id] != nil { circleIntersections[e2.id]?.append(p) }
                }
            }
        }

        // 2. Subdivide entities into atomic curves
        var atomicCurves: [AtomicCurve] = []
        var standaloneCircles: [(center: SIMD2<Double>, radius: Double)] = []

        for entity in entities {
            switch entity.kind {
            case "line":
                guard let sp = entity.startPoint, let ep = entity.endPoint else { continue }
                let startV = registry.getOrCreateVertex(sp)
                let endV = registry.getOrCreateVertex(ep)
                let lineDir = ep - sp
                let lenSq = simd_dot(lineDir, lineDir)

                var subPoints: [(t: Double, v: Int)] = [
                    (0.0, startV),
                    (1.0, endV)
                ]

                if let pts = lineIntersections[entity.id] {
                    for p in pts {
                        let t = lenSq > 1e-12 ? simd_dot(p - sp, lineDir) / lenSq : 0.0
                        if t > 1e-4 && t < (1.0 - 1e-4) {
                            let v = registry.getOrCreateVertex(p)
                            subPoints.append((t, v))
                        }
                    }
                }

                subPoints.sort { $0.t < $1.t }

                // Deduplicate adjacent identical vertices
                var cleanSubPoints: [(t: Double, v: Int)] = []
                for spItem in subPoints {
                    if let last = cleanSubPoints.last {
                        if spItem.v != last.v && abs(spItem.t - last.t) > 1e-4 {
                            cleanSubPoints.append(spItem)
                        }
                    } else {
                        cleanSubPoints.append(spItem)
                    }
                }

                for k in 0..<(cleanSubPoints.count - 1) {
                    let vA = cleanSubPoints[k].v
                    let vB = cleanSubPoints[k + 1].v
                    if vA != vB {
                        atomicCurves.append(AtomicCurve(fromVertex: vA, toVertex: vB, kind: .line, registry: registry))
                    }
                }

            case "arc":
                guard let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint else { continue }
                let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
                let cw = entity.isClockwise
                let startV = registry.getOrCreateVertex(sp)
                let endV = registry.getOrCreateVertex(ep)

                let sAngle = atan2(sp.y - cp.y, sp.x - cp.x)

                var subPoints: [(angleDelta: Double, v: Int)] = [
                    (0.0, startV),
                    (arcSweepAngle(start: sp, end: ep, center: cp, clockwise: cw), endV)
                ]

                if let pts = arcIntersections[entity.id] {
                    for p in pts {
                        let delta = arcAngleOffset(point: p, startAngle: sAngle, center: cp, clockwise: cw)
                        let maxSweep = subPoints[1].angleDelta
                        if delta > 1e-4 && delta < (maxSweep - 1e-4) {
                            let v = registry.getOrCreateVertex(p)
                            subPoints.append((delta, v))
                        }
                    }
                }

                subPoints.sort { $0.angleDelta < $1.angleDelta }

                var cleanSubPoints: [(angleDelta: Double, v: Int)] = []
                for spItem in subPoints {
                    if let last = cleanSubPoints.last {
                        if spItem.v != last.v && abs(spItem.angleDelta - last.angleDelta) > 1e-4 {
                            cleanSubPoints.append(spItem)
                        }
                    } else {
                        cleanSubPoints.append(spItem)
                    }
                }

                for k in 0..<(cleanSubPoints.count - 1) {
                    let vA = cleanSubPoints[k].v
                    let vB = cleanSubPoints[k + 1].v
                    if vA != vB {
                        atomicCurves.append(AtomicCurve(fromVertex: vA, toVertex: vB, kind: .arc(center: cp, radius: r, clockwise: cw), registry: registry))
                    }
                }

            case "circle":
                guard let cp = entity.centerPoint, let r = entity.radius, r > minTolerance else { continue }
                let pts = circleIntersections[entity.id] ?? []

                // Deduplicate points on circle
                var uniquePts: [SIMD2<Double>] = []
                for p in pts {
                    if !uniquePts.contains(where: { hypot($0.x - p.x, $0.y - p.y) <= snappingTolerance }) {
                        uniquePts.append(p)
                    }
                }

                if uniquePts.count < 2 {
                    // Isolated standalone or tangent circle loop (single contact point cannot divide disk interior)
                    standaloneCircles.append((center: cp, radius: r))
                } else {
                    // Sort points counter-clockwise by polar angle
                    uniquePts.sort {
                        normalizeAngle(atan2($0.y - cp.y, $0.x - cp.x)) < normalizeAngle(atan2($1.y - cp.y, $1.x - cp.x))
                    }

                    let vIndices = uniquePts.map { registry.getOrCreateVertex($0) }
                    let count = vIndices.count
                    for k in 0..<count {
                        let vA = vIndices[k]
                        let vB = vIndices[(k + 1) % count]
                        if vA != vB {
                            atomicCurves.append(AtomicCurve(fromVertex: vA, toVertex: vB, kind: .arc(center: cp, radius: r, clockwise: false), registry: registry))
                        }
                    }
                }

            default:
                break
            }
        }

        // 3. Build directed half-edges
        var directedHalfEdges: [DirectedHalfEdge] = []
        var outgoingMap: [Int: [DirectedHalfEdge]] = [:]

        for (curveIdx, curve) in atomicCurves.enumerated() {
            let fwdId = curveIdx * 2
            let revId = curveIdx * 2 + 1

            let (tanFwdStart, tanFwdEnd) = curveTangents(curve: curve, registry: registry)
            let tanRevStart = -tanFwdEnd

            let angleFwd = atan2(tanFwdStart.y, tanFwdStart.x)
            let angleRev = atan2(tanRevStart.y, tanRevStart.x)

            let fwdEdge = DirectedHalfEdge(
                id: fwdId,
                twinId: revId,
                fromVertex: curve.fromVertex,
                toVertex: curve.toVertex,
                departureTangent: tanFwdStart,
                departureAngle: angleFwd,
                curve: curve,
                isReversed: false
            )

            let revEdge = DirectedHalfEdge(
                id: revId,
                twinId: fwdId,
                fromVertex: curve.toVertex,
                toVertex: curve.fromVertex,
                departureTangent: tanRevStart,
                departureAngle: angleRev,
                curve: curve,
                isReversed: true
            )

            directedHalfEdges.append(fwdEdge)
            directedHalfEdges.append(revEdge)

            outgoingMap[curve.fromVertex, default: []].append(fwdEdge)
            outgoingMap[curve.toVertex, default: []].append(revEdge)
        }

        // Sort outgoing half-edges at each vertex CCW by departure angle
        for (v, edges) in outgoingMap {
            outgoingMap[v] = edges.sorted { $0.departureAngle < $1.departureAngle }
        }

        // 4. Extract minimal face cycles
        var visitedEdgeIds = Set<Int>()
        var detectedLoops: [ClosedLoop] = []

        for edge in directedHalfEdges {
            if visitedEdgeIds.contains(edge.id) { continue }

            var cycle: [DirectedHalfEdge] = []
            var curr = edge
            var cycleVisited = Set<Int>()

            while true {
                visitedEdgeIds.insert(curr.id)
                cycle.append(curr)
                cycleVisited.insert(curr.id)

                let dest = curr.toVertex
                guard let outgoing = outgoingMap[dest], !outgoing.isEmpty else { break }

                // Locate twin edge index in outgoing list of dest
                guard let twinIdx = outgoing.firstIndex(where: { $0.id == curr.twinId }) else { break }
                let nextIdx = (twinIdx + outgoing.count - 1) % outgoing.count
                let nextEdge = outgoing[nextIdx]

                if nextEdge.id == edge.id {
                    // Loop closed cleanly!
                    break
                }
                if cycleVisited.contains(nextEdge.id) || cycle.count > directedHalfEdges.count {
                    // Self-intersecting cycle or iteration bound exceeded
                    break
                }
                curr = nextEdge
            }

            guard cycle.count >= 2, let firstEdge = cycle.first, let lastEdge = cycle.last,
                  lastEdge.toVertex == firstEdge.fromVertex else {
                continue
            }

            // Discretize cycle curves into 2D polygon points
            var polygonPoints: [SIMD2<Float>] = []
            for halfEdge in cycle {
                let pts = discretizeHalfEdge(halfEdge, registry: registry)
                for pt in pts {
                    if let lastPt = polygonPoints.last {
                        if simd_distance(pt, lastPt) > Float(minTolerance) {
                            polygonPoints.append(pt)
                        }
                    } else {
                        polygonPoints.append(pt)
                    }
                }
            }

            // Ensure first and last points are clean
            if let f = polygonPoints.first, let l = polygonPoints.last, polygonPoints.count > 2 {
                if simd_distance(f, l) <= Float(minTolerance) {
                    polygonPoints.removeLast()
                }
            }

            guard polygonPoints.count >= 3 else { continue }

            // Compute signed area
            let (area, isCCW) = computeSignedArea(polygonPoints)
            if isCCW && area > Float(minTolerance) {
                let centroid = computeCentroid(polygonPoints, area: area)
                let bbox = computeBoundingBox(polygonPoints)
                detectedLoops.append(ClosedLoop(points: polygonPoints, area: area, centroid: centroid, bbox: bbox))
            }
        }

        // 5. Add standalone circles as closed loops
        for sc in standaloneCircles {
            var pts: [SIMD2<Float>] = []
            pts.reserveCapacity(32)
            for i in 0..<32 {
                let theta = (2.0 * Double.pi * Double(i)) / 32.0
                let x = Float(sc.center.x + sc.radius * cos(theta))
                let y = Float(sc.center.y + sc.radius * sin(theta))
                pts.append(SIMD2<Float>(x, y))
            }
            let area = Float(Double.pi * sc.radius * sc.radius)
            let centroid = SIMD2<Float>(Float(sc.center.x), Float(sc.center.y))
            let rF = Float(sc.radius)
            let bbox = (minX: centroid.x - rF, minY: centroid.y - rF, maxX: centroid.x + rF, maxY: centroid.y + rF)
            detectedLoops.append(ClosedLoop(points: pts, area: area, centroid: centroid, bbox: bbox))
        }

        guard !detectedLoops.isEmpty else { return [] }

        // 6. Nested Loop Containment Hierarchy & Hole Assignment
        let loopCount = detectedLoops.count
        var contains = Array(repeating: Array(repeating: false, count: loopCount), count: loopCount)

        for i in 0..<loopCount {
            for j in 0..<loopCount {
                if i == j { continue }
                let outer = detectedLoops[i]
                let inner = detectedLoops[j]

                // Fast AABB rejection
                if inner.bbox.minX < outer.bbox.minX - 1e-3 ||
                   inner.bbox.maxX > outer.bbox.maxX + 1e-3 ||
                   inner.bbox.minY < outer.bbox.minY - 1e-3 ||
                   inner.bbox.maxY > outer.bbox.maxY + 1e-3 {
                    continue
                }

                // Test centroid and vertices of inner inside outer
                var insideVotes = 0
                if SketchRegion.pointInPolygon(point: inner.centroid, polygon: outer.points) {
                    insideVotes += 2
                }
                let sampleCount = min(8, inner.points.count)
                let step = max(1, inner.points.count / sampleCount)
                for k in stride(from: 0, to: inner.points.count, by: step) {
                    if SketchRegion.pointInPolygon(point: inner.points[k], polygon: outer.points) {
                        insideVotes += 1
                    }
                }
                if insideVotes >= 3 {
                    contains[i][j] = true
                }
            }
        }

        // Direct holes: loop j is a direct hole of loop i iff contains[i][j] and there is no intermediate loop k
        var directChildren: [Int: [Int]] = [:]
        for i in 0..<loopCount {
            var holes: [Int] = []
            for j in 0..<loopCount {
                if !contains[i][j] { continue }
                var hasIntermediate = false
                for k in 0..<loopCount {
                    if k != i && k != j && contains[i][k] && contains[k][j] {
                        hasIntermediate = true
                        break
                    }
                }
                if !hasIntermediate {
                    holes.append(j)
                }
            }
            directChildren[i] = holes
        }

        // 7. Construct final SketchRegions
        var rawRegions: [(outer: ClosedLoop, holes: [ClosedLoop], netArea: Float, centroid: SIMD2<Float>)] = []
        for i in 0..<loopCount {
            let outer = detectedLoops[i]
            let holeIndices = directChildren[i] ?? []
            let holeLoops = holeIndices.map { detectedLoops[$0] }

            let totalHoleArea = holeLoops.reduce(Float(0)) { $0 + $1.area }
            let netArea = max(Float(minTolerance), outer.area - totalHoleArea)

            var weightedCentroid = outer.centroid * outer.area
            for h in holeLoops {
                weightedCentroid -= h.centroid * h.area
            }
            let netCentroid = netArea > Float(minTolerance) ? (weightedCentroid / netArea) : outer.centroid

            rawRegions.append((outer: outer, holes: holeLoops, netArea: netArea, centroid: netCentroid))
        }

        // Sort descending by area, breaking ties with centroid coordinates for stability
        rawRegions.sort {
            if abs($0.netArea - $1.netArea) > 1e-3 {
                return $0.netArea > $1.netArea
            }
            if abs($0.centroid.x - $1.centroid.x) > 1e-3 {
                return $0.centroid.x < $1.centroid.x
            }
            return $0.centroid.y < $1.centroid.y
        }

        var regions: [SketchRegion] = []
        for (idx, item) in rawRegions.enumerated() {
            let regionId = deterministicUUID(index: idx, area: item.netArea, centroid: item.centroid)
            let region = SketchRegion(
                id: regionId,
                outerLoop: item.outer.points,
                innerLoops: item.holes.map { $0.points },
                area: item.netArea,
                centroid: item.centroid
            )
            regions.append(region)
        }

        return regions
    }

    private static func deterministicUUID(index: Int, area: Float, centroid: SIMD2<Float>) -> UUID {
        var h1: UInt64 = 0xcbf29ce484222325
        func hashInt(_ val: Int) {
            var v = UInt64(bitPattern: Int64(val))
            for _ in 0..<8 {
                h1 ^= (v & 0xff)
                h1 &*= 0x100000001b3
                v >>= 8
            }
        }
        func hashFloat(_ val: Float) {
            let q = Int(round(Double(val) * 1000.0))
            hashInt(q)
        }

        hashInt(index)
        hashFloat(area)
        hashFloat(centroid.x)
        hashFloat(centroid.y)

        let h2 = h1 &* 0x517cc1b727220a95 &+ 0x62e8e947c111003f

        let b0 = UInt8((h1 >> 56) & 0xff)
        let b1 = UInt8((h1 >> 48) & 0xff)
        let b2 = UInt8((h1 >> 40) & 0xff)
        let b3 = UInt8((h1 >> 32) & 0xff)
        let b4 = UInt8((h1 >> 24) & 0xff)
        let b5 = UInt8((h1 >> 16) & 0xff)
        let b6 = (UInt8((h1 >> 8) & 0xff) & 0x0f) | 0x40
        let b7 = UInt8(h1 & 0xff)

        let b8 = (UInt8((h2 >> 56) & 0xff) & 0x3f) | 0x80
        let b9 = UInt8((h2 >> 48) & 0xff)
        let b10 = UInt8((h2 >> 40) & 0xff)
        let b11 = UInt8((h2 >> 32) & 0xff)
        let b12 = UInt8((h2 >> 24) & 0xff)
        let b13 = UInt8((h2 >> 16) & 0xff)
        let b14 = UInt8((h2 >> 8) & 0xff)
        let b15 = UInt8(h2 & 0xff)

        return UUID(uuid: (b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15))
    }

    // MARK: - Curve Discretization & Geometry Helpers

    private static func discretizeHalfEdge(_ halfEdge: DirectedHalfEdge, registry: VertexRegistry) -> [SIMD2<Float>] {
        let curve = halfEdge.curve
        let sp = halfEdge.isReversed ? curve.toPoint : curve.fromPoint
        let ep = halfEdge.isReversed ? curve.fromPoint : curve.toPoint

        switch curve.kind {
        case .line:
            return [SIMD2<Float>(Float(sp.x), Float(sp.y))]

        case .arc(let center, let radius, let origCW):
            let effectiveCW = halfEdge.isReversed ? !origCW : origCW
            let a0 = atan2(sp.y - center.y, sp.x - center.x)
            let a1 = atan2(ep.y - center.y, ep.x - center.x)
            var delta = a1 - a0
            if effectiveCW && delta > 0 { delta -= 2.0 * .pi }
            if !effectiveCW && delta < 0 { delta += 2.0 * .pi }

            let steps = 12
            var pts: [SIMD2<Float>] = []
            pts.reserveCapacity(steps)
            for k in 0..<steps {
                let a = a0 + (Double(k) / Double(steps)) * delta
                let x = Float(center.x + radius * cos(a))
                let y = Float(center.y + radius * sin(a))
                pts.append(SIMD2<Float>(x, y))
            }
            return pts
        }
    }

    private static func curveTangents(curve: AtomicCurve, registry: VertexRegistry) -> (start: SIMD2<Double>, end: SIMD2<Double>) {
        let sp = curve.fromPoint
        let ep = curve.toPoint
        switch curve.kind {
        case .line:
            let d = ep - sp
            let len = hypot(d.x, d.y)
            let dir = len > 1e-12 ? (d / len) : SIMD2<Double>(1, 0)
            return (dir, dir)

        case .arc(let cp, let r, let cw):
            let rEff = r > 1e-12 ? r : max(1e-6, hypot(sp.x - cp.x, sp.y - cp.y))
            let rStart = (sp - cp) / rEff
            let rEnd = (ep - cp) / rEff
            let tanStart = cw ? SIMD2<Double>(rStart.y, -rStart.x) : SIMD2<Double>(-rStart.y, rStart.x)
            let tanEnd = cw ? SIMD2<Double>(rEnd.y, -rEnd.x) : SIMD2<Double>(-rEnd.y, rEnd.x)
            return (tanStart, tanEnd)
        }
    }

    private static func computeSignedArea(_ points: [SIMD2<Float>]) -> (area: Float, isCCW: Bool) {
        var twiceArea: Double = 0
        let n = points.count
        for i in 0..<n {
            let a = points[i]
            let b = points[(i + 1) % n]
            twiceArea += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        let area = Float(twiceArea / 2.0)
        return (abs(area), area > 0)
    }

    private static func computeCentroid(_ points: [SIMD2<Float>], area: Float) -> SIMD2<Float> {
        var cx: Double = 0
        var cy: Double = 0
        let n = points.count
        for i in 0..<n {
            let a = points[i]
            let b = points[(i + 1) % n]
            let factor = Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
            cx += Double(a.x + b.x) * factor
            cy += Double(a.y + b.y) * factor
        }
        let denom = 6.0 * Double(area)
        if abs(denom) > 1e-6 {
            return SIMD2<Float>(Float(cx / denom), Float(cy / denom))
        }
        // Fallback to average vertex
        let avg = points.reduce(SIMD2<Float>.zero, +) / Float(max(1, points.count))
        return avg
    }

    private static func computeBoundingBox(_ points: [SIMD2<Float>]) -> (minX: Float, minY: Float, maxX: Float, maxY: Float) {
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return (minX, minY, maxX, maxY)
    }

    // MARK: - 2D Intersection Math Solvers

    public static func findIntersections(_ e1: SketchEntity, _ e2: SketchEntity) -> [SIMD2<Double>] {
        switch (e1.kind, e2.kind) {
        case ("line", "line"):
            guard let s1 = e1.startPoint, let e1p = e1.endPoint,
                  let s2 = e2.startPoint, let e2p = e2.endPoint else { return [] }
            return intersectLineLine(s1, e1p, s2, e2p)

        case ("line", "circle"):
            guard let s = e1.startPoint, let ep = e1.endPoint,
                  let cp = e2.centerPoint, let r = e2.radius else { return [] }
            return intersectLineCircle(s, ep, cp, r)

        case ("circle", "line"):
            guard let cp = e1.centerPoint, let r = e1.radius,
                  let s = e2.startPoint, let ep = e2.endPoint else { return [] }
            return intersectLineCircle(s, ep, cp, r)

        case ("line", "arc"):
            guard let s = e1.startPoint, let ep = e1.endPoint,
                  let cp = e2.centerPoint, let r = e2.radius,
                  let as_ = e2.startPoint, let ae = e2.endPoint else { return [] }
            let circlePts = intersectLineCircle(s, ep, cp, r)
            return circlePts.filter { isPointOnArc(point: $0, start: as_, end: ae, center: cp, clockwise: e2.isClockwise) }

        case ("arc", "line"):
            guard let cp = e1.centerPoint, let r = e1.radius,
                  let as_ = e1.startPoint, let ae = e1.endPoint,
                  let s = e2.startPoint, let ep = e2.endPoint else { return [] }
            let circlePts = intersectLineCircle(s, ep, cp, r)
            return circlePts.filter { isPointOnArc(point: $0, start: as_, end: ae, center: cp, clockwise: e1.isClockwise) }

        case ("circle", "circle"):
            guard let c1 = e1.centerPoint, let r1 = e1.radius,
                  let c2 = e2.centerPoint, let r2 = e2.radius else { return [] }
            return intersectCircleCircle(c1, r1, c2, r2)

        case ("circle", "arc"):
            guard let c1 = e1.centerPoint, let r1 = e1.radius,
                  let c2 = e2.centerPoint, let r2 = e2.radius,
                  let as_ = e2.startPoint, let ae = e2.endPoint else { return [] }
            let pts = intersectCircleCircle(c1, r1, c2, r2)
            return pts.filter { isPointOnArc(point: $0, start: as_, end: ae, center: c2, clockwise: e2.isClockwise) }

        case ("arc", "circle"):
            guard let c1 = e1.centerPoint, let r1 = e1.radius,
                  let as_ = e1.startPoint, let ae = e1.endPoint,
                  let c2 = e2.centerPoint, let r2 = e2.radius else { return [] }
            let pts = intersectCircleCircle(c1, r1, c2, r2)
            return pts.filter { isPointOnArc(point: $0, start: as_, end: ae, center: c1, clockwise: e1.isClockwise) }

        case ("arc", "arc"):
            guard let c1 = e1.centerPoint, let r1 = e1.radius,
                  let as1 = e1.startPoint, let ae1 = e1.endPoint,
                  let c2 = e2.centerPoint, let r2 = e2.radius,
                  let as2 = e2.startPoint, let ae2 = e2.endPoint else { return [] }
            let pts = intersectCircleCircle(c1, r1, c2, r2)
            return pts.filter {
                isPointOnArc(point: $0, start: as1, end: ae1, center: c1, clockwise: e1.isClockwise) &&
                isPointOnArc(point: $0, start: as2, end: ae2, center: c2, clockwise: e2.isClockwise)
            }

        default:
            return []
        }
    }

    private static func intersectLineLine(
        _ p1: SIMD2<Double>, _ p2: SIMD2<Double>,
        _ p3: SIMD2<Double>, _ p4: SIMD2<Double>
    ) -> [SIMD2<Double>] {
        let d1 = p2 - p1
        let d2 = p4 - p3
        let cross = d1.x * d2.y - d1.y * d2.x
        guard abs(cross) > 1e-9 else { return [] }

        let dp = p3 - p1
        let t = (dp.x * d2.y - dp.y * d2.x) / cross
        let u = (dp.x * d1.y - dp.y * d1.x) / cross

        if t >= -1e-4 && t <= 1.0 + 1e-4 && u >= -1e-4 && u <= 1.0 + 1e-4 {
            let clampedT = max(0.0, min(1.0, t))
            return [p1 + clampedT * d1]
        }
        return []
    }

    private static func intersectLineCircle(
        _ p1: SIMD2<Double>, _ p2: SIMD2<Double>,
        _ center: SIMD2<Double>, _ radius: Double
    ) -> [SIMD2<Double>] {
        let d = p2 - p1
        let a = simd_dot(d, d)
        guard a > 1e-12 else { return [] }

        let delta = p1 - center
        let b = 2.0 * simd_dot(delta, d)
        let c = simd_dot(delta, delta) - radius * radius
        let disc = b * b - 4.0 * a * c

        if disc < -1e-7 { return [] }
        let sqrtDisc = disc > 0 ? sqrt(disc) : 0.0

        let t1 = (-b - sqrtDisc) / (2.0 * a)
        let t2 = (-b + sqrtDisc) / (2.0 * a)

        var result: [SIMD2<Double>] = []
        for t in [t1, t2] {
            if t >= -1e-4 && t <= 1.0 + 1e-4 {
                let clampedT = max(0.0, min(1.0, t))
                let pt = p1 + clampedT * d
                if !result.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < 1e-4 }) {
                    result.append(pt)
                }
            }
        }
        return result
    }

    private static func intersectCircleCircle(
        _ c1: SIMD2<Double>, _ r1: Double,
        _ c2: SIMD2<Double>, _ r2: Double
    ) -> [SIMD2<Double>] {
        let dVec = c2 - c1
        let d = hypot(dVec.x, dVec.y)
        if d > (r1 + r2 + 1e-4) || d < (abs(r1 - r2) - 1e-4) || d < 1e-9 {
            return []
        }

        let a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
        let hSq = r1 * r1 - a * a
        let h = hSq > 0 ? sqrt(hSq) : 0.0

        let p0 = c1 + (a / d) * dVec
        let perp = SIMD2<Double>(-dVec.y / d, dVec.x / d)

        if h < 1e-5 {
            return [p0]
        } else {
            return [p0 + h * perp, p0 - h * perp]
        }
    }

    private static func isPointOnArc(
        point: SIMD2<Double>,
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        center: SIMD2<Double>,
        clockwise: Bool
    ) -> Bool {
        let sAngle = atan2(start.y - center.y, start.x - center.x)
        let totalSweep = arcSweepAngle(start: start, end: end, center: center, clockwise: clockwise)
        let offset = arcAngleOffset(point: point, startAngle: sAngle, center: center, clockwise: clockwise)
        return offset <= totalSweep + 1e-4
    }

    private static func arcSweepAngle(start: SIMD2<Double>, end: SIMD2<Double>, center: SIMD2<Double>, clockwise: Bool) -> Double {
        let a0 = atan2(start.y - center.y, start.x - center.x)
        let a1 = atan2(end.y - center.y, end.x - center.x)
        if !clockwise {
            return normalizeAngle(a1 - a0)
        } else {
            return normalizeAngle(a0 - a1)
        }
    }

    private static func arcAngleOffset(point: SIMD2<Double>, startAngle: Double, center: SIMD2<Double>, clockwise: Bool) -> Double {
        let a = atan2(point.y - center.y, point.x - center.x)
        if !clockwise {
            return normalizeAngle(a - startAngle)
        } else {
            return normalizeAngle(startAngle - a)
        }
    }

    private static func normalizeAngle(_ a: Double) -> Double {
        var angle = a.truncatingRemainder(dividingBy: 2.0 * .pi)
        if angle < 0 { angle += 2.0 * .pi }
        return angle
    }
}
