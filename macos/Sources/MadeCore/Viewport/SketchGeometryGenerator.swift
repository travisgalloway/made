import Foundation
import simd

/// Metadata for a rendered sketch entity in the viewport.
public struct SketchRenderItem: Sendable, Equatable {
    public let entityId: UUID
    public let kind: String
    public let isConstruction: Bool
    public var dashFlag: Bool { isConstruction }
    public var isDashed: Bool { isConstruction }
    public let vertexCount: Int

    public init(entityId: UUID, kind: String, isConstruction: Bool, vertexCount: Int) {
        self.entityId = entityId
        self.kind = kind
        self.isConstruction = isConstruction
        self.vertexCount = vertexCount
    }
}

/// Packed vertex geometry for drawing sketch entities via Metal.
public struct SketchGeometry: Sendable, Equatable {
    public let items: [SketchRenderItem]
    public let positions: [Float] // 3 floats per vertex (x, y, z)
    public let colors: [Float]    // 4 floats per vertex (r, g, b, a)
    public var vertexCount: Int { positions.count / 3 }

    public init(items: [SketchRenderItem], positions: [Float], colors: [Float]) {
        self.items = items
        self.positions = positions
        self.colors = colors
    }
}

/// Generates discretized 3D line geometry for sketch entities on a `SketchPlane`.
public enum SketchGeometryGenerator {
    /// Default color for regular sketch profile entities: high-contrast cyan/sky blue.
    public static let defaultRegularColor = SIMD4<Float>(0.2, 0.7, 1.0, 1.0)
    /// Default color for construction geometry: amber.
    public static let defaultConstructionColor = SIMD4<Float>(1.0, 0.65, 0.0, 0.85)
    /// Default dash segment length in sketch plane units.
    public static let defaultDashLength: Double = 3.0
    /// Default gap segment length in sketch plane units.
    public static let defaultGapLength: Double = 2.0

    /// Discretizes 2D sketch entities into 3D world-space lines on the specified `plane`.
    /// Continuous lines are generated for regular entities; alternating dashed segments for construction entities.
    public static func generateGeometry(
        entities: [SketchEntity],
        plane: SketchPlane = .xy,
        regularColor: SIMD4<Float> = defaultRegularColor,
        constructionColor: SIMD4<Float> = defaultConstructionColor,
        dashLength: Double = defaultDashLength,
        gapLength: Double = defaultGapLength
    ) -> SketchGeometry {
        guard !entities.isEmpty else {
            return SketchGeometry(items: [], positions: [], colors: [])
        }

        var items: [SketchRenderItem] = []
        var positions: [Float] = []
        var colors: [Float] = []

        let effectiveDash = max(dashLength, 0.001)
        let effectiveGap = max(gapLength, 0.001)
        let period = effectiveDash + effectiveGap

        for entity in entities {
            let entityColor = entity.isConstruction ? constructionColor : regularColor
            let startIndex = positions.count

            func appendSegment(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>) {
                positions.append(contentsOf: [p0.x, p0.y, p0.z, p1.x, p1.y, p1.z])
                colors.append(contentsOf: [entityColor.x, entityColor.y, entityColor.z, entityColor.w,
                                          entityColor.x, entityColor.y, entityColor.z, entityColor.w])
            }

            switch entity.kind {
            case "line":
                guard let start = entity.startPoint, let end = entity.endPoint else { continue }
                let length = hypot(end.x - start.x, end.y - start.y)
                guard length > 1e-9 else { continue }

                if !entity.isConstruction {
                    let p0 = plane.unprojectPoint(start)
                    let p1 = plane.unprojectPoint(end)
                    appendSegment(p0, p1)
                } else {
                    let dir = (end - start) / length
                    var d = 0.0
                    while d < length {
                        let segStart = d
                        let segEnd = min(d + effectiveDash, length)
                        if segEnd > segStart + 1e-9 {
                            let p0 = plane.unprojectPoint(start + dir * segStart)
                            let p1 = plane.unprojectPoint(start + dir * segEnd)
                            appendSegment(p0, p1)
                        }
                        d += period
                    }
                }

            case "arc":
                guard let center = entity.centerPoint,
                      let start = entity.startPoint,
                      let end = entity.endPoint else { continue }
                let r = entity.radius ?? hypot(start.x - center.x, start.y - center.y)
                guard r > 1e-9 else { continue }

                let a0 = atan2(start.y - center.y, start.x - center.x)
                let a1 = atan2(end.y - center.y, end.x - center.x)
                var delta = a1 - a0
                if entity.isClockwise && delta > 0 { delta -= 2.0 * .pi }
                if !entity.isClockwise && delta < 0 { delta += 2.0 * .pi }
                if abs(delta) < 1e-9 {
                    delta = entity.isClockwise ? -2.0 * .pi : 2.0 * .pi
                }

                let arcLength = abs(delta) * r
                guard arcLength > 1e-9 else { continue }

                if !entity.isConstruction {
                    let segCount = max(4, min(32, Int(ceil(Double(32) * abs(delta) / (2.0 * .pi)))))
                    for k in 0..<segCount {
                        let t0 = Double(k) / Double(segCount)
                        let t1 = Double(k + 1) / Double(segCount)
                        let angle0 = a0 + t0 * delta
                        let angle1 = a0 + t1 * delta
                        let p0_2d = center + SIMD2<Double>(r * cos(angle0), r * sin(angle0))
                        let p1_2d = center + SIMD2<Double>(r * cos(angle1), r * sin(angle1))
                        appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                    }
                } else {
                    var d = 0.0
                    while d < arcLength {
                        let segStart = d
                        let segEnd = min(d + effectiveDash, arcLength)
                        let dashSubLen = segEnd - segStart
                        if dashSubLen > 1e-9 {
                            let dashDelta = (dashSubLen / arcLength) * delta
                            let dashA0 = a0 + (segStart / arcLength) * delta
                            let dashSteps = max(1, min(8, Int(ceil(Double(32) * abs(dashDelta) / (2.0 * .pi)))))
                            for k in 0..<dashSteps {
                                let t0 = Double(k) / Double(dashSteps)
                                let t1 = Double(k + 1) / Double(dashSteps)
                                let angle0 = dashA0 + t0 * dashDelta
                                let angle1 = dashA0 + t1 * dashDelta
                                let p0_2d = center + SIMD2<Double>(r * cos(angle0), r * sin(angle0))
                                let p1_2d = center + SIMD2<Double>(r * cos(angle1), r * sin(angle1))
                                appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                            }
                        }
                        d += period
                    }
                }

            case "circle":
                guard let center = entity.centerPoint, let r = entity.radius, r > 1e-9 else { continue }
                let circumference = 2.0 * .pi * r

                if !entity.isConstruction {
                    let segCount = 32
                    for k in 0..<segCount {
                        let angle0 = (Double(k) / Double(segCount)) * 2.0 * .pi
                        let angle1 = (Double(k + 1) / Double(segCount)) * 2.0 * .pi
                        let p0_2d = center + SIMD2<Double>(r * cos(angle0), r * sin(angle0))
                        let p1_2d = center + SIMD2<Double>(r * cos(angle1), r * sin(angle1))
                        appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                    }
                } else {
                    var d = 0.0
                    while d < circumference {
                        let segStart = d
                        let segEnd = min(d + effectiveDash, circumference)
                        let dashSubLen = segEnd - segStart
                        if dashSubLen > 1e-9 {
                            let dashA0 = (segStart / circumference) * 2.0 * .pi
                            let dashSweep = (dashSubLen / circumference) * 2.0 * .pi
                            let dashSteps = max(1, min(8, Int(ceil(Double(32) * dashSweep / (2.0 * .pi)))))
                            for k in 0..<dashSteps {
                                let t0 = Double(k) / Double(dashSteps)
                                let t1 = Double(k + 1) / Double(dashSteps)
                                let angle0 = dashA0 + t0 * dashSweep
                                let angle1 = dashA0 + t1 * dashSweep
                                let p0_2d = center + SIMD2<Double>(r * cos(angle0), r * sin(angle0))
                                let p1_2d = center + SIMD2<Double>(r * cos(angle1), r * sin(angle1))
                                appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                            }
                        }
                        d += period
                    }
                }

            case "ellipse":
                guard let center = entity.centerPoint,
                      let rx = entity.radiusX,
                      let ry = entity.radiusY,
                      rx > 1e-9, ry > 1e-9 else { continue }
                let rot = entity.rotationAngle ?? 0.0
                let cosRot = cos(rot)
                let sinRot = sin(rot)
                let segCount = 32

                let h = pow(rx - ry, 2) / max(1e-9, pow(rx + ry, 2))
                let perimeter = Double.pi * (rx + ry) * (1.0 + (3.0 * h) / (10.0 + sqrt(max(0.0, 4.0 - 3.0 * h))))

                func pointOnEllipse(theta: Double) -> SIMD2<Double> {
                    let px = rx * cos(theta)
                    let py = ry * sin(theta)
                    return center + SIMD2<Double>(px * cosRot - py * sinRot, px * sinRot + py * cosRot)
                }

                if !entity.isConstruction {
                    for k in 0..<segCount {
                        let a0 = (Double(k) / Double(segCount)) * 2.0 * .pi
                        let a1 = (Double(k + 1) / Double(segCount)) * 2.0 * .pi
                        let p0_2d = pointOnEllipse(theta: a0)
                        let p1_2d = pointOnEllipse(theta: a1)
                        appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                    }
                } else {
                    var d = 0.0
                    while d < perimeter {
                        let segStart = d
                        let segEnd = min(d + effectiveDash, perimeter)
                        let dashSubLen = segEnd - segStart
                        if dashSubLen > 1e-9 {
                            let dashA0 = (segStart / perimeter) * 2.0 * .pi
                            let dashSweep = (dashSubLen / perimeter) * 2.0 * .pi
                            let dashSteps = max(1, min(8, Int(ceil(Double(32) * dashSweep / (2.0 * .pi)))))
                            for k in 0..<dashSteps {
                                let t0 = Double(k) / Double(dashSteps)
                                let t1 = Double(k + 1) / Double(dashSteps)
                                let a0 = dashA0 + t0 * dashSweep
                                let a1 = dashA0 + t1 * dashSweep
                                let p0_2d = pointOnEllipse(theta: a0)
                                let p1_2d = pointOnEllipse(theta: a1)
                                appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                            }
                        }
                        d += period
                    }
                }

            case "ellipticalArc":
                guard let center = entity.centerPoint,
                      let rx = entity.radiusX,
                      let ry = entity.radiusY,
                      let startA = entity.startAngle,
                      let endA = entity.endAngle,
                      rx > 1e-9, ry > 1e-9 else { continue }
                let rot = entity.rotationAngle ?? 0.0
                let cosRot = cos(rot)
                let sinRot = sin(rot)

                var delta = endA - startA
                if entity.isClockwise && delta > 0 { delta -= 2.0 * .pi }
                if !entity.isClockwise && delta < 0 { delta += 2.0 * .pi }
                if abs(delta) < 1e-9 {
                    delta = entity.isClockwise ? -2.0 * .pi : 2.0 * .pi
                }

                func pointOnArc(angle: Double) -> SIMD2<Double> {
                    let px = rx * cos(angle)
                    let py = ry * sin(angle)
                    return center + SIMD2<Double>(px * cosRot - py * sinRot, px * sinRot + py * cosRot)
                }

                let meanRadius = (rx + ry) / 2.0
                let approxLength = abs(delta) * meanRadius
                guard approxLength > 1e-9 else { continue }

                if !entity.isConstruction {
                    let segCount = max(4, min(32, Int(ceil(Double(32) * abs(delta) / (2.0 * .pi)))))
                    for k in 0..<segCount {
                        let t0 = Double(k) / Double(segCount)
                        let t1 = Double(k + 1) / Double(segCount)
                        let a0 = startA + t0 * delta
                        let a1 = startA + t1 * delta
                        let p0_2d = pointOnArc(angle: a0)
                        let p1_2d = pointOnArc(angle: a1)
                        appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                    }
                } else {
                    var d = 0.0
                    while d < approxLength {
                        let segStart = d
                        let segEnd = min(d + effectiveDash, approxLength)
                        let dashSubLen = segEnd - segStart
                        if dashSubLen > 1e-9 {
                            let dashDelta = (dashSubLen / approxLength) * delta
                            let dashA0 = startA + (segStart / approxLength) * delta
                            let dashSteps = max(1, min(8, Int(ceil(Double(32) * abs(dashDelta) / (2.0 * .pi)))))
                            for k in 0..<dashSteps {
                                let t0 = Double(k) / Double(dashSteps)
                                let t1 = Double(k + 1) / Double(dashSteps)
                                let a0 = dashA0 + t0 * dashDelta
                                let a1 = dashA0 + t1 * dashDelta
                                let p0_2d = pointOnArc(angle: a0)
                                let p1_2d = pointOnArc(angle: a1)
                                appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                            }
                        }
                        d += period
                    }
                }

            case "text":
                let contours = SketchTextOutliner.extractContours(for: entity)
                for contour in contours {
                    guard contour.count >= 2 else { continue }
                    let count = contour.count
                    for i in 0..<count {
                        let p0_2d = contour[i]
                        let p1_2d = contour[(i + 1) % count]
                        let segLen = hypot(p1_2d.x - p0_2d.x, p1_2d.y - p0_2d.y)
                        guard segLen > 1e-9 else { continue }
                        if !entity.isConstruction {
                            appendSegment(plane.unprojectPoint(p0_2d), plane.unprojectPoint(p1_2d))
                        } else {
                            let dir = (p1_2d - p0_2d) / segLen
                            var d = 0.0
                            while d < segLen {
                                let segStart = d
                                let segEnd = min(d + effectiveDash, segLen)
                                if segEnd > segStart + 1e-9 {
                                    let s0 = plane.unprojectPoint(p0_2d + dir * segStart)
                                    let s1 = plane.unprojectPoint(p0_2d + dir * segEnd)
                                    appendSegment(s0, s1)
                                }
                                d += period
                            }
                        }
                    }
                }

            default:
                continue
            }

            let vertexCount = (positions.count - startIndex) / 3
            if vertexCount > 0 {
                items.append(SketchRenderItem(
                    entityId: entity.id,
                    kind: entity.kind,
                    isConstruction: entity.isConstruction,
                    vertexCount: vertexCount
                ))
            }
        }

        return SketchGeometry(items: items, positions: positions, colors: colors)
    }
}
