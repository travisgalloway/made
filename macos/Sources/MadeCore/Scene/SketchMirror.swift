import Foundation
import simd

/// The entities and geometric constraints resulting from a 2D sketch mirror operation.
public struct SketchMirrorResult: Sendable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(entities: [SketchEntity], constraints: [SketchConstraint]) {
        self.entities = entities
        self.constraints = constraints
    }
}

/// Geometric engine reflecting sketch entities across an axis line with inverted arc chirality and symmetry constraints.
public enum SketchMirror {
    public static let minDimensionTolerance: Double = 1e-4

    /// Reflects a collection of sketch entities across a line entity.
    ///
    /// Inverts arc sweep chirality (`clockwise: !isClockwise`), creates `.symmetric` constraints
    /// with `referenceEntityId: mirrorLine.id`, and generates `.coincident` constraints for points/endpoints on the axis.
    public static func makeMirror(
        entities: [SketchEntity],
        mirrorLine: SketchEntity
    ) throws -> SketchMirrorResult {
        guard mirrorLine.kind == "line",
              let mStart = mirrorLine.startPoint,
              let mEnd = mirrorLine.endPoint else {
            throw SketchError.degenerateMirror("Mirror axis entity must be a valid line with endpoints")
        }

        let axisVec = mEnd - mStart
        let axisLen = hypot(axisVec.x, axisVec.y)
        guard axisLen > minDimensionTolerance else {
            throw SketchError.degenerateMirror("Mirror axis length (\(axisLen)) must exceed \(minDimensionTolerance)")
        }

        let candidates = entities.filter { $0.id != mirrorLine.id }
        guard !candidates.isEmpty else {
            throw SketchError.degenerateMirror("No entities provided to mirror")
        }

        let uAxis = axisVec / axisLen
        let nAxis = SIMD2<Double>(-uAxis.y, uAxis.x)
        let thetaAxis = atan2(axisVec.y, axisVec.x)

        func reflect(_ p: SIMD2<Double>) -> SIMD2<Double> {
            let d = simd_dot(p - mStart, nAxis)
            return p - 2.0 * d * nAxis
        }

        func isOnAxis(_ p: SIMD2<Double>) -> Bool {
            abs(simd_dot(p - mStart, nAxis)) <= minDimensionTolerance
        }

        var mirroredEntities: [SketchEntity] = []
        var generatedConstraints: [SketchConstraint] = []

        for entity in candidates {
            let mirrored: SketchEntity
            var pointsToCheck: [SIMD2<Double>] = []

            switch entity.kind {
            case "line":
                guard let s = entity.startPoint, let e = entity.endPoint else {
                    throw SketchError.degenerateMirror("Line entity \(entity.id) is missing endpoints")
                }
                let sPrime = reflect(s)
                let ePrime = reflect(e)
                mirrored = SketchEntity.line(
                    start: sPrime,
                    end: ePrime,
                    isConstruction: entity.isConstruction
                )
                pointsToCheck = [s, e]

            case "circle":
                guard let c = entity.centerPoint, let r = entity.radius else {
                    throw SketchError.degenerateMirror("Circle entity \(entity.id) is missing center or radius")
                }
                let cPrime = reflect(c)
                mirrored = SketchEntity.circle(
                    center: cPrime,
                    radius: r,
                    isConstruction: entity.isConstruction
                )
                if isOnAxis(c) {
                    pointsToCheck.append(c)
                }

            case "arc":
                guard let c = entity.centerPoint,
                      let s = entity.startPoint,
                      let e = entity.endPoint else {
                    throw SketchError.degenerateMirror("Arc entity \(entity.id) is missing center or endpoints")
                }
                let cPrime = reflect(c)
                let sPrime = reflect(s)
                let ePrime = reflect(e)
                // Invert chirality: reflection changes orientation between clockwise and counter-clockwise
                mirrored = SketchEntity.arc(
                    start: sPrime,
                    end: ePrime,
                    center: cPrime,
                    clockwise: !entity.isClockwise,
                    isConstruction: entity.isConstruction
                )
                pointsToCheck = [s, e]

            case "ellipse":
                guard let c = entity.centerPoint,
                      let rx = entity.radiusX,
                      let ry = entity.radiusY else {
                    throw SketchError.degenerateMirror("Ellipse entity \(entity.id) is missing center or radii")
                }
                let cPrime = reflect(c)
                let rot = entity.rotationAngle ?? 0.0
                let rotPrime = 2.0 * thetaAxis - rot
                mirrored = SketchEntity.ellipse(
                    center: cPrime,
                    radiusX: rx,
                    radiusY: ry,
                    rotation: rotPrime,
                    isConstruction: entity.isConstruction
                )
                if isOnAxis(c) {
                    pointsToCheck.append(c)
                }

            case "ellipticalArc":
                guard let c = entity.centerPoint,
                      let rx = entity.radiusX,
                      let ry = entity.radiusY,
                      let sAngle = entity.startAngle,
                      let eAngle = entity.endAngle else {
                    throw SketchError.degenerateMirror("Elliptical arc entity \(entity.id) is missing required parameters")
                }
                let cPrime = reflect(c)
                let rot = entity.rotationAngle ?? 0.0
                let rotPrime = 2.0 * thetaAxis - rot
                let sAnglePrime = 2.0 * thetaAxis - sAngle
                let eAnglePrime = 2.0 * thetaAxis - eAngle
                mirrored = SketchEntity.ellipticalArc(
                    center: cPrime,
                    radiusX: rx,
                    radiusY: ry,
                    rotation: rotPrime,
                    startAngle: sAnglePrime,
                    endAngle: eAnglePrime,
                    clockwise: !entity.isClockwise,
                    isConstruction: entity.isConstruction
                )
                if let s = entity.startPoint, let e = entity.endPoint {
                    pointsToCheck = [s, e]
                }

            case "point":
                guard let pt = entity.pointPosition else {
                    throw SketchError.degenerateMirror("Point entity \(entity.id) is missing position")
                }
                let ptPrime = reflect(pt)
                mirrored = SketchEntity.point(
                    position: ptPrime,
                    isConstruction: entity.isConstruction
                )
                pointsToCheck = [pt]

            default:
                throw SketchError.degenerateMirror("Unsupported entity kind '\(entity.kind)' for mirror")
            }

            mirroredEntities.append(mirrored)

            // Symmetric constraint between original and mirrored entity across mirror axis
            generatedConstraints.append(SketchConstraint(
                kind: .symmetric,
                entityIds: [entity.id, mirrored.id],
                referenceEntityId: mirrorLine.id
            ))

            // Coincident constraint for points/endpoints on the mirror axis
            for pt in pointsToCheck {
                if isOnAxis(pt) {
                    generatedConstraints.append(SketchConstraint(
                        kind: .coincident,
                        entityIds: [mirrored.id, mirrorLine.id]
                    ))
                    break
                }
            }
        }

        return SketchMirrorResult(entities: mirroredEntities, constraints: generatedConstraints)
    }
}
