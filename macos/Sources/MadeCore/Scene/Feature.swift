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

/// Severity of a feature error state (BL-FND-04).
public enum FeatureErrorSeverity: String, Sendable, Codable, Equatable {
    case error
    case warning
}

/// Persisted diagnostic information when regeneration or reference binding fails (BL-FND-04).
public struct FeatureErrorState: Sendable, Codable, Equatable {
    public var code: String
    public var message: String
    public var severity: FeatureErrorSeverity
    public var timestamp: Date

    public init(
        code: String,
        message: String,
        severity: FeatureErrorSeverity = .error,
        timestamp: Date = Date()
    ) {
        self.code = code
        self.message = message
        self.severity = severity
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case severity
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(String.self, forKey: .code)
        self.message = try container.decode(String.self, forKey: .message)
        self.severity = try container.decodeIfPresent(FeatureErrorSeverity.self, forKey: .severity) ?? .error
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encode(severity, forKey: .severity)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

/// Parameter payloads for primitive solid features.
public enum PrimitiveFeatureData: Sendable, Codable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams)
    case sphere(SphereParams)
    case cone(ConeParams)
    case torus(TorusParams)
    case wedge(WedgeParams)
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

    public static func line(id: UUID = UUID(), start: SIMD2<Double>, end: SIMD2<Double>) -> SketchEntity {
        SketchEntity(id: id, kind: "line", data: [
            "startX": start.x,
            "startY": start.y,
            "endX": end.x,
            "endY": end.y
        ])
    }

    public static func arc(
        id: UUID = UUID(),
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        center: SIMD2<Double>,
        clockwise: Bool = false
    ) -> SketchEntity {
        SketchEntity(id: id, kind: "arc", data: [
            "startX": start.x,
            "startY": start.y,
            "endX": end.x,
            "endY": end.y,
            "centerX": center.x,
            "centerY": center.y,
            "clockwise": clockwise ? 1.0 : 0.0
        ])
    }

    public static func circle(id: UUID = UUID(), center: SIMD2<Double>, radius: Double) -> SketchEntity {
        SketchEntity(id: id, kind: "circle", data: [
            "centerX": center.x,
            "centerY": center.y,
            "radius": radius
        ])
    }

    public var startPoint: SIMD2<Double>? {
        get {
            guard let sx = data["startX"], let sy = data["startY"] else { return nil }
            return SIMD2<Double>(sx, sy)
        }
        set {
            if let newValue {
                data["startX"] = newValue.x
                data["startY"] = newValue.y
            } else {
                data.removeValue(forKey: "startX")
                data.removeValue(forKey: "startY")
            }
        }
    }

    public var endPoint: SIMD2<Double>? {
        get {
            guard let ex = data["endX"], let ey = data["endY"] else { return nil }
            return SIMD2<Double>(ex, ey)
        }
        set {
            if let newValue {
                data["endX"] = newValue.x
                data["endY"] = newValue.y
            } else {
                data.removeValue(forKey: "endX")
                data.removeValue(forKey: "endY")
            }
        }
    }

    public var centerPoint: SIMD2<Double>? {
        get {
            guard let cx = data["centerX"], let cy = data["centerY"] else { return nil }
            return SIMD2<Double>(cx, cy)
        }
        set {
            if let newValue {
                data["centerX"] = newValue.x
                data["centerY"] = newValue.y
            } else {
                data.removeValue(forKey: "centerX")
                data.removeValue(forKey: "centerY")
            }
        }
    }

    public var radius: Double? {
        get {
            if let r = data["radius"] { return r }
            if let cp = centerPoint, let sp = startPoint {
                return hypot(sp.x - cp.x, sp.y - cp.y)
            }
            return nil
        }
        set {
            if let newValue {
                data["radius"] = newValue
            } else {
                data.removeValue(forKey: "radius")
            }
        }
    }

    public var isClockwise: Bool {
        get {
            data["clockwise"] == 1.0
        }
        set {
            data["clockwise"] = newValue ? 1.0 : 0.0
        }
    }

    public func updatingEndpoints(start: SIMD2<Double>? = nil, end: SIMD2<Double>? = nil) -> SketchEntity {
        var copy = self
        if let start {
            copy.data["startX"] = start.x
            copy.data["startY"] = start.y
        }
        if let end {
            copy.data["endX"] = end.x
            copy.data["endY"] = end.y
        }
        return copy
    }

    public func withEndpoints(start: SIMD2<Double>? = nil, end: SIMD2<Double>? = nil) -> SketchEntity {
        updatingEndpoints(start: start, end: end)
    }
}

/// Definition of a 2D sketch plane and its constituent geometric entities.
public struct SketchFeatureData: Sendable, Codable, Equatable {
    public var planeName: String?
    public var planeReference: TopologicalReference?
    public var datumPlaneFeatureId: UUID?
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(
        planeName: String? = nil,
        planeReference: TopologicalReference? = nil,
        datumPlaneFeatureId: UUID? = nil,
        entities: [SketchEntity] = [],
        constraints: [SketchConstraint] = []
    ) {
        self.planeName = planeName
        self.planeReference = planeReference
        self.datumPlaneFeatureId = datumPlaneFeatureId
        self.entities = entities
        self.constraints = constraints
    }

    enum CodingKeys: String, CodingKey {
        case planeName
        case planeReference
        case datumPlaneFeatureId
        case entities
        case constraints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planeName = try container.decodeIfPresent(String.self, forKey: .planeName)
        self.planeReference = try container.decodeIfPresent(TopologicalReference.self, forKey: .planeReference)
        self.datumPlaneFeatureId = try container.decodeIfPresent(UUID.self, forKey: .datumPlaneFeatureId)
        self.entities = try container.decodeIfPresent([SketchEntity].self, forKey: .entities) ?? []
        self.constraints = try container.decodeIfPresent([SketchConstraint].self, forKey: .constraints) ?? []
    }
}

/// Parameters defining an extruded solid in the scene graph.
public struct ExtrudeParams: Sendable, Codable, Equatable {
    public var profile: SketchProfile
    public var distance: Double
    public var isSymmetric: Bool
    public var draftAngle: Double
    public var sketchFeatureId: UUID?

    public init(
        profile: SketchProfile,
        distance: Double,
        isSymmetric: Bool = false,
        draftAngle: Double = 0.0,
        sketchFeatureId: UUID? = nil
    ) {
        self.profile = profile
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.draftAngle = draftAngle
        self.sketchFeatureId = sketchFeatureId
    }
}

/// Extrusion operation parameters projecting a sketch profile into 3D.
public struct ExtrudeFeatureData: Sendable, Codable, Equatable {
    public var sketchFeatureId: UUID?
    public var distance: Double
    public var isSymmetric: Bool
    public var draftAngle: Double
    public var profile: SketchProfile?

    public init(
        sketchFeatureId: UUID? = nil,
        distance: Double,
        isSymmetric: Bool = false,
        draftAngle: Double = 0.0,
        profile: SketchProfile? = nil
    ) {
        self.sketchFeatureId = sketchFeatureId
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.draftAngle = draftAngle
        self.profile = profile
    }
}

/// CSG boolean operation parameters referencing target and tool solids.
public struct BooleanFeatureData: Sendable, Codable, Equatable {
    public var op: BooleanOp
    public var targetSolidId: SolidId
    public var toolSolidId: SolidId
    public var keepTool: Bool

    public init(op: BooleanOp, targetSolidId: SolidId, toolSolidId: SolidId, keepTool: Bool = false) {
        self.op = op
        self.targetSolidId = targetSolidId
        self.toolSolidId = toolSolidId
        self.keepTool = keepTool
    }

    private enum CodingKeys: String, CodingKey {
        case op
        case targetSolidId
        case toolSolidId
        case keepTool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.op = try container.decode(BooleanOp.self, forKey: .op)
        self.targetSolidId = try container.decode(SolidId.self, forKey: .targetSolidId)
        self.toolSolidId = try container.decode(SolidId.self, forKey: .toolSolidId)
        self.keepTool = try container.decodeIfPresent(Bool.self, forKey: .keepTool) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(op, forKey: .op)
        try container.encode(targetSolidId, forKey: .targetSolidId)
        try container.encode(toolSolidId, forKey: .toolSolidId)
        try container.encode(keepTool, forKey: .keepTool)
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
    case datumPlane(DatumPlaneFeatureData)
}

/// Canonical parametric modeling feature in an ordered linear history (ADR-D2).
public struct Feature: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var operation: FeatureOperation
    public var inputExpressions: [String: FeatureExpression]
    public var references: [Reference]
    public var isSuppressed: Bool
    public var errorState: FeatureErrorState?
    public var generatedTopology: [String: TopologicalReference]
    public var outputSolidId: SolidId?
    public var bodyOperation: BodyOperation
    public var targetBodyId: BodyId?
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes

    public init(
        id: UUID = UUID(),
        name: String,
        operation: FeatureOperation,
        inputExpressions: [String: FeatureExpression] = [:],
        references: [Reference] = [],
        isSuppressed: Bool = false,
        errorState: FeatureErrorState? = nil,
        generatedTopology: [String: TopologicalReference] = [:],
        outputSolidId: SolidId? = nil,
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
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
        self.bodyOperation = bodyOperation
        self.targetBodyId = targetBodyId
        self.transform = transform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.material = material
    }

    /// Looks up an input reference by semantic role.
    public func reference(forRole role: String) -> Reference? {
        references.first(where: { $0.role == role })
    }

    /// Dictionary mapping semantic role names to their corresponding input references.
    public var inputReferences: [String: Reference] {
        var map: [String: Reference] = [:]
        for ref in references {
            if let role = ref.role {
                map[role] = ref
            }
        }
        return map
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case operation
        case inputExpressions
        case references
        case isSuppressed
        case errorState
        case generatedTopology
        case outputSolidId
        case bodyOperation
        case targetBodyId
        case transform
        case isVisible
        case isLocked
        case material
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.operation = try container.decode(FeatureOperation.self, forKey: .operation)
        self.inputExpressions = try container.decodeIfPresent([String: FeatureExpression].self, forKey: .inputExpressions) ?? [:]
        self.references = try container.decodeIfPresent([Reference].self, forKey: .references) ?? []
        self.isSuppressed = try container.decodeIfPresent(Bool.self, forKey: .isSuppressed) ?? false
        self.errorState = try container.decodeIfPresent(FeatureErrorState.self, forKey: .errorState)
        self.generatedTopology = try container.decodeIfPresent([String: TopologicalReference].self, forKey: .generatedTopology) ?? [:]
        self.outputSolidId = try container.decodeIfPresent(SolidId.self, forKey: .outputSolidId)
        self.bodyOperation = try container.decodeIfPresent(BodyOperation.self, forKey: .bodyOperation) ?? .create
        self.targetBodyId = try container.decodeIfPresent(SolidId.self, forKey: .targetBodyId)
        self.transform = try container.decodeIfPresent(Transform.self, forKey: .transform) ?? .identity
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.material = try container.decodeIfPresent(MaterialAttributes.self, forKey: .material) ?? MaterialAttributes()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(operation, forKey: .operation)
        try container.encode(inputExpressions, forKey: .inputExpressions)
        try container.encode(references, forKey: .references)
        try container.encode(isSuppressed, forKey: .isSuppressed)
        try container.encodeIfPresent(errorState, forKey: .errorState)
        try container.encode(generatedTopology, forKey: .generatedTopology)
        try container.encodeIfPresent(outputSolidId, forKey: .outputSolidId)
        try container.encode(bodyOperation, forKey: .bodyOperation)
        try container.encodeIfPresent(targetBodyId, forKey: .targetBodyId)
        try container.encode(transform, forKey: .transform)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(material, forKey: .material)
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
        case .primitive(.sphere(let p)):
            def = .sphere(p)
        case .primitive(.cone(let p)):
            def = .cone(p)
        case .primitive(.torus(let p)):
            def = .torus(p)
        case .primitive(.wedge(let p)):
            def = .wedge(p)
        case .boolean(let b):
            def = .boolean(op: b.op, solidA: b.targetSolidId, solidB: b.toolSolidId)
        case .part(let p):
            def = .part(url: p.url, shape: p.shape)
        case .imported(let imp):
            def = .imported(name: imp.name, sourceURL: imp.sourceURL, data: imp.data)
        case .sketch, .datumPlane:
            return nil
        case .extrude(let data):
            guard let profile = data.profile else { return nil }
            def = .extrude(ExtrudeParams(
                profile: profile,
                distance: data.distance,
                isSymmetric: data.isSymmetric,
                draftAngle: data.draftAngle,
                sketchFeatureId: data.sketchFeatureId
            ))
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
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Box 1"
        var topology: [String: TopologicalReference] = [:]

        let hw = Float(params.width) / 2.0
        let hd = Float(params.depth) / 2.0
        let hh = Float(params.height) / 2.0
        let w = Double(params.width)
        let d = Double(params.depth)
        let h = Double(params.height)

        // 6 Faces
        let faces: [(String, SIMD3<Float>, SIMD3<Float>, Double)] = [
            ("face:top", SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 0, hh), w * d),
            ("face:bottom", SIMD3<Float>(0, 0, -1), SIMD3<Float>(0, 0, -hh), w * d),
            ("face:front", SIMD3<Float>(0, -1, 0), SIMD3<Float>(0, -hd, 0), w * h),
            ("face:back", SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, hd, 0), w * h),
            ("face:right", SIMD3<Float>(1, 0, 0), SIMD3<Float>(hw, 0, 0), d * h),
            ("face:left", SIMD3<Float>(-1, 0, 0), SIMD3<Float>(-hw, 0, 0), d * h)
        ]

        for (label, normal, centroid, area) in faces {
            topology[label] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .face,
                historyPath: [HistoryStep(kind: .generated, label: label)],
                disambiguator: GeometricSignature(
                    surfaceOrCurveType: "plane",
                    normal: normal,
                    centroid: centroid,
                    areaOrLength: area
                )
            )
        }

        // 12 Edges
        let edges: [(String, SIMD3<Float>, Double)] = [
            // Top 4 edges
            ("edge:top-front", SIMD3<Float>(0, -hd, hh), w),
            ("edge:top-back", SIMD3<Float>(0, hd, hh), w),
            ("edge:top-left", SIMD3<Float>(-hw, 0, hh), d),
            ("edge:top-right", SIMD3<Float>(hw, 0, hh), d),
            // Bottom 4 edges
            ("edge:bottom-front", SIMD3<Float>(0, -hd, -hh), w),
            ("edge:bottom-back", SIMD3<Float>(0, hd, -hh), w),
            ("edge:bottom-left", SIMD3<Float>(-hw, 0, -hh), d),
            ("edge:bottom-right", SIMD3<Float>(hw, 0, -hh), d),
            // Vertical 4 edges
            ("edge:front-left", SIMD3<Float>(-hw, -hd, 0), h),
            ("edge:front-right", SIMD3<Float>(hw, -hd, 0), h),
            ("edge:back-left", SIMD3<Float>(-hw, hd, 0), h),
            ("edge:back-right", SIMD3<Float>(hw, hd, 0), h)
        ]

        for (label, centroid, length) in edges {
            topology[label] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: label)],
                disambiguator: GeometricSignature(
                    surfaceOrCurveType: "line",
                    centroid: centroid,
                    areaOrLength: length
                )
            )
        }

        // 8 Vertices
        let vertices: [(String, SIMD3<Float>)] = [
            ("vertex:top-front-left", SIMD3<Float>(-hw, -hd, hh)),
            ("vertex:top-front-right", SIMD3<Float>(hw, -hd, hh)),
            ("vertex:top-back-left", SIMD3<Float>(-hw, hd, hh)),
            ("vertex:top-back-right", SIMD3<Float>(hw, hd, hh)),
            ("vertex:bottom-front-left", SIMD3<Float>(-hw, -hd, -hh)),
            ("vertex:bottom-front-right", SIMD3<Float>(hw, -hd, -hh)),
            ("vertex:bottom-back-left", SIMD3<Float>(-hw, hd, -hh)),
            ("vertex:bottom-back-right", SIMD3<Float>(hw, hd, -hh))
        ]

        for (label, centroid) in vertices {
            topology[label] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: label)],
                disambiguator: GeometricSignature(
                    centroid: centroid
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
            bodyOperation: bodyOperation,
            targetBodyId: targetBodyId,
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
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Cylinder 1"
        var topology: [String: TopologicalReference] = [:]

        let r = Double(params.radius)
        let h = Double(params.height)
        let rf = params.radius
        let hh = params.height / 2.0

        // 3 Faces
        topology["face:top"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 0, 1),
                centroid: SIMD3<Float>(0, 0, hh),
                areaOrLength: Double.pi * r * r
            )
        )
        topology["face:bottom"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:bottom")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 0, -1),
                centroid: SIMD3<Float>(0, 0, -hh),
                areaOrLength: Double.pi * r * r
            )
        )
        topology["face:side"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:side")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "cylinder",
                centroid: SIMD3<Float>(0, 0, 0),
                areaOrLength: 2.0 * Double.pi * r * h
            )
        )

        // 3 Edges
        topology["edge:top"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:top")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "circle",
                centroid: SIMD3<Float>(0, 0, hh),
                areaOrLength: 2.0 * Double.pi * r
            )
        )
        topology["edge:bottom"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "circle",
                centroid: SIMD3<Float>(0, 0, -hh),
                areaOrLength: 2.0 * Double.pi * r
            )
        )
        topology["edge:seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:seam")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "line",
                centroid: SIMD3<Float>(rf, 0, 0),
                areaOrLength: h
            )
        )

        // 2 Vertices
        topology["vertex:top-seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:top-seam")],
            disambiguator: GeometricSignature(
                centroid: SIMD3<Float>(rf, 0, hh)
            )
        )
        topology["vertex:bottom-seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:bottom-seam")],
            disambiguator: GeometricSignature(
                centroid: SIMD3<Float>(rf, 0, -hh)
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
            bodyOperation: bodyOperation,
            targetBodyId: targetBodyId,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }

    /// Factory helper to build a primitive sphere feature with populated topology and expressions.
    public static func makeSphere(
        id: UUID = UUID(),
        solidId: SolidId? = nil,
        name: String? = nil,
        params: SphereParams,
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Sphere 1"
        var topology: [String: TopologicalReference] = [:]

        let r = Double(params.radius)
        let rf = params.radius

        // 1 Face: spherical surface
        topology["face:surface"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:surface")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "sphere",
                normal: SIMD3<Float>(0, 0, 1),
                centroid: SIMD3<Float>(0, 0, 0),
                areaOrLength: 4.0 * Double.pi * r * r
            )
        )

        // 1 Edge: seam curve
        topology["edge:seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:seam")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "circle",
                centroid: SIMD3<Float>(0, 0, 0),
                areaOrLength: 2.0 * Double.pi * r
            )
        )

        // 2 Vertices: north pole and south pole
        topology["vertex:north-pole"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:north-pole")],
            disambiguator: GeometricSignature(
                centroid: SIMD3<Float>(0, 0, rf)
            )
        )
        topology["vertex:south-pole"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:south-pole")],
            disambiguator: GeometricSignature(
                centroid: SIMD3<Float>(0, 0, -rf)
            )
        )

        let expressions: [String: FeatureExpression] = [
            "radius": FeatureExpression(value: Double(params.radius))
        ]

        return Feature(
            id: featureId,
            name: featureName,
            operation: .primitive(.sphere(params)),
            inputExpressions: expressions,
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: topology,
            outputSolidId: solidId,
            bodyOperation: bodyOperation,
            targetBodyId: targetBodyId,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }

    /// Factory helper to build a primitive cone feature with populated topology and expressions.
    public static func makeCone(
        id: UUID = UUID(),
        solidId: SolidId? = nil,
        name: String? = nil,
        params: ConeParams,
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Cone 1"
        var topology: [String: TopologicalReference] = [:]

        let rBot = Double(params.bottomRadius)
        let rTop = Double(params.topRadius)
        let h = Double(params.height)
        let hh = params.height / 2.0
        let slantHeight = sqrt(h * h + (rBot - rTop) * (rBot - rTop))

        // Faces
        topology["face:bottom"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:bottom")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 0, -1),
                centroid: SIMD3<Float>(0, 0, -hh),
                areaOrLength: Double.pi * rBot * rBot
            )
        )
        topology["face:side"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:side")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "cone",
                centroid: SIMD3<Float>(0, 0, 0),
                areaOrLength: Double.pi * (rBot + rTop) * slantHeight
            )
        )
        if params.topRadius > 0 {
            topology["face:top"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .face,
                historyPath: [HistoryStep(kind: .generated, label: "face:top")],
                disambiguator: GeometricSignature(
                    surfaceOrCurveType: "plane",
                    normal: SIMD3<Float>(0, 0, 1),
                    centroid: SIMD3<Float>(0, 0, hh),
                    areaOrLength: Double.pi * rTop * rTop
                )
            )
        }

        // Edges
        topology["edge:bottom"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "circle",
                centroid: SIMD3<Float>(0, 0, -hh),
                areaOrLength: 2.0 * Double.pi * rBot
            )
        )
        if params.topRadius > 0 {
            topology["edge:top"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: "edge:top")],
                disambiguator: GeometricSignature(
                    surfaceOrCurveType: "circle",
                    centroid: SIMD3<Float>(0, 0, hh),
                    areaOrLength: 2.0 * Double.pi * rTop
                )
            )
        }
        topology["edge:seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:seam")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "line",
                centroid: SIMD3<Float>((params.bottomRadius + params.topRadius) / 2.0, 0, 0),
                areaOrLength: slantHeight
            )
        )

        // Vertices
        if params.topRadius == 0 {
            topology["vertex:apex"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:apex")],
                disambiguator: GeometricSignature(
                    centroid: SIMD3<Float>(0, 0, hh)
                )
            )
        } else {
            topology["vertex:top-seam"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-seam")],
                disambiguator: GeometricSignature(
                    centroid: SIMD3<Float>(params.topRadius, 0, hh)
                )
            )
        }
        topology["vertex:bottom-seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:bottom-seam")],
            disambiguator: GeometricSignature(
                centroid: SIMD3<Float>(params.bottomRadius, 0, -hh)
            )
        )

        let expressions: [String: FeatureExpression] = [
            "bottomRadius": FeatureExpression(value: Double(params.bottomRadius)),
            "topRadius": FeatureExpression(value: Double(params.topRadius)),
            "height": FeatureExpression(value: Double(params.height))
        ]

        return Feature(
            id: featureId,
            name: featureName,
            operation: .primitive(.cone(params)),
            inputExpressions: expressions,
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: topology,
            outputSolidId: solidId,
            bodyOperation: bodyOperation,
            targetBodyId: targetBodyId,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }

    /// Factory helper to build a primitive torus feature with populated topology and expressions.
    public static func makeTorus(
        id: UUID = UUID(),
        solidId: SolidId? = nil,
        name: String? = nil,
        params: TorusParams,
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Torus 1"
        var topology: [String: TopologicalReference] = [:]

        let R = Double(params.majorRadius)
        let r = Double(params.minorRadius)

        // 1 Face: toroidal surface
        topology["face:surface"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:surface")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "torus",
                normal: SIMD3<Float>(0, 0, 1),
                centroid: SIMD3<Float>(0, 0, 0),
                areaOrLength: 4.0 * Double.pi * Double.pi * R * r
            )
        )

        // 2 Edges: major and minor circular seams
        topology["edge:major-seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:major-seam")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "circle",
                centroid: SIMD3<Float>(0, 0, 0),
                areaOrLength: 2.0 * Double.pi * R
            )
        )
        topology["edge:minor-seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:minor-seam")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "circle",
                centroid: SIMD3<Float>(params.majorRadius, 0, 0),
                areaOrLength: 2.0 * Double.pi * r
            )
        )

        // 1 Vertex: seam point
        topology["vertex:seam"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:seam")],
            disambiguator: GeometricSignature(
                centroid: SIMD3<Float>(params.majorRadius + params.minorRadius, 0, 0)
            )
        )

        let expressions: [String: FeatureExpression] = [
            "majorRadius": FeatureExpression(value: Double(params.majorRadius)),
            "minorRadius": FeatureExpression(value: Double(params.minorRadius))
        ]

        return Feature(
            id: featureId,
            name: featureName,
            operation: .primitive(.torus(params)),
            inputExpressions: expressions,
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: topology,
            outputSolidId: solidId,
            bodyOperation: bodyOperation,
            targetBodyId: targetBodyId,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }

    /// Factory helper to build a primitive wedge feature with populated topology and expressions.
    public static func makeWedge(
        id: UUID = UUID(),
        solidId: SolidId? = nil,
        name: String? = nil,
        params: WedgeParams,
        bodyOperation: BodyOperation = .create,
        targetBodyId: BodyId? = nil,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) -> Feature {
        let featureId = id
        let featureName = name ?? solidId?.rawValue ?? "Wedge 1"
        var topology: [String: TopologicalReference] = [:]

        let hw = params.width / 2.0
        let hd = params.depth / 2.0
        let hh = params.height / 2.0
        let tw = params.topWidth
        let w = Double(params.width)
        let d = Double(params.depth)
        let h = Double(params.height)
        let topW = Double(params.topWidth)
        let slantLen = sqrt((w - topW) * (w - topW) + h * h)

        // Faces: bottom, front, back, left, slanted, and optional top
        topology["face:bottom"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:bottom")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 0, -1),
                centroid: SIMD3<Float>(0, 0, -hh),
                areaOrLength: w * d
            )
        )
        topology["face:front"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:front")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, -1, 0),
                centroid: SIMD3<Float>(0, -hd, 0),
                areaOrLength: (w + topW) / 2.0 * h
            )
        )
        topology["face:back"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:back")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(0, 1, 0),
                centroid: SIMD3<Float>(0, hd, 0),
                areaOrLength: (w + topW) / 2.0 * h
            )
        )
        topology["face:left"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:left")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: SIMD3<Float>(-1, 0, 0),
                centroid: SIMD3<Float>(-hw, 0, 0),
                areaOrLength: d * h
            )
        )
        let slantNormal = normalize(SIMD3<Float>(Float(h), 0, Float(w - topW)))
        topology["face:slanted"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:slanted")],
            disambiguator: GeometricSignature(
                surfaceOrCurveType: "plane",
                normal: slantNormal,
                centroid: SIMD3<Float>((hw + (-hw + tw)) / 2.0, 0, 0),
                areaOrLength: slantLen * d
            )
        )
        if params.topWidth > 0 {
            topology["face:top"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .face,
                historyPath: [HistoryStep(kind: .generated, label: "face:top")],
                disambiguator: GeometricSignature(
                    surfaceOrCurveType: "plane",
                    normal: SIMD3<Float>(0, 0, 1),
                    centroid: SIMD3<Float>(-hw + tw / 2.0, 0, hh),
                    areaOrLength: topW * d
                )
            )
        }

        // Edges: bottom edges, vertical/left edges, slanted edges, top edges
        topology["edge:bottom-front"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom-front")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(0, -hd, -hh), areaOrLength: w)
        )
        topology["edge:bottom-back"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom-back")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(0, hd, -hh), areaOrLength: w)
        )
        topology["edge:bottom-left"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom-left")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw, 0, -hh), areaOrLength: d)
        )
        topology["edge:bottom-right"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom-right")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(hw, 0, -hh), areaOrLength: d)
        )

        topology["edge:front-left"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:front-left")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw, -hd, 0), areaOrLength: h)
        )
        topology["edge:back-left"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:back-left")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw, hd, 0), areaOrLength: h)
        )

        topology["edge:slanted-front"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:slanted-front")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>((hw + (-hw + tw)) / 2.0, -hd, 0), areaOrLength: slantLen)
        )
        topology["edge:slanted-back"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:slanted-back")],
            disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>((hw + (-hw + tw)) / 2.0, hd, 0), areaOrLength: slantLen)
        )

        if params.topWidth > 0 {
            topology["edge:top-front"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: "edge:top-front")],
                disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw + tw / 2.0, -hd, hh), areaOrLength: topW)
            )
            topology["edge:top-back"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: "edge:top-back")],
                disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw + tw / 2.0, hd, hh), areaOrLength: topW)
            )
            topology["edge:top-left"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: "edge:top-left")],
                disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw, 0, hh), areaOrLength: d)
            )
            topology["edge:top-slanted"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: "edge:top-slanted")],
                disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw + tw, 0, hh), areaOrLength: d)
            )
        } else {
            topology["edge:top-knife"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .edge,
                historyPath: [HistoryStep(kind: .generated, label: "edge:top-knife")],
                disambiguator: GeometricSignature(surfaceOrCurveType: "line", centroid: SIMD3<Float>(-hw, 0, hh), areaOrLength: d)
            )
        }

        // Vertices
        topology["vertex:bottom-front-left"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:bottom-front-left")],
            disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw, -hd, -hh))
        )
        topology["vertex:bottom-front-right"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:bottom-front-right")],
            disambiguator: GeometricSignature(centroid: SIMD3<Float>(hw, -hd, -hh))
        )
        topology["vertex:bottom-back-left"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:bottom-back-left")],
            disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw, hd, -hh))
        )
        topology["vertex:bottom-back-right"] = TopologicalReference(
            sourceFeatureId: featureId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:bottom-back-right")],
            disambiguator: GeometricSignature(centroid: SIMD3<Float>(hw, hd, -hh))
        )

        if params.topWidth > 0 {
            topology["vertex:top-front-left"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-front-left")],
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw, -hd, hh))
            )
            topology["vertex:top-front-right"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-front-right")],
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw + tw, -hd, hh))
            )
            topology["vertex:top-back-left"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-back-left")],
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw, hd, hh))
            )
            topology["vertex:top-back-right"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-back-right")],
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw + tw, hd, hh))
            )
        } else {
            topology["vertex:top-front-knife"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-front-knife")],
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw, -hd, hh))
            )
            topology["vertex:top-back-knife"] = TopologicalReference(
                sourceFeatureId: featureId,
                elementType: .vertex,
                historyPath: [HistoryStep(kind: .generated, label: "vertex:top-back-knife")],
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(-hw, hd, hh))
            )
        }

        let expressions: [String: FeatureExpression] = [
            "width": FeatureExpression(value: Double(params.width)),
            "depth": FeatureExpression(value: Double(params.depth)),
            "height": FeatureExpression(value: Double(params.height)),
            "topWidth": FeatureExpression(value: Double(params.topWidth))
        ]

        return Feature(
            id: featureId,
            name: featureName,
            operation: .primitive(.wedge(params)),
            inputExpressions: expressions,
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: topology,
            outputSolidId: solidId,
            bodyOperation: bodyOperation,
            targetBodyId: targetBodyId,
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
        case .sphere(let params):
            self = Feature.makeSphere(
                solidId: object.id,
                name: object.name,
                params: params,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .cone(let params):
            self = Feature.makeCone(
                solidId: object.id,
                name: object.name,
                params: params,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .torus(let params):
            self = Feature.makeTorus(
                solidId: object.id,
                name: object.name,
                params: params,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .wedge(let params):
            self = Feature.makeWedge(
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
                bodyOperation: BodyOperation(booleanOp: op) ?? .create,
                targetBodyId: solidA,
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
                bodyOperation: .create,
                targetBodyId: nil,
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
                bodyOperation: .create,
                targetBodyId: nil,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .extrude(let params):
            self.init(
                name: object.name,
                operation: .extrude(ExtrudeFeatureData(
                    sketchFeatureId: params.sketchFeatureId,
                    distance: params.distance,
                    isSymmetric: params.isSymmetric,
                    draftAngle: params.draftAngle,
                    profile: params.profile
                )),
                inputExpressions: ["distance": FeatureExpression(value: params.distance)],
                references: params.sketchFeatureId.map { [.feature($0, role: "sketchProfile")] } ?? [],
                outputSolidId: object.id,
                bodyOperation: .create,
                targetBodyId: nil,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        }
    }
}
