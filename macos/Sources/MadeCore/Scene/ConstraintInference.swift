import Foundation
import simd

/// Predictive inference engine detecting candidate geometric constraints live from entity geometry (Invariant 9, ADR-D4, #37).
public struct ConstraintInference: Sendable {

    public static let defaultToleranceAngleRad: Double = 5.0 * .pi / 180.0 // 5 degrees
    public static let defaultToleranceDistance: Double = 1.0 // 1.0 mm

    /// Evaluates candidate constraints between two entities (and an optional reference axis for symmetry).
    public static func inferConstraints(
        between entityA: SketchEntity,
        and entityB: SketchEntity,
        referenceEntity: SketchEntity? = nil,
        toleranceAngleRad: Double = defaultToleranceAngleRad,
        toleranceDistance: Double = defaultToleranceDistance
    ) -> [SketchConstraint] {
        guard entityA.id != entityB.id else { return [] }
        var inferred: [SketchConstraint] = []

        // Line vs Line
        if let lineA = entityA.asLine(), let lineB = entityB.asLine() {
            let vA = lineA.end - lineA.start
            let vB = lineB.end - lineB.start
            let lenA = hypot(vA.x, vA.y)
            let lenB = hypot(vB.x, vB.y)

            if lenA > 1e-5 && lenB > 1e-5 {
                let uA = vA / lenA
                let uB = vB / lenB
                let dot = abs(uA.x * uB.x + uA.y * uB.y)
                let cross = abs(uA.x * uB.y - uA.y * uB.x)

                // Parallel check: angle difference <= tolerance
                let angleParallel = asin(min(1.0, cross))
                if angleParallel <= toleranceAngleRad && dot >= cos(toleranceAngleRad) {
                    inferred.append(SketchConstraint(
                        kind: .parallel,
                        entityIds: [entityA.id, entityB.id],
                        isTemporary: true
                    ))
                }

                // Perpendicular check: dot product near 0
                let anglePerp = asin(min(1.0, dot))
                if anglePerp <= toleranceAngleRad && cross >= cos(toleranceAngleRad) {
                    inferred.append(SketchConstraint(
                        kind: .perpendicular,
                        entityIds: [entityA.id, entityB.id],
                        isTemporary: true
                    ))
                }
            }
        }

        // Line vs Circle (Tangency)
        if let line = entityA.asLine(), let circle = entityB.asCircle() {
            if isLineTangentToCircle(line: line, circle: circle, tolerance: toleranceDistance) {
                inferred.append(SketchConstraint(kind: .tangent, entityIds: [entityA.id, entityB.id], isTemporary: true))
            }
        } else if let circle = entityA.asCircle(), let line = entityB.asLine() {
            if isLineTangentToCircle(line: line, circle: circle, tolerance: toleranceDistance) {
                inferred.append(SketchConstraint(kind: .tangent, entityIds: [entityA.id, entityB.id], isTemporary: true))
            }
        }

        // Circle vs Circle (Tangency and Concentricity)
        if let cA = entityA.asCircle(), let cB = entityB.asCircle() {
            let dist = hypot(cA.center.x - cB.center.x, cA.center.y - cB.center.y)

            // Concentricity
            if dist <= toleranceDistance {
                inferred.append(SketchConstraint(kind: .concentric, entityIds: [entityA.id, entityB.id], isTemporary: true))
            }

            // Tangency (external or internal)
            let dExt = cA.radius + cB.radius
            let dInt = abs(cA.radius - cB.radius)
            if abs(dist - dExt) <= toleranceDistance || (dInt > 1e-4 && abs(dist - dInt) <= toleranceDistance) {
                inferred.append(SketchConstraint(kind: .tangent, entityIds: [entityA.id, entityB.id], isTemporary: true))
            }
        }

        // Symmetry across reference axis
        if let refAxis = referenceEntity, let axis = refAxis.asLine(), refAxis.id != entityA.id && refAxis.id != entityB.id {
            if isSymmetric(entityA: entityA, entityB: entityB, axis: axis, tolerance: toleranceDistance) {
                inferred.append(SketchConstraint(
                    kind: .symmetric,
                    entityIds: [entityA.id, entityB.id],
                    referenceEntityId: refAxis.id,
                    isTemporary: true
                ))
            }
        }

        return inferred
    }

    /// Generates batch candidate inferences across all active sketch entities.
    public static func inferCandidates(
        for entities: [SketchEntity],
        existingConstraints: [SketchConstraint] = [],
        toleranceAngleRad: Double = defaultToleranceAngleRad,
        toleranceDistance: Double = defaultToleranceDistance
    ) -> [SketchConstraint] {
        guard entities.count >= 2 else { return [] }
        var results: [SketchConstraint] = []
        let lines = entities.filter { $0.kind == "line" }

        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                let eA = entities[i]
                let eB = entities[j]

                let directInferred = inferConstraints(
                    between: eA,
                    and: eB,
                    toleranceAngleRad: toleranceAngleRad,
                    toleranceDistance: toleranceDistance
                )
                results.append(contentsOf: directInferred)

                // Test symmetry against available axis lines
                for axis in lines where axis.id != eA.id && axis.id != eB.id {
                    let symInferred = inferConstraints(
                        between: eA,
                        and: eB,
                        referenceEntity: axis,
                        toleranceAngleRad: toleranceAngleRad,
                        toleranceDistance: toleranceDistance
                    )
                    results.append(contentsOf: symInferred)
                }
            }
        }

        // Deduplicate and filter out constraints already present in existingConstraints
        return results.filter { candidate in
            !isConstraintAlreadyPresent(candidate, in: existingConstraints)
        }
    }

    // MARK: - Private Geometric Helpers

    private static func isLineTangentToCircle(line: (start: SIMD2<Double>, end: SIMD2<Double>), circle: (center: SIMD2<Double>, radius: Double), tolerance: Double) -> Bool {
        let v = line.end - line.start
        let len = hypot(v.x, v.y)
        guard len > 1e-5 else { return false }
        let cross = (line.end.x - line.start.x) * (circle.center.y - line.start.y) - (line.end.y - line.start.y) * (circle.center.x - line.start.x)
        let dist = abs(cross) / len
        return abs(dist - circle.radius) <= tolerance
    }

    private static func isSymmetric(entityA: SketchEntity, entityB: SketchEntity, axis: (start: SIMD2<Double>, end: SIMD2<Double>), tolerance: Double) -> Bool {
        let vAxis = axis.end - axis.start
        let lenAxis = hypot(vAxis.x, vAxis.y)
        guard lenAxis > 1e-5 else { return false }
        let uAxis = vAxis / lenAxis
        let nAxis = SIMD2<Double>(-uAxis.y, uAxis.x)

        if let lA = entityA.asLine(), let lB = entityB.asLine() {
            // Check direct pair or flipped pair
            let check1 = isPointPairSymmetric(pA: lA.start, pB: lB.start, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis, tol: tolerance)
                      && isPointPairSymmetric(pA: lA.end, pB: lB.end, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis, tol: tolerance)
            let check2 = isPointPairSymmetric(pA: lA.start, pB: lB.end, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis, tol: tolerance)
                      && isPointPairSymmetric(pA: lA.end, pB: lB.start, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis, tol: tolerance)
            return check1 || check2
        } else if let cA = entityA.asCircle(), let cB = entityB.asCircle() {
            let centerSym = isPointPairSymmetric(pA: cA.center, pB: cB.center, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis, tol: tolerance)
            let radiusEqual = abs(cA.radius - cB.radius) <= tolerance
            return centerSym && radiusEqual
        }
        return false
    }

    private static func isPointPairSymmetric(pA: SIMD2<Double>, pB: SIMD2<Double>, axisStart: SIMD2<Double>, uAxis: SIMD2<Double>, nAxis: SIMD2<Double>, tol: Double) -> Bool {
        let mid = (pA + pB) * 0.5
        let distFromAxis = abs((mid.x - axisStart.x) * nAxis.x + (mid.y - axisStart.y) * nAxis.y)
        let perpDot = abs((pB.x - pA.x) * uAxis.x + (pB.y - pA.y) * uAxis.y)
        return distFromAxis <= tol && perpDot <= tol
    }

    private static func isConstraintAlreadyPresent(_ candidate: SketchConstraint, in existing: [SketchConstraint]) -> Bool {
        let candidateSet = Set(candidate.entityIds)
        return existing.contains { c in
            c.kind == candidate.kind && Set(c.entityIds) == candidateSet && c.referenceEntityId == candidate.referenceEntityId
        }
    }
}

private extension SketchEntity {
    func asLine() -> (start: SIMD2<Double>, end: SIMD2<Double>)? {
        guard kind == "line", let s = startPoint, let e = endPoint else { return nil }
        return (start: s, end: e)
    }

    func asCircle() -> (center: SIMD2<Double>, radius: Double)? {
        guard kind == "circle", let c = centerPoint, let r = radius else { return nil }
        return (center: c, radius: r)
    }
}
