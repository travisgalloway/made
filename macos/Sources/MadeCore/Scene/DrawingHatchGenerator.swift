import Foundation
import simd

/// Analytical 2D cross-hatch line generator for engineering drawing section views.
public enum DrawingHatchGenerator {

    /// Analytical 2D cross-hatch line computation across bounding boxes for ANSI31, ANSI32, cross-hatch, and solid patterns.
    public static func generateHatchLines(
        in bounds: BoundingBox2D,
        pattern: HatchPatternDefinition
    ) -> [HLREdge] {
        guard bounds.width > 1e-4 && bounds.height > 1e-4 else {
            return []
        }

        switch pattern.style {
        case .ansi31:
            return generateParallelLines(in: bounds, angleDegrees: pattern.angleDegrees, spacingMM: pattern.spacingMM)
        case .ansi32:
            // Paired lines: each pair separated by spacingMM * 0.25, pairs spaced by spacingMM
            let spacing = max(1.0, pattern.spacingMM)
            let pairOffset = max(0.3, spacing * 0.25)
            let primary = generateParallelLines(in: bounds, angleDegrees: pattern.angleDegrees, spacingMM: spacing)
            let secondary = generateParallelLines(in: bounds, angleDegrees: pattern.angleDegrees, spacingMM: spacing, lineOffset: pairOffset)
            return primary + secondary
        case .crossHatch:
            // Orthogonal lines: angleDegrees and angleDegrees + 90
            let lines1 = generateParallelLines(in: bounds, angleDegrees: pattern.angleDegrees, spacingMM: pattern.spacingMM)
            let lines2 = generateParallelLines(in: bounds, angleDegrees: pattern.angleDegrees + 90.0, spacingMM: pattern.spacingMM)
            return lines1 + lines2
        case .solid:
            // Very dense lines
            let denseSpacing = max(0.4, min(pattern.spacingMM, 0.6))
            return generateParallelLines(in: bounds, angleDegrees: pattern.angleDegrees, spacingMM: denseSpacing)
        }
    }

    private static func generateParallelLines(
        in bounds: BoundingBox2D,
        angleDegrees: Double,
        spacingMM: Double,
        lineOffset: Double = 0.0
    ) -> [HLREdge] {
        let spacing = max(0.4, spacingMM)
        let rad = angleDegrees * .pi / 180.0
        let dir = SIMD2<Double>(cos(rad), sin(rad))
        let normal = SIMD2<Double>(-sin(rad), cos(rad))

        // 4 corners of bounds
        let corners = [
            bounds.min,
            SIMD2<Double>(bounds.max.x, bounds.min.y),
            bounds.max,
            SIMD2<Double>(bounds.min.x, bounds.max.y)
        ]

        let projections = corners.map { simd_dot($0, normal) }
        guard let minProj = projections.min(), let maxProj = projections.max() else {
            return []
        }

        var edges: [HLREdge] = []
        let startS = (floor(minProj / spacing) * spacing) + lineOffset
        var s = startS
        while s <= maxProj + 1e-6 {
            if s >= minProj - 1e-6 {
                if let segment = clipLineToBox(normal: normal, dir: dir, s: s, bounds: bounds) {
                    edges.append(HLREdge(category: .visibleSharp, points2D: [segment.0, segment.1]))
                }
            }
            s += spacing
        }
        return edges
    }

    private static func clipLineToBox(
        normal: SIMD2<Double>,
        dir: SIMD2<Double>,
        s: Double,
        bounds: BoundingBox2D
    ) -> (SIMD2<Double>, SIMD2<Double>)? {
        let p0 = normal * s
        var tMinX = -Double.infinity
        var tMaxX = Double.infinity
        if abs(dir.x) > 1e-9 {
            let t1 = (bounds.min.x - p0.x) / dir.x
            let t2 = (bounds.max.x - p0.x) / dir.x
            tMinX = min(t1, t2)
            tMaxX = max(t1, t2)
        } else {
            if p0.x < bounds.min.x || p0.x > bounds.max.x { return nil }
        }

        var tMinY = -Double.infinity
        var tMaxY = Double.infinity
        if abs(dir.y) > 1e-9 {
            let t1 = (bounds.min.y - p0.y) / dir.y
            let t2 = (bounds.max.y - p0.y) / dir.y
            tMinY = min(t1, t2)
            tMaxY = max(t1, t2)
        } else {
            if p0.y < bounds.min.y || p0.y > bounds.max.y { return nil }
        }

        let tEnter = max(tMinX, tMinY)
        let tExit = min(tMaxX, tMaxY)

        guard tEnter < tExit - 1e-6 else { return nil }
        return (p0 + dir * tEnter, p0 + dir * tExit)
    }
}
