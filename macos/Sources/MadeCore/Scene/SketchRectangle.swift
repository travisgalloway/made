import Foundation
import simd

/// The geometric variation of rectangle creation.
public enum SketchRectangleKind: String, Sendable, Codable, CaseIterable, Equatable {
    case corner
    case center
    case threePoint
}

/// The entities, constraints, and ordered corner vertices resulting from a rectangle generation.
public struct SketchRectangleResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public var corners: [SIMD2<Double>]

    public init(
        entities: [SketchEntity],
        constraints: [SketchConstraint],
        corners: [SIMD2<Double>]
    ) {
        self.entities = entities
        self.constraints = constraints
        self.corners = corners
    }
}

/// Geometric engine generating mathematically exact corner, center, and three-point rectangles
/// with appropriate 2D geometric constraints (coincident, horizontal, vertical, parallel, perpendicular).
public enum SketchRectangle {
    public static let minDimensionTolerance: Double = 1e-4

    /// Generates a corner rectangle defined by two opposing diagonal corner points.
    ///
    /// Produces 4 perimeter lines with 4 corner coincident constraints, 2 horizontal constraints,
    /// and 2 vertical constraints (resulting in 4 degrees of freedom).
    public static func makeCornerRectangle(
        corner1: SIMD2<Double>,
        corner2: SIMD2<Double>
    ) throws -> SketchRectangleResult {
        let width = abs(corner2.x - corner1.x)
        let height = abs(corner2.y - corner1.y)

        guard width > minDimensionTolerance && height > minDimensionTolerance else {
            throw SketchError.degenerateRectangle(
                "Corner rectangle width (\(width)) and height (\(height)) must exceed \(minDimensionTolerance)"
            )
        }

        let p0 = SIMD2<Double>(corner1.x, corner1.y)
        let p1 = SIMD2<Double>(corner2.x, corner1.y)
        let p2 = SIMD2<Double>(corner2.x, corner2.y)
        let p3 = SIMD2<Double>(corner1.x, corner2.y)

        let l0 = SketchEntity.line(start: p0, end: p1)
        let l1 = SketchEntity.line(start: p1, end: p2)
        let l2 = SketchEntity.line(start: p2, end: p3)
        let l3 = SketchEntity.line(start: p3, end: p0)

        let constraints: [SketchConstraint] = [
            SketchConstraint(kind: .coincident, entityIds: [l0.id, l1.id]),
            SketchConstraint(kind: .coincident, entityIds: [l1.id, l2.id]),
            SketchConstraint(kind: .coincident, entityIds: [l2.id, l3.id]),
            SketchConstraint(kind: .coincident, entityIds: [l3.id, l0.id]),
            SketchConstraint(kind: .horizontal, entityIds: [l0.id]),
            SketchConstraint(kind: .horizontal, entityIds: [l2.id]),
            SketchConstraint(kind: .vertical, entityIds: [l1.id]),
            SketchConstraint(kind: .vertical, entityIds: [l3.id])
        ]

        return SketchRectangleResult(
            entities: [l0, l1, l2, l3],
            constraints: constraints,
            corners: [p0, p1, p2, p3]
        )
    }

    /// Generates a center rectangle defined by a center origin and one outer corner point.
    ///
    /// Produces 4 perimeter lines, 2 diagonal construction lines, 4 perimeter coincident constraints,
    /// 4 diagonal coincident constraints, 2 horizontal constraints, and 2 vertical constraints.
    public static func makeCenterRectangle(
        center: SIMD2<Double>,
        corner: SIMD2<Double>
    ) throws -> SketchRectangleResult {
        let halfWidth = abs(corner.x - center.x)
        let halfHeight = abs(corner.y - center.y)

        guard halfWidth > minDimensionTolerance && halfHeight > minDimensionTolerance else {
            throw SketchError.degenerateRectangle(
                "Center rectangle half-width (\(halfWidth)) and half-height (\(halfHeight)) must exceed \(minDimensionTolerance)"
            )
        }

        let p0 = SIMD2<Double>(2.0 * center.x - corner.x, 2.0 * center.y - corner.y)
        let p1 = SIMD2<Double>(corner.x, p0.y)
        let p2 = corner
        let p3 = SIMD2<Double>(p0.x, corner.y)

        let l0 = SketchEntity.line(start: p0, end: p1)
        let l1 = SketchEntity.line(start: p1, end: p2)
        let l2 = SketchEntity.line(start: p2, end: p3)
        let l3 = SketchEntity.line(start: p3, end: p0)

        let d1 = SketchEntity.line(start: p0, end: p2, isConstruction: true)
        let d2 = SketchEntity.line(start: p1, end: p3, isConstruction: true)

        let constraints: [SketchConstraint] = [
            // Perimeter coincident
            SketchConstraint(kind: .coincident, entityIds: [l0.id, l1.id]),
            SketchConstraint(kind: .coincident, entityIds: [l1.id, l2.id]),
            SketchConstraint(kind: .coincident, entityIds: [l2.id, l3.id]),
            SketchConstraint(kind: .coincident, entityIds: [l3.id, l0.id]),
            // Diagonal coincident
            SketchConstraint(kind: .coincident, entityIds: [d1.id, l0.id]),
            SketchConstraint(kind: .coincident, entityIds: [d1.id, l2.id]),
            SketchConstraint(kind: .coincident, entityIds: [d2.id, l1.id]),
            SketchConstraint(kind: .coincident, entityIds: [d2.id, l3.id]),
            // Orientation
            SketchConstraint(kind: .horizontal, entityIds: [l0.id]),
            SketchConstraint(kind: .horizontal, entityIds: [l2.id]),
            SketchConstraint(kind: .vertical, entityIds: [l1.id]),
            SketchConstraint(kind: .vertical, entityIds: [l3.id])
        ]

        return SketchRectangleResult(
            entities: [l0, l1, l2, l3, d1, d2],
            constraints: constraints,
            corners: [p0, p1, p2, p3]
        )
    }

    /// Generates a three-point rectangle defined by two points establishing the base edge and orientation,
    /// and a third point establishing height.
    ///
    /// Produces 4 perimeter lines at arbitrary rotation angle with 4 corner coincident constraints,
    /// 2 parallel constraints, and 1 perpendicular constraint (resulting in 5 degrees of freedom).
    public static func makeThreePointRectangle(
        point1: SIMD2<Double>,
        point2: SIMD2<Double>,
        point3: SIMD2<Double>
    ) throws -> SketchRectangleResult {
        let baseVec = point2 - point1
        let baseLen = hypot(baseVec.x, baseVec.y)

        guard baseLen > minDimensionTolerance else {
            throw SketchError.degenerateRectangle(
                "Three-point rectangle base edge length (\(baseLen)) must exceed \(minDimensionTolerance)"
            )
        }

        let u = baseVec / baseLen
        let n = SIMD2<Double>(-u.y, u.x)

        let h = (point3.x - point1.x) * n.x + (point3.y - point1.y) * n.y
        guard abs(h) > minDimensionTolerance else {
            throw SketchError.degenerateRectangle(
                "Three-point rectangle height (\(abs(h))) must exceed \(minDimensionTolerance)"
            )
        }

        let p0 = point1
        let p1 = point2
        let p2 = point2 + n * h
        let p3 = point1 + n * h

        let l0 = SketchEntity.line(start: p0, end: p1)
        let l1 = SketchEntity.line(start: p1, end: p2)
        let l2 = SketchEntity.line(start: p2, end: p3)
        let l3 = SketchEntity.line(start: p3, end: p0)

        let constraints: [SketchConstraint] = [
            SketchConstraint(kind: .coincident, entityIds: [l0.id, l1.id]),
            SketchConstraint(kind: .coincident, entityIds: [l1.id, l2.id]),
            SketchConstraint(kind: .coincident, entityIds: [l2.id, l3.id]),
            SketchConstraint(kind: .coincident, entityIds: [l3.id, l0.id]),
            SketchConstraint(kind: .parallel, entityIds: [l0.id, l2.id]),
            SketchConstraint(kind: .parallel, entityIds: [l1.id, l3.id]),
            SketchConstraint(kind: .perpendicular, entityIds: [l0.id, l1.id])
        ]

        return SketchRectangleResult(
            entities: [l0, l1, l2, l3],
            constraints: constraints,
            corners: [p0, p1, p2, p3]
        )
    }
}
