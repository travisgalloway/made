import Foundation
import simd

/// Parameter input stored as a mathematical or parametric expression (BL-PAR-02).
public struct FeatureExpression: Sendable, Codable, Equatable {
    public var formula: String
    public var value: Double

    public init(formula: String, value: Double) {
        self.formula = formula
        self.value = value
    }

    public init(value: Double) {
        self.formula = "\(value)"
        self.value = value
    }

    public init(value: Float) {
        self.formula = "\(value)"
        self.value = Double(value)
    }
}

/// Persisted diagnostic information when regeneration or reference binding fails (BL-FND-04).
public struct FeatureErrorState: Sendable, Codable, Equatable {
    public var code: String
    public var message: String
    public var timestamp: Date

    public init(code: String, message: String, timestamp: Date = Date()) {
        self.code = code
        self.message = message
        self.timestamp = timestamp
    }
}

/// Parameter payloads for primitive solid features.
public enum PrimitiveFeatureData: Sendable, Codable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams)
}

/// Individual entity within a 2D sketch (line, arc, circle, constraint).
public struct SketchEntity: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: String
    public var data: [String: Double]

    public init(id: UUID = UUID(), kind: String, data: [String: Double] = [:]) {
        self.id = id
        self.kind = kind
        self.data = data
    }
}

/// Definition of a 2D sketch plane and its constituent geometric entities.
public struct SketchFeatureData: Sendable, Codable, Equatable {
    public var planeName: String?
    public var planeReference: TopologicalReference?
    public var entities: [SketchEntity]

    public init(planeName: String? = nil, planeReference: TopologicalReference? = nil, entities: [SketchEntity] = []) {
        self.planeName = planeName
        self.planeReference = planeReference
        self.entities = entities
    }
}

/// Extrusion operation parameters projecting a sketch profile into 3D.
public struct ExtrudeFeatureData: Sendable, Codable, Equatable {
    public var sketchFeatureId: UUID?
    public var distance: Double
    public var isSymmetric: Bool
    public var draftAngle: Double

    public init(
        sketchFeatureId: UUID? = nil,
        distance: Double,
        isSymmetric: Bool = false,
        draftAngle: Double = 0.0
    ) {
        self.sketchFeatureId = sketchFeatureId
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.draftAngle = draftAngle
    }
}

/// CSG boolean operation parameters referencing target and tool solids.
public struct BooleanFeatureData: Sendable, Codable, Equatable {
    public var op: BooleanOp
    public var targetSolidId: SolidId
    public var toolSolidId: SolidId

    public init(op: BooleanOp, targetSolidId: SolidId, toolSolidId: SolidId) {
        self.op = op
        self.targetSolidId = targetSolidId
        self.toolSolidId = toolSolidId
    }
}

/// Scripted part file definition on disk with last-evaluated shape tree.
public struct PartFeatureData: Sendable, Codable, Equatable {
    public var url: URL
    public var shape: ShapeNode?

    public init(url: URL, shape: ShapeNode? = nil) {
        self.url = url
        self.shape = shape
    }
}

/// Imported B-Rep or mesh file definition.
public struct ImportedFeatureData: Sendable, Codable, Equatable {
    public var name: String
    public var sourceURL: URL?
    public var data: Data?

    public init(name: String, sourceURL: URL? = nil, data: Data? = nil) {
        self.name = name
        self.sourceURL = sourceURL
        self.data = data
    }
}

/// Discrete modeling operation recorded in the history timeline (ADR-D2).
public enum FeatureOperation: Sendable, Codable, Equatable {
    case primitive(PrimitiveFeatureData)
    case sketch(SketchFeatureData)
    case extrude(ExtrudeFeatureData)
    case boolean(BooleanFeatureData)
    case part(PartFeatureData)
    case imported(ImportedFeatureData)
}

/// Canonical parametric modeling feature in an ordered linear history (ADR-D2).
public struct Feature: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var operation: FeatureOperation
    public var inputExpressions: [String: FeatureExpression]
    public var references: [TopologicalReference]
    public var isSuppressed: Bool
    public var errorState: FeatureErrorState?
    public var generatedTopology: [String: TopologicalReference]
    public var outputSolidId: SolidId?
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes

    public init(
        id: UUID = UUID(),
        name: String,
        operation: FeatureOperation,
        inputExpressions: [String: FeatureExpression] = [:],
        references: [TopologicalReference] = [],
        isSuppressed: Bool = false,
        errorState: FeatureErrorState? = nil,
        generatedTopology: [String: TopologicalReference] = [:],
        outputSolidId: SolidId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) {
        self.id = id
        self.name = name
        self.operation = operation
        self.inputExpressions = inputExpressions
        self.references = references
        self.isSuppressed = isSuppressed
        self.errorState = errorState
        self.generatedTopology = generatedTopology
        self.outputSolidId = outputSolidId
        self.transform = transform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.material = material
    }

    /// Converts this feature into a `SceneObject` if active, non-suppressed, and producing an output solid.
    public func toSceneObject() -> SceneObject? {
        guard !isSuppressed, let solidId = outputSolidId else { return nil }
        let def: ObjectDef
        switch operation {
        case .primitive(.box(let p)):
            def = .box(p)
        case .primitive(.cylinder(let p)):
            def = .cylinder(p)
        case .boolean(let b):
            def = .boolean(op: b.op, solidA: b.targetSolidId, solidB: b.toolSolidId)
        case .part(let p):
            def = .part(url: p.url, shape: p.shape)
        case .imported(let imp):
            def = .imported(name: imp.name, sourceURL: imp.sourceURL, data: imp.data)
        case .sketch, .extrude:
            return nil
        }
        return SceneObject(
            id: solidId,
            name: name,
            def: def,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }
}

// MARK: - Factory Helpers

extension Feature {
    /// Factory helper to build a primitive box feature with populated topology and expressions.
    public static func makeBox(
        id: UUID = UUID(),
        solidId: SolidId? = nil,
        name: String? = nil,
        params: BoxParams,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Box 1"
        var topology: [String: TopologicalReference] = [:]

        let faces: [(String, SIMD3<Float>)] = [
            ("face:top", SIMD3<Float>(0, 0, 1)),
            ("face:bottom", SIMD3<Float>(0, 0, -1)),
            ("face:front", SIMD3<Float>(0, -1, 0)),
            ("face:back", SIMD3<Float>(0, 1, 0)),
            ("face:right", SIMD3<Float>(1, 0, 0)),
            ("face:left", SIMD3<Float>(-1, 0, 0))
        ]

        for (label, normal) in faces {
            topology[label] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .face,
                historyPath: [HistoryStep(kind: .generated, label: label)],
                disambiguator: GeometricSignature(
                    surfaceOrCurveType: "plane",
                    normal: normal
                )
            )
        }

        let expressions: [String: FeatureExpression] = [
            "width": FeatureExpression(value: Double(params.width)),
            "depth": FeatureExpression(value: Double(params.depth)),
            "height": FeatureExpression(value: Double(params.height))
        ]

        return Feature(
            id: featureId,
            name: featureName,
            operation: .primitive(.box(params)),
            inputExpressions: expressions,
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: topology,
            outputSolidId: solidId,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }

    /// Factory helper to build a primitive cylinder feature with populated topology and expressions.
    public static func makeCylinder(
        id: UUID = UUID(),
        solidId: SolidId? = nil,
        name: String? = nil,
        params: CylinderParams,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Cylinder 1"
        var topology: [String: TopologicalReference] = [:]

        topology["face:top"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 0, 1)
            )
        )
        topology["face:bottom"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:bottom")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 0, -1)
            )
        )
        topology["face:side"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:side")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "cylinder"
            )
        )

        let expressions: [String: FeatureExpression] = [
            "radius": FeatureExpression(value: Double(params.radius)),
            "height": FeatureExpression(value: Double(params.height))
        ]

        return Feature(
            id: featureId,
            name: featureName,
            operation: .primitive(.cylinder(params)),
            inputExpressions: expressions,
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: topology,
            outputSolidId: solidId,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }

    /// Initializes a feature from an existing `SceneObject` representation.
    public init(from object: SceneObject) {
        switch object.def {
        case .box(let params):
            self = Feature.makeBox(
                solidId: object.id,
                name: object.name,
                params: params,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .cylinder(let params):
            self = Feature.makeCylinder(
                solidId: object.id,
                name: object.name,
                params: params,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .boolean(let op, let solidA, let solidB):
            self.init(
                name: object.name,
                operation: .boolean(BooleanFeatureData(op: op, targetSolidId: solidA, toolSolidId: solidB)),
                outputSolidId: object.id,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .part(let url, let shape):
            self.init(
                name: object.name,
                operation: .part(PartFeatureData(url: url, shape: shape)),
                outputSolidId: object.id,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .imported(let name, let sourceURL, let data):
            self.init(
                name: object.name,
                operation: .imported(ImportedFeatureData(name: name, sourceURL: sourceURL, data: data)),
                outputSolidId: object.id,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        }
    }
}
