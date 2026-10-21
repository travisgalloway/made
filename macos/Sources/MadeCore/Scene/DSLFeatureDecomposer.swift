import Foundation
import simd

/// Error encountered during decomposition of a `ShapeNode` AST into parametric features.
public enum DSLDecompositionError: LocalizedError, Equatable, Sendable {
    case invalidShape(String)
    case unsupportedNode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidShape(let message):
            return "Invalid shape: \(message)"
        case .unsupportedNode(let message):
            return "Unsupported node: \(message)"
        }
    }
}

/// The result of decomposing a `ShapeNode` tree into ordered parametric features.
public struct DecomposedFeaturesResult: Sendable, Equatable {
    public var features: [Feature]
    public var rootSolidId: SolidId?
    public var maxSequence: Int

    public init(features: [Feature], rootSolidId: SolidId?, maxSequence: Int) {
        self.features = features
        self.rootSolidId = rootSolidId
        self.maxSequence = maxSequence
    }
}

/// Translates a `ShapeNode` AST into an ordered sequence of parametric `Feature` records (BL-SCR-04 / #332).
public enum DSLFeatureDecomposer {

    private final class DecomposeContext {
        var currentSequence: Int
        var boxCount = 0
        var cylinderCount = 0
        var sphereCount = 0
        var coneCount = 0
        var sketchCount = 0
        var extrudeCount = 0
        var booleanCount = 0
        let baseName: String?

        init(startingSequence: Int, baseName: String?) {
            self.currentSequence = startingSequence
            self.baseName = baseName
        }

        func nextSolidId(prefix: String) -> SolidId {
            currentSequence += 1
            return SolidId("\(prefix)-\(currentSequence)")
        }
    }

    /// Decomposes a `ShapeNode` tree into ordered `Feature` instances.
    public static func decompose(
        _ shape: ShapeNode,
        baseName: String? = nil,
        startingSequence: Int = 0
    ) throws -> DecomposedFeaturesResult {
        if let err = shape.validate() {
            throw DSLDecompositionError.invalidShape(err.message)
        }

        let context = DecomposeContext(startingSequence: startingSequence, baseName: baseName)
        let (features, rootSolidId) = try decomposeNode(
            shape,
            transform: .identity,
            isRoot: true,
            context: context
        )

        return DecomposedFeaturesResult(
            features: features,
            rootSolidId: rootSolidId,
            maxSequence: context.currentSequence
        )
    }

    private static func decomposeNode(
        _ node: ShapeNode,
        transform: Transform,
        isRoot: Bool,
        context: DecomposeContext
    ) throws -> (features: [Feature], rootSolidId: SolidId?) {
        switch node {
        case .box(let params):
            context.boxCount += 1
            let solidId = context.nextSolidId(prefix: "box")
            let name = (isRoot && context.baseName != nil && !context.baseName!.isEmpty) ? context.baseName! : "Box \(context.boxCount)"
            let feature = Feature.makeBox(
                solidId: solidId,
                name: name,
                params: params,
                transform: transform
            )
            return ([feature], solidId)

        case .cylinder(let params, _):
            context.cylinderCount += 1
            let solidId = context.nextSolidId(prefix: "cylinder")
            let name = (isRoot && context.baseName != nil && !context.baseName!.isEmpty) ? context.baseName! : "Cylinder \(context.cylinderCount)"
            let feature = Feature.makeCylinder(
                solidId: solidId,
                name: name,
                params: params,
                transform: transform
            )
            return ([feature], solidId)

        case .sphere(let params, _):
            context.sphereCount += 1
            let solidId = context.nextSolidId(prefix: "sphere")
            let name = (isRoot && context.baseName != nil && !context.baseName!.isEmpty) ? context.baseName! : "Sphere \(context.sphereCount)"
            let feature = Feature.makeSphere(
                solidId: solidId,
                name: name,
                params: params,
                transform: transform
            )
            return ([feature], solidId)

        case .cone(let params, _):
            context.coneCount += 1
            let solidId = context.nextSolidId(prefix: "cone")
            let name = (isRoot && context.baseName != nil && !context.baseName!.isEmpty) ? context.baseName! : "Cone \(context.coneCount)"
            let feature = Feature.makeCone(
                solidId: solidId,
                name: name,
                params: params,
                transform: transform
            )
            return ([feature], solidId)

        case .extrude(let profile, let distance, let centered):
            context.sketchCount += 1
            let sketchId = UUID()
            var entities: [SketchEntity] = []

            let outerPts = profile.points
            for i in 0..<outerPts.count {
                let p1 = outerPts[i]
                let p2 = outerPts[(i + 1) % outerPts.count]
                entities.append(SketchEntity.line(
                    start: SIMD2<Double>(Double(p1.x), Double(p1.y)),
                    end: SIMD2<Double>(Double(p2.x), Double(p2.y))
                ))
            }

            for hole in profile.holes {
                guard !hole.isEmpty else { continue }
                for i in 0..<hole.count {
                    let p1 = hole[i]
                    let p2 = hole[(i + 1) % hole.count]
                    entities.append(SketchEntity.line(
                        start: SIMD2<Double>(Double(p1.x), Double(p1.y)),
                        end: SIMD2<Double>(Double(p2.x), Double(p2.y))
                    ))
                }
            }

            let planeName = resolvePlaneName(from: profile.plane)
            let sketchFeature = Feature(
                id: sketchId,
                name: "Sketch \(context.sketchCount)",
                operation: .sketch(SketchFeatureData(planeName: planeName, entities: entities)),
                outputSolidId: nil
            )

            context.extrudeCount += 1
            let extrudeSolidId = context.nextSolidId(prefix: "extrude")
            let extrudeName = (isRoot && context.baseName != nil && !context.baseName!.isEmpty) ? context.baseName! : "Extrude \(context.extrudeCount)"
            let extrudeData = ExtrudeFeatureData(
                sketchFeatureId: sketchId,
                distance: Double(distance),
                isSymmetric: centered,
                profile: profile
            )
            let extrudeFeature = Feature(
                id: UUID(),
                name: extrudeName,
                operation: .extrude(extrudeData),
                inputExpressions: ["distance": FeatureExpression(value: Double(distance))],
                references: [.feature(sketchId, role: "sketchProfile")],
                outputSolidId: extrudeSolidId,
                bodyOperation: .create,
                targetBodyId: nil,
                transform: transform,
                isVisible: true
            )
            return ([sketchFeature, extrudeFeature], extrudeSolidId)

        case .revolve, .revolveSolid:
            throw DSLDecompositionError.unsupportedNode("revolve is not yet supported in linear feature history (BL-PRT-02)")

        case .translate(let child, let offset):
            var newTransform = transform
            newTransform.position += transform.rotation.act(offset * transform.scale)
            return try decomposeNode(child, transform: newTransform, isRoot: isRoot, context: context)

        case .rotate(let child, let axis, let angleDegrees):
            var newTransform = transform
            let rad = angleDegrees * .pi / 180.0
            let normAxis = simd_length(axis) > 1e-6 ? simd_normalize(axis) : SIMD3<Float>(0, 0, 1)
            let q = simd_quatf(angle: rad, axis: normAxis)
            newTransform.rotation = transform.rotation * q
            return try decomposeNode(child, transform: newTransform, isRoot: isRoot, context: context)

        case .scale(let child, let factor):
            var newTransform = transform
            newTransform.scale *= factor
            return try decomposeNode(child, transform: newTransform, isRoot: isRoot, context: context)

        case .boolean(let op, let lhs, let rhs):
            let lhsResult = try decomposeNode(lhs, transform: .identity, isRoot: false, context: context)
            let rhsResult = try decomposeNode(rhs, transform: .identity, isRoot: false, context: context)

            guard let solidA = lhsResult.rootSolidId else {
                throw DSLDecompositionError.invalidShape("Left operand of boolean operation produced no solid")
            }
            guard let solidB = rhsResult.rootSolidId else {
                throw DSLDecompositionError.invalidShape("Right operand of boolean operation produced no solid")
            }

            var features: [Feature] = []

            for var feat in lhsResult.features {
                if feat.outputSolidId == solidA {
                    feat.isVisible = false
                }
                features.append(feat)
            }

            for var feat in rhsResult.features {
                if feat.outputSolidId == solidB {
                    feat.isVisible = false
                }
                features.append(feat)
            }

            context.booleanCount += 1
            let boolSolidId = context.nextSolidId(prefix: "boolean")
            let name = (isRoot && context.baseName != nil && !context.baseName!.isEmpty) ? context.baseName! : "Boolean \(context.booleanCount)"

            let boolFeature = Feature(
                id: UUID(),
                name: name,
                operation: .boolean(BooleanFeatureData(op: op, targetSolidId: solidA, toolSolidId: solidB, keepTool: false)),
                references: [
                    Reference.body(solidA, role: "target"),
                    Reference.body(solidB, role: "tool")
                ],
                outputSolidId: boolSolidId,
                bodyOperation: BodyOperation(booleanOp: op) ?? .create,
                targetBodyId: solidA,
                transform: transform,
                isVisible: true
            )
            features.append(boolFeature)
            return (features, boolSolidId)
        }
    }

    private static func resolvePlaneName(from plane: SketchPlane) -> String {
        let normal = simd_length(plane.normal) > 1e-6 ? simd_normalize(plane.normal) : SIMD3<Float>(0, 0, 1)
        if abs(normal.z - 1.0) < 1e-4 || abs(normal.z - (-1.0)) < 1e-4 {
            return "XY"
        } else if abs(normal.y - 1.0) < 1e-4 || abs(normal.y - (-1.0)) < 1e-4 {
            return "XZ"
        } else if abs(normal.x - 1.0) < 1e-4 || abs(normal.x - (-1.0)) < 1e-4 {
            return "YZ"
        }
        return "XY"
    }
}
