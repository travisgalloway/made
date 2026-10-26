import Foundation
import simd

/// A geometric or dimensional constraint applied to 2D sketch entities (ADR-D4, #37).
public struct SketchConstraint: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: Kind
    public var entityIds: [UUID]
    public var referenceEntityId: UUID?
    public var isDriven: Bool
    public var isTemporary: Bool

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case parallel
        case perpendicular
        case tangent
        case concentric
        case symmetric
        case coincident
        case horizontal
        case vertical
        case equal
    }

    public init(
        id: UUID = UUID(),
        kind: Kind,
        entityIds: [UUID],
        referenceEntityId: UUID? = nil,
        isDriven: Bool = false,
        isTemporary: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.entityIds = entityIds
        self.referenceEntityId = referenceEntityId
        self.isDriven = isDriven
        self.isTemporary = isTemporary
    }

    /// Evaluates the measured geometric value for this constraint from the provided sketch entities.
    ///
    /// Returns a tuple containing the scalar value and whether the value represents an angle in degrees.
    /// Returns `nil` when entities are missing, degenerate, or cannot be evaluated.
    public func measuredGeometricValue(in entities: [SketchEntity]) -> (value: Double, isAngle: Bool)? {
        let entityMap = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        switch kind {
        case .horizontal, .vertical:
            guard let entityId = entityIds.first,
                  let entity = entityMap[entityId],
                  let len = entity.length,
                  len > 1e-9, len.isFinite else { return nil }
            return (len, false)

        case .parallel:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]],
                  let s1 = e1.startPoint, let end1 = e1.endPoint,
                  let s2 = e2.startPoint, let end2 = e2.endPoint else { return nil }
            let len1 = hypot(end1.x - s1.x, end1.y - s1.y)
            let len2 = hypot(end2.x - s2.x, end2.y - s2.y)
            guard len1 > 1e-9, len2 > 1e-9 else { return nil }

            let d1x = (end1.x - s1.x) / len1
            let d1y = (end1.y - s1.y) / len1
            let n1x = -d1y
            let n1y = d1x

            let m1x = (s1.x + end1.x) * 0.5
            let m1y = (s1.y + end1.y) * 0.5
            let m2x = (s2.x + end2.x) * 0.5
            let m2y = (s2.y + end2.y) * 0.5

            let dist = abs((m2x - m1x) * n1x + (m2y - m1y) * n1y)
            guard dist.isFinite else { return nil }
            return (dist, false)

        case .perpendicular:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]],
                  let s1 = e1.startPoint, let end1 = e1.endPoint,
                  let s2 = e2.startPoint, let end2 = e2.endPoint else { return nil }
            let len1 = hypot(end1.x - s1.x, end1.y - s1.y)
            let len2 = hypot(end2.x - s2.x, end2.y - s2.y)
            guard len1 > 1e-9, len2 > 1e-9 else { return nil }

            let v1x = (end1.x - s1.x) / len1
            let v1y = (end1.y - s1.y) / len1
            let v2x = (end2.x - s2.x) / len2
            let v2y = (end2.y - s2.y) / len2

            let dot = max(-1.0, min(1.0, v1x * v2x + v1y * v2y))
            let angleRad = acos(dot)
            let angleDeg = angleRad * (180.0 / .pi)
            guard angleDeg.isFinite else { return nil }
            return (angleDeg, true)

        case .concentric:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]],
                  let c1 = e1.centerPoint,
                  let c2 = e2.centerPoint else { return nil }
            let dist = hypot(c2.x - c1.x, c2.y - c1.y)
            guard dist.isFinite else { return nil }
            return (dist, false)

        case .coincident:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]] else { return nil }

            let points1: [SIMD2<Double>] = {
                if let pt = e1.pointPosition { return [pt] }
                var pts: [SIMD2<Double>] = []
                if let s = e1.startPoint { pts.append(s) }
                if let end = e1.endPoint { pts.append(end) }
                if let c = e1.centerPoint { pts.append(c) }
                return pts
            }()

            let points2: [SIMD2<Double>] = {
                if let pt = e2.pointPosition { return [pt] }
                var pts: [SIMD2<Double>] = []
                if let s = e2.startPoint { pts.append(s) }
                if let end = e2.endPoint { pts.append(end) }
                if let c = e2.centerPoint { pts.append(c) }
                return pts
            }()

            guard !points1.isEmpty, !points2.isEmpty else { return nil }

            var minDist = Double.infinity
            for p1 in points1 {
                for p2 in points2 {
                    let d = hypot(p2.x - p1.x, p2.y - p1.y)
                    if d < minDist { minDist = d }
                }
            }
            guard minDist.isFinite else { return nil }
            return (minDist, false)

        case .tangent:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]] else { return nil }

            let circleAndLine: (circle: SketchEntity, line: SketchEntity)? = {
                if (e1.kind == "circle" || e1.kind == "arc") && e2.kind == "line" { return (e1, e2) }
                if (e2.kind == "circle" || e2.kind == "arc") && e1.kind == "line" { return (e2, e1) }
                return nil
            }()

            if let (circle, line) = circleAndLine {
                guard let center = circle.centerPoint,
                      let radius = circle.radius, radius > 0,
                      let s = line.startPoint, let end = line.endPoint else { return nil }
                let lineLen = hypot(end.x - s.x, end.y - s.y)
                guard lineLen > 1e-9 else { return nil }
                let distToLine = abs((center.x - s.x) * (end.y - s.y) - (center.y - s.y) * (end.x - s.x)) / lineLen
                let offset = abs(distToLine - radius)
                guard offset.isFinite else { return nil }
                return (offset, false)
            }

            if e1.kind == "circle" && e2.kind == "circle" {
                guard let c1 = e1.centerPoint, let r1 = e1.radius, r1 > 0,
                      let c2 = e2.centerPoint, let r2 = e2.radius, r2 > 0 else { return nil }
                let centerDist = hypot(c2.x - c1.x, c2.y - c1.y)
                let extOffset = abs(centerDist - (r1 + r2))
                let intOffset = abs(centerDist - abs(r1 - r2))
                let offset = min(extOffset, intOffset)
                guard offset.isFinite else { return nil }
                return (offset, false)
            }

            return nil

        case .symmetric:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]] else { return nil }

            let refId = referenceEntityId ?? (entityIds.count >= 3 ? entityIds[2] : nil)
            guard let refId, let refEntity = entityMap[refId],
                  let refS = refEntity.startPoint, let refEnd = refEntity.endPoint else { return nil }

            let refLen = hypot(refEnd.x - refS.x, refEnd.y - refS.y)
            guard refLen > 1e-9 else { return nil }

            let nx = -(refEnd.y - refS.y) / refLen
            let ny = (refEnd.x - refS.x) / refLen

            let p1: SIMD2<Double>? = {
                if let pt = e1.pointPosition { return pt }
                if let c = e1.centerPoint { return c }
                if let s = e1.startPoint, let end = e1.endPoint {
                    return SIMD2<Double>((s.x + end.x) * 0.5, (s.y + end.y) * 0.5)
                }
                return nil
            }()

            let p2: SIMD2<Double>? = {
                if let pt = e2.pointPosition { return pt }
                if let c = e2.centerPoint { return c }
                if let s = e2.startPoint, let end = e2.endPoint {
                    return SIMD2<Double>((s.x + end.x) * 0.5, (s.y + end.y) * 0.5)
                }
                return nil
            }()

            guard let p1, let p2 else { return nil }

            let d1 = (p1.x - refS.x) * nx + (p1.y - refS.y) * ny
            let d2 = (p2.x - refS.x) * nx + (p2.y - refS.y) * ny
            let symDiff = abs(d1 + d2)
            guard symDiff.isFinite else { return nil }
            return (symDiff, false)

        case .equal:
            guard entityIds.count >= 2,
                  let e1 = entityMap[entityIds[0]],
                  let e2 = entityMap[entityIds[1]] else { return nil }
            if let len1 = e1.length, let len2 = e2.length {
                let diff = abs(len1 - len2)
                guard diff.isFinite else { return nil }
                return (diff, false)
            }
            if let r1 = e1.radius, let r2 = e2.radius {
                let diff = abs(r1 - r2)
                guard diff.isFinite else { return nil }
                return (diff, false)
            }
            return nil
        }
    }

    /// Formats the measured geometric value enclosed in standard CAD reference parentheses `(value unit)`.
    public func formattedMeasuredValue(
        in entities: [SketchEntity],
        unitSettings: UnitSettings = UnitSettings()
    ) -> String? {
        guard let (val, isAngle) = measuredGeometricValue(in: entities) else { return nil }
        if isAngle {
            return "(\(unitSettings.formatAngle(val)))"
        } else {
            return "(\(unitSettings.formatLength(val)))"
        }
    }
}

