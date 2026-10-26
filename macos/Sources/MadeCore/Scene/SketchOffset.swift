import Foundation
import simd

/// The entities and geometric constraints resulting from a 2D sketch offset operation.
public struct SketchOffsetResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(entities: [SketchEntity], constraints: [SketchConstraint]) {
        self.entities = entities
        self.constraints = constraints
    }
}

/// Geometric engine generating offset lines, concentric circles/arcs, and trimmed/extended connected chains.
public enum SketchOffset {
    public static let minDimensionTolerance: Double = 1e-4

    /// Offsets a collection of sketch entities by a perpendicular/radial distance.
    ///
    /// Generates `.parallel` constraints for lines, `.concentric` constraints for circles and arcs,
    /// trims or extends adjacent segments in connected chains at corners, and produces corner `.coincident` constraints.
    public static func makeOffset(entities: [SketchEntity], distance: Double) throws -> SketchOffsetResult {
        guard !entities.isEmpty else {
            throw SketchError.degenerateOffset("No entities provided to offset")
        }
        guard abs(distance) > minDimensionTolerance else {
            throw SketchError.degenerateOffset("Offset distance (\(distance)) must exceed \(minDimensionTolerance)")
        }

        var offsetEntities: [SketchEntity] = []
        var generatedConstraints: [SketchConstraint] = []

        // 1. Generate individual offset entities and base constraints
        for entity in entities {
            switch entity.kind {
            case "line":
                guard let s = entity.startPoint, let e = entity.endPoint else {
                    throw SketchError.degenerateOffset("Line entity \(entity.id) is missing endpoints")
                }
                let v = e - s
                let len = hypot(v.x, v.y)
                guard len > minDimensionTolerance else {
                    throw SketchError.degenerateOffset("Line entity \(entity.id) has zero length (\(len))")
                }
                let n = SIMD2<Double>(-v.y / len, v.x / len)
                let sPrime = s + n * distance
                let ePrime = e + n * distance
                let offsetLine = SketchEntity.line(
                    start: sPrime,
                    end: ePrime,
                    isConstruction: entity.isConstruction
                )
                offsetEntities.append(offsetLine)
                generatedConstraints.append(SketchConstraint(
                    kind: .parallel,
                    entityIds: [entity.id, offsetLine.id]
                ))

            case "circle":
                guard let c = entity.centerPoint, let r = entity.radius else {
                    throw SketchError.degenerateOffset("Circle entity \(entity.id) is missing center or radius")
                }
                let rPrime = r + distance
                guard rPrime > minDimensionTolerance else {
                    throw SketchError.degenerateOffset("Offset circle radius (\(rPrime)) must exceed \(minDimensionTolerance)")
                }
                let offsetCircle = SketchEntity.circle(
                    center: c,
                    radius: rPrime,
                    isConstruction: entity.isConstruction
                )
                offsetEntities.append(offsetCircle)
                generatedConstraints.append(SketchConstraint(
                    kind: .concentric,
                    entityIds: [entity.id, offsetCircle.id]
                ))

            case "arc":
                guard let c = entity.centerPoint, let s = entity.startPoint, let e = entity.endPoint, let r = entity.radius else {
                    throw SketchError.degenerateOffset("Arc entity \(entity.id) is missing center, endpoints, or radius")
                }
                let rPrime = r + distance
                guard rPrime > minDimensionTolerance else {
                    throw SketchError.degenerateOffset("Offset arc radius (\(rPrime)) must exceed \(minDimensionTolerance)")
                }
                let us = (s - c) / r
                let ue = (e - c) / r
                let sPrime = c + us * rPrime
                let ePrime = c + ue * rPrime
                let offsetArc = SketchEntity.arc(
                    start: sPrime,
                    end: ePrime,
                    center: c,
                    clockwise: entity.isClockwise,
                    isConstruction: entity.isConstruction
                )
                offsetEntities.append(offsetArc)
                generatedConstraints.append(SketchConstraint(
                    kind: .concentric,
                    entityIds: [entity.id, offsetArc.id]
                ))

            default:
                throw SketchError.degenerateOffset("Unsupported entity kind '\(entity.kind)' for offset")
            }
        }

        // 2. Corner intersection, trimming, and coincident constraint generation for connected chains
        if entities.count >= 2 {
            for i in 0..<(entities.count - 1) {
                for j in (i + 1)..<entities.count {
                    let origA = entities[i]
                    let origB = entities[j]

                    guard let sA = origA.startPoint, let eA = origA.endPoint,
                          let sB = origB.startPoint, let eB = origB.endPoint else {
                        continue
                    }

                    // Check for endpoint coincidence in the original entities
                    let dEE = hypot(eA.x - eB.x, eA.y - eB.y)
                    let dES = hypot(eA.x - sB.x, eA.y - sB.y)
                    let dSE = hypot(sA.x - eB.x, sA.y - eB.y)
                    let dSS = hypot(sA.x - sB.x, sA.y - sB.y)

                    let tol = 1e-4
                    let match: (aIsEnd: Bool, bIsEnd: Bool, origCorner: SIMD2<Double>)? = {
                        if dES < tol { return (true, false, (eA + sB) * 0.5) }
                        if dEE < tol { return (true, true, (eA + eB) * 0.5) }
                        if dSS < tol { return (false, false, (sA + sB) * 0.5) }
                        if dSE < tol { return (false, true, (sA + eB) * 0.5) }
                        return nil
                    }()

                    guard let (aIsEnd, bIsEnd, origCorner) = match else { continue }

                    if let intPt = intersectInfiniteCurves(
                        e1: offsetEntities[i],
                        e2: offsetEntities[j],
                        near: origCorner
                    ) {
                        // Update entity i endpoint
                        if aIsEnd {
                            offsetEntities[i].data["endX"] = intPt.x
                            offsetEntities[i].data["endY"] = intPt.y
                        } else {
                            offsetEntities[i].data["startX"] = intPt.x
                            offsetEntities[i].data["startY"] = intPt.y
                        }

                        // Update entity j endpoint
                        if bIsEnd {
                            offsetEntities[j].data["endX"] = intPt.x
                            offsetEntities[j].data["endY"] = intPt.y
                        } else {
                            offsetEntities[j].data["startX"] = intPt.x
                            offsetEntities[j].data["startY"] = intPt.y
                        }

                        // Add coincident constraint at corner
                        generatedConstraints.append(SketchConstraint(
                            kind: .coincident,
                            entityIds: [offsetEntities[i].id, offsetEntities[j].id]
                        ))
                    }
                }
            }
        }

        return SketchOffsetResult(entities: offsetEntities, constraints: generatedConstraints)
    }

    // MARK: - Curve Intersection Math

    private static func intersectInfiniteCurves(
        e1: SketchEntity,
        e2: SketchEntity,
        near: SIMD2<Double>
    ) -> SIMD2<Double>? {
        if e1.kind == "line" && e2.kind == "line" {
            guard let p1 = e1.startPoint, let p2 = e1.endPoint,
                  let p3 = e2.startPoint, let p4 = e2.endPoint else { return nil }
            let d1 = p2 - p1
            let d2 = p4 - p3
            let cross = d1.x * d2.y - d1.y * d2.x
            guard abs(cross) > 1e-9 else { return nil }
            let dp = p3 - p1
            let t = (dp.x * d2.y - dp.y * d2.x) / cross
            return p1 + t * d1
        }

        if (e1.kind == "line" && e2.kind == "arc") || (e1.kind == "arc" && e2.kind == "line") {
            let line = e1.kind == "line" ? e1 : e2
            let arc = e1.kind == "arc" ? e1 : e2
            guard let p1 = line.startPoint, let p2 = line.endPoint,
                  let c = arc.centerPoint, let r = arc.radius else { return nil }
            let d = p2 - p1
            let a = d.x * d.x + d.y * d.y
            guard a > 1e-12 else { return nil }
            let delta = p1 - c
            let b = 2.0 * (delta.x * d.x + delta.y * d.y)
            let cVal = delta.x * delta.x + delta.y * delta.y - r * r
            let disc = b * b - 4.0 * a * cVal
            guard disc >= -1e-9 else { return nil }
            let sqrtDisc = disc > 0 ? sqrt(disc) : 0.0
            let t1 = (-b - sqrtDisc) / (2.0 * a)
            let t2 = (-b + sqrtDisc) / (2.0 * a)
            let pt1 = p1 + t1 * d
            let pt2 = p1 + t2 * d
            let dist1 = hypot(pt1.x - near.x, pt1.y - near.y)
            let dist2 = hypot(pt2.x - near.x, pt2.y - near.y)
            return dist1 <= dist2 ? pt1 : pt2
        }

        if e1.kind == "arc" && e2.kind == "arc" {
            guard let c1 = e1.centerPoint, let r1 = e1.radius,
                  let c2 = e2.centerPoint, let r2 = e2.radius else { return nil }
            let dVec = c2 - c1
            let d = hypot(dVec.x, dVec.y)
            guard d > 1e-9, d <= (r1 + r2 + 1e-4), d >= (abs(r1 - r2) - 1e-4) else { return nil }
            let a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
            let hSq = max(0.0, r1 * r1 - a * a)
            let h = sqrt(hSq)
            let p0 = c1 + (a / d) * dVec
            let perp = SIMD2<Double>(-dVec.y / d, dVec.x / d)
            let pt1 = p0 + h * perp
            let pt2 = p0 - h * perp
            let dist1 = hypot(pt1.x - near.x, pt1.y - near.y)
            let dist2 = hypot(pt2.x - near.x, pt2.y - near.y)
            return dist1 <= dist2 ? pt1 : pt2
        }

        return nil
    }
}
