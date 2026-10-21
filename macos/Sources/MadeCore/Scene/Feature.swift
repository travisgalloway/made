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

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
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

    private enum CodingKeys: String, CodingKey {
        case box = "box"
        case cylinder = "cylinder"
        case sphere = "sphere"
        case cone = "cone"
        case torus = "torus"
        case wedge = "wedge"
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case payload = "_0"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.box) {
            self = .box(try Self.decodePayload(BoxParams.self, forKey: .box, from: container))
            return
        }
        if container.contains(.cylinder) {
            self = .cylinder(try Self.decodePayload(CylinderParams.self, forKey: .cylinder, from: container))
            return
        }
        if container.contains(.sphere) {
            self = .sphere(try Self.decodePayload(SphereParams.self, forKey: .sphere, from: container))
            return
        }
        if container.contains(.cone) {
            self = .cone(try Self.decodePayload(ConeParams.self, forKey: .cone, from: container))
            return
        }
        if container.contains(.torus) {
            self = .torus(try Self.decodePayload(TorusParams.self, forKey: .torus, from: container))
            return
        }
        if container.contains(.wedge) {
            self = .wedge(try Self.decodePayload(WedgeParams.self, forKey: .wedge, from: container))
            return
        }

        let rawContainer = try? decoder.container(keyedBy: AnyCodingKey.self)
        let unknownKeys = rawContainer?.allKeys.map(\.stringValue).sorted().joined(separator: ", ") ?? ""
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown PrimitiveFeatureData key: \(unknownKeys.isEmpty ? "<none>" : unknownKeys)"
            )
        )
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> T {
        if let nested = try? container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: key),
           nested.contains(.payload) {
            return try nested.decode(T.self, forKey: .payload)
        }
        return try container.decode(T.self, forKey: key)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .box(let params):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .box)
            try nested.encode(params, forKey: .payload)
        case .cylinder(let params):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .cylinder)
            try nested.encode(params, forKey: .payload)
        case .sphere(let params):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .sphere)
            try nested.encode(params, forKey: .payload)
        case .cone(let params):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .cone)
            try nested.encode(params, forKey: .payload)
        case .torus(let params):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .torus)
            try nested.encode(params, forKey: .payload)
        case .wedge(let params):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .wedge)
            try nested.encode(params, forKey: .payload)
        }
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
    public var regionId: UUID?

    public init(
        profile: SketchProfile,
        distance: Double,
        isSymmetric: Bool = false,
        draftAngle: Double = 0.0,
        sketchFeatureId: UUID? = nil,
        regionId: UUID? = nil
    ) {
        self.profile = profile
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.draftAngle = draftAngle
        self.sketchFeatureId = sketchFeatureId
        self.regionId = regionId
    }
}

/// Extrusion operation parameters projecting a sketch profile into 3D.
public struct ExtrudeFeatureData: Sendable, Codable, Equatable {
    public var sketchFeatureId: UUID?
    public var distance: Double
    public var isSymmetric: Bool
    public var draftAngle: Double
    public var profile: SketchProfile?
    public var regionId: UUID?

    public init(
        sketchFeatureId: UUID? = nil,
        distance: Double,
        isSymmetric: Bool = false,
        draftAngle: Double = 0.0,
        profile: SketchProfile? = nil,
        regionId: UUID? = nil
    ) {
        self.sketchFeatureId = sketchFeatureId
        self.distance = distance
        self.isSymmetric = isSymmetric
        self.draftAngle = draftAngle
        self.profile = profile
        self.regionId = regionId
    }
}

/// Supported revolve modes for revolving sketch profiles (BL-PRT-02).
public enum RevolveMode: String, Sendable, Codable, Equatable, CaseIterable {
    case full
    case angle
    case symmetric
    case twoDirection
}

/// Parameters defining a revolved solid in the scene graph.
public struct RevolveParams: Sendable, Codable, Equatable {
    public var profile: SketchProfile
    public var mode: RevolveMode
    public var angle: Double
    public var angle2: Double
    public var axisOrigin: SIMD3<Float>
    public var axisDirection: SIMD3<Float>
    public var sketchFeatureId: UUID?
    public var regionId: UUID?
    public var axisReference: Reference?

    public init(
        profile: SketchProfile,
        mode: RevolveMode = .full,
        angle: Double = 360.0,
        angle2: Double = 0.0,
        axisOrigin: SIMD3<Float> = .zero,
        axisDirection: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        sketchFeatureId: UUID? = nil,
        regionId: UUID? = nil,
        axisReference: Reference? = nil
    ) {
        self.profile = profile
        self.mode = mode
        self.angle = angle
        self.angle2 = angle2
        self.axisOrigin = axisOrigin
        self.axisDirection = axisDirection
        self.sketchFeatureId = sketchFeatureId
        self.regionId = regionId
        self.axisReference = axisReference
    }
}

/// Revolve operation parameters sweeping a sketch profile around an axis in 3D.
public struct RevolveFeatureData: Sendable, Codable, Equatable {
    public var sketchFeatureId: UUID?
    public var regionId: UUID?
    public var mode: RevolveMode
    public var angle: Double
    public var angle2: Double
    public var axisReference: Reference?
    public var profile: SketchProfile?
    public var axisOrigin: SIMD3<Float>?
    public var axisDirection: SIMD3<Float>?

    public init(
        sketchFeatureId: UUID? = nil,
        regionId: UUID? = nil,
        mode: RevolveMode = .full,
        angle: Double = 360.0,
        angle2: Double = 0.0,
        axisReference: Reference? = nil,
        profile: SketchProfile? = nil,
        axisOrigin: SIMD3<Float>? = nil,
        axisDirection: SIMD3<Float>? = nil
    ) {
        self.sketchFeatureId = sketchFeatureId
        self.regionId = regionId
        self.mode = mode
        self.angle = angle
        self.angle2 = angle2
        self.axisReference = axisReference
        self.profile = profile
        self.axisOrigin = axisOrigin
        self.axisDirection = axisDirection
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

/// CSG boolean combine operation parameters referencing target and tool bodies (BL-PRT-18).
public struct CombineFeatureData: Sendable, Codable, Equatable {
    public var targetBodyId: BodyId
    public var toolBodyId: BodyId
    public var operation: BooleanOp
    public var keepTool: Bool

    public init(
        targetBodyId: BodyId,
        toolBodyId: BodyId,
        operation: BooleanOp,
        keepTool: Bool = false
    ) {
        self.targetBodyId = targetBodyId
        self.toolBodyId = toolBodyId
        self.operation = operation
        self.keepTool = keepTool
    }
}

/// Parameters for moving a solid body via a spatial transform (BL-PRT-18).
public struct MoveBodyFeatureData: Sendable, Codable, Equatable {
    public var targetBodyId: BodyId
    public var transform: Transform

    public init(targetBodyId: BodyId, transform: Transform) {
        self.targetBodyId = targetBodyId
        self.transform = transform
    }
}

/// Parameters for copying/duplicating a solid body (BL-PRT-18).
public struct CopyBodyFeatureData: Sendable, Codable, Equatable {
    public var sourceBodyId: BodyId
    public var newBodyId: BodyId
    public var transform: Transform

    public init(sourceBodyId: BodyId, newBodyId: BodyId, transform: Transform = .identity) {
        self.sourceBodyId = sourceBodyId
        self.newBodyId = newBodyId
        self.transform = transform
    }
}

/// Parameters for deleting a solid body from the active model (BL-PRT-18).
public struct DeleteBodyFeatureData: Sendable, Codable, Equatable {
    public var targetBodyId: BodyId

    public init(targetBodyId: BodyId) {
        self.targetBodyId = targetBodyId
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

    private enum CodingKeys: String, CodingKey {
        case url
        case shape
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlString = try container.decode(String.self, forKey: .url)
        let shape = try container.decodeIfPresent(ShapeNode.self, forKey: .shape)

        let parsedURL: URL = {
            if urlString.hasPrefix("file://"), let parsed = URL(string: urlString) {
                return parsed
            } else {
                return URL(fileURLWithPath: urlString)
            }
        }()

        let packageURL = decoder.userInfo[.packageURL] as? URL
        let finalURL: URL
        if let packageURL {
            if urlString.contains("/parts/") {
                finalURL = packageURL.appendingPathComponent("parts/\(parsedURL.lastPathComponent)")
            } else if !urlString.hasPrefix("/") && !urlString.hasPrefix("file://") {
                if urlString.hasPrefix("parts/") {
                    finalURL = packageURL.appendingPathComponent(urlString)
                } else {
                    finalURL = packageURL.appendingPathComponent("parts/\(urlString)")
                }
            } else {
                finalURL = parsedURL
            }
        } else {
            finalURL = parsedURL
        }

        self.init(url: finalURL, shape: shape)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let filename = url.lastPathComponent
        if !filename.isEmpty && filename != "/" {
            try container.encode("parts/\(filename)", forKey: .url)
        } else {
            try container.encode("parts/part", forKey: .url)
        }
        try container.encodeIfPresent(shape, forKey: .shape)
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

    private enum CodingKeys: String, CodingKey {
        case name
        case sourceURL
        case assetPath
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let data = try container.decodeIfPresent(Data.self, forKey: .data)
        let rawURLString = try container.decodeIfPresent(String.self, forKey: .sourceURL)
            ?? container.decodeIfPresent(String.self, forKey: .assetPath)

        let resolvedURL: URL?
        if let rawURLString {
            let parsedURL: URL = {
                if rawURLString.hasPrefix("file://"), let parsed = URL(string: rawURLString) {
                    return parsed
                } else {
                    return URL(fileURLWithPath: rawURLString)
                }
            }()
            let packageURL = decoder.userInfo[.packageURL] as? URL
            if let packageURL {
                if rawURLString.contains("/assets/") {
                    resolvedURL = packageURL.appendingPathComponent("assets/\(parsedURL.lastPathComponent)")
                } else if !rawURLString.hasPrefix("/") && !rawURLString.hasPrefix("file://") {
                    if rawURLString.hasPrefix("assets/") {
                        resolvedURL = packageURL.appendingPathComponent(rawURLString)
                    } else {
                        resolvedURL = packageURL.appendingPathComponent("assets/\(rawURLString)")
                    }
                } else {
                    resolvedURL = parsedURL
                }
            } else {
                resolvedURL = parsedURL
            }
        } else {
            resolvedURL = nil
        }

        self.init(name: name, sourceURL: resolvedURL, data: data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let sourceURL {
            let filename = sourceURL.lastPathComponent
            if !filename.isEmpty && filename != "/" {
                try container.encode("assets/\(filename)", forKey: .sourceURL)
            } else {
                try container.encode("assets/asset", forKey: .sourceURL)
            }
        }
        try container.encodeIfPresent(data, forKey: .data)
    }
}

/// Parameter payload for edge chamfer features (BL-PRT-07).
public struct ChamferFeatureData: Sendable, Codable, Equatable {
    public var targetSolidId: SolidId
    public var mode: ChamferMode
    public var distance: Double
    public var distance2: Double
    public var angle: Double
    public var edgeReferences: [TopologicalReference]

    public init(
        targetSolidId: SolidId,
        mode: ChamferMode = .equalDistance,
        distance: Double = 1.0,
        distance2: Double = 1.0,
        angle: Double = 45.0,
        edgeReferences: [TopologicalReference] = []
    ) {
        self.targetSolidId = targetSolidId
        self.mode = mode
        self.distance = distance
        self.distance2 = distance2
        self.angle = angle
        self.edgeReferences = edgeReferences
    }
}

/// Parameter payload for shell features (BL-PRT-08).
public struct ShellFeatureData: Sendable, Codable, Equatable {
    public var targetSolidId: SolidId
    public var thickness: Double
    public var removedFaceReferences: [TopologicalReference]
    public var perFaceOverrides: [FaceThicknessOverride]

    public init(
        targetSolidId: SolidId,
        thickness: Double = 1.0,
        removedFaceReferences: [TopologicalReference] = [],
        perFaceOverrides: [FaceThicknessOverride] = []
    ) {
        self.targetSolidId = targetSolidId
        self.thickness = thickness
        self.removedFaceReferences = removedFaceReferences
        self.perFaceOverrides = perFaceOverrides
    }
}

/// Discrete modeling operation recorded in the history timeline (ADR-D2).
public enum FeatureOperation: Sendable, Codable, Equatable {
    case primitive(PrimitiveFeatureData)
    case sketch(SketchFeatureData)
    case extrude(ExtrudeFeatureData)
    case revolve(RevolveFeatureData)
    case boolean(BooleanFeatureData)
    case part(PartFeatureData)
    case imported(ImportedFeatureData)
    case datumPlane(DatumPlaneFeatureData)
    case datumAxis(DatumAxisFeatureData)
    case datumPoint(DatumPointFeatureData)
    case datumCoordinateSystem(DatumCoordinateSystemFeatureData)
    case chamfer(ChamferFeatureData)
    case shell(ShellFeatureData)
    case hole(HoleFeatureData)
    case pattern(PatternFeatureData)
    case mirror(MirrorFeatureData)
    case combine(CombineFeatureData)
    case moveBody(MoveBodyFeatureData)
    case copyBody(CopyBodyFeatureData)
    case deleteBody(DeleteBodyFeatureData)

    private enum CodingKeys: String, CodingKey {
        case primitive = "primitive"
        case sketch = "sketch"
        case extrude = "extrude"
        case revolve = "revolve"
        case boolean = "boolean"
        case part = "part"
        case imported = "imported"
        case datumPlane = "datumPlane"
        case datumAxis = "datumAxis"
        case datumPoint = "datumPoint"
        case datumCoordinateSystem = "datumCoordinateSystem"
        case chamfer = "chamfer"
        case shell = "shell"
        case hole = "hole"
        case pattern = "pattern"
        case mirror = "mirror"
        case combine = "combine"
        case moveBody = "moveBody"
        case copyBody = "copyBody"
        case deleteBody = "deleteBody"
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case payload = "_0"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.primitive) {
            self = .primitive(try Self.decodePayload(PrimitiveFeatureData.self, forKey: .primitive, from: container))
            return
        }
        if container.contains(.sketch) {
            self = .sketch(try Self.decodePayload(SketchFeatureData.self, forKey: .sketch, from: container))
            return
        }
        if container.contains(.extrude) {
            self = .extrude(try Self.decodePayload(ExtrudeFeatureData.self, forKey: .extrude, from: container))
            return
        }
        if container.contains(.revolve) {
            self = .revolve(try Self.decodePayload(RevolveFeatureData.self, forKey: .revolve, from: container))
            return
        }
        if container.contains(.boolean) {
            self = .boolean(try Self.decodePayload(BooleanFeatureData.self, forKey: .boolean, from: container))
            return
        }
        if container.contains(.part) {
            self = .part(try Self.decodePayload(PartFeatureData.self, forKey: .part, from: container))
            return
        }
        if container.contains(.imported) {
            self = .imported(try Self.decodePayload(ImportedFeatureData.self, forKey: .imported, from: container))
            return
        }
        if container.contains(.datumPlane) {
            self = .datumPlane(try Self.decodePayload(DatumPlaneFeatureData.self, forKey: .datumPlane, from: container))
            return
        }
        if container.contains(.datumAxis) {
            self = .datumAxis(try Self.decodePayload(DatumAxisFeatureData.self, forKey: .datumAxis, from: container))
            return
        }
        if container.contains(.datumPoint) {
            self = .datumPoint(try Self.decodePayload(DatumPointFeatureData.self, forKey: .datumPoint, from: container))
            return
        }
        if container.contains(.datumCoordinateSystem) {
            self = .datumCoordinateSystem(try Self.decodePayload(DatumCoordinateSystemFeatureData.self, forKey: .datumCoordinateSystem, from: container))
            return
        }
        if container.contains(.chamfer) {
            self = .chamfer(try Self.decodePayload(ChamferFeatureData.self, forKey: .chamfer, from: container))
            return
        }
        if container.contains(.shell) {
            self = .shell(try Self.decodePayload(ShellFeatureData.self, forKey: .shell, from: container))
            return
        }
        if container.contains(.hole) {
            self = .hole(try Self.decodePayload(HoleFeatureData.self, forKey: .hole, from: container))
            return
        }
        if container.contains(.pattern) {
            self = .pattern(try Self.decodePayload(PatternFeatureData.self, forKey: .pattern, from: container))
            return
        }
        if container.contains(.mirror) {
            self = .mirror(try Self.decodePayload(MirrorFeatureData.self, forKey: .mirror, from: container))
            return
        }
        if container.contains(.combine) {
            self = .combine(try Self.decodePayload(CombineFeatureData.self, forKey: .combine, from: container))
            return
        }
        if container.contains(.moveBody) {
            self = .moveBody(try Self.decodePayload(MoveBodyFeatureData.self, forKey: .moveBody, from: container))
            return
        }
        if container.contains(.copyBody) {
            self = .copyBody(try Self.decodePayload(CopyBodyFeatureData.self, forKey: .copyBody, from: container))
            return
        }
        if container.contains(.deleteBody) {
            self = .deleteBody(try Self.decodePayload(DeleteBodyFeatureData.self, forKey: .deleteBody, from: container))
            return
        }

        let rawContainer = try? decoder.container(keyedBy: AnyCodingKey.self)
        let unknownKeys = rawContainer?.allKeys.map(\.stringValue).sorted().joined(separator: ", ") ?? ""
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown FeatureOperation key: \(unknownKeys.isEmpty ? "<none>" : unknownKeys)"
            )
        )
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> T {
        if let nested = try? container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: key),
           nested.contains(.payload) {
            return try nested.decode(T.self, forKey: .payload)
        }
        return try container.decode(T.self, forKey: key)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .primitive(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .primitive)
            try nested.encode(data, forKey: .payload)
        case .sketch(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .sketch)
            try nested.encode(data, forKey: .payload)
        case .extrude(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .extrude)
            try nested.encode(data, forKey: .payload)
        case .revolve(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .revolve)
            try nested.encode(data, forKey: .payload)
        case .boolean(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .boolean)
            try nested.encode(data, forKey: .payload)
        case .part(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .part)
            try nested.encode(data, forKey: .payload)
        case .imported(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .imported)
            try nested.encode(data, forKey: .payload)
        case .datumPlane(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .datumPlane)
            try nested.encode(data, forKey: .payload)
        case .datumAxis(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .datumAxis)
            try nested.encode(data, forKey: .payload)
        case .datumPoint(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .datumPoint)
            try nested.encode(data, forKey: .payload)
        case .datumCoordinateSystem(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .datumCoordinateSystem)
            try nested.encode(data, forKey: .payload)
        case .chamfer(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .chamfer)
            try nested.encode(data, forKey: .payload)
        case .shell(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .shell)
            try nested.encode(data, forKey: .payload)
        case .hole(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .hole)
            try nested.encode(data, forKey: .payload)
        case .pattern(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .pattern)
            try nested.encode(data, forKey: .payload)
        case .mirror(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .mirror)
            try nested.encode(data, forKey: .payload)
        case .combine(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .combine)
            try nested.encode(data, forKey: .payload)
        case .moveBody(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .moveBody)
            try nested.encode(data, forKey: .payload)
        case .copyBody(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .copyBody)
            try nested.encode(data, forKey: .payload)
        case .deleteBody(let data):
            var nested = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .deleteBody)
            try nested.encode(data, forKey: .payload)
        }
    }
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
        case .combine(let b):
            def = .boolean(op: b.operation, solidA: b.targetBodyId, solidB: b.toolBodyId)
        case .part(let p):
            def = .part(url: p.url, shape: p.shape)
        case .imported(let imp):
            def = .imported(name: imp.name, sourceURL: imp.sourceURL, data: imp.data)
        case .sketch, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem, .moveBody, .copyBody, .deleteBody:
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
        case .revolve(let data):
            guard let profile = data.profile,
                  let origin = data.axisOrigin,
                  let dir = data.axisDirection else { return nil }
            def = .revolve(RevolveParams(
                profile: profile,
                mode: data.mode,
                angle: data.angle,
                angle2: data.angle2,
                axisOrigin: origin,
                axisDirection: dir,
                sketchFeatureId: data.sketchFeatureId,
                regionId: data.regionId,
                axisReference: data.axisReference
            ))
        case .chamfer(let data):
            def = .chamfer(ChamferParams(
                targetSolidId: data.targetSolidId,
                mode: data.mode,
                distance: data.distance,
                distance2: data.distance2,
                angle: data.angle,
                edgeReferences: data.edgeReferences
            ))
        case .shell(let data):
            def = .shell(ShellParams(
                targetSolidId: data.targetSolidId,
                thickness: data.thickness,
                removedFaceReferences: data.removedFaceReferences,
                perFaceOverrides: data.perFaceOverrides
            ))
        case .hole(let data):
            def = .hole(data)
        case .pattern(let data):
            def = .pattern(data)
        case .mirror(let data):
            def = .mirror(data)
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
        case .revolve(let params):
            var refs: [Reference] = []
            if let sketchId = params.sketchFeatureId {
                refs.append(.feature(sketchId, role: "sketchProfile"))
            }
            if let axisRef = params.axisReference {
                refs.append(axisRef)
            }
            self.init(
                name: object.name,
                operation: .revolve(RevolveFeatureData(
                    sketchFeatureId: params.sketchFeatureId,
                    regionId: params.regionId,
                    mode: params.mode,
                    angle: params.angle,
                    angle2: params.angle2,
                    axisReference: params.axisReference,
                    profile: params.profile,
                    axisOrigin: params.axisOrigin,
                    axisDirection: params.axisDirection
                )),
                inputExpressions: [
                    "angle": FeatureExpression(value: params.angle),
                    "angle2": FeatureExpression(value: params.angle2)
                ],
                references: refs,
                outputSolidId: object.id,
                bodyOperation: .create,
                targetBodyId: nil,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .chamfer(let params):
            var refs: [Reference] = params.edgeReferences.map { .edge($0) }
            refs.append(.body(params.targetSolidId, role: "targetBody"))
            var exprs: [String: FeatureExpression] = [
                "distance": FeatureExpression(value: params.distance)
            ]
            if params.mode == .twoDistances {
                exprs["distance2"] = FeatureExpression(value: params.distance2)
            } else if params.mode == .distanceAngle {
                exprs["angle"] = FeatureExpression(value: params.angle)
            }
            self.init(
                name: object.name,
                operation: .chamfer(ChamferFeatureData(
                    targetSolidId: params.targetSolidId,
                    mode: params.mode,
                    distance: params.distance,
                    distance2: params.distance2,
                    angle: params.angle,
                    edgeReferences: params.edgeReferences
                )),
                inputExpressions: exprs,
                references: refs,
                outputSolidId: object.id,
                bodyOperation: .cut,
                targetBodyId: params.targetSolidId,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .shell(let params):
            var refs: [Reference] = params.removedFaceReferences.map { .face($0) }
            for override in params.perFaceOverrides {
                refs.append(.face(override.faceReference))
            }
            refs.append(.body(params.targetSolidId, role: "targetBody"))
            let exprs: [String: FeatureExpression] = [
                "thickness": FeatureExpression(value: params.thickness)
            ]
            self.init(
                name: object.name,
                operation: .shell(ShellFeatureData(
                    targetSolidId: params.targetSolidId,
                    thickness: params.thickness,
                    removedFaceReferences: params.removedFaceReferences,
                    perFaceOverrides: params.perFaceOverrides
                )),
                inputExpressions: exprs,
                references: refs,
                outputSolidId: object.id,
                bodyOperation: .cut,
                targetBodyId: params.targetSolidId,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .hole(let params):
            var refs: [Reference] = [
                .face(params.faceReference),
                .body(params.targetSolidId, role: "targetBody")
            ]
            if let sketchId = params.sketchFeatureId {
                refs.append(.feature(sketchId, role: "holePoints"))
            }
            var exprs: [String: FeatureExpression] = [
                "diameter": FeatureExpression(value: params.diameter),
                "depth": FeatureExpression(value: params.depth)
            ]
            if params.counterboreDiameter > 0 {
                exprs["counterboreDiameter"] = FeatureExpression(value: params.counterboreDiameter)
                exprs["counterboreDepth"] = FeatureExpression(value: params.counterboreDepth)
            }
            if params.countersinkDiameter > 0 {
                exprs["countersinkDiameter"] = FeatureExpression(value: params.countersinkDiameter)
                exprs["countersinkAngle"] = FeatureExpression(value: params.countersinkAngle)
            }
            self.init(
                name: object.name,
                operation: .hole(params),
                inputExpressions: exprs,
                references: refs,
                outputSolidId: object.id,
                bodyOperation: .cut,
                targetBodyId: params.targetSolidId,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .pattern(let params):
            var refs: [Reference] = [
                .body(params.targetSolidId, role: "patternTarget")
            ]
            if let baseBodyId = params.baseBodySolidId {
                refs.append(.body(baseBodyId, role: "baseBody"))
            }
            var exprs: [String: FeatureExpression] = [
                "count": FeatureExpression(value: Double(params.count))
            ]
            if params.patternType == .linear {
                exprs["linearSpacing"] = FeatureExpression(value: params.linearSpacing)
            } else {
                exprs["totalAngle"] = FeatureExpression(value: params.totalAngle)
            }
            self.init(
                name: object.name,
                operation: .pattern(params),
                inputExpressions: exprs,
                references: refs,
                outputSolidId: object.id,
                bodyOperation: .create,
                targetBodyId: params.targetSolidId,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        case .mirror(let params):
            var refs: [Reference] = [
                .body(params.targetSolidId, role: "mirrorTarget")
            ]
            if let planeRef = params.planeReference {
                refs.append(planeRef)
            }
            let exprs: [String: FeatureExpression] = [:]
            self.init(
                name: object.name,
                operation: .mirror(params),
                inputExpressions: exprs,
                references: refs,
                outputSolidId: object.id,
                bodyOperation: .create,
                targetBodyId: params.targetSolidId,
                transform: object.transform,
                isVisible: object.isVisible,
                isLocked: object.isLocked,
                material: object.material
            )
        }
    }
}

public typealias FeaturePayload = FeatureOperation
