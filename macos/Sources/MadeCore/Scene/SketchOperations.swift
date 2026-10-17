import Foundation
import simd

/// Target endpoint for sketch entity extension operations.
public enum SketchEntityEnd: String, Sendable, Codable, Equatable {
    case start
    case end
}

/// The result of trimming a sketch entity.
public enum TrimResult: Sendable, Equatable {
    case updated(SketchEntity)
    case divided(updated: SketchEntity, added: SketchEntity)
    case deleted(entityId: UUID)
}

/// Core geometric engine providing tolerance-aware trim, extend, split, and intersection operations for 2D sketch entities.
public enum SketchOperations {
    public static let tolerance: Double = 1e-4

    // MARK: - 2D Intersection Math Solvers

    public static func normalizeAngle(_ a: Double) -> Double {
        var angle = a.truncatingRemainder(dividingBy: 2.0 * .pi)
        if angle < 0 { angle += 2.0 * .pi }
        return angle
    }

    public static func arcSweepAngle(
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        center: SIMD2<Double>,
        clockwise: Bool
    ) -> Double {
        let a0 = atan2(start.y - center.y, start.x - center.x)
        let a1 = atan2(end.y - center.y, end.x - center.x)
        if !clockwise {
            return normalizeAngle(a1 - a0)
        } else {
            return normalizeAngle(a0 - a1)
        }
    }

    public static func arcAngleOffset(
        point: SIMD2<Double>,
        startAngle: Double,
        center: SIMD2<Double>,
        clockwise: Bool
    ) -> Double {
        let a = atan2(point.y - center.y, point.x - center.x)
        if !clockwise {
            return normalizeAngle(a - startAngle)
        } else {
            return normalizeAngle(startAngle - a)
        }
    }

    public static func isPointOnArc(
        point: SIMD2<Double>,
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        center: SIMD2<Double>,
        clockwise: Bool
    ) -> Bool {
        let sAngle = atan2(start.y - center.y, start.x - center.x)
        let totalSweep = arcSweepAngle(start: start, end: end, center: center, clockwise: clockwise)
        let offset = arcAngleOffset(point: point, startAngle: sAngle, center: center, clockwise: clockwise)
        return offset <= totalSweep + tolerance
    }

    public static func intersectLineLine(
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

        if t >= -tolerance && t <= 1.0 + tolerance && u >= -tolerance && u <= 1.0 + tolerance {
            let clampedT = max(0.0, min(1.0, t))
            return [p1 + clampedT * d1]
        }
        return []
    }

    public static func intersectLineCircle(
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
            if t >= -tolerance && t <= 1.0 + tolerance {
                let clampedT = max(0.0, min(1.0, t))
                let pt = p1 + clampedT * d
                if !result.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < tolerance }) {
                    result.append(pt)
                }
            }
        }
        return result
    }

    public static func intersectCircleCircle(
        _ c1: SIMD2<Double>, _ r1: Double,
        _ c2: SIMD2<Double>, _ r2: Double
    ) -> [SIMD2<Double>] {
        let dVec = c2 - c1
        let d = hypot(dVec.x, dVec.y)
        if d > (r1 + r2 + tolerance) || d < (abs(r1 - r2) - tolerance) || d < 1e-9 {
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

    public static func findIntersectionsBetween(_ e1: SketchEntity, _ e2: SketchEntity) -> [SIMD2<Double>] {
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

    /// Finds all 2D intersection points between `entity` and all other entities in `entities`.
    public static func findIntersections(
        for entity: SketchEntity,
        in entities: [SketchEntity]
    ) -> [SIMD2<Double>] {
        var rawIntersections: [SIMD2<Double>] = []
        for other in entities where other.id != entity.id {
            let pts = findIntersectionsBetween(entity, other)
            rawIntersections.append(contentsOf: pts)
        }

        // Deduplicate within tolerance
        var unique: [SIMD2<Double>] = []
        for p in rawIntersections {
            if !unique.contains(where: { hypot($0.x - p.x, $0.y - p.y) < tolerance }) {
                unique.append(p)
            }
        }
        return unique
    }

    // MARK: - Ray Intersections (For Extend)

    public struct RayIntersectionCandidate {
        public let point: SIMD2<Double>
        public let t: Double
    }

    /// Intersects a semi-infinite ray `origin + t * direction` ($t > tolerance$) with an entity.
    public static func intersectRayWithEntity(
        origin: SIMD2<Double>,
        direction: SIMD2<Double>,
        entity: SketchEntity
    ) -> [RayIntersectionCandidate] {
        var candidates: [RayIntersectionCandidate] = []

        switch entity.kind {
        case "line":
            guard let p1 = entity.startPoint, let p2 = entity.endPoint else { break }
            let segD = p2 - p1
            let cross = direction.x * segD.y - direction.y * segD.x
            guard abs(cross) > 1e-9 else { break }

            let dp = p1 - origin
            let t = (dp.x * segD.y - dp.y * segD.x) / cross
            let u = (dp.x * direction.y - dp.y * direction.x) / cross

            if t > tolerance && u >= -tolerance && u <= 1.0 + tolerance {
                let clampedU = max(0.0, min(1.0, u))
                let pt = p1 + clampedU * segD
                candidates.append(RayIntersectionCandidate(point: pt, t: t))
            }

        case "circle":
            guard let cp = entity.centerPoint, let r = entity.radius, r > 1e-6 else { break }
            let delta = origin - cp
            let a = simd_dot(direction, direction)
            guard a > 1e-12 else { break }
            let b = 2.0 * simd_dot(delta, direction)
            let c = simd_dot(delta, delta) - r * r
            let disc = b * b - 4.0 * a * c
            if disc >= -1e-7 {
                let sqrtDisc = disc > 0 ? sqrt(disc) : 0.0
                let t1 = (-b - sqrtDisc) / (2.0 * a)
                let t2 = (-b + sqrtDisc) / (2.0 * a)
                for t in [t1, t2] where t > tolerance {
                    let pt = origin + t * direction
                    candidates.append(RayIntersectionCandidate(point: pt, t: t))
                }
            }

        case "arc":
            guard let cp = entity.centerPoint, let r = entity.radius,
                  let as_ = entity.startPoint, let ae = entity.endPoint, r > 1e-6 else { break }
            let delta = origin - cp
            let a = simd_dot(direction, direction)
            guard a > 1e-12 else { break }
            let b = 2.0 * simd_dot(delta, direction)
            let c = simd_dot(delta, delta) - r * r
            let disc = b * b - 4.0 * a * c
            if disc >= -1e-7 {
                let sqrtDisc = disc > 0 ? sqrt(disc) : 0.0
                let t1 = (-b - sqrtDisc) / (2.0 * a)
                let t2 = (-b + sqrtDisc) / (2.0 * a)
                for t in [t1, t2] where t > tolerance {
                    let pt = origin + t * direction
                    if isPointOnArc(point: pt, start: as_, end: ae, center: cp, clockwise: entity.isClockwise) {
                        candidates.append(RayIntersectionCandidate(point: pt, t: t))
                    }
                }
            }

        default:
            break
        }

        return candidates
    }

    // MARK: - Click Trim

    /// Trims an entity at a clicked 2D point based on its intersections with sibling entities.
    public static func trim(
        entity: SketchEntity,
        at clickPoint: SIMD2<Double>,
        in entities: [SketchEntity]
    ) throws -> TrimResult {
        switch entity.kind {
        case "line":
            guard let sp = entity.startPoint, let ep = entity.endPoint else {
                throw SketchError.invalidEntity("Line entity \(entity.id) missing endpoints")
            }
            let v = ep - sp
            let lenSq = simd_dot(v, v)
            guard lenSq > 1e-8 else {
                throw SketchError.zeroLengthLine(entityId: entity.id)
            }

            let intersections = findIntersections(for: entity, in: entities)
            var tValues: [Double] = []
            for pt in intersections {
                let t = simd_dot(pt - sp, v) / lenSq
                if t > tolerance && t < (1.0 - tolerance) {
                    if !tValues.contains(where: { abs($0 - t) < 1e-4 }) {
                        tValues.append(t)
                    }
                }
            }
            tValues.sort()

            if tValues.isEmpty {
                return .deleted(entityId: entity.id)
            }

            let clickT = max(0.0, min(1.0, simd_dot(clickPoint - sp, v) / lenSq))
            let bounds = [0.0] + tValues + [1.0]

            // Find interval containing clickT
            var intervalIdx = 0
            for i in 0..<(bounds.count - 1) {
                if clickT >= bounds[i] && clickT <= bounds[i + 1] {
                    intervalIdx = i
                    break
                }
            }

            if intervalIdx == 0 {
                // Trim start segment
                let newStart = sp + bounds[1] * v
                let updated = entity.updatingEndpoints(start: newStart, end: ep)
                return .updated(updated)
            } else if intervalIdx == bounds.count - 2 {
                // Trim end segment
                let newEnd = sp + bounds[intervalIdx] * v
                let updated = entity.updatingEndpoints(start: sp, end: newEnd)
                return .updated(updated)
            } else {
                // Trim middle segment: divide into two lines
                let p1 = sp + bounds[intervalIdx] * v
                let p2 = sp + bounds[intervalIdx + 1] * v
                let updated = entity.updatingEndpoints(start: sp, end: p1)
                let added = SketchEntity.line(
                    id: UUID(),
                    start: p2,
                    end: ep,
                    isConstruction: entity.isConstruction
                )
                return .divided(updated: updated, added: added)
            }

        case "arc":
            guard let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint else {
                throw SketchError.invalidEntity("Arc entity \(entity.id) missing geometry")
            }
            let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
            guard r > 1e-6 else {
                throw SketchError.degenerateArc(entityId: entity.id, message: "Radius too small")
            }
            let cw = entity.isClockwise
            let totalSweep = arcSweepAngle(start: sp, end: ep, center: cp, clockwise: cw)
            guard totalSweep > tolerance else {
                throw SketchError.degenerateArc(entityId: entity.id, message: "Sweep angle too small")
            }
            let sAngle = atan2(sp.y - cp.y, sp.x - cp.x)

            let intersections = findIntersections(for: entity, in: entities)
            var angleOffsets: [Double] = []
            for pt in intersections {
                let offset = arcAngleOffset(point: pt, startAngle: sAngle, center: cp, clockwise: cw)
                if offset > tolerance && offset < (totalSweep - tolerance) {
                    if !angleOffsets.contains(where: { abs($0 - offset) < 1e-4 }) {
                        angleOffsets.append(offset)
                    }
                }
            }
            angleOffsets.sort()

            if angleOffsets.isEmpty {
                return .deleted(entityId: entity.id)
            }

            let clickOffset = max(0.0, min(totalSweep, arcAngleOffset(point: clickPoint, startAngle: sAngle, center: cp, clockwise: cw)))
            let bounds = [0.0] + angleOffsets + [totalSweep]

            var intervalIdx = 0
            for i in 0..<(bounds.count - 1) {
                if clickOffset >= bounds[i] && clickOffset <= bounds[i + 1] {
                    intervalIdx = i
                    break
                }
            }

            func pointAtOffset(_ offset: Double) -> SIMD2<Double> {
                let ang = cw ? (sAngle - offset) : (sAngle + offset)
                return cp + r * SIMD2<Double>(cos(ang), sin(ang))
            }

            if intervalIdx == 0 {
                // Trim start
                let newStart = pointAtOffset(bounds[1])
                let updated = SketchEntity.arc(
                    id: entity.id,
                    start: newStart,
                    end: ep,
                    center: cp,
                    clockwise: cw,
                    isConstruction: entity.isConstruction
                )
                return .updated(updated)
            } else if intervalIdx == bounds.count - 2 {
                // Trim end
                let newEnd = pointAtOffset(bounds[intervalIdx])
                let updated = SketchEntity.arc(
                    id: entity.id,
                    start: sp,
                    end: newEnd,
                    center: cp,
                    clockwise: cw,
                    isConstruction: entity.isConstruction
                )
                return .updated(updated)
            } else {
                // Trim middle: divide into two arcs
                let p1 = pointAtOffset(bounds[intervalIdx])
                let p2 = pointAtOffset(bounds[intervalIdx + 1])
                let updated = SketchEntity.arc(
                    id: entity.id,
                    start: sp,
                    end: p1,
                    center: cp,
                    clockwise: cw,
                    isConstruction: entity.isConstruction
                )
                let added = SketchEntity.arc(
                    id: UUID(),
                    start: p2,
                    end: ep,
                    center: cp,
                    clockwise: cw,
                    isConstruction: entity.isConstruction
                )
                return .divided(updated: updated, added: added)
            }

        case "circle":
            guard let cp = entity.centerPoint, let r = entity.radius, r > 1e-6 else {
                throw SketchError.invalidEntity("Circle entity \(entity.id) missing geometry")
            }

            let intersections = findIntersections(for: entity, in: entities)
            var polarAngles: [Double] = []
            for pt in intersections {
                let a = normalizeAngle(atan2(pt.y - cp.y, pt.x - cp.x))
                if !polarAngles.contains(where: { abs($0 - a) < 1e-4 }) {
                    polarAngles.append(a)
                }
            }
            polarAngles.sort()

            if polarAngles.count < 2 {
                return .deleted(entityId: entity.id)
            }

            let clickAngle = normalizeAngle(atan2(clickPoint.y - cp.y, clickPoint.x - cp.x))
            let m = polarAngles.count

            // Intervals: [a_0, a_1], [a_1, a_2], ..., [a_{m-1}, a_0 + 2pi]
            var trimInterval: (start: Double, end: Double) = (polarAngles[0], polarAngles[1])
            var found = false
            for i in 0..<(m - 1) {
                if clickAngle >= polarAngles[i] && clickAngle <= polarAngles[i + 1] {
                    trimInterval = (polarAngles[i], polarAngles[i + 1])
                    found = true
                    break
                }
            }
            if !found {
                // Last wrapping interval
                trimInterval = (polarAngles[m - 1], polarAngles[0])
            }

            // Trimming away [trimInterval.start, trimInterval.end] leaves an arc from end CCW to start
            let arcStart = cp + r * SIMD2<Double>(cos(trimInterval.end), sin(trimInterval.end))
            let arcEnd = cp + r * SIMD2<Double>(cos(trimInterval.start), sin(trimInterval.start))

            let remainingArc = SketchEntity.arc(
                id: entity.id,
                start: arcStart,
                end: arcEnd,
                center: cp,
                clockwise: false,
                isConstruction: entity.isConstruction
            )
            return .updated(remainingArc)

        default:
            throw SketchError.invalidEntity("Cannot trim entity kind \(entity.kind)")
        }
    }

    // MARK: - Drag Trim ("Power Trim")

    /// Trims entities crossed by a continuous cursor trajectory path.
    public static func trimAlongPath(
        path: [SIMD2<Double>],
        in entities: inout [SketchEntity]
    ) -> [TrimResult] {
        guard path.count >= 2 else { return [] }
        var results: [TrimResult] = []

        for i in 0..<(path.count - 1) {
            let p1 = path[i]
            let p2 = path[i + 1]
            let strokeLen = hypot(p2.x - p1.x, p2.y - p1.y)
            guard strokeLen > 1e-6 else { continue }

            let strokeEntity = SketchEntity.line(start: p1, end: p2)

            // Find all crossings between stroke and current entities
            struct Crossing {
                let entityId: UUID
                let point: SIMD2<Double>
                let dist: Double
            }
            var crossings: [Crossing] = []

            for entity in entities {
                let pts = findIntersectionsBetween(strokeEntity, entity)
                for pt in pts {
                    let d = hypot(pt.x - p1.x, pt.y - p1.y)
                    crossings.append(Crossing(entityId: entity.id, point: pt, dist: d))
                }
            }

            crossings.sort { $0.dist < $1.dist }

            for crossing in crossings {
                guard let target = entities.first(where: { $0.id == crossing.entityId }) else {
                    continue
                }

                if let res = try? trim(entity: target, at: crossing.point, in: entities) {
                    switch res {
                    case .updated(let u):
                        if let idx = entities.firstIndex(where: { $0.id == u.id }) {
                            entities[idx] = u
                        }
                    case .divided(let u, let added):
                        if let idx = entities.firstIndex(where: { $0.id == u.id }) {
                            entities[idx] = u
                            entities.insert(added, at: idx + 1)
                        }
                    case .deleted(let id):
                        entities.removeAll(where: { $0.id == id })
                    }
                    results.append(res)
                }
            }
        }

        return results
    }

    // MARK: - Extend

    /// Extends a line or arc entity from its specified endpoint to the nearest forward intersection boundary.
    public static func extend(
        entity: SketchEntity,
        targetEnd: SketchEntityEnd,
        in entities: [SketchEntity]
    ) throws -> SketchEntity {
        switch entity.kind {
        case "line":
            guard let sp = entity.startPoint, let ep = entity.endPoint else {
                throw SketchError.invalidEntity("Line entity \(entity.id) missing endpoints")
            }
            let len = hypot(ep.x - sp.x, ep.y - sp.y)
            guard len > 1e-8 else {
                throw SketchError.zeroLengthLine(entityId: entity.id)
            }

            let origin: SIMD2<Double>
            let dir: SIMD2<Double>
            if targetEnd == .end {
                origin = ep
                dir = SIMD2<Double>((ep.x - sp.x) / len, (ep.y - sp.y) / len)
            } else {
                origin = sp
                dir = SIMD2<Double>((sp.x - ep.x) / len, (sp.y - ep.y) / len)
            }

            var allCandidates: [RayIntersectionCandidate] = []
            for other in entities where other.id != entity.id {
                let candidates = intersectRayWithEntity(origin: origin, direction: dir, entity: other)
                allCandidates.append(contentsOf: candidates)
            }

            // Pick nearest candidate with t > tolerance
            guard let nearest = allCandidates.min(by: { $0.t < $1.t }) else {
                throw SketchError.noIntersection("No intersecting boundary found to extend line")
            }

            if targetEnd == .end {
                return entity.updatingEndpoints(start: sp, end: nearest.point)
            } else {
                return entity.updatingEndpoints(start: nearest.point, end: ep)
            }

        case "arc":
            guard let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint else {
                throw SketchError.invalidEntity("Arc entity \(entity.id) missing geometry")
            }
            let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
            guard r > 1e-6 else {
                throw SketchError.degenerateArc(entityId: entity.id, message: "Radius too small")
            }
            let cw = entity.isClockwise
            let totalSweep = arcSweepAngle(start: sp, end: ep, center: cp, clockwise: cw)
            let maxExtendAngle = 2.0 * .pi - totalSweep - tolerance
            guard maxExtendAngle > tolerance else {
                throw SketchError.noIntersection("Arc already completes a full circle")
            }

            // Intersect full circle of arc with other entities
            let fullCircle = SketchEntity.circle(center: cp, radius: r)
            let intersections = findIntersections(for: fullCircle, in: entities.filter { $0.id != entity.id })

            struct ArcExtendCandidate {
                let point: SIMD2<Double>
                let deltaAngle: Double
            }
            var candidates: [ArcExtendCandidate] = []

            if targetEnd == .end {
                let endAngle = atan2(ep.y - cp.y, ep.x - cp.x)
                for pt in intersections {
                    let delta = arcAngleOffset(point: pt, startAngle: endAngle, center: cp, clockwise: cw)
                    if delta > tolerance && delta <= maxExtendAngle {
                        candidates.append(ArcExtendCandidate(point: pt, deltaAngle: delta))
                    }
                }
            } else {
                let startAngle = atan2(sp.y - cp.y, sp.x - cp.x)
                for pt in intersections {
                    let delta = arcAngleOffset(point: pt, startAngle: startAngle, center: cp, clockwise: !cw)
                    if delta > tolerance && delta <= maxExtendAngle {
                        candidates.append(ArcExtendCandidate(point: pt, deltaAngle: delta))
                    }
                }
            }

            guard let nearest = candidates.min(by: { $0.deltaAngle < $1.deltaAngle }) else {
                throw SketchError.noIntersection("No intersecting boundary found to extend arc")
            }

            if targetEnd == .end {
                return SketchEntity.arc(
                    id: entity.id,
                    start: sp,
                    end: nearest.point,
                    center: cp,
                    clockwise: cw,
                    isConstruction: entity.isConstruction
                )
            } else {
                return SketchEntity.arc(
                    id: entity.id,
                    start: nearest.point,
                    end: ep,
                    center: cp,
                    clockwise: cw,
                    isConstruction: entity.isConstruction
                )
            }

        case "circle":
            throw SketchError.invalidEntity("Circle entities cannot be extended")

        default:
            throw SketchError.invalidEntity("Cannot extend entity of kind \(entity.kind)")
        }
    }

    // MARK: - Split

    /// Splits an entity at a given point into two connected sub-entities.
    public static func split(
        entity: SketchEntity,
        at point: SIMD2<Double>
    ) throws -> (SketchEntity, SketchEntity) {
        switch entity.kind {
        case "line":
            guard let sp = entity.startPoint, let ep = entity.endPoint else {
                throw SketchError.invalidEntity("Line entity \(entity.id) missing endpoints")
            }
            let v = ep - sp
            let lenSq = simd_dot(v, v)
            guard lenSq > 1e-8 else {
                throw SketchError.zeroLengthLine(entityId: entity.id)
            }

            let t = simd_dot(point - sp, v) / lenSq
            let proj = sp + t * v
            guard hypot(point.x - proj.x, point.y - proj.y) <= 1e-3 else {
                throw SketchError.pointNotOnEntity(entityId: entity.id)
            }
            guard t > tolerance && t < (1.0 - tolerance) else {
                throw SketchError.invalidEntity("Split point cannot be at or beyond endpoints")
            }

            let first = SketchEntity.line(id: entity.id, start: sp, end: proj, isConstruction: entity.isConstruction)
            let second = SketchEntity.line(id: UUID(), start: proj, end: ep, isConstruction: entity.isConstruction)
            return (first, second)

        case "arc":
            guard let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint else {
                throw SketchError.invalidEntity("Arc entity \(entity.id) missing geometry")
            }
            let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
            let distFromCenter = hypot(point.x - cp.x, point.y - cp.y)
            guard abs(distFromCenter - r) <= 1e-3 else {
                throw SketchError.pointNotOnEntity(entityId: entity.id)
            }

            let cw = entity.isClockwise
            let totalSweep = arcSweepAngle(start: sp, end: ep, center: cp, clockwise: cw)
            let sAngle = atan2(sp.y - cp.y, sp.x - cp.x)
            let offset = arcAngleOffset(point: point, startAngle: sAngle, center: cp, clockwise: cw)
            guard offset > tolerance && offset < (totalSweep - tolerance) else {
                throw SketchError.invalidEntity("Split point cannot be at or beyond endpoints")
            }

            let projAngle = cw ? (sAngle - offset) : (sAngle + offset)
            let proj = cp + r * SIMD2<Double>(cos(projAngle), sin(projAngle))

            let first = SketchEntity.arc(
                id: entity.id,
                start: sp,
                end: proj,
                center: cp,
                clockwise: cw,
                isConstruction: entity.isConstruction
            )
            let second = SketchEntity.arc(
                id: UUID(),
                start: proj,
                end: ep,
                center: cp,
                clockwise: cw,
                isConstruction: entity.isConstruction
            )
            return (first, second)

        case "circle":
            guard let cp = entity.centerPoint, let r = entity.radius, r > 1e-6 else {
                throw SketchError.invalidEntity("Circle entity \(entity.id) missing geometry")
            }
            let distFromCenter = hypot(point.x - cp.x, point.y - cp.y)
            guard abs(distFromCenter - r) <= 1e-3 else {
                throw SketchError.pointNotOnEntity(entityId: entity.id)
            }

            let dir = (point - cp) / distFromCenter
            let p1 = cp + r * dir
            let p2 = cp - r * dir // antipode: 2C - p1

            let first = SketchEntity.arc(
                id: entity.id,
                start: p1,
                end: p2,
                center: cp,
                clockwise: false,
                isConstruction: entity.isConstruction
            )
            let second = SketchEntity.arc(
                id: UUID(),
                start: p2,
                end: p1,
                center: cp,
                clockwise: false,
                isConstruction: entity.isConstruction
            )
            return (first, second)

        default:
            throw SketchError.invalidEntity("Cannot split entity of kind \(entity.kind)")
        }
    }

    // MARK: - Hit Testing

    /// Hit-tests sketch entities against a 2D query point within a maximum distance.
    public static func hitTestEntity(
        at point: SIMD2<Double>,
        in entities: [SketchEntity],
        maxDistance: Double = 0.5
    ) -> SketchEntity? {
        var closest: (entity: SketchEntity, dist: Double)?

        for entity in entities {
            let dist: Double
            switch entity.kind {
            case "line":
                guard let sp = entity.startPoint, let ep = entity.endPoint else { continue }
                let v = ep - sp
                let lenSq = simd_dot(v, v)
                if lenSq < 1e-8 {
                    dist = hypot(point.x - sp.x, point.y - sp.y)
                } else {
                    let t = max(0.0, min(1.0, simd_dot(point - sp, v) / lenSq))
                    let proj = sp + t * v
                    dist = hypot(point.x - proj.x, point.y - proj.y)
                }

            case "circle":
                guard let cp = entity.centerPoint, let r = entity.radius else { continue }
                dist = abs(hypot(point.x - cp.x, point.y - cp.y) - r)

            case "arc":
                guard let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint else { continue }
                let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
                let radialDist = abs(hypot(point.x - cp.x, point.y - cp.y) - r)
                if isPointOnArc(point: point, start: sp, end: ep, center: cp, clockwise: entity.isClockwise) {
                    dist = radialDist
                } else {
                    let dStart = hypot(point.x - sp.x, point.y - sp.y)
                    let dEnd = hypot(point.x - ep.x, point.y - ep.y)
                    dist = min(dStart, dEnd)
                }

            default:
                continue
            }

            if dist <= maxDistance {
                if let current = closest {
                    if dist < current.dist {
                        closest = (entity, dist)
                    }
                } else {
                    closest = (entity, dist)
                }
            }
        }

        return closest?.entity
    }
}
