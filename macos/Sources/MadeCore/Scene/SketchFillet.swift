import Foundation
import simd

/// The entities and geometric constraints resulting from a 2D sketch corner fillet operation.
public struct SketchFilletResult: Sendable, Equatable {
    public var updatedLine1: SketchEntity
    public var updatedLine2: SketchEntity
    public var filletArc: SketchEntity
    public var constraints: [SketchConstraint]

    public init(
        updatedLine1: SketchEntity,
        updatedLine2: SketchEntity,
        filletArc: SketchEntity,
        constraints: [SketchConstraint]
    ) {
        self.updatedLine1 = updatedLine1
        self.updatedLine2 = updatedLine2
        self.filletArc = filletArc
        self.constraints = constraints
    }
}

/// Geometric engine creating a tangent circular arc fillet between two intersecting lines,
/// trimming bounding lines back to setback points, and generating coincident and tangent constraints.
public enum SketchFillet {
    public static let tolerance: Double = 1e-4

    /// Computes a corner fillet between two line entities with the given radius.
    ///
    /// - Parameters:
    ///   - line1: The first line entity forming the corner.
    ///   - line2: The second line entity forming the corner.
    ///   - radius: The fillet arc radius in mm (must be positive).
    /// - Returns: A `SketchFilletResult` containing trimmed lines, the fillet arc, and constraints.
    /// - Throws: `SketchError.degenerateFillet` if geometry is parallel, collinear, or setback exceeds line length.
    public static func makeFillet(
        line1: SketchEntity,
        line2: SketchEntity,
        radius: Double
    ) throws -> SketchFilletResult {
        guard radius > tolerance else {
            throw SketchError.degenerateFillet("Fillet radius (\(radius)) must exceed \(tolerance) mm")
        }

        guard line1.kind == "line", let s1 = line1.startPoint, let e1 = line1.endPoint else {
            throw SketchError.degenerateFillet("Line 1 is invalid or missing endpoints")
        }
        guard line2.kind == "line", let s2 = line2.startPoint, let e2 = line2.endPoint else {
            throw SketchError.degenerateFillet("Line 2 is invalid or missing endpoints")
        }

        let rawLen1 = hypot(e1.x - s1.x, e1.y - s1.y)
        let rawLen2 = hypot(e2.x - s2.x, e2.y - s2.y)
        guard rawLen1 > tolerance else {
            throw SketchError.degenerateFillet("Line 1 has zero length")
        }
        guard rawLen2 > tolerance else {
            throw SketchError.degenerateFillet("Line 2 has zero length")
        }

        // Identify corner vertex V and which end of each line is the corner end
        var corner1IsStart = false
        var corner2IsStart = false
        var cornerV: SIMD2<Double>?

        if hypot(s1.x - s2.x, s1.y - s2.y) <= tolerance {
            corner1IsStart = true
            corner2IsStart = true
            cornerV = (s1 + s2) * 0.5
        } else if hypot(s1.x - e2.x, s1.y - e2.y) <= tolerance {
            corner1IsStart = true
            corner2IsStart = false
            cornerV = (s1 + e2) * 0.5
        } else if hypot(e1.x - s2.x, e1.y - s2.y) <= tolerance {
            corner1IsStart = false
            corner2IsStart = true
            cornerV = (e1 + s2) * 0.5
        } else if hypot(e1.x - e2.x, e1.y - e2.y) <= tolerance {
            corner1IsStart = false
            corner2IsStart = false
            cornerV = (e1 + e2) * 0.5
        } else {
            // Infinite line intersection
            let d1 = e1 - s1
            let d2 = e2 - s2
            let cross = d1.x * d2.y - d1.y * d2.x
            guard abs(cross) > 1e-9 else {
                throw SketchError.degenerateFillet("Lines are parallel or collinear")
            }
            let dp = s2 - s1
            let t = (dp.x * d2.y - dp.y * d2.x) / cross
            let u = (dp.x * d1.y - dp.y * d1.x) / cross

            guard t >= -0.1 && t <= 1.1 && u >= -0.1 && u <= 1.1 else {
                throw SketchError.degenerateFillet("Lines do not intersect near segment endpoints")
            }

            let intersection = s1 + t * d1
            cornerV = intersection
            corner1IsStart = hypot(s1.x - intersection.x, s1.y - intersection.y) < hypot(e1.x - intersection.x, e1.y - intersection.y)
            corner2IsStart = hypot(s2.x - intersection.x, s2.y - intersection.y) < hypot(e2.x - intersection.x, e2.y - intersection.y)
        }

        guard let V = cornerV else {
            throw SketchError.degenerateFillet("Failed to locate corner vertex")
        }

        let far1 = corner1IsStart ? e1 : s1
        let far2 = corner2IsStart ? e2 : s2
        let v1 = far1 - V
        let v2 = far2 - V
        let L1 = hypot(v1.x, v1.y)
        let L2 = hypot(v2.x, v2.y)
        guard L1 > tolerance, L2 > tolerance else {
            throw SketchError.degenerateFillet("Line segment to corner has zero length")
        }

        let u1 = v1 / L1
        let u2 = v2 / L2

        let dot = max(-1.0, min(1.0, u1.x * u2.x + u1.y * u2.y))
        let crossU = u1.x * u2.y - u1.y * u2.x
        let sinTheta = abs(crossU)
        let theta = acos(dot)

        guard sinTheta >= 1e-4, theta >= 1e-4, theta <= (.pi - 1e-4) else {
            throw SketchError.degenerateFillet("Lines are parallel or collinear")
        }

        let halfTheta = theta * 0.5
        let tanHalf = tan(halfTheta)
        guard tanHalf > 1e-9 else {
            throw SketchError.degenerateFillet("Corner angle too sharp or collinear")
        }
        let d = radius / tanHalf

        guard d < L1 - tolerance && d < L2 - tolerance else {
            throw SketchError.degenerateFillet("Fillet radius \(radius) requires setback \(d) mm which exceeds line length (\(min(L1, L2)) mm)")
        }

        let T1 = V + d * u1
        let T2 = V + d * u2

        let bisectorSum = u1 + u2
        let bisectorLen = hypot(bisectorSum.x, bisectorSum.y)
        guard bisectorLen > 1e-9 else {
            throw SketchError.degenerateFillet("Invalid angle bisector")
        }
        let ub = bisectorSum / bisectorLen
        let sinHalf = sin(halfTheta)
        guard sinHalf > 1e-9 else {
            throw SketchError.degenerateFillet("Invalid sine for half angle")
        }
        let distToCenter = radius / sinHalf
        let C = V + distToCenter * ub

        let w1 = T1 - C
        let w2 = T2 - C
        let crossArc = w1.x * w2.y - w1.y * w2.x
        let clockwise = (crossArc < 0.0)

        let filletArc = SketchEntity.arc(
            start: T1,
            end: T2,
            center: C,
            clockwise: clockwise,
            isConstruction: line1.isConstruction && line2.isConstruction
        )

        let updatedLine1 = SketchEntity.line(
            id: line1.id,
            start: corner1IsStart ? T1 : s1,
            end: corner1IsStart ? e1 : T1,
            isConstruction: line1.isConstruction,
            reference: line1.reference
        )

        let updatedLine2 = SketchEntity.line(
            id: line2.id,
            start: corner2IsStart ? T2 : s2,
            end: corner2IsStart ? e2 : T2,
            isConstruction: line2.isConstruction,
            reference: line2.reference
        )

        let constraints: [SketchConstraint] = [
            SketchConstraint(kind: .coincident, entityIds: [line1.id, filletArc.id]),
            SketchConstraint(kind: .coincident, entityIds: [line2.id, filletArc.id]),
            SketchConstraint(kind: .tangent, entityIds: [line1.id, filletArc.id]),
            SketchConstraint(kind: .tangent, entityIds: [line2.id, filletArc.id])
        ]

        return SketchFilletResult(
            updatedLine1: updatedLine1,
            updatedLine2: updatedLine2,
            filletArc: filletArc,
            constraints: constraints
        )
    }
}
