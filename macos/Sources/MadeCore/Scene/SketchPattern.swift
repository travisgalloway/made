import Foundation
import simd

/// The entities and geometric constraints resulting from a 2D sketch pattern operation.
public struct SketchPatternResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(entities: [SketchEntity], constraints: [SketchConstraint]) {
        self.entities = entities
        self.constraints = constraints
    }
}

/// Geometric engine replicating sketch entities in 1D/2D linear grids and circular distributions.
public enum SketchPattern {
    public static let minDimensionTolerance: Double = 1e-4

    /// Replicates sketch entities along 1 or 2 linear directions with spacing and count.
    ///
    /// Generates `.parallel` and `.equal` constraints for lines, `.equal` constraints for circles and arcs,
    /// and preserves internal coincident connections across patterned copies.
    public static func makeLinearPattern(
        entities: [SketchEntity],
        direction1: SIMD2<Double>,
        spacing1: Double,
        count1: Int,
        direction2: SIMD2<Double>? = nil,
        spacing2: Double = 0.0,
        count2: Int = 1
    ) throws -> SketchPatternResult {
        guard !entities.isEmpty else {
            throw SketchError.degeneratePattern("No entities provided to pattern")
        }
        guard count1 >= 1, count2 >= 1 else {
            throw SketchError.degeneratePattern("Pattern counts must be at least 1 (got count1: \(count1), count2: \(count2))")
        }
        guard count1 > 1 || count2 > 1 else {
            throw SketchError.degeneratePattern("Total pattern count must exceed 1")
        }

        let len1 = hypot(direction1.x, direction1.y)
        if count1 > 1 {
            guard len1 > minDimensionTolerance else {
                throw SketchError.degeneratePattern("Pattern direction1 has zero length (\(len1))")
            }
            guard abs(spacing1) > minDimensionTolerance else {
                throw SketchError.degeneratePattern("Pattern spacing1 (\(spacing1)) must exceed \(minDimensionTolerance)")
            }
        }
        let u1 = len1 > 0 ? direction1 / len1 : SIMD2<Double>(1, 0)

        var u2 = SIMD2<Double>(0, 1)
        if count2 > 1 {
            guard let dir2 = direction2 else {
                throw SketchError.degeneratePattern("Direction 2 must be provided when count2 > 1")
            }
            let len2 = hypot(dir2.x, dir2.y)
            guard len2 > minDimensionTolerance else {
                throw SketchError.degeneratePattern("Pattern direction2 has zero length (\(len2))")
            }
            guard abs(spacing2) > minDimensionTolerance else {
                throw SketchError.degeneratePattern("Pattern spacing2 (\(spacing2)) must exceed \(minDimensionTolerance)")
            }
            u2 = dir2 / len2
        }

        // Identify internal coincident joints among source entities
        let internalJoints = findInternalCoincidentJoints(in: entities)

        var patternedEntities: [SketchEntity] = []
        var generatedConstraints: [SketchConstraint] = []

        for i in 0..<count1 {
            for j in 0..<count2 {
                if i == 0 && j == 0 { continue }

                let translation = Double(i) * spacing1 * u1 + Double(j) * spacing2 * u2
                var instanceEntities: [SketchEntity] = []

                for orig in entities {
                    let copy = translateEntity(orig, by: translation)
                    instanceEntities.append(copy)
                    patternedEntities.append(copy)

                    switch orig.kind {
                    case "line":
                        generatedConstraints.append(SketchConstraint(
                            kind: .parallel,
                            entityIds: [orig.id, copy.id]
                        ))
                        generatedConstraints.append(SketchConstraint(
                            kind: .equal,
                            entityIds: [orig.id, copy.id]
                        ))
                    case "circle", "arc":
                        generatedConstraints.append(SketchConstraint(
                            kind: .equal,
                            entityIds: [orig.id, copy.id]
                        ))
                    default:
                        break
                    }
                }

                // Replicate internal coincident joints for this pattern instance
                for (idxA, idxB) in internalJoints {
                    let copyA = instanceEntities[idxA]
                    let copyB = instanceEntities[idxB]
                    generatedConstraints.append(SketchConstraint(
                        kind: .coincident,
                        entityIds: [copyA.id, copyB.id]
                    ))
                }
            }
        }

        return SketchPatternResult(entities: patternedEntities, constraints: generatedConstraints)
    }

    /// Replicates sketch entities around a center point with count and angular span.
    ///
    /// Generates `.equal` constraints for replicated lines, circles, and arcs,
    /// and preserves internal coincident connections across patterned copies.
    public static func makeCircularPattern(
        entities: [SketchEntity],
        center: SIMD2<Double>,
        count: Int,
        totalAngle: Double = 2.0 * .pi,
        equalSpacing: Bool = true
    ) throws -> SketchPatternResult {
        guard !entities.isEmpty else {
            throw SketchError.degeneratePattern("No entities provided to pattern")
        }
        guard count >= 2 else {
            throw SketchError.degeneratePattern("Circular pattern count (\(count)) must be at least 2")
        }
        guard abs(totalAngle) > minDimensionTolerance else {
            throw SketchError.degeneratePattern("Circular pattern total angle (\(totalAngle)) must exceed \(minDimensionTolerance)")
        }

        let isFullCircle = abs(abs(totalAngle) - 2.0 * .pi) < 1e-4
        let stepAngle: Double = {
            if equalSpacing {
                return isFullCircle ? (totalAngle / Double(count)) : (totalAngle / Double(count - 1))
            } else {
                return totalAngle
            }
        }()

        let internalJoints = findInternalCoincidentJoints(in: entities)

        var patternedEntities: [SketchEntity] = []
        var generatedConstraints: [SketchConstraint] = []

        for k in 1..<count {
            let theta = Double(k) * stepAngle
            var instanceEntities: [SketchEntity] = []

            for orig in entities {
                let copy = rotateEntity(orig, center: center, angle: theta)
                instanceEntities.append(copy)
                patternedEntities.append(copy)

                switch orig.kind {
                case "line", "circle", "arc":
                    generatedConstraints.append(SketchConstraint(
                        kind: .equal,
                        entityIds: [orig.id, copy.id]
                    ))
                default:
                    break
                }
            }

            for (idxA, idxB) in internalJoints {
                let copyA = instanceEntities[idxA]
                let copyB = instanceEntities[idxB]
                generatedConstraints.append(SketchConstraint(
                    kind: .coincident,
                    entityIds: [copyA.id, copyB.id]
                ))
            }
        }

        return SketchPatternResult(entities: patternedEntities, constraints: generatedConstraints)
    }

    // MARK: - Internal Joint Tracking

    private static func findInternalCoincidentJoints(in entities: [SketchEntity]) -> [(Int, Int)] {
        var joints: [(Int, Int)] = []
        guard entities.count >= 2 else { return joints }

        for i in 0..<(entities.count - 1) {
            for j in (i + 1)..<entities.count {
                let eA = entities[i]
                let eB = entities[j]

                let ptsA = collectEndpoints(of: eA)
                let ptsB = collectEndpoints(of: eB)

                var matched = false
                for pA in ptsA {
                    for pB in ptsB {
                        if hypot(pA.x - pB.x, pA.y - pB.y) < 1e-4 {
                            joints.append((i, j))
                            matched = true
                            break
                        }
                    }
                    if matched { break }
                }
            }
        }
        return joints
    }

    private static func collectEndpoints(of entity: SketchEntity) -> [SIMD2<Double>] {
        if let pt = entity.pointPosition { return [pt] }
        var pts: [SIMD2<Double>] = []
        if let s = entity.startPoint { pts.append(s) }
        if let e = entity.endPoint { pts.append(e) }
        return pts
    }

    // MARK: - Entity Transforms

    private static func translateEntity(_ orig: SketchEntity, by delta: SIMD2<Double>) -> SketchEntity {
        switch orig.kind {
        case "line":
            let s = (orig.startPoint ?? .zero) + delta
            let e = (orig.endPoint ?? .zero) + delta
            return SketchEntity.line(start: s, end: e, isConstruction: orig.isConstruction)

        case "circle":
            let c = (orig.centerPoint ?? .zero) + delta
            return SketchEntity.circle(center: c, radius: orig.radius ?? 10.0, isConstruction: orig.isConstruction)

        case "arc":
            let s = (orig.startPoint ?? .zero) + delta
            let e = (orig.endPoint ?? .zero) + delta
            let c = (orig.centerPoint ?? .zero) + delta
            return SketchEntity.arc(start: s, end: e, center: c, clockwise: orig.isClockwise, isConstruction: orig.isConstruction)

        case "ellipse":
            let c = (orig.centerPoint ?? .zero) + delta
            return SketchEntity.ellipse(
                center: c,
                radiusX: orig.radiusX ?? 10.0,
                radiusY: orig.radiusY ?? 5.0,
                rotation: orig.rotationAngle ?? 0.0,
                isConstruction: orig.isConstruction
            )

        case "ellipticalArc":
            let c = (orig.centerPoint ?? .zero) + delta
            return SketchEntity.ellipticalArc(
                center: c,
                radiusX: orig.radiusX ?? 10.0,
                radiusY: orig.radiusY ?? 5.0,
                rotation: orig.rotationAngle ?? 0.0,
                startAngle: orig.startAngle ?? 0.0,
                endAngle: orig.endAngle ?? .pi,
                clockwise: orig.isClockwise,
                isConstruction: orig.isConstruction
            )

        case "point":
            let p = (orig.pointPosition ?? .zero) + delta
            return SketchEntity.point(position: p, isConstruction: orig.isConstruction)

        case "text":
            let o = (orig.origin ?? .zero) + delta
            return SketchEntity.text(
                text: orig.textString ?? "",
                origin: o,
                fontSize: orig.fontSize ?? 12.0,
                fontName: orig.fontName ?? "Helvetica",
                isConstruction: orig.isConstruction
            )

        default:
            var copy = orig
            copy.id = UUID()
            return copy
        }
    }

    private static func rotateEntity(_ orig: SketchEntity, center: SIMD2<Double>, angle: Double) -> SketchEntity {
        let cosA = cos(angle)
        let sinA = sin(angle)

        func rot(_ p: SIMD2<Double>) -> SIMD2<Double> {
            let dx = p.x - center.x
            let dy = p.y - center.y
            return center + SIMD2<Double>(dx * cosA - dy * sinA, dx * sinA + dy * cosA)
        }

        switch orig.kind {
        case "line":
            let s = rot(orig.startPoint ?? .zero)
            let e = rot(orig.endPoint ?? .zero)
            return SketchEntity.line(start: s, end: e, isConstruction: orig.isConstruction)

        case "circle":
            let c = rot(orig.centerPoint ?? .zero)
            return SketchEntity.circle(center: c, radius: orig.radius ?? 10.0, isConstruction: orig.isConstruction)

        case "arc":
            let s = rot(orig.startPoint ?? .zero)
            let e = rot(orig.endPoint ?? .zero)
            let c = rot(orig.centerPoint ?? .zero)
            return SketchEntity.arc(start: s, end: e, center: c, clockwise: orig.isClockwise, isConstruction: orig.isConstruction)

        case "ellipse":
            let c = rot(orig.centerPoint ?? .zero)
            let newRot = (orig.rotationAngle ?? 0.0) + angle
            return SketchEntity.ellipse(
                center: c,
                radiusX: orig.radiusX ?? 10.0,
                radiusY: orig.radiusY ?? 5.0,
                rotation: newRot,
                isConstruction: orig.isConstruction
            )

        case "ellipticalArc":
            let c = rot(orig.centerPoint ?? .zero)
            let newRot = (orig.rotationAngle ?? 0.0) + angle
            let newStart = (orig.startAngle ?? 0.0) + angle
            let newEnd = (orig.endAngle ?? .pi) + angle
            return SketchEntity.ellipticalArc(
                center: c,
                radiusX: orig.radiusX ?? 10.0,
                radiusY: orig.radiusY ?? 5.0,
                rotation: newRot,
                startAngle: newStart,
                endAngle: newEnd,
                clockwise: orig.isClockwise,
                isConstruction: orig.isConstruction
            )

        case "point":
            let p = rot(orig.pointPosition ?? .zero)
            return SketchEntity.point(position: p, isConstruction: orig.isConstruction)

        case "text":
            let o = rot(orig.origin ?? .zero)
            return SketchEntity.text(
                text: orig.textString ?? "",
                origin: o,
                fontSize: orig.fontSize ?? 12.0,
                fontName: orig.fontName ?? "Helvetica",
                isConstruction: orig.isConstruction
            )

        default:
            var copy = orig
            copy.id = UUID()
            return copy
        }
    }
}
