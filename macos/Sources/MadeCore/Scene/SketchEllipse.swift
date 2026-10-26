import Foundation
import simd

/// The entities and constraints resulting from ellipse or elliptical arc generation.
public struct SketchEllipseResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(
        entities: [SketchEntity],
        constraints: [SketchConstraint] = []
    ) {
        self.entities = entities
        self.constraints = constraints
    }
}

/// Geometric engine generating mathematically exact ellipses and elliptical arcs.
public enum SketchEllipse {
    public static let minDimensionTolerance: Double = 1e-4

    /// Generates an ellipse entity centered at `center` with radii `radiusX`, `radiusY`, and `rotation`.
    public static func makeEllipse(
        center: SIMD2<Double>,
        radiusX: Double,
        radiusY: Double,
        rotation: Double = 0.0,
        addAxes: Bool = false
    ) throws -> SketchEllipseResult {
        guard radiusX > minDimensionTolerance && radiusY > minDimensionTolerance else {
            throw SketchError.degenerateEllipse(
                "Ellipse radiusX (\(radiusX)) and radiusY (\(radiusY)) must exceed \(minDimensionTolerance)"
            )
        }

        let ellipse = SketchEntity.ellipse(
            center: center,
            radiusX: radiusX,
            radiusY: radiusY,
            rotation: rotation
        )

        var entities = [ellipse]
        if addAxes {
            let cosRot = cos(rotation)
            let sinRot = sin(rotation)

            // Major axis line along local X
            let maj1 = center + SIMD2<Double>(-radiusX * cosRot, -radiusX * sinRot)
            let maj2 = center + SIMD2<Double>(radiusX * cosRot, radiusX * sinRot)
            entities.append(SketchEntity.line(start: maj1, end: maj2, isConstruction: true))

            // Minor axis line along local Y
            let min1 = center + SIMD2<Double>(radiusY * sinRot, -radiusY * cosRot)
            let min2 = center + SIMD2<Double>(-radiusY * sinRot, radiusY * cosRot)
            entities.append(SketchEntity.line(start: min1, end: min2, isConstruction: true))
        }

        return SketchEllipseResult(entities: entities, constraints: [])
    }

    /// Generates an elliptical arc entity.
    public static func makeEllipticalArc(
        center: SIMD2<Double>,
        radiusX: Double,
        radiusY: Double,
        rotation: Double = 0.0,
        startAngle: Double,
        endAngle: Double,
        clockwise: Bool = false
    ) throws -> SketchEllipseResult {
        guard radiusX > minDimensionTolerance && radiusY > minDimensionTolerance else {
            throw SketchError.degenerateEllipse(
                "Elliptical arc radiusX (\(radiusX)) and radiusY (\(radiusY)) must exceed \(minDimensionTolerance)"
            )
        }
        let span = abs(endAngle - startAngle)
        guard span > minDimensionTolerance else {
            throw SketchError.degenerateEllipse(
                "Elliptical arc angular span (\(span)) must exceed \(minDimensionTolerance)"
            )
        }

        let arc = SketchEntity.ellipticalArc(
            center: center,
            radiusX: radiusX,
            radiusY: radiusY,
            rotation: rotation,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )

        return SketchEllipseResult(entities: [arc], constraints: [])
    }
}
