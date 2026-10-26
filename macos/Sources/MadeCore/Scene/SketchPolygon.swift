import Foundation
import simd

/// Sizing mode for regular polygon creation.
public enum SketchPolygonKind: String, Sendable, Codable, CaseIterable, Equatable {
    case inscribed
    case circumscribed
}

/// The entities, constraints, and vertex positions resulting from regular polygon generation.
public struct SketchPolygonResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public var vertices: [SIMD2<Double>]
    public var guideCircle: SketchEntity?

    public init(
        entities: [SketchEntity],
        constraints: [SketchConstraint],
        vertices: [SIMD2<Double>],
        guideCircle: SketchEntity? = nil
    ) {
        self.entities = entities
        self.constraints = constraints
        self.vertices = vertices
        self.guideCircle = guideCircle
    }
}

/// Geometric engine generating regular polygons with 3 to 64 sides and closed perimeter constraints.
public enum SketchPolygon {
    public static let minDimensionTolerance: Double = 1e-4

    /// Generates a regular polygon with N sides, centered at `center`.
    public static func makeRegularPolygon(
        center: SIMD2<Double>,
        radius: Double,
        sides: Int,
        rotationAngle: Double = 0.0,
        kind: SketchPolygonKind = .inscribed,
        addGuideCircle: Bool = false
    ) throws -> SketchPolygonResult {
        guard sides >= 3 && sides <= 64 else {
            throw SketchError.degeneratePolygon("Regular polygon side count (\(sides)) must be between 3 and 64")
        }
        guard radius > minDimensionTolerance else {
            throw SketchError.degeneratePolygon("Regular polygon radius (\(radius)) must exceed \(minDimensionTolerance)")
        }

        let effectiveRadius: Double
        switch kind {
        case .inscribed:
            effectiveRadius = radius
        case .circumscribed:
            effectiveRadius = radius / cos(Double.pi / Double(sides))
        }

        var vertices: [SIMD2<Double>] = []
        vertices.reserveCapacity(sides)
        for k in 0..<sides {
            let theta = rotationAngle + (2.0 * Double.pi * Double(k)) / Double(sides)
            let vk = center + SIMD2<Double>(effectiveRadius * cos(theta), effectiveRadius * sin(theta))
            vertices.append(vk)
        }

        var lines: [SketchEntity] = []
        lines.reserveCapacity(sides)
        for k in 0..<sides {
            let start = vertices[k]
            let end = vertices[(k + 1) % sides]
            lines.append(SketchEntity.line(start: start, end: end))
        }

        var constraints: [SketchConstraint] = []
        constraints.reserveCapacity(sides)
        for k in 0..<sides {
            let currentLine = lines[k]
            let nextLine = lines[(k + 1) % sides]
            constraints.append(SketchConstraint(kind: .coincident, entityIds: [currentLine.id, nextLine.id]))
        }

        var guide: SketchEntity? = nil
        var allEntities = lines
        if addGuideCircle {
            let circle = SketchEntity.circle(center: center, radius: radius, isConstruction: true)
            guide = circle
            allEntities.append(circle)
        }

        return SketchPolygonResult(
            entities: allEntities,
            constraints: constraints,
            vertices: vertices,
            guideCircle: guide
        )
    }
}
