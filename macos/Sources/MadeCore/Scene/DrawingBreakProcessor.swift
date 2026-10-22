import Foundation
import simd

/// Edge coordinate compression and break line generator for interrupted engineering drawing views.
public enum DrawingBreakProcessor {

    /// Compresses coordinates across break intervals, clips removed geometry, and generates boundary break lines.
    public static func applyBreak(
        to hlr: HLRResult,
        definition: BreakViewDefinition
    ) -> HLRResult {
        let start = definition.startMM
        let end = definition.endMM
        let gap = definition.gapMM
        let span = definition.breakSpan
        let offset = definition.compressionOffset

        // If span is zero, nothing to compress
        guard span > 1e-6 else {
            return hlr
        }

        var compressedEdges: [HLREdge] = []
        let isHorizontal = definition.orientation == .horizontal

        for edge in hlr.edges {
            guard edge.points2D.count >= 2 else { continue }
            for i in 0..<(edge.points2D.count - 1) {
                let p1 = edge.points2D[i]
                let p2 = edge.points2D[i + 1]

                let u1 = isHorizontal ? p1.x : p1.y
                let u2 = isHorizontal ? p2.x : p2.y

                // Case 1: entirely before start
                if u1 <= start && u2 <= start {
                    compressedEdges.append(HLREdge(category: edge.category, points2D: [p1, p2]))
                    continue
                }

                // Case 2: entirely after end
                if u1 >= end && u2 >= end {
                    let shifted1 = shiftPoint(p1, isHorizontal: isHorizontal, offset: offset)
                    let shifted2 = shiftPoint(p2, isHorizontal: isHorizontal, offset: offset)
                    compressedEdges.append(HLREdge(category: edge.category, points2D: [shifted1, shifted2]))
                    continue
                }

                // Case 3: entirely inside break interval
                if u1 >= start && u1 <= end && u2 >= start && u2 <= end {
                    continue
                }

                // Case 4: crossing start or end
                let deltaU = u2 - u1
                if abs(deltaU) < 1e-9 { continue }

                let tStart = (start - u1) / deltaU
                let tEnd = (end - u1) / deltaU

                // Sub-segment before start
                let tBeforeMin = max(0.0, min(u1 <= start ? 0.0 : 1.0, u2 <= start ? 1.0 : 0.0))
                let tBeforeMax = min(1.0, max(0.0, tStart))
                let t0_before = min(tBeforeMin, tBeforeMax)
                let t1_before = max(tBeforeMin, tBeforeMax)
                if t1_before - t0_before > 1e-6 {
                    let ptA = p1 + (p2 - p1) * t0_before
                    let ptB = p1 + (p2 - p1) * t1_before
                    let midU = isHorizontal ? (ptA.x + ptB.x) * 0.5 : (ptA.y + ptB.y) * 0.5
                    if midU <= start + 1e-6 {
                        compressedEdges.append(HLREdge(category: edge.category, points2D: [ptA, ptB]))
                    }
                }

                // Sub-segment after end
                let tAfterMin = max(0.0, min(1.0, tEnd))
                let tAfterMax = min(1.0, max(u1 >= end ? 0.0 : 1.0, u2 >= end ? 1.0 : 0.0))
                let t0_after = min(tAfterMin, tAfterMax)
                let t1_after = max(tAfterMin, tAfterMax)
                if t1_after - t0_after > 1e-6 {
                    let ptA = p1 + (p2 - p1) * t0_after
                    let ptB = p1 + (p2 - p1) * t1_after
                    let midU = isHorizontal ? (ptA.x + ptB.x) * 0.5 : (ptA.y + ptB.y) * 0.5
                    if midU >= end - 1e-6 {
                        let shiftedA = shiftPoint(ptA, isHorizontal: isHorizontal, offset: offset)
                        let shiftedB = shiftPoint(ptB, isHorizontal: isHorizontal, offset: offset)
                        compressedEdges.append(HLREdge(category: edge.category, points2D: [shiftedA, shiftedB]))
                    }
                }
            }
        }

        // Generate break lines at start and start + gap
        let vBounds: (min: Double, max: Double) = {
            if let b = hlr.bounds2D {
                return isHorizontal ? (b.min.y - 2.0, b.max.y + 2.0) : (b.min.x - 2.0, b.max.x + 2.0)
            }
            return (-20.0, 20.0)
        }()

        let breakLine1 = generateBreakLine(
            u: start,
            vMin: vBounds.min,
            vMax: vBounds.max,
            isHorizontal: isHorizontal,
            style: definition.style
        )
        let breakLine2 = generateBreakLine(
            u: start + gap,
            vMin: vBounds.min,
            vMax: vBounds.max,
            isHorizontal: isHorizontal,
            style: definition.style
        )

        compressedEdges.append(contentsOf: breakLine1)
        compressedEdges.append(contentsOf: breakLine2)

        return HLRResult(edges: compressedEdges, viewDirection: hlr.viewDirection)
    }

    private static func shiftPoint(_ pt: SIMD2<Double>, isHorizontal: Bool, offset: Double) -> SIMD2<Double> {
        if isHorizontal {
            return SIMD2<Double>(pt.x - offset, pt.y)
        } else {
            return SIMD2<Double>(pt.x, pt.y - offset)
        }
    }

    private static func generateBreakLine(
        u: Double,
        vMin: Double,
        vMax: Double,
        isHorizontal: Bool,
        style: BreakLineStyle
    ) -> [HLREdge] {
        guard vMax > vMin + 1e-4 else { return [] }
        let vSpan = vMax - vMin

        switch style {
        case .straight:
            let pt1 = isHorizontal ? SIMD2<Double>(u, vMin) : SIMD2<Double>(vMin, u)
            let pt2 = isHorizontal ? SIMD2<Double>(u, vMax) : SIMD2<Double>(vMax, u)
            return [HLREdge(category: .visibleSharp, points2D: [pt1, pt2])]

        case .zigzag:
            let midV = (vMin + vMax) * 0.5
            let toothHeight = min(vSpan * 0.25, 4.0)
            let amp = 2.0

            var pts: [SIMD2<Double>] = []
            pts.append(isHorizontal ? SIMD2<Double>(u, vMin) : SIMD2<Double>(vMin, u))
            pts.append(isHorizontal ? SIMD2<Double>(u, midV - toothHeight) : SIMD2<Double>(midV - toothHeight, u))
            pts.append(isHorizontal ? SIMD2<Double>(u - amp, midV - toothHeight * 0.5) : SIMD2<Double>(midV - toothHeight * 0.5, u - amp))
            pts.append(isHorizontal ? SIMD2<Double>(u + amp, midV + toothHeight * 0.5) : SIMD2<Double>(midV + toothHeight * 0.5, u + amp))
            pts.append(isHorizontal ? SIMD2<Double>(u, midV + toothHeight) : SIMD2<Double>(midV + toothHeight, u))
            pts.append(isHorizontal ? SIMD2<Double>(u, vMax) : SIMD2<Double>(vMax, u))

            var edges: [HLREdge] = []
            for i in 0..<(pts.count - 1) {
                edges.append(HLREdge(category: .visibleSharp, points2D: [pts[i], pts[i + 1]]))
            }
            return edges

        case .wavy:
            let steps = 16
            let amp = 1.5
            var pts: [SIMD2<Double>] = []
            for step in 0...steps {
                let frac = Double(step) / Double(steps)
                let v = vMin + vSpan * frac
                let waveU = u + amp * sin(frac * .pi * 4.0)
                pts.append(isHorizontal ? SIMD2<Double>(waveU, v) : SIMD2<Double>(v, waveU))
            }
            var edges: [HLREdge] = []
            for i in 0..<(pts.count - 1) {
                edges.append(HLREdge(category: .visibleSharp, points2D: [pts[i], pts[i + 1]]))
            }
            return edges
        }
    }
}
