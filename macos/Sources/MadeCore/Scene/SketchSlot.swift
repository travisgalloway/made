import Foundation
import simd

/// The geometric variation of slot creation.
public enum SketchSlotKind: String, Sendable, Codable, CaseIterable, Equatable {
    case straight
    case arc
}

/// The entities, constraints, and auxiliary centerline resulting from a slot generation.
public struct SketchSlotResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public var centerline: SketchEntity?

    public init(
        entities: [SketchEntity],
        constraints: [SketchConstraint],
        centerline: SketchEntity? = nil
    ) {
        self.entities = entities
        self.constraints = constraints
        self.centerline = centerline
    }
}

/// Geometric engine generating mathematically exact straight and arc slots with appropriate 2D geometric constraints.
public enum SketchSlot {
    public static let minDimensionTolerance: Double = 1e-4

    /// Generates a straight slot defined by two center points and a slot width.
    ///
    /// Produces 2 parallel lines and 2 semicircular end caps with 4 coincidence constraints,
    /// 4 line-to-arc tangency constraints, and 1 parallel constraint.
    public static func makeStraightSlot(
        center1: SIMD2<Double>,
        center2: SIMD2<Double>,
        width: Double,
        addCenterline: Bool = false
    ) throws -> SketchSlotResult {
        guard width > minDimensionTolerance else {
            throw SketchError.degenerateSlot("Slot width (\(width)) must exceed \(minDimensionTolerance)")
        }
        let centerVec = center2 - center1
        let centerDist = hypot(centerVec.x, centerVec.y)
        guard centerDist > minDimensionTolerance else {
            throw SketchError.degenerateSlot("Center distance (\(centerDist)) must exceed \(minDimensionTolerance)")
        }

        let u = centerVec / centerDist
        let n = SIMD2<Double>(-u.y, u.x)
        let r = width / 2.0

        let p0 = center1 - n * r
        let p1 = center2 - n * r
        let p2 = center2 + n * r
        let p3 = center1 + n * r

        let line1 = SketchEntity.line(start: p0, end: p1)
        let line2 = SketchEntity.line(start: p2, end: p3)

        let arc1 = SketchEntity.arc(start: p1, end: p2, center: center2, clockwise: false)
        let arc2 = SketchEntity.arc(start: p3, end: p0, center: center1, clockwise: false)

        var entities = [line1, arc1, line2, arc2]
        let constraints: [SketchConstraint] = [
            // Closed perimeter coincidence
            SketchConstraint(kind: .coincident, entityIds: [line1.id, arc1.id]),
            SketchConstraint(kind: .coincident, entityIds: [arc1.id, line2.id]),
            SketchConstraint(kind: .coincident, entityIds: [line2.id, arc2.id]),
            SketchConstraint(kind: .coincident, entityIds: [arc2.id, line1.id]),

            // Tangency constraints
            SketchConstraint(kind: .tangent, entityIds: [line1.id, arc1.id]),
            SketchConstraint(kind: .tangent, entityIds: [arc1.id, line2.id]),
            SketchConstraint(kind: .tangent, entityIds: [line2.id, arc2.id]),
            SketchConstraint(kind: .tangent, entityIds: [arc2.id, line1.id]),

            // Parallel side lines
            SketchConstraint(kind: .parallel, entityIds: [line1.id, line2.id])
        ]

        var centerlineEntity: SketchEntity? = nil
        if addCenterline {
            let cl = SketchEntity.line(start: center1, end: center2, isConstruction: true)
            centerlineEntity = cl
            entities.append(cl)
        }

        return SketchSlotResult(
            entities: entities,
            constraints: constraints,
            centerline: centerlineEntity
        )
    }

    /// Generates an arc slot defined by center origin, radius, angular span, and width.
    ///
    /// Produces 2 concentric arcs and 2 semicircular end caps with 4 coincidence constraints,
    /// 4 tangency constraints, and 1 concentricity constraint.
    public static func makeArcSlot(
        center: SIMD2<Double>,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        width: Double,
        addCenterline: Bool = false
    ) throws -> SketchSlotResult {
        guard width > minDimensionTolerance else {
            throw SketchError.degenerateSlot("Arc slot width (\(width)) must exceed \(minDimensionTolerance)")
        }
        guard radius > width / 2.0 + minDimensionTolerance else {
            throw SketchError.degenerateSlot("Arc slot centerline radius (\(radius)) must exceed half width (\(width / 2.0))")
        }
        let span = abs(endAngle - startAngle)
        guard span > minDimensionTolerance else {
            throw SketchError.degenerateSlot("Arc slot angular span (\(span)) must exceed \(minDimensionTolerance)")
        }

        let rIn = radius - width / 2.0
        let rOut = radius + width / 2.0

        let (a0, a1) = startAngle < endAngle ? (startAngle, endAngle) : (endAngle, startAngle)

        let cStart = center + SIMD2<Double>(radius * cos(a0), radius * sin(a0))
        let cEnd = center + SIMD2<Double>(radius * cos(a1), radius * sin(a1))

        let pIn0 = center + SIMD2<Double>(rIn * cos(a0), rIn * sin(a0))
        let pOut0 = center + SIMD2<Double>(rOut * cos(a0), rOut * sin(a0))
        let pIn1 = center + SIMD2<Double>(rIn * cos(a1), rIn * sin(a1))
        let pOut1 = center + SIMD2<Double>(rOut * cos(a1), rOut * sin(a1))

        let innerArc = SketchEntity.arc(start: pIn0, end: pIn1, center: center, clockwise: false)
        let outerArc = SketchEntity.arc(start: pOut1, end: pOut0, center: center, clockwise: true)
        let capEnd = SketchEntity.arc(start: pIn1, end: pOut1, center: cEnd, clockwise: false)
        let capStart = SketchEntity.arc(start: pOut0, end: pIn0, center: cStart, clockwise: false)

        var entities = [innerArc, capEnd, outerArc, capStart]

        let constraints: [SketchConstraint] = [
            // Closed loop coincidence
            SketchConstraint(kind: .coincident, entityIds: [innerArc.id, capEnd.id]),
            SketchConstraint(kind: .coincident, entityIds: [capEnd.id, outerArc.id]),
            SketchConstraint(kind: .coincident, entityIds: [outerArc.id, capStart.id]),
            SketchConstraint(kind: .coincident, entityIds: [capStart.id, innerArc.id]),

            // Concentricity between inner and outer arcs
            SketchConstraint(kind: .concentric, entityIds: [innerArc.id, outerArc.id]),

            // Tangency constraints
            SketchConstraint(kind: .tangent, entityIds: [innerArc.id, capEnd.id]),
            SketchConstraint(kind: .tangent, entityIds: [capEnd.id, outerArc.id]),
            SketchConstraint(kind: .tangent, entityIds: [outerArc.id, capStart.id]),
            SketchConstraint(kind: .tangent, entityIds: [capStart.id, innerArc.id])
        ]

        var centerlineEntity: SketchEntity? = nil
        if addCenterline {
            let cl = SketchEntity.arc(start: cStart, end: cEnd, center: center, clockwise: false, isConstruction: true)
            centerlineEntity = cl
            entities.append(cl)
        }

        return SketchSlotResult(
            entities: entities,
            constraints: constraints,
            centerline: centerlineEntity
        )
    }
}
