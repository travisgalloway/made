import Foundation
import simd

/// The entities and geometric constraints resulting from a 2D sketch corner chamfer operation.
public struct SketchChamferResult: Sendable, Equatable {
    public var updatedLine1: SketchEntity
    public var updatedLine2: SketchEntity
    public var chamferLine: SketchEntity
    public var constraints: [SketchConstraint]

    public init(
        updatedLine1: SketchEntity,
        updatedLine2: SketchEntity,
        chamferLine: SketchEntity,
        constraints: [SketchConstraint]
    ) {
        self.updatedLine1 = updatedLine1
        self.updatedLine2 = updatedLine2
        self.chamferLine = chamferLine
        self.constraints = constraints
    }
}

/// Geometric engine creating a straight bevel chamfer segment between two intersecting lines,
/// trimming bounding lines back to setback points, and generating coincident constraints.
public enum SketchChamfer {
    public static let tolerance: Double = 1e-4

    /// Computes a corner chamfer between two line entities with the given setback distances or angle.
    ///
    /// - Parameters:
    ///   - line1: The first line entity forming the corner.
    ///   - line2: The second line entity forming the corner.
    ///   - distance1: The setback distance along line 1 in mm (must be positive).
    ///   - distance2: Optional setback distance along line 2 in mm. If omitted, defaults to distance1 or is derived from angle.
    ///   - angle: Optional chamfer angle in degrees (between 0.01 and 89.99) for distance-angle mode.
    /// - Returns: A `SketchChamferResult` containing trimmed lines, the bevel line, and coincident constraints.
    /// - Throws: `SketchError.degenerateChamfer` if geometry is parallel, collinear, or setbacks exceed line length.
    public static func makeChamfer(
        line1: SketchEntity,
        line2: SketchEntity,
        distance1: Double,
        distance2: Double? = nil,
        angle: Double? = nil
    ) throws -> SketchChamferResult {
        guard distance1 > tolerance else {
            throw SketchError.degenerateChamfer("Chamfer distance1 (\(distance1)) must exceed \(tolerance) mm")
        }

        let d2: Double
        if let explicitD2 = distance2 {
            guard explicitD2 > tolerance else {
                throw SketchError.degenerateChamfer("Chamfer distance2 (\(explicitD2)) must exceed \(tolerance) mm")
            }
            d2 = explicitD2
        } else if let explicitAngle = angle {
            guard explicitAngle > 0.01 && explicitAngle < 89.99 else {
                throw SketchError.degenerateChamfer("Chamfer angle (\(explicitAngle)) must be between 0.01 and 89.99 degrees")
            }
            let rad = explicitAngle * .pi / 180.0
            let computed = distance1 * tan(rad)
            guard computed > tolerance else {
                throw SketchError.degenerateChamfer("Computed chamfer distance2 (\(computed)) must exceed \(tolerance) mm")
            }
            d2 = computed
        } else {
            d2 = distance1
        }

        guard line1.kind == "line", let s1 = line1.startPoint, let e1 = line1.endPoint else {
            throw SketchError.degenerateChamfer("Line 1 is invalid or missing endpoints")
        }
        guard line2.kind == "line", let s2 = line2.startPoint, let e2 = line2.endPoint else {
            throw SketchError.degenerateChamfer("Line 2 is invalid or missing endpoints")
        }

        let rawLen1 = hypot(e1.x - s1.x, e1.y - s1.y)
        let rawLen2 = hypot(e2.x - s2.x, e2.y - s2.y)
        guard rawLen1 > tolerance else {
            throw SketchError.degenerateChamfer("Line 1 has zero length")
        }
        guard rawLen2 > tolerance else {
            throw SketchError.degenerateChamfer("Line 2 has zero length")
        }

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
            let d1 = e1 - s1
            let d2 = e2 - s2
            let cross = d1.x * d2.y - d1.y * d2.x
            guard abs(cross) > 1e-9 else {
                throw SketchError.degenerateChamfer("Lines are parallel or collinear")
            }
            let dp = s2 - s1
            let t = (dp.x * d2.y - dp.y * d2.x) / cross
            let u = (dp.x * d1.y - dp.y * d1.x) / cross

            guard t >= -0.1 && t <= 1.1 && u >= -0.1 && u <= 1.1 else {
                throw SketchError.degenerateChamfer("Lines do not intersect near segment endpoints")
            }

            let intersection = s1 + t * d1
            cornerV = intersection
            corner1IsStart = hypot(s1.x - intersection.x, s1.y - intersection.y) < hypot(e1.x - intersection.x, e1.y - intersection.y)
            corner2IsStart = hypot(s2.x - intersection.x, s2.y - intersection.y) < hypot(e2.x - intersection.x, e2.y - intersection.y)
        }

        guard let V = cornerV else {
            throw SketchError.degenerateChamfer("Failed to locate corner vertex")
        }

        let far1 = corner1IsStart ? e1 : s1
        let far2 = corner2IsStart ? e2 : s2
        let v1 = far1 - V
        let v2 = far2 - V
        let L1 = hypot(v1.x, v1.y)
        let L2 = hypot(v2.x, v2.y)
        guard L1 > tolerance, L2 > tolerance else {
            throw SketchError.degenerateChamfer("Line segment to corner has zero length")
        }

        let u1 = v1 / L1
        let u2 = v2 / L2

        let dot = max(-1.0, min(1.0, u1.x * u2.x + u1.y * u2.y))
        let crossU = u1.x * u2.y - u1.y * u2.x
        let sinTheta = abs(crossU)
        let theta = acos(dot)

        guard sinTheta >= 1e-4, theta >= 1e-4, theta <= (.pi - 1e-4) else {
            throw SketchError.degenerateChamfer("Lines are parallel or collinear")
        }

        guard distance1 < L1 - tolerance else {
            throw SketchError.degenerateChamfer("Chamfer distance1 (\(distance1)) requires setback which exceeds line 1 length (\(L1) mm)")
        }
        guard d2 < L2 - tolerance else {
            throw SketchError.degenerateChamfer("Chamfer distance2 (\(d2)) requires setback which exceeds line 2 length (\(L2) mm)")
        }

        let Pc1 = V + distance1 * u1
        let Pc2 = V + d2 * u2

        let chamferLine = SketchEntity.line(
            start: Pc1,
            end: Pc2,
            isConstruction: line1.isConstruction && line2.isConstruction
        )

        let updatedLine1 = SketchEntity.line(
            id: line1.id,
            start: corner1IsStart ? Pc1 : s1,
            end: corner1IsStart ? e1 : Pc1,
            isConstruction: line1.isConstruction,
            reference: line1.reference
        )

        let updatedLine2 = SketchEntity.line(
            id: line2.id,
            start: corner2IsStart ? Pc2 : s2,
            end: corner2IsStart ? e2 : Pc2,
            isConstruction: line2.isConstruction,
            reference: line2.reference
        )

        let constraints: [SketchConstraint] = [
            SketchConstraint(kind: .coincident, entityIds: [line1.id, chamferLine.id]),
            SketchConstraint(kind: .coincident, entityIds: [line2.id, chamferLine.id])
        ]

        return SketchChamferResult(
            updatedLine1: updatedLine1,
            updatedLine2: updatedLine2,
            chamferLine: chamferLine,
            constraints: constraints
        )
    }
}
