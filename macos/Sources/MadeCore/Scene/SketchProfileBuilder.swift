import Foundation
import simd

/// Validates 2D sketch entities and constructs closed, oriented `SketchProfile`s for extrusion.
public enum SketchProfileBuilder {
    public static let snappingTolerance: Double = 1e-3
    public static let minEntityTolerance: Double = 1e-5

    /// Validates individual entity geometry against degenerate bounds.
    public static func validateEntity(_ entity: SketchEntity) throws {
        switch entity.kind {
        case "line":
            guard let sp = entity.startPoint, let ep = entity.endPoint else {
                throw SketchError.invalidEntity("Line entity \(entity.id.uuidString) is missing coordinates")
            }
            let len = hypot(ep.x - sp.x, ep.y - sp.y)
            if len <= minEntityTolerance {
                throw SketchError.zeroLengthLine(entityId: entity.id)
            }
        case "arc":
            guard let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint else {
                throw SketchError.invalidEntity("Arc entity \(entity.id.uuidString) is missing coordinates")
            }
            let chord = hypot(ep.x - sp.x, ep.y - sp.y)
            if chord <= minEntityTolerance {
                throw SketchError.degenerateArc(entityId: entity.id, message: "Start and end points are coincident")
            }
            let rStart = hypot(sp.x - cp.x, sp.y - cp.y)
            let rEnd = hypot(ep.x - cp.x, ep.y - cp.y)
            if rStart <= minEntityTolerance || rEnd <= minEntityTolerance {
                throw SketchError.degenerateArc(entityId: entity.id, message: "Radius too small (<= 1e-5 mm)")
            }
            if abs(rStart - rEnd) > 1e-2 {
                throw SketchError.degenerateArc(entityId: entity.id, message: "Start and end radii mismatch")
            }
        case "circle":
            guard let r = entity.radius, r > minEntityTolerance else {
                throw SketchError.invalidEntity("Circle entity \(entity.id.uuidString) radius must be greater than 1e-5 mm")
            }
        default:
            throw SketchError.invalidEntity("Unsupported entity kind: '\(entity.kind)'")
        }
    }

    /// Detects all closed planar regions and holes from sketch entities.
    public static func detectRegions(
        from entities: [SketchEntity],
        plane: SketchPlane = .xy
    ) throws -> [SketchRegion] {
        try SketchRegionDetector.detectRegions(from: entities)
    }

    /// Chains entities, discretizes curved geometry, and returns an oriented, closed `SketchProfile`.
    public static func build(
        from entities: [SketchEntity],
        plane: SketchPlane = .xy
    ) throws -> SketchProfile {
        guard !entities.isEmpty else {
            throw SketchError.emptySketch
        }

        for entity in entities {
            try validateEntity(entity)
        }

        // Single circle loop fast path
        if entities.count == 1, entities[0].kind == "circle" {
            let circle = entities[0]
            guard let r = circle.radius, r > minEntityTolerance else {
                throw SketchError.invalidEntity("Circle radius must be positive")
            }
            let center = circle.centerPoint ?? .zero
            var points: [SIMD2<Float>] = []
            points.reserveCapacity(32)
            for i in 0..<32 {
                let theta = (2.0 * Double.pi * Double(i)) / 32.0
                let x = Float(center.x + r * cos(theta))
                let y = Float(center.y + r * sin(theta))
                points.append(SIMD2<Float>(x, y))
            }
            return SketchProfile(plane: plane, points: points)
        }

        // Validate that sketch does not contain dangling or open endpoints
        if hasOpenEndpoints(in: entities) {
            throw SketchError.openProfile(message: "Sketch contains disconnected or dangling entities")
        }

        // If sketch forms closed regions (e.g. nested loops with holes or complex planar arrangements), extract primary region
        if let regions = try? detectRegions(from: entities, plane: plane), let primary = regions.first {
            return primary.toProfile(plane: plane)
        }

        // Chaining curve segments (lines and arcs)
        struct ChainedSegment {
            let entity: SketchEntity
            let start: SIMD2<Double>
            let end: SIMD2<Double>
            let isReversed: Bool
        }

        var pool = entities
        let first = pool.removeFirst()
        guard let firstStart = first.startPoint, let firstEnd = first.endPoint else {
            throw SketchError.invalidEntity("First entity has no start or end point")
        }

        var chain: [ChainedSegment] = [
            ChainedSegment(entity: first, start: firstStart, end: firstEnd, isReversed: false)
        ]
        var currentEnd = firstEnd

        while !pool.isEmpty {
            var foundIndex: Int? = nil
            var isReversed = false

            for (idx, candidate) in pool.enumerated() {
                guard let candStart = candidate.startPoint, let candEnd = candidate.endPoint else {
                    continue
                }
                if hypot(candStart.x - currentEnd.x, candStart.y - currentEnd.y) <= snappingTolerance {
                    foundIndex = idx
                    isReversed = false
                    break
                } else if hypot(candEnd.x - currentEnd.x, candEnd.y - currentEnd.y) <= snappingTolerance {
                    foundIndex = idx
                    isReversed = true
                    break
                }
            }

            guard let idx = foundIndex else {
                throw SketchError.openProfile(message: "Sketch contains disconnected or dangling entities")
            }

            let nextEntity = pool.remove(at: idx)
            let segStart = isReversed ? nextEntity.endPoint! : nextEntity.startPoint!
            let segEnd = isReversed ? nextEntity.startPoint! : nextEntity.endPoint!
            chain.append(ChainedSegment(entity: nextEntity, start: segStart, end: segEnd, isReversed: isReversed))
            currentEnd = segEnd
        }

        let loopClosureGap = hypot(currentEnd.x - chain[0].start.x, currentEnd.y - chain[0].start.y)
        guard loopClosureGap <= snappingTolerance else {
            throw SketchError.openProfile(
                message: "Endpoints do not meet within tolerance (gap: \(String(format: "%.4f", loopClosureGap)) mm)"
            )
        }

        // Discretize chained segments into polygon points
        var rawPoints: [SIMD2<Float>] = []
        for segment in chain {
            switch segment.entity.kind {
            case "line":
                rawPoints.append(SIMD2<Float>(Float(segment.start.x), Float(segment.start.y)))

            case "arc":
                let center = segment.entity.centerPoint ?? .zero
                let r = segment.entity.radius ?? hypot(segment.start.x - center.x, segment.start.y - center.y)
                let originalCW = segment.entity.isClockwise
                let effectiveCW = segment.isReversed ? !originalCW : originalCW

                let a0 = atan2(segment.start.y - center.y, segment.start.x - center.x)
                let a1 = atan2(segment.end.y - center.y, segment.end.x - center.x)
                var delta = a1 - a0
                if effectiveCW && delta > 0 { delta -= 2.0 * .pi }
                if !effectiveCW && delta < 0 { delta += 2.0 * .pi }

                let arcSegments = 12
                for k in 0..<arcSegments {
                    let a = a0 + (Double(k) / Double(arcSegments)) * delta
                    let x = Float(center.x + r * cos(a))
                    let y = Float(center.y + r * sin(a))
                    rawPoints.append(SIMD2<Float>(x, y))
                }

            default:
                throw SketchError.invalidEntity("Unsupported entity in chain: '\(segment.entity.kind)'")
            }
        }

        // Deduplicate adjacent vertices
        var deduped: [SIMD2<Float>] = []
        for pt in rawPoints {
            if let last = deduped.last {
                if simd_distance(pt, last) > Float(minEntityTolerance) {
                    deduped.append(pt)
                }
            } else {
                deduped.append(pt)
            }
        }
        if let first = deduped.first, let last = deduped.last, deduped.count > 1 {
            if simd_distance(first, last) <= Float(minEntityTolerance) {
                deduped.removeLast()
            }
        }

        guard deduped.count >= 3 else {
            throw SketchError.noClosedLoop
        }

        // Verify signed area and orient counter-clockwise
        var twiceArea: Double = 0
        for i in 0..<deduped.count {
            let a = deduped[i]
            let b = deduped[(i + 1) % deduped.count]
            twiceArea += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        let signedArea = twiceArea / 2.0
        guard abs(signedArea) > minEntityTolerance else {
            throw SketchError.noClosedLoop
        }

        let orientedPoints = (signedArea > 0) ? deduped : Array(deduped.reversed())
        return SketchProfile(plane: plane, points: orientedPoints)
    }

    private static func hasOpenEndpoints(in entities: [SketchEntity]) -> Bool {
        for (i, entity) in entities.enumerated() {
            let endpoints: [SIMD2<Double>]
            switch entity.kind {
            case "line", "arc":
                guard let sp = entity.startPoint, let ep = entity.endPoint else { continue }
                endpoints = [sp, ep]
            default:
                continue
            }

            for pt in endpoints {
                var connects = false
                for (j, other) in entities.enumerated() {
                    if i == j { continue }
                    if isPointOnEntity(pt, entity: other, tolerance: snappingTolerance) {
                        connects = true
                        break
                    }
                }
                if !connects {
                    return true
                }
            }
        }
        return false
    }

    private static func isPointOnEntity(_ pt: SIMD2<Double>, entity: SketchEntity, tolerance: Double) -> Bool {
        switch entity.kind {
        case "line":
            guard let sp = entity.startPoint, let ep = entity.endPoint else { return false }
            if hypot(pt.x - sp.x, pt.y - sp.y) <= tolerance || hypot(pt.x - ep.x, pt.y - ep.y) <= tolerance {
                return true
            }
            let d = ep - sp
            let lenSq = simd_dot(d, d)
            if lenSq < 1e-12 { return false }
            let t = simd_dot(pt - sp, d) / lenSq
            if t >= -1e-4 && t <= 1.0 + 1e-4 {
                let proj = sp + max(0.0, min(1.0, t)) * d
                return hypot(pt.x - proj.x, pt.y - proj.y) <= tolerance
            }
            return false

        case "arc":
            guard let cp = entity.centerPoint, let r = entity.radius,
                  let sp = entity.startPoint, let ep = entity.endPoint else { return false }
            if hypot(pt.x - sp.x, pt.y - sp.y) <= tolerance || hypot(pt.x - ep.x, pt.y - ep.y) <= tolerance {
                return true
            }
            let dist = hypot(pt.x - cp.x, pt.y - cp.y)
            guard abs(dist - r) <= tolerance else { return false }
            let a0 = atan2(sp.y - cp.y, sp.x - cp.x)
            let a1 = atan2(ep.y - cp.y, ep.x - cp.x)
            let ptA = atan2(pt.y - cp.y, pt.x - cp.x)
            let sweep: Double
            let offset: Double
            if !entity.isClockwise {
                var s = a1 - a0
                if s < 0 { s += 2.0 * .pi }
                var o = ptA - a0
                if o < 0 { o += 2.0 * .pi }
                sweep = s
                offset = o
            } else {
                var s = a0 - a1
                if s < 0 { s += 2.0 * .pi }
                var o = a0 - ptA
                if o < 0 { o += 2.0 * .pi }
                sweep = s
                offset = o
            }
            return offset <= sweep + 1e-4

        case "circle":
            guard let cp = entity.centerPoint, let r = entity.radius else { return false }
            let dist = hypot(pt.x - cp.x, pt.y - cp.y)
            return abs(dist - r) <= tolerance

        default:
            return false
        }
    }
}
