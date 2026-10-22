import Foundation
import Observation
import simd

public typealias ObjectId = SolidId

public enum ObjectDef: Sendable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams)
    case sphere(SphereParams)
    case cone(ConeParams)
    case torus(TorusParams)
    case wedge(WedgeParams)
    case imported(
        name: String,
        sourceURL: URL? = nil,
        data: Data? = nil,
        isLinked: Bool = false,
        lastModifiedDate: Date? = nil,
        fileChecksum: String? = nil
    )
    /// A boolean result: the operation and its operand IDs, with no replay (#35).
    case boolean(op: BooleanOp, solidA: ObjectId, solidB: ObjectId)
    /// A scripted `.part.ts` or `.part.js` source file on disk, with its last evaluated shape tree (#427).
    case part(url: URL, shape: ShapeNode? = nil)
    /// A solid extruded from a 2D sketch profile.
    case extrude(ExtrudeParams)
    /// A solid revolved from a 2D sketch profile about an axis (BL-PRT-02).
    case revolve(RevolveParams)
    /// A solid with chamfered edges (BL-PRT-07).
    case chamfer(ChamferParams)
    /// A solid shelled to uniform wall thickness (BL-PRT-08).
    case shell(ShellParams)
    /// A solid with holes cut into a face (BL-PRT-10).
    case hole(HoleParams)
    /// A pattern repeating bodies or features linearly or circularly (BL-PRT-12).
    case pattern(PatternParams)
    /// A mirror reflecting solid bodies about a plane (BL-PRT-14).
    case mirror(MirrorParams)
    
    public var kind: String {
        switch self {
        case .box: return "box"
        case .cylinder: return "cylinder"
        case .sphere: return "sphere"
        case .cone: return "cone"
        case .torus: return "torus"
        case .wedge: return "wedge"
        case .imported: return "imported"
        case .boolean: return "boolean"
        case .part: return "part"
        case .extrude: return "extrude"
        case .revolve: return "revolve"
        case .chamfer: return "chamfer"
        case .shell: return "shell"
        case .hole: return "hole"
        case .pattern: return "pattern"
        case .mirror: return "mirror"
        }
    }
}

public typealias ObjectDefinition = ObjectDef

extension ObjectDef {
    /// Whether this object represents an externally linked reference.
    public var isLinked: Bool {
        if case .imported(_, _, _, let isLinked, _, _) = self {
            return isLinked
        }
        return false
    }

    /// The external source URL if this object is a linked reference.
    public var linkedSourceURL: URL? {
        if case .imported(_, let sourceURL, _, let isLinked, _, _) = self, isLinked {
            return sourceURL
        }
        return nil
    }

    /// Human-readable summary of the object's primary parameters.
    public var parameterSummary: String {
        switch self {
        case .box(let p):
            return "\(Self.formatDim(p.width)) × \(Self.formatDim(p.depth)) × \(Self.formatDim(p.height)) mm"
        case .cylinder(let p):
            return "r \(Self.formatDim(p.radius)) × h \(Self.formatDim(p.height)) mm"
        case .sphere(let p):
            return "r \(Self.formatDim(p.radius)) mm"
        case .cone(let p):
            if p.topRadius > 0 {
                return "r1 \(Self.formatDim(p.bottomRadius)) × r2 \(Self.formatDim(p.topRadius)) × h \(Self.formatDim(p.height)) mm"
            } else {
                return "r \(Self.formatDim(p.bottomRadius)) × h \(Self.formatDim(p.height)) mm"
            }
        case .torus(let p):
            return "R \(Self.formatDim(p.majorRadius)) × r \(Self.formatDim(p.minorRadius)) mm"
        case .wedge(let p):
            if p.topWidth > 0 {
                return "\(Self.formatDim(p.width))(\(Self.formatDim(p.topWidth))) × \(Self.formatDim(p.depth)) × \(Self.formatDim(p.height)) mm"
            } else {
                return "\(Self.formatDim(p.width)) × \(Self.formatDim(p.depth)) × \(Self.formatDim(p.height)) mm"
            }
        case .imported(let name, _, _, _, _, _):
            return name.isEmpty ? "Imported mesh" : name
        case .boolean(let op, let solidA, let solidB):
            return "\(op.rawValue)(\(solidA.rawValue), \(solidB.rawValue))"
        case .part(let url, _):
            let filename = url.lastPathComponent
            return (filename.isEmpty || filename == "/") ? "part" : filename
        case .extrude(let p):
            return "h \(Self.formatDim(Float(p.distance))) mm"
        case .revolve(let p):
            switch p.mode {
            case .full:
                return "360°"
            case .angle:
                return "\(Self.formatDim(Float(p.angle)))°"
            case .symmetric:
                return "±\(Self.formatDim(Float(p.angle / 2.0)))°"
            case .twoDirection:
                return "\(Self.formatDim(Float(p.angle)))° / \(Self.formatDim(Float(p.angle2)))°"
            }
        case .chamfer(let p):
            switch p.mode {
            case .equalDistance:
                return "\(Self.formatDim(Float(p.distance))) mm"
            case .twoDistances:
                return "\(Self.formatDim(Float(p.distance))) × \(Self.formatDim(Float(p.distance2))) mm"
            case .distanceAngle:
                return "\(Self.formatDim(Float(p.distance))) mm × \(Self.formatDim(Float(p.angle)))°"
            }
        case .shell(let p):
            return "\(Self.formatDim(Float(p.thickness))) mm"
        case .hole(let p):
            let typePrefix: String
            switch p.holeType {
            case .simple: typePrefix = "⌀ \(Self.formatDim(Float(p.diameter)))"
            case .counterbore: typePrefix = "⌀ \(Self.formatDim(Float(p.diameter))) cb ⌀\(Self.formatDim(Float(p.counterboreDiameter)))"
            case .countersink: typePrefix = "⌀ \(Self.formatDim(Float(p.diameter))) cs ⌀\(Self.formatDim(Float(p.countersinkDiameter)))"
            case .tapped: typePrefix = p.threadMetadata?.designation ?? "M\(Self.formatDim(Float(p.diameter)))"
            }
            let depthStr = p.isThrough ? "Through" : "d \(Self.formatDim(Float(p.depth))) mm"
            return "\(typePrefix) × \(depthStr)"
        case .pattern(let p):
            switch p.patternType {
            case .linear:
                return "Linear: \(p.count)x @ \(Self.formatDim(Float(p.linearSpacing))) mm"
            case .circular:
                return "Circular: \(p.count)x @ \(Self.formatDim(Float(p.totalAngle)))°"
            }
        case .mirror(let p):
            let normalStr = "[\(Self.formatDim(Float(p.planeNormal.x))), \(Self.formatDim(Float(p.planeNormal.y))), \(Self.formatDim(Float(p.planeNormal.z)))]"
            return p.keepOriginal ? "Mirror + Original (n: \(normalStr))" : "Mirror (n: \(normalStr))"
        }
    }

    private static func formatDim(_ val: Float) -> String {
        guard !val.isNaN && !val.isInfinite else { return "—" }
        let cleanVal = val == 0 ? 0 : val
        if cleanVal.rounded() == cleanVal {
            return String(format: "%.0f", cleanVal)
        } else {
            let formatted = String(format: "%.2f", cleanVal)
            return formatted.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
    }
}

public struct MaterialAttributes: Sendable, Equatable, Codable {
    public var color: SIMD4<Float>
    
    public init(color: SIMD4<Float> = SIMD4<Float>(0.35, 0.65, 0.95, 1.0)) {
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .color) ?? SIMD4<Float>(0.35, 0.65, 0.95, 1.0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
    }
}

public struct SceneObject: Identifiable, Sendable, Equatable, PropertyContainer {
    public let id: ObjectId
    public var name: String
    public var def: ObjectDef
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
    public var metadata: [String: String]
    
    public init(
        id: ObjectId,
        name: String? = nil,
        def: ObjectDef,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name ?? id.rawValue
        self.def = def
        self.transform = transform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.material = material
        self.metadata = metadata
    }
}

extension SceneObject {
    public var isLinked: Bool { def.isLinked }
    public var linkedSourceURL: URL? { def.linkedSourceURL }
}

extension ObjectDef: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case params
        case name
        case assetPath
        case op
        case solidA
        case solidB
        case url
        case isLinked
        case lastModifiedDate
        case fileChecksum
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "box":
            let params = try container.decode(BoxParams.self, forKey: .params)
            self = DocumentLimits.clamp(.box(params))
        case "cylinder":
            let params = try container.decode(CylinderParams.self, forKey: .params)
            self = DocumentLimits.clamp(.cylinder(params))
        case "sphere":
            let params = try container.decode(SphereParams.self, forKey: .params)
            self = DocumentLimits.clamp(.sphere(params))
        case "cone":
            let params = try container.decode(ConeParams.self, forKey: .params)
            self = DocumentLimits.clamp(.cone(params))
        case "torus":
            let params = try container.decode(TorusParams.self, forKey: .params)
            self = DocumentLimits.clamp(.torus(params))
        case "wedge":
            let params = try container.decode(WedgeParams.self, forKey: .params)
            self = DocumentLimits.clamp(.wedge(params))
        case "imported":
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            let assetPath = try container.decodeIfPresent(String.self, forKey: .assetPath)
                ?? container.decodeIfPresent(String.self, forKey: .url)
            let isLinked = try container.decodeIfPresent(Bool.self, forKey: .isLinked) ?? false
            let lastModifiedDate = try container.decodeIfPresent(Date.self, forKey: .lastModifiedDate)
            let fileChecksum = try container.decodeIfPresent(String.self, forKey: .fileChecksum)
            let packageURL = decoder.userInfo[.packageURL] as? URL
            let sourceURL: URL? = assetPath.map { path in
                if isLinked {
                    if path.hasPrefix("file://"), let parsed = URL(string: path) {
                        return parsed
                    } else {
                        return URL(fileURLWithPath: path)
                    }
                } else if let packageURL {
                    if path.contains("/assets/") {
                        let filename = URL(fileURLWithPath: path).lastPathComponent
                        return packageURL.appendingPathComponent("assets/\(filename)")
                    } else if !path.hasPrefix("/") && !path.hasPrefix("file://") {
                        if path.hasPrefix("assets/") {
                            return packageURL.appendingPathComponent(path)
                        } else {
                            return packageURL.appendingPathComponent("assets/\(path)")
                        }
                    } else {
                        return URL(fileURLWithPath: path)
                    }
                } else {
                    return URL(fileURLWithPath: path)
                }
            }
            self = .imported(
                name: name,
                sourceURL: sourceURL,
                data: nil,
                isLinked: isLinked,
                lastModifiedDate: lastModifiedDate,
                fileChecksum: fileChecksum
            )
        case "boolean":
            let op = try container.decode(BooleanOp.self, forKey: .op)
            let solidA = try container.decode(ObjectId.self, forKey: .solidA)
            let solidB = try container.decode(ObjectId.self, forKey: .solidB)
            self = .boolean(op: op, solidA: solidA, solidB: solidB)
        case "part":
            let urlString = try container.decode(String.self, forKey: .url)
            let parsedURL: URL = {
                if urlString.hasPrefix("file://"), let parsed = URL(string: urlString) {
                    return parsed
                } else {
                    return URL(fileURLWithPath: urlString)
                }
            }()
            let packageURL = decoder.userInfo[.packageURL] as? URL
            let url: URL
            if let packageURL {
                if urlString.contains("/parts/") {
                    url = packageURL.appendingPathComponent("parts/\(parsedURL.lastPathComponent)")
                } else if !urlString.hasPrefix("/") && !urlString.hasPrefix("file://") {
                    if urlString.hasPrefix("parts/") {
                        url = packageURL.appendingPathComponent(urlString)
                    } else {
                        url = packageURL.appendingPathComponent("parts/\(urlString)")
                    }
                } else {
                    url = parsedURL
                }
            } else {
                url = parsedURL
            }
            self = DocumentLimits.clamp(.part(url: url, shape: nil))
        case "extrude":
            let params = try container.decode(ExtrudeParams.self, forKey: .params)
            self = DocumentLimits.clamp(.extrude(params))
        case "revolve":
            let params = try container.decode(RevolveParams.self, forKey: .params)
            self = DocumentLimits.clamp(.revolve(params))
        case "chamfer":
            let params = try container.decode(ChamferParams.self, forKey: .params)
            self = DocumentLimits.clamp(.chamfer(params))
        case "shell":
            let params = try container.decode(ShellParams.self, forKey: .params)
            self = DocumentLimits.clamp(.shell(params))
        case "hole":
            let params = try container.decode(HoleParams.self, forKey: .params)
            self = DocumentLimits.clamp(.hole(params))
        case "pattern":
            let params = try container.decode(PatternParams.self, forKey: .params)
            self = DocumentLimits.clamp(.pattern(params))
        case "mirror":
            let params = try container.decode(MirrorParams.self, forKey: .params)
            self = DocumentLimits.clamp(.mirror(params))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown ObjectDef kind: '\(kind)'")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .box(let params):
            try container.encode("box", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .cylinder(let params):
            try container.encode("cylinder", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .sphere(let params):
            try container.encode("sphere", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .cone(let params):
            try container.encode("cone", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .torus(let params):
            try container.encode("torus", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .wedge(let params):
            try container.encode("wedge", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .imported(let name, let sourceURL, _, let isLinked, let lastModifiedDate, let fileChecksum):
            try container.encode("imported", forKey: .kind)
            try container.encode(name, forKey: .name)
            if isLinked {
                try container.encode(true, forKey: .isLinked)
                try container.encodeIfPresent(lastModifiedDate, forKey: .lastModifiedDate)
                try container.encodeIfPresent(fileChecksum, forKey: .fileChecksum)
                if let sourceURL {
                    try container.encode(sourceURL.path, forKey: .assetPath)
                }
            } else {
                if let sourceURL {
                    let filename = sourceURL.lastPathComponent
                    try container.encode("assets/\(filename)", forKey: .assetPath)
                } else if !name.isEmpty {
                    let filename = (name.hasSuffix(".step") || name.hasSuffix(".stp") || name.hasSuffix(".iges") || name.hasSuffix(".igs")) ? name : "\(name).step"
                    try container.encode("assets/\(filename)", forKey: .assetPath)
                }
            }
        case .boolean(let op, let solidA, let solidB):
            try container.encode("boolean", forKey: .kind)
            try container.encode(op, forKey: .op)
            try container.encode(solidA, forKey: .solidA)
            try container.encode(solidB, forKey: .solidB)
        case .part(let url, _):
            try container.encode("part", forKey: .kind)
            let filename = url.lastPathComponent
            if !filename.isEmpty && filename != "/" {
                try container.encode("parts/\(filename)", forKey: .url)
            } else {
                try container.encode("parts/part", forKey: .url)
            }
        case .extrude(let params):
            try container.encode("extrude", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .revolve(let params):
            try container.encode("revolve", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .chamfer(let params):
            try container.encode("chamfer", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .shell(let params):
            try container.encode("shell", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .hole(let params):
            try container.encode("hole", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .pattern(let params):
            try container.encode("pattern", forKey: .kind)
            try container.encode(params, forKey: .params)
        case .mirror(let params):
            try container.encode("mirror", forKey: .kind)
            try container.encode(params, forKey: .params)
        }
    }
}

extension SceneObject: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case def
        case transform
        case isVisible
        case isLocked
        case material
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(ObjectId.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? id.rawValue
        self.def = try container.decode(ObjectDef.self, forKey: .def)
        self.transform = try container.decodeIfPresent(Transform.self, forKey: .transform) ?? .identity
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.material = try container.decodeIfPresent(MaterialAttributes.self, forKey: .material) ?? MaterialAttributes()
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(def, forKey: .def)
        try container.encode(transform, forKey: .transform)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(material, forKey: .material)
        if !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }
    }
}

extension SceneObject {
    /// Human-readable summary of the object's primary parameters.
    public var parameterSummary: String {
        def.parameterSummary
    }

    /// Convenience accessor for the solid definition kind.
    public var kind: String {
        def.kind
    }
}

public struct ParamRange: Sendable {
    public let min: Float
    public let max: Float
    
    public func clamp(_ value: Float) -> Float {
        if value.isNaN { return min }
        return Swift.min(max, Swift.max(min, value))
    }
}

public enum DocumentLimits {
    public static let boxWidth = ParamRange(min: 5, max: 90)
    public static let boxDepth = ParamRange(min: 5, max: 90)
    public static let boxHeight = ParamRange(min: 5, max: 90)
    
    public static let cylinderRadius = ParamRange(min: 5, max: 50)
    public static let cylinderHeight = ParamRange(min: 5, max: 90)

    public static let sphereRadius = ParamRange(min: 5, max: 50)

    public static let coneBottomRadius = ParamRange(min: 5, max: 50)
    public static let coneTopRadius = ParamRange(min: 0, max: 50)
    public static let coneHeight = ParamRange(min: 5, max: 90)

    public static let torusMajorRadius = ParamRange(min: 10, max: 80)
    public static let torusMinorRadius = ParamRange(min: 2, max: 30)

    public static let wedgeWidth = ParamRange(min: 5, max: 90)
    public static let wedgeDepth = ParamRange(min: 5, max: 90)
    public static let wedgeHeight = ParamRange(min: 5, max: 90)
    public static let wedgeTopWidth = ParamRange(min: 0, max: 90)
    public static let extrudeDistance = ParamRange(min: 0.01, max: 10_000)
    public static let revolveAngle = ParamRange(min: 0.1, max: 360.0)
    public static let chamferDistance = ParamRange(min: 0.01, max: 10_000)
    public static let chamferAngle = ParamRange(min: 0.1, max: 89.9)
    public static let shellThickness = ParamRange(min: 0.01, max: 10_000)
    public static let holeDiameter = ParamRange(min: 0.1, max: 10_000)
    public static let holeDepth = ParamRange(min: 0.1, max: 10_000)
    public static let countersinkAngle = ParamRange(min: 30.0, max: 150.0)
    public static let patternCount = ParamRange(min: 1, max: 1000)
    public static let patternSpacing = ParamRange(min: 0.01, max: 10_000)
    public static let patternAngle = ParamRange(min: 0.1, max: 360.0)
    
    /// World position bound per axis in mm, enforced on agent tool arguments.
    public static let position = ParamRange(min: -10_000, max: 10_000)
    
    /// Minimum scale floor enforced on interactive and scripted scale edits.
    public static let scaleFloor: Float = 0.01
    
    public static func clampBox(key: String, value: Float) -> Float {
        switch key {
        case "width": return boxWidth.clamp(value)
        case "depth": return boxDepth.clamp(value)
        case "height": return boxHeight.clamp(value)
        default: return value
        }
    }
    
    public static func clampCylinder(key: String, value: Float) -> Float {
        switch key {
        case "radius": return cylinderRadius.clamp(value)
        case "height": return cylinderHeight.clamp(value)
        default: return value
        }
    }

    public static func clampSphere(key: String, value: Float) -> Float {
        switch key {
        case "radius": return sphereRadius.clamp(value)
        default: return value
        }
    }

    public static func clampCone(key: String, value: Float) -> Float {
        switch key {
        case "bottomRadius": return coneBottomRadius.clamp(value)
        case "topRadius": return coneTopRadius.clamp(value)
        case "height": return coneHeight.clamp(value)
        default: return value
        }
    }

    public static func clampTorus(key: String, value: Float, majorRadius: Float? = nil, minorRadius: Float? = nil) -> Float {
        switch key {
        case "majorRadius":
            let maj = torusMajorRadius.clamp(value)
            if let minR = minorRadius, maj <= minR {
                return Swift.min(torusMajorRadius.max, minR + 1.0)
            }
            return maj
        case "minorRadius":
            let minR = torusMinorRadius.clamp(value)
            if let maj = majorRadius, minR >= maj {
                return Swift.max(torusMinorRadius.min, maj - 1.0)
            }
            return minR
        default: return value
        }
    }

    public static func clampWedge(key: String, value: Float, width: Float? = nil) -> Float {
        switch key {
        case "width": return wedgeWidth.clamp(value)
        case "depth": return wedgeDepth.clamp(value)
        case "height": return wedgeHeight.clamp(value)
        case "topWidth":
            let tw = wedgeTopWidth.clamp(value)
            if let w = width {
                return Swift.min(tw, w)
            }
            return tw
        default: return value
        }
    }

    public static func clampExtrude(key: String, value: Float) -> Float {
        switch key {
        case "distance": return extrudeDistance.clamp(value)
        default: return value
        }
    }

    public static func clampRevolve(key: String, value: Float) -> Float {
        switch key {
        case "angle", "angle2": return revolveAngle.clamp(value)
        default: return value
        }
    }

    public static func clampChamfer(key: String, value: Float) -> Float {
        switch key {
        case "distance", "distance2": return chamferDistance.clamp(value)
        case "angle": return chamferAngle.clamp(value)
        default: return value
        }
    }

    public static func clampShell(key: String, value: Float) -> Float {
        switch key {
        case "thickness": return shellThickness.clamp(value)
        default: return value
        }
    }

    public static func clampHole(key: String, value: Float) -> Float {
        switch key {
        case "diameter", "counterboreDiameter", "countersinkDiameter":
            return holeDiameter.clamp(value)
        case "depth", "counterboreDepth":
            return holeDepth.clamp(value)
        case "countersinkAngle":
            return countersinkAngle.clamp(value)
        default:
            return value
        }
    }

    public static func clampPattern(key: String, value: Float) -> Float {
        switch key {
        case "count": return patternCount.clamp(value)
        case "linearSpacing": return patternSpacing.clamp(value)
        case "totalAngle": return patternAngle.clamp(value)
        default: return value
        }
    }

    public static func clamp(_ def: ObjectDef) -> ObjectDef {
        switch def {
        case .box(let p):
            return .box(BoxParams(width: boxWidth.clamp(p.width), depth: boxDepth.clamp(p.depth), height: boxHeight.clamp(p.height)))
        case .cylinder(let p):
            return .cylinder(CylinderParams(radius: cylinderRadius.clamp(p.radius), height: cylinderHeight.clamp(p.height)))
        case .sphere(let p):
            return .sphere(SphereParams(radius: sphereRadius.clamp(p.radius)))
        case .cone(let p):
            return .cone(ConeParams(
                bottomRadius: coneBottomRadius.clamp(p.bottomRadius),
                topRadius: coneTopRadius.clamp(p.topRadius),
                height: coneHeight.clamp(p.height)
            ))
        case .torus(let p):
            var maj = torusMajorRadius.clamp(p.majorRadius)
            var minR = torusMinorRadius.clamp(p.minorRadius)
            if minR >= maj {
                if maj < torusMajorRadius.max {
                    minR = Swift.max(torusMinorRadius.min, maj - 1.0)
                } else {
                    maj = minR + 1.0
                }
            }
            return .torus(TorusParams(majorRadius: maj, minorRadius: minR))
        case .wedge(let p):
            let w = wedgeWidth.clamp(p.width)
            let d = wedgeDepth.clamp(p.depth)
            let h = wedgeHeight.clamp(p.height)
            let tw = Swift.min(wedgeTopWidth.clamp(p.topWidth), w)
            return .wedge(WedgeParams(width: w, depth: d, height: h, topWidth: tw))
        case .part(let url, let shape):
            return .part(url: url.standardizedFileURL, shape: shape)
        case .extrude(var p):
            let clamped = extrudeDistance.clamp(Float(p.distance))
            p.distance = Double(clamped)
            return .extrude(p)
        case .revolve(var p):
            let clampedAngle = revolveAngle.clamp(Float(p.angle))
            p.angle = Double(clampedAngle)
            let clampedAngle2 = revolveAngle.clamp(Float(p.angle2))
            p.angle2 = Double(clampedAngle2)
            return .revolve(p)
        case .chamfer(var p):
            let clampedDist = chamferDistance.clamp(Float(p.distance))
            p.distance = Double(clampedDist)
            let clampedDist2 = chamferDistance.clamp(Float(p.distance2))
            p.distance2 = Double(clampedDist2)
            let clampedAngle = chamferAngle.clamp(Float(p.angle))
            p.angle = Double(clampedAngle)
            return .chamfer(p)
        case .shell(var p):
            let clampedThickness = shellThickness.clamp(Float(p.thickness))
            p.thickness = Double(clampedThickness)
            for i in p.perFaceOverrides.indices {
                p.perFaceOverrides[i].thickness = Double(shellThickness.clamp(Float(p.perFaceOverrides[i].thickness)))
            }
            return .shell(p)
        case .hole(var p):
            p.diameter = Double(holeDiameter.clamp(Float(p.diameter)))
            p.depth = Double(holeDepth.clamp(Float(p.depth)))
            if p.counterboreDiameter > 0 {
                p.counterboreDiameter = Double(holeDiameter.clamp(Float(p.counterboreDiameter)))
            }
            if p.counterboreDepth > 0 {
                p.counterboreDepth = Double(holeDepth.clamp(Float(p.counterboreDepth)))
            }
            if p.countersinkDiameter > 0 {
                p.countersinkDiameter = Double(holeDiameter.clamp(Float(p.countersinkDiameter)))
            }
            if p.countersinkAngle > 0 {
                p.countersinkAngle = Double(countersinkAngle.clamp(Float(p.countersinkAngle)))
            }
            return .hole(p)
        case .pattern(var p):
            p.count = Int(patternCount.clamp(Float(p.count)))
            if p.patternType == .linear {
                p.linearSpacing = Double(patternSpacing.clamp(Float(p.linearSpacing)))
            } else {
                p.totalAngle = Double(patternAngle.clamp(Float(p.totalAngle)))
            }
            return .pattern(p)
        case .imported, .boolean, .mirror:
            return def
        }
    }
}

public enum DocumentMutationError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case objectLocked(ObjectId)
    case objectNotFound(ObjectId)
    case sketchError(SketchError)
    case referenceResolutionFailed(ReferenceResolutionError)
    case invalidOperation(String)

    public var description: String {
        switch self {
        case .objectLocked(let id):
            return "Solid '\(id.rawValue)' is locked and cannot be modified"
        case .objectNotFound(let id):
            return "Solid '\(id.rawValue)' not found"
        case .sketchError(let err):
            return "Sketch error: \(err.localizedDescription)"
        case .referenceResolutionFailed(let err):
            return "Reference resolution failed: \(err.description)"
        case .invalidOperation(let msg):
            return msg
        }
    }

    public var errorDescription: String? {
        description
    }
}

extension Result where Success == Void, Failure: Equatable {
    public static func == (lhs: Result<Void, Failure>, rhs: Result<Void, Failure>) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): return true
        case (.failure(let l), .failure(let r)): return l == r
        default: return false
        }
    }
}

public enum DocumentMutation: Sendable, Equatable {
    case added(ObjectId)
    case removed(ObjectId)
    case paramChanged(ObjectId, key: String, value: Float)
    case transformChanged(ObjectId, transform: Transform)
}

public let boxSolidId = SolidId("box-1")
public let cylinderSolidId = SolidId("cylinder-1")

@Observable
@MainActor
public final class DocumentModel {
    public private(set) var rollbackIndex: Int? {
        didSet {
            if let idx = rollbackIndex {
                let clamped = min(max(0, idx), features.count)
                let normalized = (clamped >= features.count) ? nil : clamped
                if normalized != rollbackIndex {
                    rollbackIndex = normalized
                    return
                }
            }
            syncObjectsFromFeatures()
        }
    }

    public private(set) var features: [Feature] = [] {
        didSet {
            if let idx = rollbackIndex {
                let clamped = min(max(0, idx), features.count)
                let normalized = (clamped >= features.count) ? nil : clamped
                if normalized != rollbackIndex {
                    rollbackIndex = normalized
                    return
                }
            }
            syncObjectsFromFeatures()
        }
    }
    public private(set) var objects: [SceneObject] = []
    public private(set) var bodies: [Body] = []
    public private(set) var parameters: [DocumentParameter] = []
    public private(set) var parameterGraph = ParameterDependencyGraph()
    public private(set) var settings: DocumentSettings = DocumentSettings()
    public private(set) var documentType: DocumentType = .part
    public private(set) var componentInstances: [ComponentInstance] = []
    public private(set) var assemblyConstraints: [AssemblyConstraint] = []
    public private(set) var componentPatterns: [ComponentPattern] = []
    public private(set) var componentMirrors: [ComponentMirror] = []
    public private(set) var explodedViews: [ExplodedView] = []
    public private(set) var activeExplodedViewId: UUID? = nil
    public private(set) var sheets: [DrawingSheet] = []
    public private(set) var activeSheetId: UUID? = nil
    public var activeSheet: DrawingSheet? {
        if let activeSheetId, let sheet = sheets.first(where: { $0.id == activeSheetId }) {
            return sheet
        }
        return sheets.first
    }
    public private(set) var selectedDrawingViewId: UUID? = nil
    public var selectedDrawingView: DrawingView? {
        guard let selectedDrawingViewId else { return nil }
        for sheet in sheets {
            if let view = sheet.views.first(where: { $0.id == selectedDrawingViewId }) {
                return view
            }
        }
        return nil
    }
    public private(set) var selectedDrawingAnnotationId: UUID? = nil
    public var selectedDrawingAnnotation: DrawingAnnotation? {
        guard let selectedDrawingAnnotationId else { return nil }
        for sheet in sheets {
            if let annotation = sheet.annotations.first(where: { $0.id == selectedDrawingAnnotationId }) {
                return annotation
            }
        }
        return nil
    }
    public private(set) var metadata: [String: String] = [:]
    private var seq: Int = 1
    @ObservationIgnored private var isSyncingObjects = false
    @ObservationIgnored private var _selection: Set<Reference> = [Reference.body(boxSolidId)]
    @ObservationIgnored private var _selectedId: ObjectId? = boxSolidId
    @ObservationIgnored private var _selectedSubElement: SelectedSubElement? = nil

    public var undoManager: UndoManager? = UndoManager() {
        didSet {
            setupUndoObservers()
            undoStateVersion += 1
        }
    }
    public private(set) var undoStateVersion: Int = 0
    public var onUndoRedoMutation: (@MainActor (DocumentMutation) -> Void)?
    private var activeInteractiveParamEdit: (id: ObjectId, key: String, initialValue: Float)?
    public private(set) var activeInteractiveSketchDrag: (featureId: UUID, initialEntities: [SketchEntity])?
    public private(set) var activeAssemblyDragInitialTransforms: [UUID: Transform]?
    private var activeAssemblyDragInitialInstances: [ComponentInstance]?
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []

    public var isRolledBack: Bool { rollbackIndex != nil }
    public var effectiveRollbackIndex: Int { rollbackIndex ?? features.count }
    public var activeFeatures: [Feature] { Array(features.prefix(effectiveRollbackIndex)) }
    public var rolledBackFeatures: [Feature] { Array(features.dropFirst(effectiveRollbackIndex)) }

    public func isFeatureActive(id: UUID) -> Bool {
        guard let idx = features.firstIndex(where: { $0.id == id }) else { return false }
        return idx < effectiveRollbackIndex
    }

    public func isFeatureActive(solidId: ObjectId) -> Bool {
        guard let idx = features.firstIndex(where: { $0.outputSolidId == solidId }) else { return false }
        return idx < effectiveRollbackIndex
    }

    public var selection: Set<Reference> {
        get {
            access(keyPath: \.selection)
            return _selection
        }
        set {
            guard _selection != newValue else { return }
            withMutation(keyPath: \.selection) {
                _selection = newValue
            }
            let derivedId = primarySolidId(for: _selection)
            if _selectedId != derivedId {
                withMutation(keyPath: \.selectedId) {
                    _selectedId = derivedId
                }
            }
            if derivedId == nil || _selectedSubElement?.solidId != derivedId {
                selectedSubElement = nil
            }
        }
    }

    public var selectedId: ObjectId? {
        get {
            access(keyPath: \.selectedId)
            return _selectedId
        }
        set {
            guard _selectedId != newValue else { return }
            withMutation(keyPath: \.selectedId) {
                _selectedId = newValue
            }
            let newSelection: Set<Reference> = {
                if let newValue {
                    return [Reference.body(newValue)]
                } else {
                    return []
                }
            }()
            if _selection != newSelection {
                withMutation(keyPath: \.selection) {
                    _selection = newSelection
                }
            }
            if newValue == nil || _selectedSubElement?.solidId != newValue {
                selectedSubElement = nil
            }
        }
    }

    public var selectedIds: Set<ObjectId> {
        get {
            access(keyPath: \.selection)
            var ids = Set<ObjectId>()
            for ref in _selection {
                switch ref.target {
                case .body(let solidId):
                    ids.insert(solidId)
                case .feature(let featId):
                    if let solidId = feature(for: featId)?.outputSolidId {
                        ids.insert(solidId)
                    }
                case .component(let compId):
                    if let comp = componentInstances.first(where: { $0.id == compId }) {
                        ids.insert(comp.solidId)
                    }
                default:
                    break
                }
            }
            return ids
        }
        set {
            let currentIds = selectedIds
            guard currentIds != newValue else { return }
            selection = Set(newValue.map { Reference.body($0) })
        }
    }

    public var selectedSubElement: SelectedSubElement? {
        get {
            access(keyPath: \.selectedSubElement)
            return _selectedSubElement
        }
        set {
            guard _selectedSubElement != newValue else { return }
            withMutation(keyPath: \.selectedSubElement) {
                _selectedSubElement = newValue
            }
            if let sub = newValue, let detId = sub.deterministicId {
                if let feat = features.first(where: { $0.outputSolidId == sub.solidId }),
                   let topRef = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                    let ref: Reference
                    switch sub.elementType {
                    case .face: ref = .face(topRef)
                    case .edge: ref = .edge(topRef)
                    case .vertex: ref = .vertex(topRef)
                    }
                    select(ref)
                }
            }
        }
    }

    private func primarySolidId(for selection: Set<Reference>) -> ObjectId? {
        if let current = _selectedId {
            let stillPresent = selection.contains { ref in
                switch ref.target {
                case .body(let solidId):
                    return solidId == current
                case .feature(let featId):
                    return feature(for: featId)?.outputSolidId == current
                case .face(let topRef), .edge(let topRef), .vertex(let topRef):
                    return feature(for: topRef.sourceFeatureId)?.outputSolidId == current
                case .component(let compId):
                    return SolidId("component-\(compId.uuidString)") == current
                default:
                    return false
                }
            }
            if stillPresent {
                return current
            }
        }

        for feat in activeFeatures {
            if let solidId = feat.outputSolidId {
                let matches = selection.contains { ref in
                    switch ref.target {
                    case .body(let sId):
                        return sId == solidId
                    case .feature(let fId):
                        return fId == feat.id
                    case .face(let topRef), .edge(let topRef), .vertex(let topRef):
                        return topRef.sourceFeatureId == feat.id
                    default:
                        return false
                    }
                }
                if matches {
                    return solidId
                }
            }
        }

        for ref in selection {
            switch ref.target {
            case .body(let solidId):
                return solidId
            case .component(let compId):
                if let comp = componentInstances.first(where: { $0.id == compId }) {
                    return comp.solidId
                }
            default:
                break
            }
        }
        return nil
    }

    // MARK: - Multi-Selection API (BL-SEL-03)

    public func select(_ reference: Reference) {
        guard !_selection.contains(reference) else { return }
        var updated = _selection
        updated.insert(reference)
        selection = updated
    }

    public func deselect(_ reference: Reference) {
        guard _selection.contains(reference) else { return }
        var updated = _selection
        updated.remove(reference)
        selection = updated
    }

    public func toggleSelection(_ reference: Reference) {
        if _selection.contains(reference) {
            deselect(reference)
        } else {
            select(reference)
        }
    }

    public func clearSelection() {
        guard !_selection.isEmpty || _selectedId != nil || _selectedSubElement != nil else { return }
        if !_selection.isEmpty {
            withMutation(keyPath: \.selection) {
                _selection = []
            }
        }
        if _selectedId != nil {
            withMutation(keyPath: \.selectedId) {
                _selectedId = nil
            }
        }
        if _selectedSubElement != nil {
            withMutation(keyPath: \.selectedSubElement) {
                _selectedSubElement = nil
            }
        }
    }

    public func isSelected(_ reference: Reference) -> Bool {
        access(keyPath: \.selection)
        return _selection.contains(reference)
    }

    public func select(solidId: ObjectId) {
        select(Reference.body(solidId))
    }

    public func deselect(solidId: ObjectId) {
        let matching = _selection.filter { ref in
            switch ref.target {
            case .body(let sId):
                return sId == solidId
            case .feature(let fId):
                return feature(for: fId)?.outputSolidId == solidId
            case .component(let compId):
                return SolidId("component-\(compId.uuidString)") == solidId
            default:
                return false
            }
        }
        guard !matching.isEmpty else { return }
        var updated = _selection
        for ref in matching {
            updated.remove(ref)
        }
        selection = updated
    }

    public func toggleSelection(solidId: ObjectId) {
        if isSelected(solidId: solidId) {
            deselect(solidId: solidId)
        } else {
            select(solidId: solidId)
        }
    }

    public func isSelected(solidId: ObjectId) -> Bool {
        access(keyPath: \.selection)
        return _selection.contains { ref in
            switch ref.target {
            case .body(let sId):
                return sId == solidId
            case .feature(let fId):
                return feature(for: fId)?.outputSolidId == solidId
            case .component(let compId):
                return SolidId("component-\(compId.uuidString)") == solidId
            default:
                return false
            }
        }
    }

    public var selectedObject: SceneObject? {
        guard let selectedId else { return nil }
        return objects.first { $0.id == selectedId }
    }

    public var selectedBody: Body? {
        guard let selectedId else { return nil }
        return body(for: selectedId)
    }

    public var selectedFeature: Feature? {
        guard let selectedId else { return nil }
        return feature(for: selectedId)
    }

    public var selectedFeatures: [Feature] {
        access(keyPath: \.selection)
        var result: [Feature] = []
        for ref in _selection {
            switch ref.target {
            case .feature(let featId):
                if let feat = feature(for: featId), !result.contains(where: { $0.id == feat.id }) {
                    result.append(feat)
                }
            case .sketchEntity(let featId, _):
                if let feat = feature(for: featId), !result.contains(where: { $0.id == feat.id }) {
                    result.append(feat)
                }
            case .body(let solidId):
                if let feat = feature(for: solidId), !result.contains(where: { $0.id == feat.id }) {
                    result.append(feat)
                }
            case .face(let topRef), .edge(let topRef), .vertex(let topRef):
                if let feat = feature(for: topRef.sourceFeatureId), !result.contains(where: { $0.id == feat.id }) {
                    result.append(feat)
                }
            case .component:
                break
            }
        }
        return result
    }

    public var selectedBodies: [Body] {
        access(keyPath: \.selection)
        var result: [Body] = []
        for ref in _selection {
            switch ref.target {
            case .body(let solidId):
                if let b = body(for: solidId), !result.contains(where: { $0.id == b.id }) {
                    result.append(b)
                }
            case .feature(let featId):
                if let solidId = feature(for: featId)?.outputSolidId, let b = body(for: solidId), !result.contains(where: { $0.id == b.id }) {
                    result.append(b)
                }
            case .component(let compId):
                let solidId = SolidId("component-\(compId.uuidString)")
                if let b = body(for: solidId), !result.contains(where: { $0.id == b.id }) {
                    result.append(b)
                }
            default:
                break
            }
        }
        return result
    }

    public func pruneInvalidSelection() {
        let validSelection = _selection.filter { ref in
            switch ReferenceResolver.resolve(reference: ref, for: nil, in: self) {
            case .success(let resolved):
                switch resolved.target {
                case .feature(let feat):
                    return isFeatureActive(id: feat.id) && !feat.isSuppressed
                case .sketchEntity(let feat, _):
                    return isFeatureActive(id: feat.id) && !feat.isSuppressed
                case .body(let solidId, let feat):
                    if let feat {
                        return isFeatureActive(id: feat.id) && !feat.isSuppressed
                    }
                    return objects.contains(where: { $0.id == solidId }) || findComponentInstance(solidId: solidId) != nil
                case .face(let feat, _), .edge(let feat, _), .vertex(let feat, _):
                    return isFeatureActive(id: feat.id) && !feat.isSuppressed
                case .component(let comp):
                    return comp.isVisible && findComponentInstance(id: comp.id) != nil
                }
            case .failure:
                return false
            }
        }
        if validSelection != _selection {
            selection = validSelection
        }
        if let selId = _selectedId, !objects.contains(where: { $0.id == selId }) && findComponentInstance(solidId: selId) == nil {
            selectedId = nil
        }
    }
    
    public init(settings: DocumentSettings = DocumentSettings(), metadata: [String: String] = [:]) {
        // Initialize with default box and cylinder scene.
        let boxFeature = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20),
            transform: Transform(position: SIMD3<Float>(-25, 0, 0))
        )
        let cylinderFeature = Feature.makeCylinder(
            solidId: cylinderSolidId,
            params: CylinderParams(radius: 15, height: 40),
            transform: Transform(position: SIMD3<Float>(25, 0, 0))
        )
        self.features = [boxFeature, cylinderFeature]
        self.rollbackIndex = nil
        self._selection = [Reference.body(boxSolidId)]
        self._selectedId = boxSolidId
        self.settings = settings
        self.metadata = metadata
        syncObjectsFromFeatures()
        self.seq = Self.computeMaxSequence(features: self.features)
        setupUndoObservers()
    }

    public init(documentType: DocumentType, componentInstances: [ComponentInstance] = [], assemblyConstraints: [AssemblyConstraint] = [], componentPatterns: [ComponentPattern] = [], componentMirrors: [ComponentMirror] = [], explodedViews: [ExplodedView] = [], activeExplodedViewId: UUID? = nil, sheets: [DrawingSheet] = [], activeSheetId: UUID? = nil, settings: DocumentSettings = DocumentSettings(), metadata: [String: String] = [:]) {
        self.features = []
        self.rollbackIndex = nil
        self.documentType = documentType
        self.componentInstances = componentInstances
        self.assemblyConstraints = assemblyConstraints
        self.componentPatterns = componentPatterns
        self.componentMirrors = componentMirrors
        self.explodedViews = explodedViews
        self.activeExplodedViewId = activeExplodedViewId
        if documentType == .drawing && sheets.isEmpty {
            let defaultSheet = DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape)
            self.sheets = [defaultSheet]
            self.activeSheetId = defaultSheet.id
        } else {
            self.sheets = sheets
            self.activeSheetId = activeSheetId ?? sheets.first?.id
        }
        self.settings = settings
        self.metadata = metadata
        self._selection = []
        self._selectedId = nil
        syncObjectsFromFeatures()
        self.seq = 1
        setupUndoObservers()
    }

    public init(features: [Feature], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil, documentType: DocumentType = .part, componentInstances: [ComponentInstance] = [], assemblyConstraints: [AssemblyConstraint] = [], componentPatterns: [ComponentPattern] = [], componentMirrors: [ComponentMirror] = [], explodedViews: [ExplodedView] = [], activeExplodedViewId: UUID? = nil, sheets: [DrawingSheet] = [], activeSheetId: UUID? = nil, metadata: [String: String] = [:]) {
        self.features = features
        self.documentType = documentType
        self.componentInstances = componentInstances
        self.assemblyConstraints = assemblyConstraints
        self.componentPatterns = componentPatterns
        self.componentMirrors = componentMirrors
        self.explodedViews = explodedViews
        self.activeExplodedViewId = activeExplodedViewId
        if documentType == .drawing && sheets.isEmpty {
            let defaultSheet = DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape)
            self.sheets = [defaultSheet]
            self.activeSheetId = defaultSheet.id
        } else {
            self.sheets = sheets
            self.activeSheetId = activeSheetId ?? sheets.first?.id
        }
        self.metadata = metadata
        if let idx = rollbackIndex {
            let clamped = min(max(0, idx), features.count)
            self.rollbackIndex = (clamped >= features.count) ? nil : clamped
        } else {
            self.rollbackIndex = nil
        }
        self.settings = settings ?? DocumentSettings()
        syncObjectsFromFeatures()
        if let selection {
            self._selection = selection
            self._selectedId = selectedId ?? primarySolidId(for: selection)
        } else if let selectedId {
            self._selection = [Reference.body(selectedId)]
            self._selectedId = selectedId
        } else {
            let fallbackId = activeFeatures.compactMap(\.outputSolidId).first
            self._selection = fallbackId.map { [Reference.body($0)] } ?? []
            self._selectedId = fallbackId
        }
        pruneInvalidSelection()
        self.seq = Self.computeMaxSequence(features: features)
        setupUndoObservers()
    }

    public init(objects: [SceneObject], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil, sheets: [DrawingSheet] = [], activeSheetId: UUID? = nil, metadata: [String: String] = [:]) {
        let convertedFeatures = objects.map { Feature(from: $0) }
        self.features = convertedFeatures
        self.sheets = sheets
        self.activeSheetId = activeSheetId ?? sheets.first?.id
        self.metadata = metadata
        if let idx = rollbackIndex {
            let clamped = min(max(0, idx), convertedFeatures.count)
            self.rollbackIndex = (clamped >= convertedFeatures.count) ? nil : clamped
        } else {
            self.rollbackIndex = nil
        }
        self.settings = settings ?? DocumentSettings()
        syncObjectsFromFeatures()
        if let selection {
            self._selection = selection
            self._selectedId = selectedId ?? primarySolidId(for: selection)
        } else if let selectedId {
            self._selection = [Reference.body(selectedId)]
            self._selectedId = selectedId
        } else {
            let fallbackId = activeFeatures.compactMap(\.outputSolidId).first
            self._selection = fallbackId.map { [Reference.body($0)] } ?? []
            self._selectedId = fallbackId
        }
        pruneInvalidSelection()
        self.seq = Self.computeMaxSequence(objects: objects)
        setupUndoObservers()
    }

    public func reset(with newFeatures: [Feature], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil, parameters: [DocumentParameter] = [], documentType: DocumentType = .part, componentInstances: [ComponentInstance] = [], assemblyConstraints: [AssemblyConstraint] = [], componentPatterns: [ComponentPattern] = [], componentMirrors: [ComponentMirror] = [], explodedViews: [ExplodedView] = [], activeExplodedViewId: UUID? = nil, sheets: [DrawingSheet] = [], activeSheetId: UUID? = nil, metadata: [String: String] = [:]) {
        undoManager?.removeAllActions()
        self.documentType = documentType
        self.componentInstances = componentInstances
        self.assemblyConstraints = assemblyConstraints
        self.componentPatterns = componentPatterns
        self.componentMirrors = componentMirrors
        self.explodedViews = explodedViews
        self.activeExplodedViewId = activeExplodedViewId
        if documentType == .drawing && sheets.isEmpty {
            let defaultSheet = DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape)
            self.sheets = [defaultSheet]
            self.activeSheetId = defaultSheet.id
        } else {
            self.sheets = sheets
            self.activeSheetId = activeSheetId ?? sheets.first?.id
        }
        self.parameters = parameters
        self.metadata = metadata
        rebuildParameterGraph()
        features = newFeatures
        if let idx = rollbackIndex {
            let clamped = min(max(0, idx), newFeatures.count)
            self.rollbackIndex = (clamped >= newFeatures.count) ? nil : clamped
        } else {
            self.rollbackIndex = nil
        }
        if let settings {
            self.settings = settings
        }
        seq = Self.computeMaxSequence(features: newFeatures)
        if let selection {
            self.selection = selection
            pruneInvalidSelection()
        } else if let selectedId {
            self.selectedId = selectedId
        } else {
            self.selectedId = activeFeatures.compactMap(\.outputSolidId).first ?? componentInstances.first?.solidId
        }
        self.selectedSubElement = nil
        activeInteractiveParamEdit = nil
        activeInteractiveSketchDrag = nil
        activeAssemblyDragInitialTransforms = nil
        activeAssemblyDragInitialInstances = nil
        undoStateVersion += 1
    }

    public func reset(with newObjects: [SceneObject], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil, parameters: [DocumentParameter] = [], documentType: DocumentType = .part, componentInstances: [ComponentInstance] = [], assemblyConstraints: [AssemblyConstraint] = [], componentPatterns: [ComponentPattern] = [], componentMirrors: [ComponentMirror] = [], explodedViews: [ExplodedView] = [], activeExplodedViewId: UUID? = nil, sheets: [DrawingSheet] = [], activeSheetId: UUID? = nil, metadata: [String: String] = [:]) {
        undoManager?.removeAllActions()
        self.documentType = documentType
        self.componentInstances = componentInstances
        self.assemblyConstraints = assemblyConstraints
        self.componentPatterns = componentPatterns
        self.componentMirrors = componentMirrors
        self.explodedViews = explodedViews
        self.activeExplodedViewId = activeExplodedViewId
        if documentType == .drawing && sheets.isEmpty {
            let defaultSheet = DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape)
            self.sheets = [defaultSheet]
            self.activeSheetId = defaultSheet.id
        } else {
            self.sheets = sheets
            self.activeSheetId = activeSheetId ?? sheets.first?.id
        }
        self.parameters = parameters
        self.metadata = metadata
        rebuildParameterGraph()
        let convertedFeatures = newObjects.map { Feature(from: $0) }
        features = convertedFeatures
        if let idx = rollbackIndex {
            let clamped = min(max(0, idx), convertedFeatures.count)
            self.rollbackIndex = (clamped >= convertedFeatures.count) ? nil : clamped
        } else {
            self.rollbackIndex = nil
        }
        if let settings {
            self.settings = settings
        }
        seq = Self.computeMaxSequence(objects: newObjects)
        if let selection {
            self.selection = selection
            pruneInvalidSelection()
        } else if let selectedId {
            self.selectedId = selectedId
        } else {
            self.selectedId = activeFeatures.compactMap(\.outputSolidId).first ?? componentInstances.first?.solidId
        }
        self.selectedSubElement = nil
        activeInteractiveParamEdit = nil
        activeInteractiveSketchDrag = nil
        activeAssemblyDragInitialTransforms = nil
        activeAssemblyDragInitialInstances = nil
        undoStateVersion += 1
    }

    /// Rebases in-memory feature and object part and asset file paths to point inside the specified package directory.
    public func rebasePaths(to packageURL: URL) {
        var updatedFeatures = features
        var changed = false
        for i in 0..<updatedFeatures.count {
            switch updatedFeatures[i].operation {
            case .part(var partData):
                let filename = partData.url.lastPathComponent
                guard !filename.isEmpty && filename != "/" else { break }
                let newURL = packageURL.appendingPathComponent("parts/\(filename)")
                if partData.url != newURL {
                    partData.url = newURL
                    updatedFeatures[i].operation = .part(partData)
                    changed = true
                }
            case .imported(var impData):
                guard !impData.isLinked else { break }
                if let sourceURL = impData.sourceURL {
                    let filename = sourceURL.lastPathComponent
                    guard !filename.isEmpty && filename != "/" else { break }
                    let newURL = packageURL.appendingPathComponent("assets/\(filename)")
                    if impData.sourceURL != newURL {
                        impData.sourceURL = newURL
                        updatedFeatures[i].operation = .imported(impData)
                        changed = true
                    }
                }
            default:
                break
            }
        }
        if changed {
            features = updatedFeatures
        }

        for i in 0..<objects.count {
            switch objects[i].def {
            case .part(let url, let shape):
                let filename = url.lastPathComponent
                guard !filename.isEmpty && filename != "/" else { break }
                let newURL = packageURL.appendingPathComponent("parts/\(filename)")
                if url != newURL {
                    objects[i].def = .part(url: newURL, shape: shape)
                }
            case .imported(let name, let sourceURL, let data, let isLinked, let lastModifiedDate, let fileChecksum):
                guard !isLinked else { break }
                if let sourceURL {
                    let filename = sourceURL.lastPathComponent
                    guard !filename.isEmpty && filename != "/" else { break }
                    let newURL = packageURL.appendingPathComponent("assets/\(filename)")
                    if sourceURL != newURL {
                        objects[i].def = .imported(
                            name: name,
                            sourceURL: newURL,
                            data: data,
                            isLinked: isLinked,
                            lastModifiedDate: lastModifiedDate,
                            fileChecksum: fileChecksum
                        )
                    }
                }
            default:
                break
            }
        }
    }

    private func syncObjectsFromFeatures() {
        guard !isSyncingObjects else { return }
        isSyncingObjects = true
        defer { isSyncingObjects = false }

        var currentObjects: [SceneObject] = []

        for feature in activeFeatures {
            guard !feature.isSuppressed else { continue }
            switch feature.operation {
            case .combine(let data):
                if let obj = feature.toSceneObject() {
                    currentObjects.append(obj)
                }
                if let targetIdx = currentObjects.firstIndex(where: { $0.id == data.targetBodyId }) {
                    currentObjects[targetIdx].isVisible = false
                }
                if let toolIdx = currentObjects.firstIndex(where: { $0.id == data.toolBodyId }) {
                    if !data.keepTool {
                        currentObjects[toolIdx].isVisible = false
                    }
                }
            case .moveBody(let data):
                if let idx = currentObjects.firstIndex(where: { $0.id == data.targetBodyId }) {
                    currentObjects[idx].transform = data.transform * currentObjects[idx].transform
                }
            case .copyBody(let data):
                if let source = currentObjects.first(where: { $0.id == data.sourceBodyId }) {
                    let copyObj = SceneObject(
                        id: data.newBodyId,
                        name: feature.name,
                        def: source.def,
                        transform: data.transform * source.transform,
                        isVisible: feature.isVisible,
                        isLocked: feature.isLocked,
                        material: feature.material
                    )
                    currentObjects.append(copyObj)
                }
            case .deleteBody(let data):
                currentObjects.removeAll(where: { $0.id == data.targetBodyId })
            default:
                if let obj = feature.toSceneObject() {
                    currentObjects.append(obj)
                }
            }
        }

        var cumulativeDisplacements: [UUID: SIMD3<Float>] = [:]
        if let activeId = activeExplodedViewId,
           let activeView = explodedViews.first(where: { $0.id == activeId }),
           !activeView.isCollapsed {
            cumulativeDisplacements = activeView.cumulativeDisplacements()
        }

        func appendSceneObjects(for instance: ComponentInstance, parentTransform: Transform) {
            var instanceTransform = instance.transform
            if let displacement = cumulativeDisplacements[instance.id] {
                instanceTransform.position += displacement
            }
            let worldTransform = parentTransform * instanceTransform
            if instance.childInstances.isEmpty {
                let def: ObjectDef
                switch instance.reference {
                case .internalPart(let name, let bodyId):
                    if let bodyId, let matchingObj = currentObjects.first(where: { $0.id == bodyId }) {
                        def = matchingObj.def
                    } else if let matchingObj = currentObjects.first(where: { $0.name == name }) {
                        def = matchingObj.def
                    } else {
                        def = .imported(name: name, sourceURL: nil, data: nil, isLinked: false)
                    }
                case .externalDocument(let url, let partName):
                    let displayName = partName ?? url.deletingPathExtension().lastPathComponent
                    def = .imported(name: displayName, sourceURL: url, data: nil, isLinked: true)
                case .subassembly(let name):
                    def = .imported(name: name, sourceURL: nil, data: nil, isLinked: false)
                }
                let obj = SceneObject(
                    id: instance.solidId,
                    name: instance.name,
                    def: def,
                    transform: worldTransform,
                    isVisible: instance.isVisible,
                    isLocked: instance.isLocked || instance.isGrounded,
                    material: instance.material,
                    metadata: instance.metadata
                )
                currentObjects.append(obj)
            } else {
                for child in instance.childInstances {
                    appendSceneObjects(for: child, parentTransform: worldTransform)
                }
            }
        }

        for instance in componentInstances {
            appendSceneObjects(for: instance, parentTransform: .identity)
        }

        objects = currentObjects
        bodies = objects.map { Body(from: $0) }
        pruneInvalidSelection()
        updateDrawingAssociativity()
    }

    public func validateTimelineFeatureErrors() {
        for feature in activeFeatures {
            let upstreamIds = directDependencies(of: feature)
            let hasFailedParent = upstreamIds.compactMap { self.feature(for: $0) }.contains { $0.errorState != nil }
            if hasFailedParent {
                let errorState = FeatureErrorState(
                    code: "parent-failed",
                    message: "parent failed",
                    severity: .warning
                )
                setFeatureError(id: feature.id, error: errorState)
                continue
            } else if feature.errorState?.code == "parent-failed" {
                setFeatureError(id: feature.id, error: nil)
            }

            if let brokenErr = ReferenceResolver.validateReferences(for: feature, in: self) {
                let errorState = FeatureErrorState(
                    code: "reference-broken",
                    message: "Reference broken: \(brokenErr.description)",
                    severity: .error
                )
                setFeatureError(id: feature.id, error: errorState)
                for dep in dependentFeatures(referencing: feature.id) {
                    setFeatureError(
                        id: dep.id,
                        error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                    )
                }
            } else if feature.errorState?.code == "missing-reference" || feature.errorState?.code == "reference-broken" {
                setFeatureError(id: feature.id, error: nil)
            }
        }
    }

    public func body(for id: BodyId) -> Body? {
        bodies.first(where: { $0.id == id })
    }

    private static func computeMaxSequence(features: [Feature]) -> Int {
        var maxSeq = 1
        for f in features {
            if let solidId = f.outputSolidId {
                let parts = solidId.rawValue.split(separator: "-")
                if parts.count >= 2, let lastNum = Int(parts.last!) {
                    maxSeq = max(maxSeq, lastNum)
                }
            }
        }
        return maxSeq
    }

    private static func computeMaxSequence(objects: [SceneObject]) -> Int {
        var maxSeq = 1
        for obj in objects {
            let parts = obj.id.rawValue.split(separator: "-")
            if parts.count >= 2, let lastNum = Int(parts.last!) {
                maxSeq = max(maxSeq, lastNum)
            }
        }
        return maxSeq
    }

    private func setupUndoObservers() {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        undoObservers.removeAll()

        guard let um = undoManager else { return }
        let nc = NotificationCenter.default
        let o1 = nc.addObserver(forName: .NSUndoManagerDidUndoChange, object: um, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.undoStateVersion += 1
            }
        }
        let o2 = nc.addObserver(forName: .NSUndoManagerDidRedoChange, object: um, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.undoStateVersion += 1
            }
        }
        let o3 = nc.addObserver(forName: .NSUndoManagerCheckpoint, object: um, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.undoStateVersion += 1
            }
        }
        undoObservers = [o1, o2, o3]
    }

    isolated deinit {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public var canUndo: Bool {
        _ = undoStateVersion
        return undoManager?.canUndo ?? false
    }

    public var canRedo: Bool {
        _ = undoStateVersion
        return undoManager?.canRedo ?? false
    }

    public var undoActionTitle: String {
        _ = undoStateVersion
        guard let title = undoManager?.undoActionName, !title.isEmpty else {
            return "Undo"
        }
        return "Undo \(title)"
    }

    public var redoActionTitle: String {
        _ = undoStateVersion
        guard let title = undoManager?.redoActionName, !title.isEmpty else {
            return "Redo"
        }
        return "Redo \(title)"
    }

    public var undoTitle: String {
        undoActionTitle
    }

    public var redoTitle: String {
        redoActionTitle
    }

    public func undo() {
        undoManager?.undo()
    }

    public func redo() {
        undoManager?.redo()
    }

    // MARK: - Document Settings Mutators (BL-FND-11)

    public func setSettings(_ newSettings: DocumentSettings, actionName: String? = nil, registerUndo: Bool = true) {
        let clamped = DocumentSettings(
            units: newSettings.units,
            tolerances: newSettings.tolerances.clamped(),
            defaultMaterial: newSettings.defaultMaterial
        )
        guard settings != clamped else { return }

        let previous = settings
        if registerUndo {
            let undoName = actionName ?? "Change Document Settings"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setSettings(previous, actionName: undoName, registerUndo: true)
                    target.undoManager?.setActionName(undoName)
                }
            }
            undoManager?.setActionName(undoName)
            undoStateVersion += 1
        }
        settings = clamped
    }

    public func setUnits(_ units: UnitSettings) {
        var newSettings = settings
        newSettings.units = units
        setSettings(newSettings, actionName: "Change Document Settings")
    }

    public func setTolerances(_ tolerances: KernelTolerances) {
        var newSettings = settings
        newSettings.tolerances = tolerances.clamped()
        setSettings(newSettings, actionName: "Change Document Settings")
    }

    public func setDefaultMaterial(_ material: MaterialAttributes) {
        var newSettings = settings
        newSettings.defaultMaterial = material
        setSettings(newSettings, actionName: "Change Document Settings")
    }

    // MARK: - Metadata & Custom Properties (BL-FND-14, #172)

    public var partNumber: String? {
        metadata[CustomPropertyKey.partNumber]
    }

    public var itemDescription: String? {
        metadata[CustomPropertyKey.description]
    }

    public var revision: String? {
        metadata[CustomPropertyKey.revision]
    }

    public var vendor: String? {
        metadata[CustomPropertyKey.vendor]
    }

    public var customProperties: [String: String] {
        metadata.customProperties
    }

    public func property(forKey key: String) -> String? {
        metadata.property(forKey: key)
    }

    public func setDocumentMetadata(_ newMetadata: [String: String], actionName: String? = nil, registerUndo: Bool = true) {
        guard metadata != newMetadata else { return }
        let oldMetadata = metadata
        if registerUndo {
            let undoName = actionName ?? "Edit Document Metadata"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setDocumentMetadata(oldMetadata, actionName: undoName, registerUndo: true)
                    target.undoManager?.setActionName(undoName)
                }
            }
            undoManager?.setActionName(undoName)
            undoStateVersion += 1
        }
        metadata = newMetadata
    }

    public func setDocumentProperty(key: String, value: String?) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        var newMetadata = metadata
        if let value, !value.isEmpty {
            newMetadata[trimmedKey] = value
        } else {
            newMetadata.removeValue(forKey: trimmedKey)
        }
        guard newMetadata != metadata else { return }
        let oldMetadata = metadata
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setDocumentMetadata(oldMetadata, actionName: "Edit Document Property", registerUndo: true)
                target.undoManager?.setActionName("Edit Document Property")
            }
        }
        undoManager?.setActionName("Edit Document Property")
        undoStateVersion += 1
        metadata = newMetadata
    }

    public func setFeatureMetadata(id: UUID, metadata newMetadata: [String: String], actionName: String? = nil, registerUndo: Bool = true) {
        guard let index = features.firstIndex(where: { $0.id == id }) else { return }
        guard features[index].metadata != newMetadata else { return }
        let oldMetadata = features[index].metadata
        if registerUndo {
            let undoName = actionName ?? "Edit Feature Metadata"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setFeatureMetadata(id: id, metadata: oldMetadata, actionName: undoName, registerUndo: true)
                    target.undoManager?.setActionName(undoName)
                }
            }
            undoManager?.setActionName(undoName)
            undoStateVersion += 1
        }
        features[index].metadata = newMetadata
        syncObjectsFromFeatures()
    }

    public func setFeatureProperty(id: UUID, key: String, value: String?) {
        guard let index = features.firstIndex(where: { $0.id == id }) else { return }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        var newMetadata = features[index].metadata
        if let value, !value.isEmpty {
            newMetadata[trimmedKey] = value
        } else {
            newMetadata.removeValue(forKey: trimmedKey)
        }
        guard newMetadata != features[index].metadata else { return }
        let oldMetadata = features[index].metadata
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setFeatureMetadata(id: id, metadata: oldMetadata, actionName: "Edit Feature Property", registerUndo: true)
                target.undoManager?.setActionName("Edit Feature Property")
            }
        }
        undoManager?.setActionName("Edit Feature Property")
        undoStateVersion += 1
        features[index].metadata = newMetadata
        syncObjectsFromFeatures()
    }

    public func setComponentInstanceMetadata(id: ComponentInstanceId, metadata newMetadata: [String: String], actionName: String? = nil, registerUndo: Bool = true) {
        guard var comp = findComponentInstance(id: id) else { return }
        guard comp.metadata != newMetadata else { return }
        comp.metadata = newMetadata
        _ = updateComponentInstance(comp, actionName: actionName ?? "Edit Component Metadata", registerUndo: registerUndo)
    }

    public func setComponentInstanceProperty(id: ComponentInstanceId, key: String, value: String?) {
        guard var comp = findComponentInstance(id: id) else { return }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        var newMetadata = comp.metadata
        if let value, !value.isEmpty {
            newMetadata[trimmedKey] = value
        } else {
            newMetadata.removeValue(forKey: trimmedKey)
        }
        guard newMetadata != comp.metadata else { return }
        comp.metadata = newMetadata
        _ = updateComponentInstance(comp, actionName: "Edit Component Property", registerUndo: true)
    }

    public func setBodyMetadata(id: BodyId, metadata newMetadata: [String: String], actionName: String? = nil, registerUndo: Bool = true) {
        if let comp = findComponentInstance(solidId: id) {
            setComponentInstanceMetadata(id: comp.id, metadata: newMetadata, actionName: actionName, registerUndo: registerUndo)
            return
        }
        if let featIndex = features.firstIndex(where: { $0.outputSolidId == id }) {
            setFeatureMetadata(id: features[featIndex].id, metadata: newMetadata, actionName: actionName, registerUndo: registerUndo)
            return
        }
    }

    public func setBodyProperty(id: BodyId, key: String, value: String?) {
        if let comp = findComponentInstance(solidId: id) {
            setComponentInstanceProperty(id: comp.id, key: key, value: value)
            return
        }
        if let featIndex = features.firstIndex(where: { $0.outputSolidId == id }) {
            setFeatureProperty(id: features[featIndex].id, key: key, value: value)
            return
        }
    }

    // MARK: - Rollback Marker (BL-FND-05)

    @discardableResult
    public func setRollbackIndex(_ index: Int?, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        let normalizedIndex: Int?
        if let index {
            let clamped = min(max(0, index), features.count)
            normalizedIndex = (clamped >= features.count) ? nil : clamped
        } else {
            normalizedIndex = nil
        }
        guard rollbackIndex != normalizedIndex else { return .success(()) }

        let previousIndex = rollbackIndex
        if registerUndo {
            let undoName = actionName ?? "Rollback"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.setRollbackIndex(previousIndex, actionName: undoName, registerUndo: true)
                    target.undoManager?.setActionName(undoName)
                }
            }
            undoManager?.setActionName(undoName)
            undoStateVersion += 1
        }

        rollbackIndex = normalizedIndex
        return .success(())
    }

    @discardableResult
    public func rollBack(to index: Int) -> Result<Void, DocumentMutationError> {
        return setRollbackIndex(index, actionName: "Roll Back")
    }

    @discardableResult
    public func rollBack(to featureId: UUID) -> Result<Void, DocumentMutationError> {
        guard let idx = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        return setRollbackIndex(idx + 1, actionName: "Roll Back")
    }

    @discardableResult
    public func rollBack(before featureId: UUID) -> Result<Void, DocumentMutationError> {
        guard let idx = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        return setRollbackIndex(idx, actionName: "Roll Back")
    }

    @discardableResult
    public func rollBack(to solidId: ObjectId) -> Result<Void, DocumentMutationError> {
        guard let feat = feature(for: solidId) else {
            return .failure(.objectNotFound(solidId))
        }
        return rollBack(to: feat.id)
    }

    @discardableResult
    public func rollBack(before solidId: ObjectId) -> Result<Void, DocumentMutationError> {
        guard let feat = feature(for: solidId) else {
            return .failure(.objectNotFound(solidId))
        }
        return rollBack(before: feat.id)
    }

    @discardableResult
    public func rollForwardToEnd() -> Result<Void, DocumentMutationError> {
        setRollbackIndex(nil, actionName: "Roll Forward to End")
    }

    @discardableResult
    public func rollBackOne() -> Result<Void, DocumentMutationError> {
        guard effectiveRollbackIndex > 0 else { return .success(()) }
        return setRollbackIndex(effectiveRollbackIndex - 1, actionName: "Roll Back")
    }

    @discardableResult
    public func rollForwardOne() -> Result<Void, DocumentMutationError> {
        guard isRolledBack else { return .success(()) }
        return setRollbackIndex(effectiveRollbackIndex + 1, actionName: "Roll Forward")
    }

    // MARK: - Feature Mutators (ADR-D2)

    @discardableResult
    public func addFeature(_ feature: Feature) -> UUID {
        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if let solidId = feature.outputSolidId {
            let parts = solidId.rawValue.split(separator: "-")
            if parts.count >= 2, let lastNum = Int(parts.last!) {
                seq = max(seq, lastNum)
            }
            selectedId = solidId
        }

        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }

        let featureId = feature.id
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeFeature(id: featureId)
                target.rollbackIndex = previousRollback
                target.undoManager?.setActionName("Add Feature")
                if let solidId = feature.outputSolidId {
                    target.onUndoRedoMutation?(.removed(solidId))
                }
            }
        }
        undoManager?.setActionName("Add Feature")
        undoStateVersion += 1
        return featureId
    }

    @discardableResult
    public func removeFeature(id: UUID, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(ObjectId(id.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(id.uuidString)))
        }
        let removedFeature = features[index]
        let removedIndex = index
        let previousRollback = rollbackIndex

        features.remove(at: index)

        if let curRollback = rollbackIndex {
            if removedIndex < curRollback {
                let decremented = max(0, curRollback - 1)
                rollbackIndex = (decremented >= features.count) ? nil : decremented
            } else {
                if curRollback >= features.count {
                    rollbackIndex = nil
                }
            }
        }

        if let solidId = removedFeature.outputSolidId, selectedId == solidId {
            selectedId = nil
        }
        pruneInvalidSelection()

        let redoName = actionName ?? (undoManager?.isUndoing == true ? "Add \(removedFeature.name)" : "Delete \(removedFeature.name)")
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.insertFeature(removedFeature, at: removedIndex, actionName: redoName, registerUndo: true)
                    target.rollbackIndex = previousRollback
                    target.undoManager?.setActionName(redoName)
                    if let solidId = removedFeature.outputSolidId {
                        target.onUndoRedoMutation?(.added(solidId))
                    }
                }
            }
            undoManager?.setActionName(redoName)
            undoStateVersion += 1
        }
        return .success(())
    }

    @discardableResult
    public func insertFeature(_ feature: Feature, at index: Int, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        guard !features.contains(where: { $0.id == feature.id }) else {
            return .failure(.objectLocked(feature.outputSolidId ?? ObjectId(feature.id.uuidString)))
        }
        let targetIndex = min(max(0, index), features.count)
        let previousRollback = rollbackIndex

        features.insert(feature, at: targetIndex)
        if let curRollback = rollbackIndex {
            if targetIndex <= curRollback {
                let newIndex = curRollback + 1
                rollbackIndex = (newIndex >= features.count) ? nil : newIndex
            }
        }
        if let solidId = feature.outputSolidId {
            selectedId = solidId
        }

        let undoName = actionName ?? "Delete \(feature.name)"
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeFeature(id: feature.id, actionName: undoName, registerUndo: true)
                    target.rollbackIndex = previousRollback
                    target.undoManager?.setActionName(undoName)
                    if let solidId = feature.outputSolidId {
                        target.onUndoRedoMutation?(.removed(solidId))
                    }
                }
            }
            undoManager?.setActionName(undoName)
            undoStateVersion += 1
        }
        return .success(())
    }

    @discardableResult
    public func updateFeature(_ feature: Feature) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == feature.id }) else {
            return .failure(.objectNotFound(feature.outputSolidId ?? ObjectId(feature.id.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(feature.outputSolidId ?? ObjectId(feature.id.uuidString)))
        }
        let oldFeature = features[index]
        guard oldFeature != feature else {
            return .success(())
        }

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateFeature(oldFeature)
                target.undoManager?.setActionName("Update Feature")
            }
        }
        undoManager?.setActionName("Update Feature")
        undoStateVersion += 1
        features[index] = feature
        return .success(())
    }

    @discardableResult
    public func setFeatureSuppressed(id: UUID, isSuppressed: Bool) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(ObjectId(id.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(id.uuidString)))
        }
        let oldSuppressed = features[index].isSuppressed
        guard oldSuppressed != isSuppressed else {
            return .success(())
        }

        let actionTitle = isSuppressed ? "Suppress Feature" : "Unsuppress Feature"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.setFeatureSuppressed(id: id, isSuppressed: oldSuppressed)
                target.undoManager?.setActionName(actionTitle)
            }
        }
        undoManager?.setActionName(actionTitle)
        undoStateVersion += 1
        features[index].isSuppressed = isSuppressed
        if isSuppressed, let solidId = features[index].outputSolidId, selectedId == solidId {
            selectedId = nil
        }
        pruneInvalidSelection()
        return .success(())
    }

    public func setFeatureError(id: UUID, error: FeatureErrorState?) {
        guard let index = features.firstIndex(where: { $0.id == id }) else { return }
        guard features[index].errorState != error else { return }
        let prevSyncing = isSyncingObjects
        isSyncingObjects = true
        features[index].errorState = error
        isSyncingObjects = prevSyncing
        updateDrawingAssociativity()
    }

    @discardableResult
    public func setFeatureName(id: UUID, name: String) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(ObjectId(id.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(id.uuidString)))
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(()) }
        let oldName = features[index].name
        guard oldName != trimmed else { return .success(()) }

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.setFeatureName(id: id, name: oldName)
                target.undoManager?.setActionName("Rename Feature")
            }
        }
        undoManager?.setActionName("Rename Feature")
        undoStateVersion += 1
        features[index].name = trimmed
        return .success(())
    }

    @discardableResult
    public func setFeatureVisibility(id: UUID, isVisible: Bool) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(ObjectId(id.uuidString)))
        }
        let oldVisible = features[index].isVisible
        guard oldVisible != isVisible else { return .success(()) }

        let actionTitle = isVisible ? "Show Feature" : "Hide Feature"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.setFeatureVisibility(id: id, isVisible: oldVisible)
                target.undoManager?.setActionName(actionTitle)
            }
        }
        undoManager?.setActionName(actionTitle)
        undoStateVersion += 1
        features[index].isVisible = isVisible
        return .success(())
    }

    @discardableResult
    public func setFeatureLocked(id: UUID, isLocked: Bool) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(ObjectId(id.uuidString)))
        }
        let oldLocked = features[index].isLocked
        guard oldLocked != isLocked else { return .success(()) }

        let actionTitle = isLocked ? "Lock Feature" : "Unlock Feature"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.setFeatureLocked(id: id, isLocked: oldLocked)
                target.undoManager?.setActionName(actionTitle)
            }
        }
        undoManager?.setActionName(actionTitle)
        undoStateVersion += 1
        features[index].isLocked = isLocked
        return .success(())
    }

    public func feature(for id: UUID) -> Feature? {
        features.first(where: { $0.id == id })
    }

    public func feature(for solidId: SolidId) -> Feature? {
        features.first(where: { $0.outputSolidId == solidId })
    }

    // MARK: - Sketch Feature Mutators

    @discardableResult
    public func addSketchFeature(
        planeName: String = "XY",
        entities: [SketchEntity] = []
    ) -> Feature {
        let sketchCount = features.filter {
            if case .sketch = $0.operation { return true }
            return false
        }.count + 1
        let feature = Feature(
            name: "Sketch \(sketchCount)",
            operation: .sketch(SketchFeatureData(planeName: planeName, entities: entities))
        )
        _ = addFeature(feature)
        selection = [Reference.feature(feature.id)]
        return feature
    }

    // MARK: - Datum Plane Mutators & Sketch Plane Resolution

    @discardableResult
    public func addDatumPlaneFeature(
        name: String? = nil,
        data: DatumPlaneFeatureData = DatumPlaneFeatureData(),
        references: [Reference] = []
    ) -> Feature {
        let datumCount = features.filter {
            if case .datumPlane = $0.operation { return true }
            return false
        }.count + 1
        let featureName = name ?? "Plane \(datumCount)"
        var datumData = data
        var feature = Feature(
            name: featureName,
            operation: .datumPlane(datumData),
            references: references
        )
        if let evaluated = try? DatumPlaneEvaluator.evaluate(feature: feature, data: datumData, in: self) {
            datumData.cachedPlane = evaluated
            feature.operation = .datumPlane(datumData)
        }
        _ = addFeature(feature)
        selection = [Reference.feature(feature.id)]
        return feature
    }

    // MARK: - Datum Axis, Point & Coordinate System Mutators

    @discardableResult
    public func addDatumAxisFeature(
        name: String? = nil,
        data: DatumAxisFeatureData = DatumAxisFeatureData(),
        references: [Reference] = []
    ) -> Feature {
        let datumCount = features.filter {
            if case .datumAxis = $0.operation { return true }
            return false
        }.count + 1
        let featureName = name ?? "Axis \(datumCount)"
        var axisData = data
        var feature = Feature(
            name: featureName,
            operation: .datumAxis(axisData),
            references: references
        )
        if let evaluated = try? DatumAxisEvaluator.evaluate(feature: feature, data: axisData, in: self) {
            axisData.cachedAxis = evaluated
            feature.operation = .datumAxis(axisData)
        }
        _ = addFeature(feature)
        selection = [Reference.feature(feature.id)]
        return feature
    }

    @discardableResult
    public func addDatumPointFeature(
        name: String? = nil,
        data: DatumPointFeatureData = DatumPointFeatureData(),
        references: [Reference] = []
    ) -> Feature {
        let datumCount = features.filter {
            if case .datumPoint = $0.operation { return true }
            return false
        }.count + 1
        let featureName = name ?? "Point \(datumCount)"
        var pointData = data
        var feature = Feature(
            name: featureName,
            operation: .datumPoint(pointData),
            references: references
        )
        if let evaluated = try? DatumPointEvaluator.evaluate(feature: feature, data: pointData, in: self) {
            pointData.cachedPoint = evaluated
            feature.operation = .datumPoint(pointData)
        }
        _ = addFeature(feature)
        selection = [Reference.feature(feature.id)]
        return feature
    }

    @discardableResult
    public func addDatumCoordinateSystemFeature(
        name: String? = nil,
        data: DatumCoordinateSystemFeatureData = DatumCoordinateSystemFeatureData(),
        references: [Reference] = []
    ) -> Feature {
        let datumCount = features.filter {
            if case .datumCoordinateSystem = $0.operation { return true }
            return false
        }.count + 1
        let featureName = name ?? "UCS \(datumCount)"
        var ucsData = data
        var feature = Feature(
            name: featureName,
            operation: .datumCoordinateSystem(ucsData),
            references: references
        )
        if let evaluated = try? DatumCoordinateSystemEvaluator.evaluate(feature: feature, data: ucsData, in: self) {
            ucsData.cachedCoordinateSystem = evaluated
            feature.operation = .datumCoordinateSystem(ucsData)
        }
        _ = addFeature(feature)
        selection = [Reference.feature(feature.id)]
        return feature
    }

    // MARK: - User Coordinate System Queries

    /// Returns all active, unsuppressed coordinate system features in the document timeline.
    public func activeCoordinateSystems() -> [Feature] {
        activeFeatures.filter {
            if case .datumCoordinateSystem = $0.operation { return true }
            return false
        }
    }

    /// Returns the evaluated geometry for a coordinate system feature by ID.
    public func coordinateSystemGeometry(id: UUID) -> DatumCoordinateSystemGeometry? {
        guard let feat = feature(for: id), case .datumCoordinateSystem(let ucsData) = feat.operation else {
            return nil
        }
        if let cached = ucsData.cachedCoordinateSystem {
            return cached
        }
        return try? DatumCoordinateSystemEvaluator.evaluate(feature: feat, data: ucsData, in: self)
    }

    /// Returns the rigid transform matrix for export or simulation referencing a coordinate system.
    public func exportTransform(coordinateSystemId: UUID) -> Transform? {
        guard let geom = coordinateSystemGeometry(id: coordinateSystemId) else {
            return nil
        }
        return geom.asTransform
    }

    /// Resolves the 3D coordinate frame for a sketch by checking datum plane ID or name before falling back to presets.
    public func resolveSketchPlane(for sketchData: SketchFeatureData) -> SketchPlane {
        if let datumId = sketchData.datumPlaneFeatureId,
           let feat = feature(for: datumId),
           case .datumPlane(let datumData) = feat.operation {
            if let cached = datumData.cachedPlane {
                return cached
            }
            if let evaluated = try? DatumPlaneEvaluator.evaluate(feature: feat, data: datumData, in: self) {
                return evaluated
            }
        }
        if let planeRef = sketchData.planeReference,
           let feat = feature(for: planeRef.sourceFeatureId),
           case .datumPlane(let datumData) = feat.operation {
            if let cached = datumData.cachedPlane {
                return cached
            }
            if let evaluated = try? DatumPlaneEvaluator.evaluate(feature: feat, data: datumData, in: self) {
                return evaluated
            }
        }
        if let name = sketchData.planeName {
            if let feat = features.first(where: { $0.name == name }),
               case .datumPlane(let datumData) = feat.operation {
                if let cached = datumData.cachedPlane {
                    return cached
                }
                if let evaluated = try? DatumPlaneEvaluator.evaluate(feature: feat, data: datumData, in: self) {
                    return evaluated
                }
            }
            return DatumPlaneEvaluator.presetPlane(named: name)
        }
        return .xy
    }

    @discardableResult
    public func addSketchEntity(to featureId: UUID, entity: SketchEntity) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let entityId = entity.id
        sketchData.entities.append(entity)
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeSketchEntity(from: featureId, entityId: entityId)
            }
        }
        undoManager?.setActionName("Add Sketch Entity")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func updateSketchEntity(in featureId: UUID, entity: SketchEntity) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entity.id }) else {
            return .failure(.objectNotFound(ObjectId(entity.id.uuidString)))
        }

        let oldEntity = sketchData.entities[entityIndex]
        sketchData.entities[entityIndex] = entity
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
            }
        }
        undoManager?.setActionName("Update Sketch Entity")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func setSketchLineLength(
        in featureId: UUID,
        entityId: UUID,
        length: Double
    ) throws -> SketchEntity {
        guard length > 0, length.isFinite else {
            throw SketchError.zeroLengthLine(entityId: entityId)
        }
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            throw SketchError.invalidEntity("Feature \(featureId) not found")
        }
        guard !features[index].isLocked else {
            throw SketchError.invalidEntity("Feature \(featureId) is locked")
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            throw SketchError.invalidEntity("Feature \(featureId) is not a sketch")
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            throw SketchError.invalidEntity("Entity \(entityId) not found in sketch")
        }
        let entity = sketchData.entities[entityIndex]
        guard entity.kind == "line" else {
            throw SketchError.invalidEntity("Entity \(entityId) is not a line")
        }

        let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
        let dofStatus = ConstraintSolver.computeDOFStatus(system: system)
        if case .overConstrained = dofStatus {
            let solveRes = ConstraintSolver.solve(system: system)
            var conflicting: [UUID] = []
            if case .overConstrained(let ids) = solveRes.status { conflicting = ids }
            throw SketchError.overConstrained(message: "Cannot dimension line in over-constrained sketch", conflictingConstraints: conflicting)
        }

        let oldEntity = entity
        let updatedEntity = entity.updatingLength(length)
        sketchData.entities[entityIndex] = updatedEntity
        features[index].operation = .sketch(sketchData)

        let actionName = "Dimension Sketch Line"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
                target.undoManager?.setActionName(actionName)
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1
        return updatedEntity
    }

    @discardableResult
    public func toggleSketchEntityConstruction(in featureId: UUID, entityId: UUID) -> Result<SketchEntity, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            return .failure(.objectNotFound(ObjectId(entityId.uuidString)))
        }

        let oldEntity = sketchData.entities[entityIndex]
        var updated = oldEntity
        updated.isConstruction.toggle()
        sketchData.entities[entityIndex] = updated
        features[index].operation = .sketch(sketchData)

        let actionName = "Toggle Construction Geometry"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
                target.undoManager?.setActionName(actionName)
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1
        return .success(updated)
    }

    @discardableResult
    public func removeSketchEntity(from featureId: UUID, entityId: UUID) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            return .failure(.objectNotFound(ObjectId(entityId.uuidString)))
        }

        let removedEntity = sketchData.entities.remove(at: entityIndex)
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertSketchEntity(to: featureId, entity: removedEntity, at: entityIndex)
            }
        }
        undoManager?.setActionName("Delete Sketch Entity")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func insertSketchEntity(to featureId: UUID, entity: SketchEntity, at insertIndex: Int) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let clampedIndex = min(max(0, insertIndex), sketchData.entities.count)
        sketchData.entities.insert(entity, at: clampedIndex)
        features[index].operation = .sketch(sketchData)

        let entityId = entity.id
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeSketchEntity(from: featureId, entityId: entityId)
            }
        }
        undoManager?.setActionName("Add Sketch Entity")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func addSketchConstraint(to featureId: UUID, constraint: SketchConstraint) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let constraintId = constraint.id
        sketchData.constraints.append(constraint)
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeSketchConstraint(from: featureId, constraintId: constraintId)
            }
        }
        undoManager?.setActionName("Add Sketch Constraint")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func removeSketchConstraint(from featureId: UUID, constraintId: UUID) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let constraintIndex = sketchData.constraints.firstIndex(where: { $0.id == constraintId }) else {
            return .failure(.objectNotFound(ObjectId(constraintId.uuidString)))
        }

        let removed = sketchData.constraints.remove(at: constraintIndex)
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertSketchConstraint(to: featureId, constraint: removed, at: constraintIndex)
            }
        }
        undoManager?.setActionName("Delete Sketch Constraint")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func insertSketchConstraint(to featureId: UUID, constraint: SketchConstraint, at insertIndex: Int) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let clamped = min(max(0, insertIndex), sketchData.constraints.count)
        sketchData.constraints.insert(constraint, at: clamped)
        features[index].operation = .sketch(sketchData)

        let constraintId = constraint.id
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeSketchConstraint(from: featureId, constraintId: constraintId)
            }
        }
        undoManager?.setActionName("Add Sketch Constraint")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func updateSketchConstraints(in featureId: UUID, constraints: [SketchConstraint]) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let oldConstraints = sketchData.constraints
        sketchData.constraints = constraints
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchConstraints(in: featureId, constraints: oldConstraints)
            }
        }
        undoManager?.setActionName("Update Sketch Constraints")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func setSketchConstraintDriven(in featureId: UUID, constraintId: UUID, isDriven: Bool) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let constraintIndex = sketchData.constraints.firstIndex(where: { $0.id == constraintId }) else {
            return .failure(.objectNotFound(ObjectId(constraintId.uuidString)))
        }

        let previousDriven = sketchData.constraints[constraintIndex].isDriven
        if previousDriven == isDriven {
            return .success(())
        }

        sketchData.constraints[constraintIndex].isDriven = isDriven
        features[index].operation = .sketch(sketchData)

        let currentDriven = isDriven
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.setSketchConstraintDriven(in: featureId, constraintId: constraintId, isDriven: previousDriven)
                target.undoManager?.setActionName(currentDriven ? "Convert Constraint to Driven" : "Convert Constraint to Driving")
            }
        }
        undoManager?.setActionName(currentDriven ? "Convert Constraint to Driven" : "Convert Constraint to Driving")
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func addSketchEntitiesAndConstraints(
        to featureId: UUID,
        entities: [SketchEntity],
        constraints: [SketchConstraint],
        actionName: String = "Add Sketch Geometry"
    ) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let addedEntityIds = entities.map(\.id)
        let addedConstraintIds = constraints.map(\.id)

        sketchData.entities.append(contentsOf: entities)
        sketchData.constraints.append(contentsOf: constraints)
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.removeSketchEntitiesAndConstraints(
                    from: featureId,
                    entityIds: addedEntityIds,
                    constraintIds: addedConstraintIds,
                    actionName: actionName
                )
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1
        return .success(())
    }

    private func removeSketchEntitiesAndConstraints(
        from featureId: UUID,
        entityIds: [UUID],
        constraintIds: [UUID],
        actionName: String
    ) {
        guard let index = features.firstIndex(where: { $0.id == featureId }),
              case .sketch(var sketchData) = features[index].operation else {
            return
        }
        let removedEntities = sketchData.entities.filter { entityIds.contains($0.id) }
        let removedConstraints = sketchData.constraints.filter { constraintIds.contains($0.id) }
        sketchData.entities.removeAll(where: { entityIds.contains($0.id) })
        sketchData.constraints.removeAll(where: { constraintIds.contains($0.id) })
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.addSketchEntitiesAndConstraints(
                    to: featureId,
                    entities: removedEntities,
                    constraints: removedConstraints,
                    actionName: actionName
                )
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1
    }

    // MARK: - Interactive Sketch Drag Sessions (BL-CON-07)

    public func beginInteractiveSketchDrag(featureId: UUID) {
        guard let index = features.firstIndex(where: { $0.id == featureId }),
              case .sketch(let sketchData) = features[index].operation else {
            return
        }
        guard !features[index].isLocked else { return }
        activeInteractiveSketchDrag = (featureId: featureId, initialEntities: sketchData.entities)
    }

    public func endInteractiveSketchDrag(featureId: UUID) {
        guard let active = activeInteractiveSketchDrag, active.featureId == featureId else {
            activeInteractiveSketchDrag = nil
            return
        }
        activeInteractiveSketchDrag = nil

        guard let index = features.firstIndex(where: { $0.id == featureId }),
              case .sketch(let sketchData) = features[index].operation else {
            return
        }

        let initialEntities = active.initialEntities
        let finalEntities = sketchData.entities
        guard finalEntities != initialEntities else { return }

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchEntities(in: featureId, entities: initialEntities)
                target.undoManager?.setActionName("Drag Sketch Entity")
            }
        }
        undoManager?.setActionName("Drag Sketch Entity")
        undoStateVersion += 1
    }

    @discardableResult
    public func updateSketchEntities(in featureId: UUID, entities: [SketchEntity]) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }

        let oldEntities = sketchData.entities
        sketchData.entities = entities
        features[index].operation = .sketch(sketchData)

        if activeInteractiveSketchDrag == nil {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateSketchEntities(in: featureId, entities: oldEntities)
                }
            }
            undoManager?.setActionName("Update Sketch Entities")
        }
        undoStateVersion += 1
        return .success(())
    }

    // MARK: - Sketch Trim, Extend & Split Mutators (BL-SKT-08)

    @discardableResult
    public func trimSketchEntity(
        in featureId: UUID,
        entityId: UUID,
        clickPoint: SIMD2<Double>
    ) -> Result<TrimResult, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            return .failure(.objectNotFound(ObjectId(entityId.uuidString)))
        }

        let entity = sketchData.entities[entityIndex]
        let trimResult: TrimResult
        do {
            trimResult = try SketchOperations.trim(entity: entity, at: clickPoint, in: sketchData.entities)
        } catch let err as SketchError {
            return .failure(.sketchError(err))
        } catch {
            return .failure(.sketchError(.invalidEntity(error.localizedDescription)))
        }

        let oldEntity = entity

        switch trimResult {
        case .updated(let updated):
            sketchData.entities[entityIndex] = updated
            features[index].operation = .sketch(sketchData)

            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
                }
            }

        case .divided(let updated, let added):
            sketchData.entities[entityIndex] = updated
            sketchData.entities.insert(added, at: entityIndex + 1)
            features[index].operation = .sketch(sketchData)

            let addedId = added.id
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeSketchEntity(from: featureId, entityId: addedId)
                    _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
                }
            }

        case .deleted:
            sketchData.entities.remove(at: entityIndex)
            features[index].operation = .sketch(sketchData)

            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.insertSketchEntity(to: featureId, entity: oldEntity, at: entityIndex)
                }
            }
        }

        undoManager?.setActionName("Trim Sketch Entity")
        undoStateVersion += 1
        return .success(trimResult)
    }

    @discardableResult
    public func trimSketchEntitiesAlongPath(
        in featureId: UUID,
        path: [SIMD2<Double>]
    ) -> Result<[TrimResult], DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard path.count >= 2 else {
            return .success([])
        }

        let oldEntities = sketchData.entities
        var currentEntities = sketchData.entities
        let trimResults = SketchOperations.trimAlongPath(path: path, in: &currentEntities)

        guard !trimResults.isEmpty else {
            return .success([])
        }

        sketchData.entities = currentEntities
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchEntities(in: featureId, entities: oldEntities)
            }
        }
        undoManager?.setActionName("Trim Sketch Entity")
        undoStateVersion += 1
        return .success(trimResults)
    }

    @discardableResult
    public func extendSketchEntity(
        in featureId: UUID,
        entityId: UUID,
        targetEnd: SketchEntityEnd
    ) -> Result<SketchEntity, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            return .failure(.objectNotFound(ObjectId(entityId.uuidString)))
        }

        let entity = sketchData.entities[entityIndex]
        let extended: SketchEntity
        do {
            extended = try SketchOperations.extend(entity: entity, targetEnd: targetEnd, in: sketchData.entities)
        } catch let err as SketchError {
            return .failure(.sketchError(err))
        } catch {
            return .failure(.sketchError(.invalidEntity(error.localizedDescription)))
        }

        let oldEntity = entity
        sketchData.entities[entityIndex] = extended
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
            }
        }
        undoManager?.setActionName("Extend Sketch Entity")
        undoStateVersion += 1
        return .success(extended)
    }

    @discardableResult
    public func splitSketchEntity(
        in featureId: UUID,
        entityId: UUID,
        at point: SIMD2<Double>
    ) -> Result<(SketchEntity, SketchEntity), DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == featureId }) else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(featureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(featureId.uuidString)))
        }
        guard let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            return .failure(.objectNotFound(ObjectId(entityId.uuidString)))
        }

        let entity = sketchData.entities[entityIndex]
        let parts: (SketchEntity, SketchEntity)
        do {
            parts = try SketchOperations.split(entity: entity, at: point)
        } catch let err as SketchError {
            return .failure(.sketchError(err))
        } catch {
            return .failure(.sketchError(.invalidEntity(error.localizedDescription)))
        }

        let oldEntity = entity
        let secondId = parts.1.id
        sketchData.entities[entityIndex] = parts.0
        sketchData.entities.insert(parts.1, at: entityIndex + 1)
        features[index].operation = .sketch(sketchData)

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeSketchEntity(from: featureId, entityId: secondId)
                _ = target.updateSketchEntity(in: featureId, entity: oldEntity)
            }
        }
        undoManager?.setActionName("Split Sketch Entity")
        undoStateVersion += 1
        return .success(parts)
    }

    @discardableResult
    public func projectEntity(
        reference: Reference,
        into sketchFeatureId: UUID
    ) -> Result<SketchEntity, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.id == sketchFeatureId }) else {
            return .failure(.objectNotFound(ObjectId(sketchFeatureId.uuidString)))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(features[index].outputSolidId ?? ObjectId(sketchFeatureId.uuidString)))
        }
        guard case .sketch(var sketchData) = features[index].operation else {
            return .failure(.objectNotFound(ObjectId(sketchFeatureId.uuidString)))
        }

        // Validate reference ordering and existence
        switch ReferenceResolver.resolve(reference: reference, for: features[index], in: self) {
        case .failure(let error):
            return .failure(.referenceResolutionFailed(error))
        case .success:
            break
        }

        // Evaluate 3D curve
        let curveResult = ModelEdgeEvaluator.evaluate(reference: reference, in: self)
        let curve: EvaluatedCurve3D
        switch curveResult {
        case .success(let evaluated):
            curve = evaluated
        case .failure(let error):
            return .failure(.referenceResolutionFailed(error))
        }

        // Resolve sketch plane
        let plane = resolveSketchPlane(for: sketchData)

        // Project into 2D
        let projectedEntity: SketchEntity
        do {
            projectedEntity = try SketchOperations.project(curve: curve, onto: plane, reference: reference)
        } catch let sketchErr as SketchError {
            return .failure(.sketchError(sketchErr))
        } catch {
            return .failure(.sketchError(.invalidEntity(error.localizedDescription)))
        }

        // Append to sketch entities and register reference in feature.references
        sketchData.entities.append(projectedEntity)
        features[index].operation = .sketch(sketchData)
        let referenceWasAdded: Bool
        if !features[index].references.contains(reference) {
            features[index].references.append(reference)
            referenceWasAdded = true
        } else {
            referenceWasAdded = false
        }

        let entityId = projectedEntity.id
        let actionName = "Project Geometry"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.unprojectEntity(from: sketchFeatureId, entityId: entityId, reference: referenceWasAdded ? reference : nil)
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1

        return .success(projectedEntity)
    }

    private func unprojectEntity(from sketchFeatureId: UUID, entityId: UUID, reference: Reference?) {
        guard let index = features.firstIndex(where: { $0.id == sketchFeatureId }),
              case .sketch(var sketchData) = features[index].operation,
              let entityIndex = sketchData.entities.firstIndex(where: { $0.id == entityId }) else {
            return
        }
        let removed = sketchData.entities.remove(at: entityIndex)
        features[index].operation = .sketch(sketchData)
        if let reference {
            features[index].references.removeAll(where: { $0 == reference })
        }
        let actionName = "Project Geometry"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.reprojectEntity(into: sketchFeatureId, entity: removed, at: entityIndex, reference: reference)
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1
    }

    private func reprojectEntity(into sketchFeatureId: UUID, entity: SketchEntity, at insertIndex: Int, reference: Reference?) {
        guard let index = features.firstIndex(where: { $0.id == sketchFeatureId }),
              case .sketch(var sketchData) = features[index].operation else {
            return
        }
        let safeIndex = max(0, min(insertIndex, sketchData.entities.count))
        sketchData.entities.insert(entity, at: safeIndex)
        features[index].operation = .sketch(sketchData)
        if let reference, !features[index].references.contains(reference) {
            features[index].references.append(reference)
        }
        let entityId = entity.id
        let actionName = "Project Geometry"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.unprojectEntity(from: sketchFeatureId, entityId: entityId, reference: reference)
            }
        }
        undoManager?.setActionName(actionName)
        undoStateVersion += 1
    }

    @discardableResult
    public func extrudeSketch(
        sketchFeatureId: UUID,
        distance: Double,
        isSymmetric: Bool = false,
        draftAngle: Double = 0.0,
        regionId: UUID? = nil
    ) throws -> Feature {
        guard let sketchFeature = feature(for: sketchFeatureId) else {
            throw DocumentMutationError.objectNotFound(ObjectId(sketchFeatureId.uuidString))
        }
        guard case .sketch(let sketchData) = sketchFeature.operation else {
            throw DocumentMutationError.objectNotFound(ObjectId(sketchFeatureId.uuidString))
        }

        let sketchPlane = resolveSketchPlane(for: sketchData)
        let profile: SketchProfile
        if let regionId,
           let regions = try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: sketchPlane),
           let matched = regions.first(where: { $0.id == regionId }) {
            profile = matched.toProfile(plane: sketchPlane)
        } else {
            profile = try SketchProfileBuilder.build(from: sketchData.entities, plane: sketchPlane)
        }
        let clampedDistance = Double(DocumentLimits.extrudeDistance.clamp(Float(distance)))

        seq += 1
        let solidId = ObjectId("extrude-\(seq)")
        let extrudeFeature = Feature(
            name: "Extrude \(seq)",
            operation: .extrude(ExtrudeFeatureData(
                sketchFeatureId: sketchFeatureId,
                distance: clampedDistance,
                isSymmetric: isSymmetric,
                draftAngle: draftAngle,
                profile: profile,
                regionId: regionId
            )),
            inputExpressions: ["distance": FeatureExpression(value: clampedDistance)],
            references: [.feature(sketchFeatureId, role: "sketchProfile")],
            outputSolidId: solidId,
            bodyOperation: .create,
            targetBodyId: nil
        )

        _ = addFeature(extrudeFeature)
        return extrudeFeature
    }

    /// Resolves an axis reference into an origin and unit direction vector (BL-PRT-02).
    public func resolveAxis(from reference: Reference) -> Result<(origin: SIMD3<Float>, direction: SIMD3<Float>), DocumentMutationError> {
        switch reference.target {
        case .feature(let featId):
            guard let feat = self.feature(for: featId) else {
                return .failure(.invalidOperation("Referenced feature \(featId.uuidString) not found"))
            }
            guard case .datumAxis(let axisData) = feat.operation else {
                return .failure(.invalidOperation("Feature \(feat.name) is not a datum axis"))
            }
            do {
                let geom = try DatumAxisEvaluator.evaluate(feature: feat, data: axisData, in: self)
                let len = simd_length(geom.direction)
                guard len > 1e-6 else {
                    return .failure(.invalidOperation("Datum axis has zero direction"))
                }
                return .success((geom.origin, geom.direction / len))
            } catch {
                return .failure(.invalidOperation(error.localizedDescription))
            }
        case .sketchEntity, .edge:
            let curveResult = ModelEdgeEvaluator.evaluate(reference: reference, in: self)
            switch curveResult {
            case .success(.line(let start, let end)):
                let diff = end - start
                let len = simd_length(diff)
                guard len > 1e-6 else {
                    return .failure(.invalidOperation("Axis line has zero length"))
                }
                return .success((start, diff / len))
            case .success:
                return .failure(.invalidOperation("Selected axis edge is not a straight line"))
            case .failure(let err):
                return .failure(.invalidOperation(err.description))
            }
        default:
            return .failure(.invalidOperation("Unsupported axis reference target"))
        }
    }

    /// Validates that a revolve axis does not cross the sketch profile and has valid direction and extent.
    public static func validateRevolveAxis(
        profile: SketchProfile,
        axisOrigin: SIMD3<Float>,
        axisDirection: SIMD3<Float>
    ) -> String? {
        ShapeEvaluator.validateRevolveAxis(
            profile: profile,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection
        )
    }

    /// Creates a revolved solid from a sketch region or profile about an axis (BL-PRT-02).
    @discardableResult
    public func revolveSketch(
        sketchFeatureId: UUID,
        regionId: UUID? = nil,
        mode: RevolveMode = .full,
        angle: Double = 360.0,
        angle2: Double = 0.0,
        axisReference: Reference
    ) throws -> Feature {
        guard angle > 0 && angle <= 360.0 else {
            throw DocumentMutationError.invalidOperation("Revolve angle must be within (0, 360]")
        }
        if mode == .twoDirection {
            guard angle2 > 0 && angle2 <= 360.0 else {
                throw DocumentMutationError.invalidOperation("Revolve angle2 must be within (0, 360]")
            }
        }

        guard let sketchFeature = feature(for: sketchFeatureId) else {
            throw DocumentMutationError.objectNotFound(ObjectId(sketchFeatureId.uuidString))
        }
        guard case .sketch(let sketchData) = sketchFeature.operation else {
            throw DocumentMutationError.objectNotFound(ObjectId(sketchFeatureId.uuidString))
        }

        let sketchPlane = resolveSketchPlane(for: sketchData)
        let profile: SketchProfile
        do {
            if let regionId,
               let regions = try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: sketchPlane),
               let matched = regions.first(where: { $0.id == regionId }) {
                profile = matched.toProfile(plane: sketchPlane)
            } else {
                profile = try SketchProfileBuilder.build(from: sketchData.entities, plane: sketchPlane)
            }
        } catch let sketchErr as SketchError {
            throw DocumentMutationError.sketchError(sketchErr)
        }

        guard profile.points.count >= 3 else {
            throw DocumentMutationError.invalidOperation("Profile must have at least 3 points")
        }

        let axisGeom: (origin: SIMD3<Float>, direction: SIMD3<Float>)
        switch resolveAxis(from: axisReference) {
        case .success(let geom):
            axisGeom = geom
        case .failure(let msg):
            throw DocumentMutationError.invalidOperation("Failed to resolve revolve axis: \(msg)")
        }

        if let validationError = ShapeEvaluator.validateRevolveAxis(
            profile: profile,
            axisOrigin: axisGeom.origin,
            axisDirection: axisGeom.direction
        ) {
            throw DocumentMutationError.invalidOperation(validationError)
        }

        let clampedAngle = Double(DocumentLimits.revolveAngle.clamp(Float(angle)))
        let clampedAngle2 = Double(DocumentLimits.revolveAngle.clamp(Float(angle2)))

        seq += 1
        let solidId = ObjectId("revolve-\(seq)")
        var refs: [Reference] = [.feature(sketchFeatureId, role: "sketchProfile")]
        refs.append(axisReference)

        let revolveFeature = Feature(
            name: "Revolve \(seq)",
            operation: .revolve(RevolveFeatureData(
                sketchFeatureId: sketchFeatureId,
                regionId: regionId,
                mode: mode,
                angle: clampedAngle,
                angle2: clampedAngle2,
                axisReference: axisReference,
                profile: profile,
                axisOrigin: axisGeom.origin,
                axisDirection: axisGeom.direction
            )),
            inputExpressions: [
                "angle": FeatureExpression(value: clampedAngle),
                "angle2": FeatureExpression(value: clampedAngle2)
            ],
            references: refs,
            outputSolidId: solidId,
            bodyOperation: .create,
            targetBodyId: nil
        )

        _ = addFeature(revolveFeature)
        undoManager?.setActionName("Revolve Sketch")
        return revolveFeature
    }

    /// Chamfers selected edges on a solid across equal-distance, two-distances, or distance-angle modes (BL-PRT-07).
    @discardableResult
    public func chamferEdges(
        targetSolidId: SolidId,
        edgeReferences: [TopologicalReference],
        mode: ChamferMode = .equalDistance,
        distance: Double = 1.0,
        distance2: Double = 1.0,
        angle: Double = 45.0,
        actionName: String? = nil
    ) throws -> Feature {
        guard distance > 0 else {
            throw DocumentMutationError.invalidOperation("Chamfer distance must be positive")
        }
        if mode == .twoDistances {
            guard distance2 > 0 else {
                throw DocumentMutationError.invalidOperation("Chamfer distance2 must be positive")
            }
        }
        if mode == .distanceAngle {
            guard angle > 0 && angle < 90 else {
                throw DocumentMutationError.invalidOperation("Chamfer angle must be between 0 and 90 degrees")
            }
        }
        guard !edgeReferences.isEmpty else {
            throw DocumentMutationError.invalidOperation("Chamfer requires at least one edge reference")
        }
        guard let targetFeature = features.first(where: { $0.outputSolidId == targetSolidId }) else {
            throw DocumentMutationError.objectNotFound(targetSolidId)
        }
        guard !targetFeature.isLocked else {
            throw DocumentMutationError.objectLocked(targetSolidId)
        }

        let clampedDist = Double(DocumentLimits.chamferDistance.clamp(Float(distance)))
        let clampedDist2 = Double(DocumentLimits.chamferDistance.clamp(Float(distance2)))
        let clampedAngle = Double(DocumentLimits.chamferAngle.clamp(Float(angle)))

        seq += 1
        let solidId = ObjectId("chamfer-\(seq)")
        var exprs: [String: FeatureExpression] = [
            "distance": FeatureExpression(value: clampedDist)
        ]
        if mode == .twoDistances {
            exprs["distance2"] = FeatureExpression(value: clampedDist2)
        } else if mode == .distanceAngle {
            exprs["angle"] = FeatureExpression(value: clampedAngle)
        }

        var refs: [Reference] = edgeReferences.map { Reference.edge($0) }
        refs.append(Reference.body(targetSolidId, role: "targetBody"))

        let chamferFeature = Feature(
            name: "Chamfer \(seq)",
            operation: .chamfer(ChamferFeatureData(
                targetSolidId: targetSolidId,
                mode: mode,
                distance: clampedDist,
                distance2: clampedDist2,
                angle: clampedAngle,
                edgeReferences: edgeReferences
            )),
            inputExpressions: exprs,
            references: refs,
            outputSolidId: solidId,
            bodyOperation: .cut,
            targetBodyId: targetSolidId,
            transform: targetFeature.transform,
            isVisible: true,
            isLocked: false,
            material: targetFeature.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex
        let origTargetVis = targetFeature.isVisible

        features.insert(chamferFeature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = solidId
        setVisibility(id: targetSolidId, isVisible: false)

        let effectiveActionName = actionName ?? "Chamfer Edges"
        registerChamferUndo(
            id: solidId,
            feature: chamferFeature,
            targetSolidId: targetSolidId,
            origTargetVis: origTargetVis,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return chamferFeature
    }

    private func registerChamferUndo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setVisibility(id: targetSolidId, isVisible: origTargetVis)
                let res = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }

                target.registerChamferRedo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
    }

    private func registerChamferRedo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                guard case .success = res else { return }
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.setVisibility(id: targetSolidId, isVisible: false)
                target.registerChamferUndo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
    }

    /// Hollows a solid body to uniform wall thickness with optional removed open faces and per-face thickness overrides (BL-PRT-08).
    @discardableResult
    public func shellBody(
        targetSolidId: SolidId,
        thickness: Double = 1.0,
        removedFaceReferences: [TopologicalReference] = [],
        perFaceOverrides: [FaceThicknessOverride] = [],
        actionName: String? = nil
    ) throws -> Feature {
        guard thickness > 0 else {
            throw DocumentMutationError.invalidOperation("Shell thickness must be positive")
        }
        for override in perFaceOverrides {
            guard override.thickness > 0 else {
                throw DocumentMutationError.invalidOperation("Shell face thickness override must be positive")
            }
        }
        guard let targetFeature = features.first(where: { $0.outputSolidId == targetSolidId }) else {
            throw DocumentMutationError.objectNotFound(targetSolidId)
        }
        guard !targetFeature.isLocked else {
            throw DocumentMutationError.objectLocked(targetSolidId)
        }

        let clampedThickness = Double(DocumentLimits.shellThickness.clamp(Float(thickness)))
        let clampedOverrides = perFaceOverrides.map {
            FaceThicknessOverride(faceReference: $0.faceReference, thickness: Double(DocumentLimits.shellThickness.clamp(Float($0.thickness))))
        }

        seq += 1
        let solidId = ObjectId("shell-\(seq)")
        let exprs: [String: FeatureExpression] = [
            "thickness": FeatureExpression(value: clampedThickness)
        ]

        var refs: [Reference] = removedFaceReferences.map { Reference.face($0) }
        for override in clampedOverrides {
            refs.append(Reference.face(override.faceReference))
        }
        refs.append(Reference.body(targetSolidId, role: "targetBody"))

        let shellFeature = Feature(
            name: "Shell \(seq)",
            operation: .shell(ShellFeatureData(
                targetSolidId: targetSolidId,
                thickness: clampedThickness,
                removedFaceReferences: removedFaceReferences,
                perFaceOverrides: clampedOverrides
            )),
            inputExpressions: exprs,
            references: refs,
            outputSolidId: solidId,
            bodyOperation: .cut,
            targetBodyId: targetSolidId,
            transform: targetFeature.transform,
            isVisible: true,
            isLocked: false,
            material: targetFeature.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex
        let origTargetVis = targetFeature.isVisible

        features.insert(shellFeature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = solidId
        setVisibility(id: targetSolidId, isVisible: false)

        let effectiveActionName = actionName ?? "Shell Body"
        registerShellUndo(
            id: solidId,
            feature: shellFeature,
            targetSolidId: targetSolidId,
            origTargetVis: origTargetVis,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return shellFeature
    }

    private func registerShellUndo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setVisibility(id: targetSolidId, isVisible: origTargetVis)
                let res = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }

                target.registerShellRedo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
    }

    private func registerShellRedo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                guard case .success = res else { return }
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.setVisibility(id: targetSolidId, isVisible: false)
                target.registerShellUndo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
    }

    /// Cuts standard or custom holes into a solid planar face (BL-PRT-10).
    @discardableResult
    public func holeBody(
        targetSolidId: SolidId,
        faceReference: TopologicalReference,
        sketchFeatureId: UUID? = nil,
        points: [SIMD2<Double>] = [],
        holeType: HoleType = .simple,
        standard: HoleStandard = .custom,
        sizeDesignation: String? = nil,
        diameter: Double = 5.0,
        depth: Double = 10.0,
        isThrough: Bool = true,
        counterboreDiameter: Double = 0.0,
        counterboreDepth: Double = 0.0,
        countersinkDiameter: Double = 0.0,
        countersinkAngle: Double = 90.0,
        drillTipAngle: Double? = nil,
        threadMetadata: ThreadMetadata? = nil,
        actionName: String? = nil
    ) throws -> Feature {
        guard diameter > 0 else {
            throw DocumentMutationError.invalidOperation("Hole diameter must be positive")
        }
        if !isThrough {
            guard depth > 0 else {
                throw DocumentMutationError.invalidOperation("Hole depth must be positive")
            }
        }
        if holeType == .counterbore {
            guard counterboreDiameter > diameter else {
                throw DocumentMutationError.invalidOperation("Counterbore diameter must be greater than hole diameter")
            }
            guard counterboreDepth > 0 else {
                throw DocumentMutationError.invalidOperation("Counterbore depth must be positive")
            }
        }
        if holeType == .countersink {
            guard countersinkDiameter > diameter else {
                throw DocumentMutationError.invalidOperation("Countersink diameter must be greater than hole diameter")
            }
            guard countersinkAngle > 0 && countersinkAngle < 180 else {
                throw DocumentMutationError.invalidOperation("Countersink angle must be between 0 and 180 degrees")
            }
        }
        if standard != .custom {
            guard let designation = sizeDesignation, HoleStandards.lookup(standard: standard, designation: designation) != nil else {
                throw DocumentMutationError.invalidOperation("Unknown standard hole size: \(sizeDesignation ?? "none")")
            }
        }
        guard let targetFeature = features.first(where: { $0.outputSolidId == targetSolidId }) else {
            throw DocumentMutationError.objectNotFound(targetSolidId)
        }
        guard !targetFeature.isLocked else {
            throw DocumentMutationError.objectLocked(targetSolidId)
        }

        let clampedDiameter = Double(DocumentLimits.holeDiameter.clamp(Float(diameter)))
        let clampedDepth = Double(DocumentLimits.holeDepth.clamp(Float(depth)))
        let clampedCbDia = counterboreDiameter > 0 ? Double(DocumentLimits.holeDiameter.clamp(Float(counterboreDiameter))) : 0.0
        let clampedCbDepth = counterboreDepth > 0 ? Double(DocumentLimits.holeDepth.clamp(Float(counterboreDepth))) : 0.0
        let clampedCsDia = countersinkDiameter > 0 ? Double(DocumentLimits.holeDiameter.clamp(Float(countersinkDiameter))) : 0.0
        let clampedCsAngle = countersinkAngle > 0 ? Double(DocumentLimits.countersinkAngle.clamp(Float(countersinkAngle))) : 90.0

        seq += 1
        let solidId = ObjectId("hole-\(seq)")
        var exprs: [String: FeatureExpression] = [
            "diameter": FeatureExpression(value: clampedDiameter),
            "depth": FeatureExpression(value: clampedDepth)
        ]
        if clampedCbDia > 0 {
            exprs["counterboreDiameter"] = FeatureExpression(value: clampedCbDia)
            exprs["counterboreDepth"] = FeatureExpression(value: clampedCbDepth)
        }
        if clampedCsDia > 0 {
            exprs["countersinkDiameter"] = FeatureExpression(value: clampedCsDia)
            exprs["countersinkAngle"] = FeatureExpression(value: clampedCsAngle)
        }

        var refs: [Reference] = [
            .face(faceReference),
            .body(targetSolidId, role: "targetBody")
        ]
        if let sketchFeatureId {
            refs.append(.feature(sketchFeatureId, role: "holePoints"))
        }

        let holeData = HoleFeatureData(
            targetSolidId: targetSolidId,
            faceReference: faceReference,
            sketchFeatureId: sketchFeatureId,
            points: points,
            holeType: holeType,
            standard: standard,
            sizeDesignation: sizeDesignation,
            diameter: clampedDiameter,
            depth: clampedDepth,
            isThrough: isThrough,
            counterboreDiameter: clampedCbDia,
            counterboreDepth: clampedCbDepth,
            countersinkDiameter: clampedCsDia,
            countersinkAngle: clampedCsAngle,
            drillTipAngle: drillTipAngle,
            threadMetadata: threadMetadata
        )

        let holeFeature = Feature(
            name: "Hole \(seq)",
            operation: .hole(holeData),
            inputExpressions: exprs,
            references: refs,
            outputSolidId: solidId,
            bodyOperation: .cut,
            targetBodyId: targetSolidId,
            transform: targetFeature.transform,
            isVisible: true,
            isLocked: false,
            material: targetFeature.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex
        let origTargetVis = targetFeature.isVisible

        features.insert(holeFeature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = solidId
        setVisibility(id: targetSolidId, isVisible: false)

        let effectiveActionName = actionName ?? "Create Hole"
        registerHoleUndo(
            id: solidId,
            feature: holeFeature,
            targetSolidId: targetSolidId,
            origTargetVis: origTargetVis,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return holeFeature
    }

    private func registerHoleUndo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setVisibility(id: targetSolidId, isVisible: origTargetVis)
                let res = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }

                target.registerHoleRedo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
    }

    private func registerHoleRedo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                guard case .success = res else { return }
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.setVisibility(id: targetSolidId, isVisible: false)
                target.registerHoleUndo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
    }

    // MARK: - Pattern Mutations (BL-PRT-12)

    public func patternBody(
        params: PatternParams,
        actionName: String? = nil
    ) throws -> Feature {
        guard params.count > 0 else {
            throw DocumentMutationError.invalidOperation("Pattern count must be positive")
        }
        if params.patternType == .linear {
            guard params.linearSpacing > 0 else {
                throw DocumentMutationError.invalidOperation("Pattern linear spacing must be positive")
            }
            guard simd_length(params.linearDirection) > 1e-6 else {
                throw DocumentMutationError.invalidOperation("Pattern linear direction must not be zero")
            }
        } else if params.patternType == .circular {
            guard params.totalAngle > 0 else {
                throw DocumentMutationError.invalidOperation("Pattern total angle must be positive")
            }
            guard simd_length(params.axisDirection) > 1e-6 else {
                throw DocumentMutationError.invalidOperation("Pattern axis direction must not be zero")
            }
        }

        guard let targetFeature = features.first(where: { $0.outputSolidId == params.targetSolidId }) else {
            throw DocumentMutationError.objectNotFound(params.targetSolidId)
        }
        guard !targetFeature.isLocked else {
            throw DocumentMutationError.objectLocked(params.targetSolidId)
        }

        var clampedParams = params
        clampedParams.count = Int(DocumentLimits.patternCount.clamp(Float(params.count)))
        if params.patternType == .linear {
            clampedParams.linearSpacing = Double(DocumentLimits.patternSpacing.clamp(Float(params.linearSpacing)))
        } else {
            clampedParams.totalAngle = Double(DocumentLimits.patternAngle.clamp(Float(params.totalAngle)))
        }

        seq += 1
        let solidId = ObjectId("pattern-\(seq)")
        var exprs: [String: FeatureExpression] = [
            "count": FeatureExpression(value: Double(clampedParams.count))
        ]
        if clampedParams.patternType == .linear {
            exprs["linearSpacing"] = FeatureExpression(value: clampedParams.linearSpacing)
        } else {
            exprs["totalAngle"] = FeatureExpression(value: clampedParams.totalAngle)
        }

        var refs: [Reference] = [
            .body(params.targetSolidId, role: "patternTarget")
        ]
        if let baseBodyId = params.baseBodySolidId {
            refs.append(.body(baseBodyId, role: "baseBody"))
        }

        let patternFeature = Feature(
            name: clampedParams.patternType == .linear ? "Linear Pattern \(seq)" : "Circular Pattern \(seq)",
            operation: .pattern(clampedParams),
            inputExpressions: exprs,
            references: refs,
            outputSolidId: solidId,
            bodyOperation: .create,
            targetBodyId: params.targetSolidId,
            transform: targetFeature.transform,
            isVisible: true,
            isLocked: false,
            material: targetFeature.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex
        let origTargetVis = targetFeature.isVisible

        features.insert(patternFeature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = solidId
        setVisibility(id: params.targetSolidId, isVisible: false)

        let effectiveActionName = actionName ?? (clampedParams.patternType == .linear ? "Linear Pattern" : "Circular Pattern")
        registerPatternUndo(
            id: solidId,
            feature: patternFeature,
            targetSolidId: params.targetSolidId,
            origTargetVis: origTargetVis,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return patternFeature
    }

    public func patternBody(
        targetSolidId: SolidId,
        patternType: PatternType,
        count: Int,
        linearSpacing: Double = 10.0,
        linearDirection: SIMD3<Double> = SIMD3<Double>(1, 0, 0),
        axisOrigin: SIMD3<Double> = SIMD3<Double>(0, 0, 0),
        axisDirection: SIMD3<Double> = SIMD3<Double>(0, 0, 1),
        totalAngle: Double = 360.0,
        isFullCircle: Bool = true,
        skippedIndices: Set<Int> = [],
        actionName: String? = nil
    ) throws -> Feature {
        let params = PatternParams(
            targetSolidId: targetSolidId,
            targetType: .body,
            patternType: patternType,
            count: count,
            linearSpacing: linearSpacing,
            linearDirection: linearDirection,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            totalAngle: totalAngle,
            isFullCircle: isFullCircle,
            skippedIndices: skippedIndices
        )
        return try patternBody(params: params, actionName: actionName)
    }

    private func registerPatternUndo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setVisibility(id: targetSolidId, isVisible: origTargetVis)
                let res = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }

                target.registerPatternRedo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
    }

    private func registerPatternRedo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                guard case .success = res else { return }
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.setVisibility(id: targetSolidId, isVisible: false)
                target.registerPatternUndo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
    }

    public func mirrorBody(
        params: MirrorParams,
        actionName: String? = nil
    ) throws -> Feature {
        let normalLen = simd_length(params.planeNormal)
        guard normalLen > 1e-6 else {
            throw DocumentMutationError.invalidOperation("Mirror plane normal must not be zero length")
        }

        guard let targetFeature = features.first(where: { $0.outputSolidId == params.targetSolidId }) else {
            throw DocumentMutationError.objectNotFound(params.targetSolidId)
        }
        guard !targetFeature.isLocked else {
            throw DocumentMutationError.objectLocked(params.targetSolidId)
        }

        seq += 1
        let solidId = ObjectId("mirror-\(seq)")
        let exprs: [String: FeatureExpression] = [:]

        var refs: [Reference] = [
            .body(params.targetSolidId, role: "mirrorTarget")
        ]
        if let planeRef = params.planeReference {
            refs.append(planeRef)
        }

        let mirrorFeature = Feature(
            name: "Mirror \(seq)",
            operation: .mirror(params),
            inputExpressions: exprs,
            references: refs,
            outputSolidId: solidId,
            bodyOperation: .create,
            targetBodyId: params.targetSolidId,
            transform: targetFeature.transform,
            isVisible: true,
            isLocked: false,
            material: targetFeature.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex
        let origTargetVis = targetFeature.isVisible

        features.insert(mirrorFeature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = solidId
        if params.keepOriginal {
            setVisibility(id: params.targetSolidId, isVisible: false)
        }

        let effectiveActionName = actionName ?? "Mirror Body"
        registerMirrorUndo(
            id: solidId,
            feature: mirrorFeature,
            targetSolidId: params.targetSolidId,
            origTargetVis: origTargetVis,
            keepOriginal: params.keepOriginal,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return mirrorFeature
    }

    public func mirrorBody(
        targetSolidId: SolidId,
        planeNormal: SIMD3<Double>,
        planeOrigin: SIMD3<Double> = .zero,
        keepOriginal: Bool = true,
        planeReference: Reference? = nil,
        actionName: String? = nil
    ) throws -> Feature {
        let params = MirrorParams(
            targetSolidId: targetSolidId,
            targetType: .body,
            planeNormal: planeNormal,
            planeOrigin: planeOrigin,
            keepOriginal: keepOriginal,
            planeReference: planeReference
        )
        return try mirrorBody(params: params, actionName: actionName)
    }

    private func registerMirrorUndo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        keepOriginal: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                if keepOriginal {
                    target.setVisibility(id: targetSolidId, isVisible: origTargetVis)
                }
                let res = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }

                target.registerMirrorRedo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    keepOriginal: keepOriginal,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
    }

    private func registerMirrorRedo(
        id: ObjectId,
        feature: Feature,
        targetSolidId: SolidId,
        origTargetVis: Bool,
        keepOriginal: Bool,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                guard case .success = res else { return }
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                if keepOriginal {
                    target.setVisibility(id: targetSolidId, isVisible: false)
                }
                target.registerMirrorUndo(
                    id: id,
                    feature: feature,
                    targetSolidId: targetSolidId,
                    origTargetVis: origTargetVis,
                    keepOriginal: keepOriginal,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
    }

    // MARK: - Body Feature Mutators (BL-PRT-18)

    /// Combines two solid bodies using boolean union, subtract, or intersect recorded as a timeline feature (BL-PRT-18).
    @discardableResult
    public func combineBodies(
        targetBodyId: BodyId,
        toolBodyId: BodyId,
        operation: BooleanOp,
        keepTool: Bool = false,
        actionName: String? = nil
    ) throws -> Feature {
        guard targetBodyId != toolBodyId else {
            throw DocumentMutationError.invalidOperation("Cannot combine a body with itself")
        }
        guard let targetObj = objects.first(where: { $0.id == targetBodyId }) else {
            throw DocumentMutationError.objectNotFound(targetBodyId)
        }
        guard let toolObj = objects.first(where: { $0.id == toolBodyId }) else {
            throw DocumentMutationError.objectNotFound(toolBodyId)
        }
        guard !targetObj.isLocked else {
            throw DocumentMutationError.objectLocked(targetBodyId)
        }
        if let targetFeat = feature(for: targetBodyId), targetFeat.isLocked {
            throw DocumentMutationError.objectLocked(targetBodyId)
        }
        if !keepTool {
            if toolObj.isLocked || (feature(for: toolBodyId)?.isLocked == true) {
                throw DocumentMutationError.objectLocked(toolBodyId)
            }
        }

        seq += 1
        let solidId = ObjectId("combine-\(seq)")
        let data = CombineFeatureData(
            targetBodyId: targetBodyId,
            toolBodyId: toolBodyId,
            operation: operation,
            keepTool: keepTool
        )

        let refs = [
            Reference.body(targetBodyId, role: "targetBody"),
            Reference.body(toolBodyId, role: "toolBody")
        ]

        let feature = Feature(
            name: "Combine \(seq)",
            operation: .combine(data),
            references: refs,
            outputSolidId: solidId,
            targetBodyId: targetBodyId,
            transform: targetObj.transform,
            material: targetObj.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = solidId

        let effectiveActionName = actionName ?? "Combine Bodies"
        registerCombineUndo(
            feature: feature,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return feature
    }

    private func registerCombineUndo(
        feature: Feature,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                target.registerCombineRedo(
                    feature: feature,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let solidId = feature.outputSolidId {
                    target.onUndoRedoMutation?(.removed(solidId))
                }
            }
        }
    }

    private func registerCombineRedo(
        feature: Feature,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.registerCombineUndo(
                    feature: feature,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let solidId = feature.outputSolidId {
                    target.onUndoRedoMutation?(.added(solidId))
                }
            }
        }
    }

    /// Moves a solid body via spatial transform recorded as a timeline feature (BL-PRT-18).
    @discardableResult
    public func moveBody(
        targetBodyId: BodyId,
        transform: Transform,
        actionName: String? = nil
    ) throws -> Feature {
        guard transform != .identity else {
            throw DocumentMutationError.invalidOperation("Move transform is identity")
        }
        guard let targetObj = objects.first(where: { $0.id == targetBodyId }) else {
            throw DocumentMutationError.objectNotFound(targetBodyId)
        }
        guard !targetObj.isLocked else {
            throw DocumentMutationError.objectLocked(targetBodyId)
        }
        if let targetFeat = feature(for: targetBodyId), targetFeat.isLocked {
            throw DocumentMutationError.objectLocked(targetBodyId)
        }

        seq += 1
        let data = MoveBodyFeatureData(targetBodyId: targetBodyId, transform: transform)
        let feature = Feature(
            name: "Move Body \(seq)",
            operation: .moveBody(data),
            references: [Reference.body(targetBodyId, role: "targetBody")],
            targetBodyId: targetBodyId,
            transform: transform
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = targetBodyId

        let effectiveActionName = actionName ?? "Move Body"
        registerMoveBodyUndo(
            feature: feature,
            targetBodyId: targetBodyId,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return feature
    }

    private func registerMoveBodyUndo(
        feature: Feature,
        targetBodyId: BodyId,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                target.registerMoveBodyRedo(
                    feature: feature,
                    targetBodyId: targetBodyId,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let obj = target.objects.first(where: { $0.id == targetBodyId }) {
                    target.onUndoRedoMutation?(.transformChanged(targetBodyId, transform: obj.transform))
                }
            }
        }
    }

    private func registerMoveBodyRedo(
        feature: Feature,
        targetBodyId: BodyId,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.registerMoveBodyUndo(
                    feature: feature,
                    targetBodyId: targetBodyId,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let obj = target.objects.first(where: { $0.id == targetBodyId }) {
                    target.onUndoRedoMutation?(.transformChanged(targetBodyId, transform: obj.transform))
                }
            }
        }
    }

    /// Duplicates a solid body with a unique non-colliding name recorded as a timeline feature (BL-PRT-18).
    @discardableResult
    public func copyBody(
        sourceBodyId: BodyId,
        transform: Transform = .identity,
        actionName: String? = nil
    ) throws -> Feature {
        guard let sourceObj = objects.first(where: { $0.id == sourceBodyId }) else {
            throw DocumentMutationError.objectNotFound(sourceBodyId)
        }

        seq += 1
        let newBodyId = ObjectId("copy-\(seq)")
        let uniqueName = generateUniqueBodyName(base: sourceObj.name)
        let data = CopyBodyFeatureData(
            sourceBodyId: sourceBodyId,
            newBodyId: newBodyId,
            transform: transform
        )

        let composedTransform = transform * sourceObj.transform

        let feature = Feature(
            name: uniqueName,
            operation: .copyBody(data),
            references: [Reference.body(sourceBodyId, role: "sourceBody")],
            outputSolidId: newBodyId,
            targetBodyId: sourceBodyId,
            transform: composedTransform,
            material: sourceObj.material
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = newBodyId

        let effectiveActionName = actionName ?? "Copy Body"
        registerCopyBodyUndo(
            feature: feature,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return feature
    }

    private func generateUniqueBodyName(base: String) -> String {
        let existingNames = Set(bodies.map(\.name) + features.map(\.name) + objects.map(\.name))
        let candidate = "\(base) Copy"
        if !existingNames.contains(candidate) {
            return candidate
        }
        var count = 2
        while existingNames.contains("\(base) Copy \(count)") {
            count += 1
        }
        return "\(base) Copy \(count)"
    }

    private func registerCopyBodyUndo(
        feature: Feature,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                target.registerCopyBodyRedo(
                    feature: feature,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let solidId = feature.outputSolidId {
                    target.onUndoRedoMutation?(.removed(solidId))
                }
            }
        }
    }

    private func registerCopyBodyRedo(
        feature: Feature,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.registerCopyBodyUndo(
                    feature: feature,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let solidId = feature.outputSolidId {
                    target.onUndoRedoMutation?(.added(solidId))
                }
            }
        }
    }

    /// Deletes a solid body from the active model recorded as a timeline feature (BL-PRT-18).
    @discardableResult
    public func deleteBody(
        targetBodyId: BodyId,
        actionName: String? = nil
    ) throws -> Feature {
        guard let targetObj = objects.first(where: { $0.id == targetBodyId }) else {
            throw DocumentMutationError.objectNotFound(targetBodyId)
        }
        guard !targetObj.isLocked else {
            throw DocumentMutationError.objectLocked(targetBodyId)
        }
        if let targetFeat = feature(for: targetBodyId), targetFeat.isLocked {
            throw DocumentMutationError.objectLocked(targetBodyId)
        }

        seq += 1
        let data = DeleteBodyFeatureData(targetBodyId: targetBodyId)
        let feature = Feature(
            name: "Delete Body \(seq)",
            operation: .deleteBody(data),
            references: [Reference.body(targetBodyId, role: "targetBody")],
            targetBodyId: targetBodyId
        )

        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        if selectedId == targetBodyId {
            selectedId = nil
        }

        let effectiveActionName = actionName ?? "Delete Body"
        registerDeleteBodyUndo(
            feature: feature,
            targetBodyId: targetBodyId,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return feature
    }

    private func registerDeleteBodyUndo(
        feature: Feature,
        targetBodyId: BodyId,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                target.registerDeleteBodyRedo(
                    feature: feature,
                    targetBodyId: targetBodyId,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(targetBodyId))
            }
        }
    }

    private func registerDeleteBodyRedo(
        feature: Feature,
        targetBodyId: BodyId,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                target.registerDeleteBodyUndo(
                    feature: feature,
                    targetBodyId: targetBodyId,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(targetBodyId))
            }
        }
    }

    // MARK: - Reference Resolution (BL-FND-02, BL-FND-03)

    /// Resolves an input reference in the context of this document.
    public func resolve(reference: Reference, for feature: Feature? = nil) -> Result<ResolvedReference, ReferenceResolutionError> {
        ReferenceResolver.resolve(reference: reference, for: feature, in: self)
    }

    /// Returns all references associated with the given feature.
    public func references(for feature: Feature) -> [Reference] {
        feature.references
    }

    /// Returns all upstream feature UUIDs directly referenced by the given feature via its references or operations (BL-FND-03).
    public func directDependencies(of feature: Feature) -> Set<UUID> {
        var result = Set<UUID>()

        // Explicit references
        for ref in feature.references {
            if let id = ref.referencedFeatureId {
                result.insert(id)
            }
            if case .body(let solidId) = ref.target,
               let targetFeat = self.feature(for: solidId) {
                result.insert(targetFeat.id)
            }
        }

        // Target body dependency for feature body operations (BL-FND-12)
        if feature.bodyOperation != .create,
           let target = feature.targetBodyId,
           let targetFeat = self.feature(for: target) {
            result.insert(targetFeat.id)
        }

        // Operation inputs
        switch feature.operation {
        case .boolean(let b):
            if let fA = self.feature(for: b.targetSolidId) {
                result.insert(fA.id)
            }
            if let fB = self.feature(for: b.toolSolidId) {
                result.insert(fB.id)
            }
        case .extrude(let e):
            if let sId = e.sketchFeatureId {
                result.insert(sId)
            }
        case .revolve(let r):
            if let sId = r.sketchFeatureId {
                result.insert(sId)
            }
            if let axisRef = r.axisReference, let aId = axisRef.referencedFeatureId {
                result.insert(aId)
            }
        case .sketch(let s):
            if let planeRef = s.planeReference {
                result.insert(planeRef.sourceFeatureId)
            }
            if let datumId = s.datumPlaneFeatureId {
                result.insert(datumId)
            }
            if let name = s.planeName, let feat = features.first(where: { $0.name == name }) {
                result.insert(feat.id)
            }
            for entity in s.entities {
                if let refId = entity.reference?.referencedFeatureId {
                    result.insert(refId)
                }
            }
        case .chamfer(let c):
            if let targetFeat = self.feature(for: c.targetSolidId) {
                result.insert(targetFeat.id)
            }
            for edgeRef in c.edgeReferences {
                result.insert(edgeRef.sourceFeatureId)
            }
        case .shell(let s):
            if let targetFeat = self.feature(for: s.targetSolidId) {
                result.insert(targetFeat.id)
            }
            for faceRef in s.removedFaceReferences {
                result.insert(faceRef.sourceFeatureId)
            }
            for override in s.perFaceOverrides {
                result.insert(override.faceReference.sourceFeatureId)
            }
        case .hole(let h):
            if let targetFeat = self.feature(for: h.targetSolidId) {
                result.insert(targetFeat.id)
            }
            result.insert(h.faceReference.sourceFeatureId)
            if let sId = h.sketchFeatureId {
                result.insert(sId)
            }
        case .pattern(let p):
            if let targetFeat = self.feature(for: p.targetSolidId) {
                result.insert(targetFeat.id)
            }
            if let baseBodyId = p.baseBodySolidId, let baseFeat = self.feature(for: baseBodyId) {
                result.insert(baseFeat.id)
            }
        case .mirror(let m):
            if let targetFeat = self.feature(for: m.targetSolidId) {
                result.insert(targetFeat.id)
            }
            if let planeRef = m.planeReference {
                switch planeRef.target {
                case .feature(let featId):
                    result.insert(featId)
                case .face(let topRef):
                    result.insert(topRef.sourceFeatureId)
                default:
                    break
                }
            }
        case .combine(let c):
            if let fA = self.feature(for: c.targetBodyId) {
                result.insert(fA.id)
            }
            if let fB = self.feature(for: c.toolBodyId) {
                result.insert(fB.id)
            }
        case .moveBody(let m):
            if let f = self.feature(for: m.targetBodyId) {
                result.insert(f.id)
            }
        case .copyBody(let c):
            if let f = self.feature(for: c.sourceBodyId) {
                result.insert(f.id)
            }
        case .deleteBody(let d):
            if let f = self.feature(for: d.targetBodyId) {
                result.insert(f.id)
            }
        case .primitive, .part, .imported, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem:
            break
        }

        result.remove(feature.id)
        return result
    }

    /// Returns all features in the document that directly reference `targetFeatureId` (BL-FND-03).
    public func directDependentFeatures(referencing targetFeatureId: UUID) -> [Feature] {
        features.filter { feat in
            directDependencies(of: feat).contains(targetFeatureId)
        }
    }

    /// Returns all features in the document that directly or transitively reference `targetFeatureId` in topological (timeline) order (BL-FND-03).
    public func dependentFeatures(referencing targetFeatureId: UUID) -> [Feature] {
        guard let targetIndex = features.firstIndex(where: { $0.id == targetFeatureId }) else {
            return []
        }
        var dirtyIds: Set<UUID> = [targetFeatureId]
        var dependents: [Feature] = []

        for feature in features[(targetIndex + 1)...] {
            let deps = directDependencies(of: feature)
            if !deps.isDisjoint(with: dirtyIds) {
                dirtyIds.insert(feature.id)
                dependents.append(feature)
            }
        }
        return dependents
    }

    // MARK: - SceneObject Bridged Mutators

    public func paramValue(for id: ObjectId, key: String) -> Float? {
        guard let feature = features.first(where: { $0.outputSolidId == id }) else { return nil }
        switch feature.operation {
        case .primitive(.box(let p)):
            switch key {
            case "width": return p.width
            case "depth": return p.depth
            case "height": return p.height
            default: return nil
            }
        case .primitive(.cylinder(let p)):
            switch key {
            case "radius": return p.radius
            case "height": return p.height
            default: return nil
            }
        case .primitive(.sphere(let p)):
            switch key {
            case "radius": return p.radius
            default: return nil
            }
        case .primitive(.cone(let p)):
            switch key {
            case "bottomRadius": return p.bottomRadius
            case "topRadius": return p.topRadius
            case "height": return p.height
            default: return nil
            }
        case .primitive(.torus(let p)):
            switch key {
            case "majorRadius": return p.majorRadius
            case "minorRadius": return p.minorRadius
            default: return nil
            }
        case .primitive(.wedge(let p)):
            switch key {
            case "width": return p.width
            case "depth": return p.depth
            case "height": return p.height
            case "topWidth": return p.topWidth
            default: return nil
            }
        case .extrude(let data):
            switch key {
            case "distance": return Float(data.distance)
            default: return nil
            }
        case .revolve(let data):
            switch key {
            case "angle": return Float(data.angle)
            case "angle2": return Float(data.angle2)
            default: return nil
            }
        case .chamfer(let data):
            switch key {
            case "distance": return Float(data.distance)
            case "distance2": return Float(data.distance2)
            case "angle": return Float(data.angle)
            default: return nil
            }
        case .shell(let data):
            switch key {
            case "thickness": return Float(data.thickness)
            default: return nil
            }
        case .hole(let data):
            switch key {
            case "diameter": return Float(data.diameter)
            case "depth": return Float(data.depth)
            case "counterboreDiameter": return Float(data.counterboreDiameter)
            case "counterboreDepth": return Float(data.counterboreDepth)
            case "countersinkDiameter": return Float(data.countersinkDiameter)
            case "countersinkAngle": return Float(data.countersinkAngle)
            default: return nil
            }
        case .pattern(let data):
            switch key {
            case "count": return Float(data.count)
            case "linearSpacing": return Float(data.linearSpacing)
            case "totalAngle": return Float(data.totalAngle)
            default: return nil
            }
        case .mirror(let data):
            switch key {
            case "normalX": return Float(data.planeNormal.x)
            case "normalY": return Float(data.planeNormal.y)
            case "normalZ": return Float(data.planeNormal.z)
            case "keepOriginal": return data.keepOriginal ? 1.0 : 0.0
            default: return nil
            }
        case .imported, .boolean, .part, .sketch, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem, .combine, .moveBody, .copyBody, .deleteBody:
            return nil
        }
    }

    public func beginInteractiveParamEdit(id: ObjectId, key: String) {
        guard let feature = features.first(where: { $0.outputSolidId == id }) else { return }
        guard !feature.isLocked else { return }
        guard let currentVal = paramValue(for: id, key: key) else { return }
        activeInteractiveParamEdit = (id: id, key: key, initialValue: currentVal)
    }

    public func endInteractiveParamEdit(id: ObjectId, key: String) {
        guard let active = activeInteractiveParamEdit, active.id == id, active.key == key else {
            activeInteractiveParamEdit = nil
            return
        }
        activeInteractiveParamEdit = nil
        guard let finalVal = paramValue(for: id, key: key) else { return }
        let initialValue = active.initialValue
        guard finalVal != initialValue else { return }

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.setParam(id: id, key: key, value: initialValue)
                guard case .success = res else { return }
                target.undoManager?.setActionName("Change \(key.capitalized)")
                target.onUndoRedoMutation?(.paramChanged(id, key: key, value: initialValue))
            }
        }
        undoManager?.setActionName("Change \(key.capitalized)")
        undoStateVersion += 1
    }
    
    public func paramsFor(id: ObjectId) -> ObjectDef? {
        return objects.first(where: { $0.id == id })?.def
    }
    
    @discardableResult
    public func addObject(def: ObjectDef, transform: Transform = .identity, material: MaterialAttributes? = nil, actionName: String? = nil) -> ObjectId {
        addObject(reserveId(for: def), def: def, transform: transform, material: material, actionName: actionName)
    }
    
    /// Advances the sequence and returns an ID no object has used; the caller may never add it.
    public func reserveId(for def: ObjectDef) -> ObjectId {
        seq += 1
        return ObjectId("\(def.kind)-\(seq)")
    }
    
    /// Adds an object under an ID from `reserveId(for:)`, so a kernel call can use the ID before the object exists.
    @discardableResult
    public func addObject(_ id: ObjectId, def: ObjectDef, transform: Transform = .identity, material: MaterialAttributes? = nil, actionName: String? = nil) -> ObjectId {
        let clamped = DocumentLimits.clamp(def)
        let defaultName: String?
        if case .part(let url, _) = clamped, !url.lastPathComponent.isEmpty {
            defaultName = url.lastPathComponent
        } else if case .imported(let name, _, _, _, _, _) = clamped, !name.isEmpty {
            defaultName = name
        } else {
            defaultName = nil
        }
        let effectiveMaterial = material ?? settings.defaultMaterial
        let obj = SceneObject(id: id, name: defaultName, def: clamped, transform: transform, material: effectiveMaterial)
        let feature = Feature(from: obj)
        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = id

        let effectiveActionName = actionName ?? "Add \(clamped.kind.capitalized)"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.removeObject(id: id, actionName: effectiveActionName)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }
                target.undoManager?.setActionName(effectiveActionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return id
    }

    /// Adds a compound boolean object and updates operand visibilities in a single undo step.
    @discardableResult
    public func addBooleanObject(
        _ id: ObjectId,
        def: ObjectDef,
        keepTool: Bool? = nil,
        actionName: String? = nil
    ) -> ObjectId {
        let clamped = DocumentLimits.clamp(def)
        guard case .boolean(_, let solidA, let solidB) = clamped else {
            return addObject(id, def: clamped, actionName: actionName)
        }
        let feature = Feature(from: SceneObject(id: id, name: nil, def: clamped, transform: .identity, material: settings.defaultMaterial))
        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        let origVisA = features.first(where: { $0.outputSolidId == solidA })?.isVisible
        let origVisB = features.first(where: { $0.outputSolidId == solidB })?.isVisible

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = id

        if let keepTool {
            setVisibility(id: solidA, isVisible: false)
            setVisibility(id: solidB, isVisible: keepTool)
        }

        let effectiveActionName = actionName ?? "Add Boolean"
        registerBooleanUndo(
            id: id,
            feature: feature,
            solidA: solidA,
            solidB: solidB,
            origVisA: origVisA,
            origVisB: origVisB,
            keepTool: keepTool,
            previousRollback: previousRollback,
            insertIndex: insertIndex,
            actionName: effectiveActionName
        )
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return id
    }

    @discardableResult
    public func addBooleanObject(
        def: ObjectDef,
        keepTool: Bool? = nil,
        actionName: String? = nil
    ) -> ObjectId {
        addBooleanObject(reserveId(for: def), def: def, keepTool: keepTool, actionName: actionName)
    }

    private func registerBooleanUndo(
        id: ObjectId,
        feature: Feature,
        solidA: SolidId,
        solidB: SolidId,
        origVisA: Bool?,
        origVisB: Bool?,
        keepTool: Bool?,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                if keepTool != nil {
                    if let origVisA {
                        target.setVisibility(id: solidA, isVisible: origVisA)
                    }
                    if let origVisB {
                        target.setVisibility(id: solidB, isVisible: origVisB)
                    }
                }
                let res = target.removeFeature(id: feature.id, registerUndo: false)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }

                target.registerBooleanRedo(
                    id: id,
                    feature: feature,
                    solidA: solidA,
                    solidB: solidB,
                    origVisA: origVisA,
                    origVisB: origVisB,
                    keepTool: keepTool,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.removed(id))
            }
        }
    }

    private func registerBooleanRedo(
        id: ObjectId,
        feature: Feature,
        solidA: SolidId,
        solidB: SolidId,
        origVisA: Bool?,
        origVisB: Bool?,
        keepTool: Bool?,
        previousRollback: Int?,
        insertIndex: Int,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.insertFeature(feature, at: insertIndex, registerUndo: false)
                guard case .success = res else { return }
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + 1
                }
                if let keepTool {
                    target.setVisibility(id: solidA, isVisible: false)
                    target.setVisibility(id: solidB, isVisible: keepTool)
                }
                target.registerBooleanUndo(
                    id: id,
                    feature: feature,
                    solidA: solidA,
                    solidB: solidB,
                    origVisA: origVisA,
                    origVisB: origVisB,
                    keepTool: keepTool,
                    previousRollback: previousRollback,
                    insertIndex: insertIndex,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
    }

    /// Restores a previously removed object at its original index, preserving its identity.
    @discardableResult
    public func insertObject(_ obj: SceneObject, at index: Int, actionName: String? = nil) -> Result<Void, DocumentMutationError> {
        guard !features.contains(where: { $0.outputSolidId == obj.id }) else {
            return .failure(.objectLocked(obj.id))
        }
        let targetIndex = min(max(0, index), features.count)
        let previousRollback = rollbackIndex
        let feature = Feature(from: obj)
        features.insert(feature, at: targetIndex)
        if let curRollback = rollbackIndex {
            if targetIndex <= curRollback {
                let newIndex = curRollback + 1
                rollbackIndex = (newIndex >= features.count) ? nil : newIndex
            }
        }
        selectedId = obj.id

        let undoName = actionName ?? "Delete \(obj.name)"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.removeObject(id: obj.id)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }
                target.undoManager?.setActionName(undoName)
                target.onUndoRedoMutation?(.removed(obj.id))
            }
        }
        undoManager?.setActionName(undoName)
        undoStateVersion += 1
        return .success(())
    }

    /// Adds a scripted `.part.ts` or `.part.js` source file to the document under a fresh `part-<seq>` ID.
    @discardableResult
    public func addPart(url: URL, name: String? = nil, transform: Transform = .identity) -> ObjectId {
        let canonical = url.standardizedFileURL
        let def = ObjectDef.part(url: canonical, shape: nil)
        let id = reserveId(for: def)
        let displayName = name ?? (canonical.lastPathComponent.isEmpty ? id.rawValue : canonical.lastPathComponent)
        let feature = Feature(
            name: displayName,
            operation: .part(PartFeatureData(url: canonical, shape: nil)),
            outputSolidId: id,
            transform: transform,
            material: settings.defaultMaterial
        )
        let insertIndex = effectiveRollbackIndex
        let previousRollback = rollbackIndex

        features.insert(feature, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + 1
        }
        selectedId = id

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.removeObject(id: id)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }
                target.undoManager?.setActionName("Add Part")
                target.onUndoRedoMutation?(.removed(id))
            }
        }
        undoManager?.setActionName("Add Part")
        undoStateVersion += 1
        return id
    }

    /// Records the latest successfully evaluated `ShapeNode` for a scripted part object (#427).
    public func setPartShape(id: ObjectId, shape: ShapeNode) {
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        if case .part(var partData) = features[index].operation {
            partData.shape = shape
            features[index].operation = .part(partData)
        }
    }

    // MARK: - DSL Feature Import (BL-SCR-04 / #332)

    /// Imports an evaluated shape AST tree into the document as canonical, ordered features.
    @discardableResult
    public func importFeatures(from shape: ShapeNode, baseName: String? = nil) throws -> [Feature] {
        let result = try DSLFeatureDecomposer.decompose(shape, baseName: baseName, startingSequence: seq)
        seq = max(seq, result.maxSequence)

        let previousRollback = rollbackIndex
        let insertIndex = effectiveRollbackIndex

        features.insert(contentsOf: result.features, at: insertIndex)
        if previousRollback != nil {
            rollbackIndex = insertIndex + result.features.count
        }
        if let rootSolidId = result.rootSolidId {
            selectedId = rootSolidId
        }

        let importedFeatures = result.features
        let rootSolidId = result.rootSolidId
        registerImportFeaturesUndo(
            features: importedFeatures,
            rootSolidId: rootSolidId,
            insertIndex: insertIndex,
            previousRollback: previousRollback,
            actionName: "Import DSL Features"
        )
        undoManager?.setActionName("Import DSL Features")
        undoStateVersion += 1
        return result.features
    }

    /// Imports features from an evaluated part script evaluation.
    @discardableResult
    public func importFeatures(from evaluation: PartScriptEvaluation, baseName: String? = nil) throws -> [Feature] {
        try importFeatures(from: evaluation.shape, baseName: baseName)
    }

    private func registerImportFeaturesUndo(
        features importedFeatures: [Feature],
        rootSolidId: SolidId?,
        insertIndex: Int,
        previousRollback: Int?,
        actionName: String
    ) {
        let importedIds = importedFeatures.map(\.id)
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                for id in importedIds.reversed() {
                    _ = target.removeFeature(id: id, registerUndo: false)
                }
                target.rollbackIndex = previousRollback
                target.registerImportFeaturesRedo(
                    features: importedFeatures,
                    rootSolidId: rootSolidId,
                    insertIndex: insertIndex,
                    previousRollback: previousRollback,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let rootSolidId {
                    target.onUndoRedoMutation?(.removed(rootSolidId))
                }
            }
        }
    }

    private func registerImportFeaturesRedo(
        features importedFeatures: [Feature],
        rootSolidId: SolidId?,
        insertIndex: Int,
        previousRollback: Int?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.features.insert(contentsOf: importedFeatures, at: insertIndex)
                if previousRollback != nil {
                    target.rollbackIndex = insertIndex + importedFeatures.count
                }
                if let rootSolidId {
                    target.selectedId = rootSolidId
                }
                target.registerImportFeaturesUndo(
                    features: importedFeatures,
                    rootSolidId: rootSolidId,
                    insertIndex: insertIndex,
                    previousRollback: previousRollback,
                    actionName: actionName
                )
                target.undoManager?.setActionName(actionName)
                if let rootSolidId {
                    target.onUndoRedoMutation?(.added(rootSolidId))
                }
            }
        }
    }


    @discardableResult
    public func removeObject(id: ObjectId, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            return removeComponentInstance(id: componentInstances[compIndex].id, actionName: actionName, registerUndo: registerUndo)
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else {
            return .failure(.objectNotFound(id))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(id))
        }
        let removedFeature = features[index]
        let removedIndex = index
        let previousRollback = rollbackIndex

        features.remove(at: index)

        if let curRollback = rollbackIndex {
            if removedIndex < curRollback {
                let decremented = max(0, curRollback - 1)
                rollbackIndex = (decremented >= features.count) ? nil : decremented
            } else {
                if curRollback >= features.count {
                    rollbackIndex = nil
                }
            }
        }

        if selectedId == id {
            selectedId = nil
        }
        pruneInvalidSelection()

        let kind = removedFeature.toSceneObject()?.def.kind.capitalized ?? "Solid"
        let redoName = actionName ?? (undoManager?.isUndoing == true ? "Add \(kind)" : "Delete \(removedFeature.name)")
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.insertFeature(removedFeature, at: removedIndex, actionName: redoName, registerUndo: true)
                    target.rollbackIndex = previousRollback
                    target.undoManager?.setActionName(redoName)
                    target.onUndoRedoMutation?(.added(id))
                }
            }
            undoManager?.setActionName(redoName)
            undoStateVersion += 1
        }
        return .success(())
    }
    
    // MARK: - Document Parameters (BL-PAR-01, BL-PAR-02)

    public func parameter(named name: String) -> DocumentParameter? {
        parameters.first { $0.name == name }
    }

    public func parameter(id: UUID) -> DocumentParameter? {
        parameters.first { $0.id == id }
    }

    public func evaluateExpression(_ expr: String) throws -> ExpressionEvaluationResult {
        let context = EvaluationContext(documentParameters: parameters, unitSettings: settings.unitSettings)
        return try ExpressionEvaluator.evaluate(expr, context: context)
    }

    public func rebuildParameterGraph() {
        parameterGraph = ParameterDependencyGraph()
        for param in parameters {
            if let expr = param.expression, !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try? parameterGraph.updateDependencies(for: param.name, expression: expr)
            }
        }
    }

    public func referencingFeatures(for parameterName: String) -> [(feature: Feature, key: String)] {
        var results: [(feature: Feature, key: String)] = []
        for feature in features {
            for (key, expr) in feature.inputExpressions {
                if expr.formula == parameterName {
                    results.append((feature, key))
                } else if let refs = try? ExpressionEvaluator.extractReferencedParameters(from: expr.formula),
                          refs.contains(parameterName) {
                    results.append((feature, key))
                }
            }
        }
        return results
    }

    public func addParameter(
        _ parameter: DocumentParameter,
        at index: Int? = nil,
        registerUndo: Bool = true
    ) throws {
        try DocumentParameter.validateName(parameter.name, existingNames: parameters.map(\.name))
        try DocumentParameter.validateRange(min: parameter.min, max: parameter.max)

        var paramToInsert = parameter
        if let expr = parameter.expression, !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let refs = try ExpressionEvaluator.extractReferencedParameters(from: expr)
            if let cycle = parameterGraph.detectCycle(for: parameter.name, referencing: refs) {
                throw DocumentParameterError.referenceCycle(cycle)
            }
            let existingNames = Set(parameters.map(\.name))
            if refs.isSubset(of: existingNames) {
                let evalResult = try evaluateExpression(expr)
                paramToInsert.value = evalResult.value
                if paramToInsert.unit.isEmpty, let unit = evalResult.unit {
                    paramToInsert.unit = unit
                }
            }
        }

        guard !paramToInsert.value.isNaN && !paramToInsert.value.isInfinite else {
            throw DocumentParameterError.emptyValue
        }
        if let min = parameter.min, paramToInsert.value < min {
            throw DocumentParameterError.valueOutOfRange(value: paramToInsert.value, min: parameter.min, max: parameter.max)
        }
        if let max = parameter.max, paramToInsert.value > max {
            throw DocumentParameterError.valueOutOfRange(value: paramToInsert.value, min: parameter.min, max: parameter.max)
        }
        let insertIndex = min(max(0, index ?? parameters.count), parameters.count)
        parameters.insert(paramToInsert, at: insertIndex)

        if let expr = paramToInsert.expression, !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? parameterGraph.updateDependencies(for: paramToInsert.name, expression: expr)
        }

        _ = try? reevaluateDependents(of: paramToInsert.name)

        if registerUndo {
            let paramId = paramToInsert.id
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = try? target.deleteParameter(id: paramId, registerUndo: true, allowReferencedOnUndo: true)
                }
            }
            undoManager?.setActionName("Add Parameter")
            undoStateVersion += 1
        }
    }

    public func deleteParameter(
        id: UUID,
        registerUndo: Bool = true,
        allowReferencedOnUndo: Bool = false
    ) throws {
        guard let index = parameters.firstIndex(where: { $0.id == id }) else {
            throw DocumentParameterError.parameterNotFound(id.uuidString)
        }
        let param = parameters[index]
        if !allowReferencedOnUndo {
            let referencing = referencingFeatures(for: param.name)
            if !referencing.isEmpty {
                let referencingNames = referencing.map(\.feature.name).reduce(into: [String]()) { names, name in
                    if !names.contains(name) { names.append(name) }
                }
                throw DocumentParameterError.parameterInUse(name: param.name, referencingFeatures: referencingNames)
            }
        }

        parameters.remove(at: index)
        parameterGraph.removeParameter(param.name)

        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = try? target.addParameter(param, at: index, registerUndo: true)
                }
            }
            undoManager?.setActionName("Delete Parameter")
            undoStateVersion += 1
        }
    }

    public func renameParameter(
        id: UUID,
        newName: String,
        registerUndo: Bool = true
    ) throws {
        guard let index = parameters.firstIndex(where: { $0.id == id }) else {
            throw DocumentParameterError.parameterNotFound(id.uuidString)
        }
        let oldName = parameters[index].name
        if oldName == newName {
            return
        }
        try DocumentParameter.validateName(
            newName,
            existingNames: parameters.map(\.name),
            ignoringName: oldName
        )

        parameters[index].name = newName
        parameterGraph.renameParameter(from: oldName, to: newName)

        for i in 0..<parameters.count {
            if let expr = parameters[i].expression, !expr.isEmpty {
                let renamed = ExpressionEvaluator.renameIdentifier(in: expr, from: oldName, to: newName)
                if renamed != expr {
                    parameters[i].expression = renamed
                }
            }
        }

        for i in 0..<features.count {
            var feature = features[i]
            var updated = false
            for (key, expr) in feature.inputExpressions {
                if expr.formula == oldName {
                    feature.inputExpressions[key] = FeatureExpression(formula: newName, value: expr.value)
                    updated = true
                } else if let refs = try? ExpressionEvaluator.extractReferencedParameters(from: expr.formula),
                          refs.contains(oldName) {
                    let renamedFormula = ExpressionEvaluator.renameIdentifier(in: expr.formula, from: oldName, to: newName)
                    feature.inputExpressions[key] = FeatureExpression(formula: renamedFormula, value: expr.value)
                    updated = true
                }
            }
            if updated {
                features[i] = feature
            }
        }

        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = try? target.renameParameter(id: id, newName: oldName, registerUndo: true)
                }
            }
            undoManager?.setActionName("Rename Parameter")
            undoStateVersion += 1
        }
    }

    @discardableResult
    public func updateParameter(
        id: UUID,
        value: Double? = nil,
        unit: String? = nil,
        comment: String? = nil,
        expression: String?? = nil,
        min: Double?? = nil,
        max: Double?? = nil,
        step: Double?? = nil,
        registerUndo: Bool = true
    ) throws -> [ObjectId] {
        guard let index = parameters.firstIndex(where: { $0.id == id }) else {
            throw DocumentParameterError.parameterNotFound(id.uuidString)
        }
        let oldParam = parameters[index]

        let targetMin: Double? = (min != nil) ? min! : oldParam.min
        let targetMax: Double? = (max != nil) ? max! : oldParam.max
        let targetStep: Double? = (step != nil) ? step! : oldParam.step

        try DocumentParameter.validateRange(min: targetMin, max: targetMax)

        var targetValue = value ?? oldParam.value
        var targetUnit = unit ?? oldParam.unit
        let targetComment = comment ?? oldParam.comment
        let targetExpression = (expression != nil) ? expression! : oldParam.expression

        if let expr = targetExpression, !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let refs = try ExpressionEvaluator.extractReferencedParameters(from: expr)
            if let cycle = parameterGraph.detectCycle(for: oldParam.name, referencing: refs) {
                throw DocumentParameterError.referenceCycle(cycle)
            }
            if value == nil {
                let evalResult = try evaluateExpression(expr)
                targetValue = evalResult.value
                if unit == nil, let u = evalResult.unit {
                    targetUnit = u
                }
            }
        }

        guard !targetValue.isNaN && !targetValue.isInfinite else {
            throw DocumentParameterError.emptyValue
        }

        if value != nil || expression != nil {
            if let tMin = targetMin, targetValue < tMin {
                throw DocumentParameterError.valueOutOfRange(value: targetValue, min: targetMin, max: targetMax)
            }
            if let tMax = targetMax, targetValue > tMax {
                throw DocumentParameterError.valueOutOfRange(value: targetValue, min: targetMin, max: targetMax)
            }
        }

        let newParam = DocumentParameter(
            id: id,
            name: oldParam.name,
            value: targetValue,
            unit: targetUnit,
            comment: targetComment,
            expression: targetExpression,
            min: targetMin,
            max: targetMax,
            step: targetStep
        )
        parameters[index] = newParam

        if let expr = targetExpression, !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? parameterGraph.updateDependencies(for: oldParam.name, expression: expr)
        } else {
            try? parameterGraph.updateDependencies(for: oldParam.name, expression: nil)
        }

        let valueChanged = (targetValue != oldParam.value)
        var affectedSolidIds: [ObjectId] = []

        if valueChanged {
            let oldFeatures = features
            let referencing = referencingFeatures(for: oldParam.name)
            let newMagnitude = Float(newParam.value)

            for ref in referencing {
                guard let fIdx = features.firstIndex(where: { $0.id == ref.feature.id }) else { continue }
                var feature = features[fIdx]
                guard let fExpr = feature.inputExpressions[ref.key] else { continue }

                let effectiveVal: Float
                if fExpr.formula == oldParam.name {
                    effectiveVal = newMagnitude
                } else if let fEval = try? evaluateExpression(fExpr.formula) {
                    effectiveVal = Float(fEval.value)
                } else {
                    effectiveVal = newMagnitude
                }

                let clampedValue = applyParamValue(to: &feature, key: ref.key, value: effectiveVal)
                feature.inputExpressions[ref.key] = FeatureExpression(formula: fExpr.formula, value: Double(clampedValue))
                features[fIdx] = feature
                if let solidId = feature.outputSolidId, !affectedSolidIds.contains(solidId) {
                    affectedSolidIds.append(solidId)
                }
            }

            let dependentAffected = (try? reevaluateDependents(of: oldParam.name)) ?? []
            for dSolid in dependentAffected {
                if !affectedSolidIds.contains(dSolid) {
                    affectedSolidIds.append(dSolid)
                }
            }

            syncObjectsFromFeatures()

            if registerUndo {
                let capturedNewParam = newParam
                let capturedNewFeatures = features
                let capturedAffected = affectedSolidIds
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        target.restoreParameter(
                            previousParam: oldParam,
                            previousFeatures: oldFeatures,
                            redoParam: capturedNewParam,
                            redoFeatures: capturedNewFeatures,
                            affectedSolidIds: capturedAffected
                        )
                    }
                }
                undoManager?.setActionName("Update Parameter")
                undoStateVersion += 1
            }
        } else if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = try? target.updateParameter(
                        id: id,
                        value: oldParam.value,
                        unit: oldParam.unit,
                        comment: oldParam.comment,
                        expression: .some(oldParam.expression),
                        min: .some(oldParam.min),
                        max: .some(oldParam.max),
                        step: .some(oldParam.step),
                        registerUndo: true
                    )
                }
            }
            undoManager?.setActionName("Update Parameter")
            undoStateVersion += 1
        }

        return affectedSolidIds
    }

    @discardableResult
    public func reevaluateDependents(of parameterName: String) throws -> [ObjectId] {
        let downstream = parameterGraph.topologicalDependents(of: parameterName)
        var affectedSolidIds: [ObjectId] = []
        for depName in downstream {
            guard let idx = parameters.firstIndex(where: { $0.name == depName }),
                  let expr = parameters[idx].expression,
                  !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let evalResult = try evaluateExpression(expr)
            parameters[idx].value = evalResult.value
            if parameters[idx].unit.isEmpty, let u = evalResult.unit {
                parameters[idx].unit = u
            }
            let referencing = referencingFeatures(for: depName)
            for ref in referencing {
                guard let fIdx = features.firstIndex(where: { $0.id == ref.feature.id }) else { continue }
                var feature = features[fIdx]
                guard let fExpr = feature.inputExpressions[ref.key] else { continue }
                let newMag: Float
                if fExpr.formula == depName {
                    newMag = Float(evalResult.value)
                } else if let fEval = try? evaluateExpression(fExpr.formula) {
                    newMag = Float(fEval.value)
                } else {
                    newMag = Float(evalResult.value)
                }
                let clamped = applyParamValue(to: &feature, key: ref.key, value: newMag)
                feature.inputExpressions[ref.key] = FeatureExpression(formula: fExpr.formula, value: Double(clamped))
                features[fIdx] = feature
                if let solidId = feature.outputSolidId, !affectedSolidIds.contains(solidId) {
                    affectedSolidIds.append(solidId)
                }
            }
        }
        return affectedSolidIds
    }

    private func restoreParameter(
        previousParam: DocumentParameter,
        previousFeatures: [Feature],
        redoParam: DocumentParameter,
        redoFeatures: [Feature],
        affectedSolidIds: [ObjectId]
    ) {
        guard let index = parameters.firstIndex(where: { $0.id == previousParam.id }) else { return }
        parameters[index] = previousParam
        rebuildParameterGraph()
        features = previousFeatures
        syncObjectsFromFeatures()

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreParameter(
                    previousParam: redoParam,
                    previousFeatures: redoFeatures,
                    redoParam: previousParam,
                    redoFeatures: previousFeatures,
                    affectedSolidIds: affectedSolidIds
                )
            }
        }
        undoManager?.setActionName("Update Parameter")
        undoStateVersion += 1

        for solidId in affectedSolidIds {
            onUndoRedoMutation?(.paramChanged(solidId, key: "", value: Float(previousParam.value)))
        }
    }

    @discardableResult
    private func applyParamValue(to feature: inout Feature, key: String, value: Float) -> Float {
        let clampedValue: Float
        switch feature.operation {
        case .primitive(.box(var params)):
            switch key {
            case "width": params.width = DocumentLimits.clampBox(key: "width", value: value)
            case "depth": params.depth = DocumentLimits.clampBox(key: "depth", value: value)
            case "height": params.height = DocumentLimits.clampBox(key: "height", value: value)
            default: break
            }
            clampedValue = (key == "width" ? params.width : (key == "depth" ? params.depth : params.height))
            feature.operation = .primitive(.box(params))

        case .primitive(.cylinder(var params)):
            switch key {
            case "radius": params.radius = DocumentLimits.clampCylinder(key: "radius", value: value)
            case "height": params.height = DocumentLimits.clampCylinder(key: "height", value: value)
            default: break
            }
            clampedValue = (key == "radius" ? params.radius : params.height)
            feature.operation = .primitive(.cylinder(params))

        case .primitive(.sphere(var params)):
            switch key {
            case "radius": params.radius = DocumentLimits.clampSphere(key: "radius", value: value)
            default: break
            }
            clampedValue = params.radius
            feature.operation = .primitive(.sphere(params))

        case .primitive(.cone(var params)):
            switch key {
            case "bottomRadius": params.bottomRadius = DocumentLimits.clampCone(key: "bottomRadius", value: value)
            case "topRadius": params.topRadius = DocumentLimits.clampCone(key: "topRadius", value: value)
            case "height": params.height = DocumentLimits.clampCone(key: "height", value: value)
            default: break
            }
            clampedValue = (key == "bottomRadius" ? params.bottomRadius : (key == "topRadius" ? params.topRadius : params.height))
            feature.operation = .primitive(.cone(params))

        case .primitive(.torus(var params)):
            switch key {
            case "majorRadius": params.majorRadius = DocumentLimits.clampTorus(key: "majorRadius", value: value, minorRadius: params.minorRadius)
            case "minorRadius": params.minorRadius = DocumentLimits.clampTorus(key: "minorRadius", value: value, majorRadius: params.majorRadius)
            default: break
            }
            clampedValue = (key == "majorRadius" ? params.majorRadius : params.minorRadius)
            feature.operation = .primitive(.torus(params))

        case .primitive(.wedge(var params)):
            switch key {
            case "width":
                params.width = DocumentLimits.clampWedge(key: "width", value: value)
                if params.topWidth > params.width { params.topWidth = params.width }
            case "depth": params.depth = DocumentLimits.clampWedge(key: "depth", value: value)
            case "height": params.height = DocumentLimits.clampWedge(key: "height", value: value)
            case "topWidth": params.topWidth = DocumentLimits.clampWedge(key: "topWidth", value: value, width: params.width)
            default: break
            }
            clampedValue = (key == "width" ? params.width : (key == "depth" ? params.depth : (key == "height" ? params.height : params.topWidth)))
            feature.operation = .primitive(.wedge(params))

        case .extrude(var data):
            switch key {
            case "distance":
                data.distance = Double(DocumentLimits.clampExtrude(key: "distance", value: value))
            default: break
            }
            clampedValue = Float(data.distance)
            feature.operation = .extrude(data)

        case .revolve(var data):
            switch key {
            case "angle":
                data.angle = Double(DocumentLimits.clampRevolve(key: "angle", value: value))
                clampedValue = Float(data.angle)
            case "angle2":
                data.angle2 = Double(DocumentLimits.clampRevolve(key: "angle2", value: value))
                clampedValue = Float(data.angle2)
            default:
                clampedValue = value
            }
            feature.operation = .revolve(data)

        case .chamfer(var data):
            switch key {
            case "distance":
                data.distance = Double(DocumentLimits.clampChamfer(key: "distance", value: value))
                clampedValue = Float(data.distance)
            case "distance2":
                data.distance2 = Double(DocumentLimits.clampChamfer(key: "distance2", value: value))
                clampedValue = Float(data.distance2)
            case "angle":
                data.angle = Double(DocumentLimits.clampChamfer(key: "angle", value: value))
                clampedValue = Float(data.angle)
            default:
                clampedValue = value
            }
            feature.operation = .chamfer(data)

        case .shell(var data):
            switch key {
            case "thickness":
                data.thickness = Double(DocumentLimits.clampShell(key: "thickness", value: value))
                clampedValue = Float(data.thickness)
            default:
                clampedValue = value
            }
            feature.operation = .shell(data)

        case .hole(var data):
            switch key {
            case "diameter":
                data.diameter = Double(DocumentLimits.clampHole(key: "diameter", value: value))
                clampedValue = Float(data.diameter)
            case "depth":
                data.depth = Double(DocumentLimits.clampHole(key: "depth", value: value))
                clampedValue = Float(data.depth)
            case "counterboreDiameter":
                data.counterboreDiameter = Double(DocumentLimits.clampHole(key: "counterboreDiameter", value: value))
                clampedValue = Float(data.counterboreDiameter)
            case "counterboreDepth":
                data.counterboreDepth = Double(DocumentLimits.clampHole(key: "counterboreDepth", value: value))
                clampedValue = Float(data.counterboreDepth)
            case "countersinkDiameter":
                data.countersinkDiameter = Double(DocumentLimits.clampHole(key: "countersinkDiameter", value: value))
                clampedValue = Float(data.countersinkDiameter)
            case "countersinkAngle":
                data.countersinkAngle = Double(DocumentLimits.clampHole(key: "countersinkAngle", value: value))
                clampedValue = Float(data.countersinkAngle)
            default:
                clampedValue = value
            }
            feature.operation = .hole(data)

        case .pattern(var data):
            switch key {
            case "count":
                data.count = Int(DocumentLimits.clampPattern(key: "count", value: value))
                clampedValue = Float(data.count)
            case "linearSpacing":
                data.linearSpacing = Double(DocumentLimits.clampPattern(key: "linearSpacing", value: value))
                clampedValue = Float(data.linearSpacing)
            case "totalAngle":
                data.totalAngle = Double(DocumentLimits.clampPattern(key: "totalAngle", value: value))
                clampedValue = Float(data.totalAngle)
            default:
                clampedValue = value
            }
            feature.operation = .pattern(data)

        case .mirror(var data):
            switch key {
            case "normalX":
                data.planeNormal.x = Double(value)
                clampedValue = value
            case "normalY":
                data.planeNormal.y = Double(value)
                clampedValue = value
            case "normalZ":
                data.planeNormal.z = Double(value)
                clampedValue = value
            case "keepOriginal":
                data.keepOriginal = value > 0.5
                clampedValue = data.keepOriginal ? 1.0 : 0.0
            default:
                clampedValue = value
            }
            feature.operation = .mirror(data)

        case .imported, .boolean, .part, .sketch, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem, .combine, .moveBody, .copyBody, .deleteBody:
            clampedValue = value
        }
        return clampedValue
    }

    @discardableResult
    public func setParam(
        id: ObjectId,
        key: String,
        value: Float,
        expression: String? = nil,
        actionName: String? = nil
    ) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else {
            return .failure(.objectNotFound(id))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(id))
        }
        guard let oldValue = paramValue(for: id, key: key) else {
            return .success(())
        }
        var updatedFeature = features[index]
        let clampedValue = applyParamValue(to: &updatedFeature, key: key, value: value)
        if let expression {
            updatedFeature.inputExpressions[key] = FeatureExpression(formula: expression, value: Double(clampedValue))
        } else {
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)
        }

        let oldExpr = features[index].inputExpressions[key]
        if clampedValue == oldValue && updatedFeature.inputExpressions[key] == oldExpr {
            return .success(())
        }

        if let active = activeInteractiveParamEdit, active.id == id, active.key == key {
            features[index] = updatedFeature
            return .success(())
        }

        let effectiveActionName = actionName ?? "Change \(key.capitalized)"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.setParam(id: id, key: key, value: oldValue, expression: oldExpr?.formula, actionName: effectiveActionName)
                guard case .success = res else { return }
                target.undoManager?.setActionName(effectiveActionName)
                target.onUndoRedoMutation?(.paramChanged(id, key: key, value: oldValue))
            }
        }
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        features[index] = updatedFeature
        return .success(())
    }
    
    @discardableResult
    public func setTransform(id: ObjectId, transform: Transform, actionName: String? = nil) -> Result<Void, DocumentMutationError> {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            guard !componentInstances[compIndex].isLocked else {
                return .failure(.objectLocked(id))
            }
            let oldTransform = componentInstances[compIndex].transform
            guard oldTransform != transform else {
                return .success(())
            }
            componentInstances[compIndex].transform = transform
            syncObjectsFromFeatures()

            let effectiveActionName = actionName ?? "Move Component"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    let res = target.setTransform(id: id, transform: oldTransform, actionName: effectiveActionName)
                    guard case .success = res else { return }
                    target.undoManager?.setActionName(effectiveActionName)
                    target.onUndoRedoMutation?(.transformChanged(id, transform: oldTransform))
                }
            }
            undoManager?.setActionName(effectiveActionName)
            undoStateVersion += 1
            return .success(())
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else {
            return .failure(.objectNotFound(id))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(id))
        }
        let oldTransform = features[index].transform
        guard oldTransform != transform else {
            return .success(())
        }
        features[index].transform = transform

        let effectiveActionName = actionName ?? "Move Solid"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.setTransform(id: id, transform: oldTransform, actionName: effectiveActionName)
                guard case .success = res else { return }
                target.undoManager?.setActionName(effectiveActionName)
                target.onUndoRedoMutation?(.transformChanged(id, transform: oldTransform))
            }
        }
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
        return .success(())
    }
    
    public func setName(id: ObjectId, name: String) {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            guard !componentInstances[compIndex].isLocked else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard componentInstances[compIndex].name != trimmed else { return }
            componentInstances[compIndex].name = trimmed
            syncObjectsFromFeatures()
            return
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        guard !features[index].isLocked else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard features[index].name != trimmed else { return }
        features[index].name = trimmed
    }
    
    public func setVisibility(id: ObjectId, isVisible: Bool) {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            componentInstances[compIndex].isVisible = isVisible
            syncObjectsFromFeatures()
            return
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        features[index].isVisible = isVisible
    }
    
    public func setLocked(id: ObjectId, isLocked: Bool) {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            componentInstances[compIndex].isLocked = isLocked
            syncObjectsFromFeatures()
            return
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        features[index].isLocked = isLocked
    }
    
    @discardableResult
    public func setMaterial(id: ObjectId, material: MaterialAttributes) -> Result<Void, DocumentMutationError> {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            guard !componentInstances[compIndex].isLocked else {
                return .failure(.objectLocked(id))
            }
            componentInstances[compIndex].material = material
            syncObjectsFromFeatures()
            return .success(())
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else {
            return .failure(.objectNotFound(id))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(id))
        }
        features[index].material = material
        return .success(())
    }

    // MARK: - Body Mutators (BL-FND-12)

    public func setBodyVisibility(id: BodyId, isVisible: Bool) {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            let oldVisible = componentInstances[compIndex].isVisible
            guard oldVisible != isVisible else { return }
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setBodyVisibility(id: id, isVisible: oldVisible)
                    target.undoManager?.setActionName(oldVisible ? "Show Component" : "Hide Component")
                }
            }
            undoManager?.setActionName(isVisible ? "Show Component" : "Hide Component")
            undoStateVersion += 1
            setVisibility(id: id, isVisible: isVisible)
            return
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        let oldVisible = features[index].isVisible
        guard oldVisible != isVisible else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setBodyVisibility(id: id, isVisible: oldVisible)
                target.undoManager?.setActionName(oldVisible ? "Show Body" : "Hide Body")
            }
        }
        undoManager?.setActionName(isVisible ? "Show Body" : "Hide Body")
        undoStateVersion += 1
        setVisibility(id: id, isVisible: isVisible)
    }

    public func setBodyName(id: BodyId, name: String) {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            guard !componentInstances[compIndex].isLocked else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let oldName = componentInstances[compIndex].name
            guard oldName != trimmed else { return }
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setBodyName(id: id, name: oldName)
                    target.undoManager?.setActionName("Rename Component")
                }
            }
            undoManager?.setActionName("Rename Component")
            undoStateVersion += 1
            setName(id: id, name: trimmed)
            return
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        guard !features[index].isLocked else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let oldName = features[index].name
        guard oldName != trimmed else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setBodyName(id: id, name: oldName)
                target.undoManager?.setActionName("Rename Body")
            }
        }
        undoManager?.setActionName("Rename Body")
        undoStateVersion += 1
        setName(id: id, name: trimmed)
    }

    @discardableResult
    public func setBodyMaterial(id: BodyId, material: MaterialAttributes) -> Result<Void, DocumentMutationError> {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            guard !componentInstances[compIndex].isLocked else {
                return .failure(.objectLocked(id))
            }
            let oldMaterial = componentInstances[compIndex].material
            guard oldMaterial != material else {
                return .success(())
            }
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.setBodyMaterial(id: id, material: oldMaterial)
                    target.undoManager?.setActionName("Change Component Material")
                }
            }
            undoManager?.setActionName("Change Component Material")
            undoStateVersion += 1
            return setMaterial(id: id, material: material)
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else {
            return .failure(.objectNotFound(id))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(id))
        }
        let oldMaterial = features[index].material
        guard oldMaterial != material else {
            return .success(())
        }
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.setBodyMaterial(id: id, material: oldMaterial)
                target.undoManager?.setActionName("Change Body Material")
            }
        }
        undoManager?.setActionName("Change Body Material")
        undoStateVersion += 1
        return setMaterial(id: id, material: material)
    }

    @discardableResult
    public func setBodyColor(id: BodyId, color: SIMD4<Float>) -> Result<Void, DocumentMutationError> {
        guard let currentBody = body(for: id) else {
            return .failure(.objectNotFound(id))
        }
        guard !currentBody.isLocked else {
            return .failure(.objectLocked(id))
        }
        var newMaterial = currentBody.material
        newMaterial.color = color
        return setBodyMaterial(id: id, material: newMaterial)
    }

    public func setBodyLocked(id: BodyId, isLocked: Bool) {
        if let compIndex = componentInstances.firstIndex(where: { $0.solidId == id }) {
            let oldLocked = componentInstances[compIndex].isLocked
            guard oldLocked != isLocked else { return }
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setBodyLocked(id: id, isLocked: oldLocked)
                    target.undoManager?.setActionName(oldLocked ? "Lock Component" : "Unlock Component")
                }
            }
            undoManager?.setActionName(isLocked ? "Lock Component" : "Unlock Component")
            undoStateVersion += 1
            setLocked(id: id, isLocked: isLocked)
            return
        }
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        let oldLocked = features[index].isLocked
        guard oldLocked != isLocked else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.setBodyLocked(id: id, isLocked: oldLocked)
                target.undoManager?.setActionName(oldLocked ? "Lock Body" : "Unlock Body")
            }
        }
        undoManager?.setActionName(isLocked ? "Lock Body" : "Unlock Body")
        undoStateVersion += 1
        setLocked(id: id, isLocked: isLocked)
    }

    // MARK: - Assembly Component Mutations (BL-ASM-01)

    @discardableResult
    public func addComponentInstance(_ instance: ComponentInstance, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        componentInstances.append(instance)
        syncObjectsFromFeatures()
        if registerUndo {
            let effectiveActionName = actionName ?? "Add Component"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeComponentInstance(id: instance.id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                    target.onUndoRedoMutation?(.removed(instance.solidId))
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func removeComponentInstance(id: UUID, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        if let index = componentInstances.firstIndex(where: { $0.id == id }) {
            let instance = componentInstances[index]
            let oldExplodedViews = explodedViews
            pruneComponentFromExplodedViews(id: id)
            componentInstances.remove(at: index)
            if selectedId == instance.solidId {
                selectedId = nil
            }
            pruneInvalidSelection()
            syncObjectsFromFeatures()
            if registerUndo {
                let effectiveActionName = actionName ?? "Remove Component"
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        _ = target.addComponentInstance(instance, actionName: effectiveActionName, registerUndo: true)
                        target.explodedViews = oldExplodedViews
                        target.syncObjectsFromFeatures()
                        target.undoManager?.setActionName(effectiveActionName)
                        target.onUndoRedoMutation?(.removed(instance.solidId))
                    }
                }
                undoManager?.setActionName(effectiveActionName)
            }
            undoStateVersion += 1
            return .success(())
        }

        // Check if inside a subassembly
        for subIdx in 0..<componentInstances.count {
            if let childIdx = componentInstances[subIdx].childInstances.firstIndex(where: { $0.id == id }) {
                let child = componentInstances[subIdx].childInstances[childIdx]
                let oldExplodedViews = explodedViews
                pruneComponentFromExplodedViews(id: id)
                componentInstances[subIdx].childInstances.remove(at: childIdx)
                if selectedId == child.solidId {
                    selectedId = nil
                }
                pruneInvalidSelection()
                syncObjectsFromFeatures()
                if registerUndo {
                    let effectiveActionName = actionName ?? "Remove Component"
                    undoManager?.registerUndo(withTarget: self) { target in
                        MainActor.assumeIsolated {
                            if let sIdx = target.componentInstances.firstIndex(where: { $0.id == target.componentInstances[subIdx].id }) {
                                target.componentInstances[sIdx].childInstances.insert(child, at: childIdx)
                                target.explodedViews = oldExplodedViews
                                target.syncObjectsFromFeatures()
                                target.undoStateVersion += 1
                                target.undoManager?.setActionName(effectiveActionName)
                            }
                        }
                    }
                    undoManager?.setActionName(effectiveActionName)
                }
                undoStateVersion += 1
                return .success(())
            }
        }

        return .failure(.objectNotFound(SolidId("component-\(id.uuidString)")))
    }

    @discardableResult
    public func updateComponentInstanceTransform(id: UUID, transform: Transform, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        if let index = componentInstances.firstIndex(where: { $0.id == id }) {
            guard !componentInstances[index].isLocked else {
                return .failure(.objectLocked(componentInstances[index].solidId))
            }
            guard !componentInstances[index].isGrounded else {
                return .failure(.invalidOperation("Component '\(componentInstances[index].name)' is grounded and cannot be moved"))
            }
            let oldTransform = componentInstances[index].transform
            guard oldTransform != transform else {
                return .success(())
            }
            componentInstances[index].transform = transform
            syncObjectsFromFeatures()
            if registerUndo {
                let effectiveActionName = actionName ?? "Move Component"
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        _ = target.updateComponentInstanceTransform(id: id, transform: oldTransform, actionName: effectiveActionName, registerUndo: true)
                        target.undoManager?.setActionName(effectiveActionName)
                        target.onUndoRedoMutation?(.transformChanged(SolidId("component-\(id.uuidString)"), transform: oldTransform))
                    }
                }
                undoManager?.setActionName(effectiveActionName)
            }
            undoStateVersion += 1
            return .success(())
        }

        // Child in subassembly
        for subIdx in 0..<componentInstances.count {
            if let childIdx = componentInstances[subIdx].childInstances.firstIndex(where: { $0.id == id }) {
                guard !componentInstances[subIdx].childInstances[childIdx].isLocked else {
                    return .failure(.objectLocked(componentInstances[subIdx].childInstances[childIdx].solidId))
                }
                guard !componentInstances[subIdx].childInstances[childIdx].isGrounded else {
                    return .failure(.invalidOperation("Component '\(componentInstances[subIdx].childInstances[childIdx].name)' is grounded and cannot be moved"))
                }
                let oldTransform = componentInstances[subIdx].childInstances[childIdx].transform
                guard oldTransform != transform else { return .success(()) }
                componentInstances[subIdx].childInstances[childIdx].transform = transform
                syncObjectsFromFeatures()
                if registerUndo {
                    let effectiveActionName = actionName ?? "Move Component"
                    undoManager?.registerUndo(withTarget: self) { target in
                        MainActor.assumeIsolated {
                            _ = target.updateComponentInstanceTransform(id: id, transform: oldTransform, actionName: effectiveActionName, registerUndo: true)
                            target.undoManager?.setActionName(effectiveActionName)
                            target.onUndoRedoMutation?(.transformChanged(SolidId("component-\(id.uuidString)"), transform: oldTransform))
                        }
                    }
                    undoManager?.setActionName(effectiveActionName)
                }
                undoStateVersion += 1
                return .success(())
            }
        }

        return .failure(.objectNotFound(SolidId("component-\(id.uuidString)")))
    }

    @discardableResult
    public func updateComponentInstance(_ instance: ComponentInstance, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        if let index = componentInstances.firstIndex(where: { $0.id == instance.id }) {
            let old = componentInstances[index]
            guard old != instance else { return .success(()) }
            componentInstances[index] = instance
            syncObjectsFromFeatures()
            if registerUndo {
                let effectiveActionName = actionName ?? "Update Component"
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        _ = target.updateComponentInstance(old, actionName: effectiveActionName, registerUndo: true)
                        target.undoManager?.setActionName(effectiveActionName)
                    }
                }
                undoManager?.setActionName(effectiveActionName)
            }
            undoStateVersion += 1
            return .success(())
        }

        for subIdx in 0..<componentInstances.count {
            if let childIdx = componentInstances[subIdx].childInstances.firstIndex(where: { $0.id == instance.id }) {
                let old = componentInstances[subIdx].childInstances[childIdx]
                guard old != instance else { return .success(()) }
                componentInstances[subIdx].childInstances[childIdx] = instance
                syncObjectsFromFeatures()
                if registerUndo {
                    let effectiveActionName = actionName ?? "Update Component"
                    undoManager?.registerUndo(withTarget: self) { target in
                        MainActor.assumeIsolated {
                            _ = target.updateComponentInstance(old, actionName: effectiveActionName, registerUndo: true)
                            target.undoManager?.setActionName(effectiveActionName)
                        }
                    }
                    undoManager?.setActionName(effectiveActionName)
                }
                undoStateVersion += 1
                return .success(())
            }
        }

        return .failure(.objectNotFound(instance.solidId))
    }

    @discardableResult
    public func setComponentInstanceGrounded(id: UUID, isGrounded: Bool, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        if let compIndex = componentInstances.firstIndex(where: { $0.id == id }) {
            let oldGrounded = componentInstances[compIndex].isGrounded
            guard oldGrounded != isGrounded else { return .success(()) }
            componentInstances[compIndex].isGrounded = isGrounded
            syncObjectsFromFeatures()
            if registerUndo {
                let effectiveActionName = actionName ?? (isGrounded ? "Ground Component" : "Float Component")
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        _ = target.setComponentInstanceGrounded(id: id, isGrounded: oldGrounded, actionName: effectiveActionName, registerUndo: true)
                        target.undoManager?.setActionName(effectiveActionName)
                    }
                }
                undoManager?.setActionName(effectiveActionName)
            }
            undoStateVersion += 1
            return .success(())
        }

        for subIdx in 0..<componentInstances.count {
            if let childIdx = componentInstances[subIdx].childInstances.firstIndex(where: { $0.id == id }) {
                let oldGrounded = componentInstances[subIdx].childInstances[childIdx].isGrounded
                guard oldGrounded != isGrounded else { return .success(()) }
                componentInstances[subIdx].childInstances[childIdx].isGrounded = isGrounded
                syncObjectsFromFeatures()
                if registerUndo {
                    let effectiveActionName = actionName ?? (isGrounded ? "Ground Component" : "Float Component")
                    undoManager?.registerUndo(withTarget: self) { target in
                        MainActor.assumeIsolated {
                            _ = target.setComponentInstanceGrounded(id: id, isGrounded: oldGrounded, actionName: effectiveActionName, registerUndo: true)
                            target.undoManager?.setActionName(effectiveActionName)
                        }
                    }
                    undoManager?.setActionName(effectiveActionName)
                }
                undoStateVersion += 1
                return .success(())
            }
        }

        return .failure(.objectNotFound(SolidId("component-\(id.uuidString)")))
    }

    // MARK: - Component Lookups & Hierarchy (BL-ASM-07, #168)

    /// Finds a component instance anywhere in the assembly hierarchy by UUID.
    public func findComponentInstance(id: UUID) -> ComponentInstance? {
        for instance in componentInstances {
            if let found = instance.findComponent(id: id) {
                return found.instance
            }
        }
        return nil
    }

    /// Finds a component instance anywhere in the assembly hierarchy by SolidId.
    public func findComponentInstance(solidId: SolidId) -> ComponentInstance? {
        for instance in componentInstances {
            if let found = instance.findComponent(solidId: solidId) {
                return found.instance
            }
        }
        return nil
    }

    /// Recursively returns all component instances in the document.
    public var allComponentInstances: [ComponentInstance] {
        componentInstances.flatMap { $0.allComponentInstances(recursive: true, includeSelf: true) }
    }

    // MARK: - Subassembly Mutations (BL-ASM-07, #168)

    @discardableResult
    public func groupAsSubassembly(
        instanceIds: [UUID],
        name: String = "Subassembly",
        id: UUID = UUID(),
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ComponentInstance, DocumentMutationError> {
        guard !instanceIds.isEmpty else {
            return .failure(.invalidOperation("No component instances specified for subassembly"))
        }
        let matchingIndices = instanceIds.compactMap { id in
            componentInstances.firstIndex(where: { $0.id == id })
        }
        guard matchingIndices.count == instanceIds.count else {
            return .failure(.invalidOperation("One or more component instances not found at the top level"))
        }

        let selectedInstances = matchingIndices.map { componentInstances[$0] }
        let rootTransform = selectedInstances[0].transform
        let isGrounded = selectedInstances.contains(where: { $0.isGrounded })

        var children: [ComponentInstance] = []
        for inst in selectedInstances {
            var child = inst
            child.transform = rootTransform.inverse * inst.transform
            children.append(child)
        }

        let idSet = Set(instanceIds)
        var internalConstraints: [AssemblyConstraint] = []
        var remainingConstraints: [AssemblyConstraint] = []
        for constraint in assemblyConstraints {
            let firstInSub = constraint.firstFeature.componentInstanceId.map { idSet.contains($0) } ?? false
            let secondInSub = constraint.secondFeature.componentInstanceId.map { idSet.contains($0) } ?? false
            if firstInSub && secondInSub {
                internalConstraints.append(constraint)
            } else {
                remainingConstraints.append(constraint)
            }
        }

        let subassembly = ComponentInstance(
            id: id,
            name: name,
            reference: .subassembly(name: name),
            transform: rootTransform,
            isGrounded: isGrounded,
            subassemblyBehavior: .rigid,
            childInstances: children,
            childConstraints: internalConstraints
        )

        let removeSet = Set(instanceIds)
        var newInstances: [ComponentInstance] = []
        var inserted = false
        for inst in componentInstances {
            if removeSet.contains(inst.id) {
                if !inserted {
                    newInstances.append(subassembly)
                    inserted = true
                }
            } else {
                newInstances.append(inst)
            }
        }

        let oldInstances = componentInstances
        let oldConstraints = assemblyConstraints
        let oldSelectedId = selectedId

        componentInstances = newInstances
        assemblyConstraints = remainingConstraints
        syncObjectsFromFeatures()
        selectedId = subassembly.solidId
        pruneInvalidSelection()

        if registerUndo {
            let effectiveActionName = actionName ?? "Group as Subassembly"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.componentInstances = oldInstances
                    target.assemblyConstraints = oldConstraints
                    target.selectedId = oldSelectedId
                    target.syncObjectsFromFeatures()
                    target.undoStateVersion += 1
                    target.undoManager?.setActionName(effectiveActionName)
                    target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                        MainActor.assumeIsolated {
                            _ = redoTarget.groupAsSubassembly(
                                instanceIds: instanceIds,
                                name: name,
                                id: subassembly.id,
                                actionName: effectiveActionName,
                                registerUndo: true
                            )
                        }
                    }
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(subassembly)
    }

    @discardableResult
    public func dissolveSubassembly(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let index = componentInstances.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(SolidId("component-\(id.uuidString)")))
        }
        let sub = componentInstances[index]
        guard sub.isSubassembly else {
            return .failure(.invalidOperation("Component '\(sub.name)' is not a subassembly"))
        }

        var promotedChildren: [ComponentInstance] = []
        for (childIdx, child) in sub.childInstances.enumerated() {
            var promoted = child
            promoted.transform = sub.transform * child.transform
            if sub.isGrounded && childIdx == 0 && !sub.childInstances.contains(where: { $0.isGrounded }) {
                promoted.isGrounded = true
            }
            promotedChildren.append(promoted)
        }

        let oldInstances = componentInstances
        let oldConstraints = assemblyConstraints
        let oldSelectedId = selectedId

        componentInstances.remove(at: index)
        componentInstances.insert(contentsOf: promotedChildren, at: index)
        assemblyConstraints.append(contentsOf: sub.childConstraints)
        syncObjectsFromFeatures()

        if selectedId == sub.solidId {
            selectedId = promotedChildren.first?.solidId
        }
        pruneInvalidSelection()

        if registerUndo {
            let effectiveActionName = actionName ?? "Dissolve Subassembly"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.componentInstances = oldInstances
                    target.assemblyConstraints = oldConstraints
                    target.selectedId = oldSelectedId
                    target.syncObjectsFromFeatures()
                    target.undoStateVersion += 1
                    target.undoManager?.setActionName(effectiveActionName)
                    target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                        MainActor.assumeIsolated {
                            _ = redoTarget.dissolveSubassembly(id: id, actionName: effectiveActionName, registerUndo: true)
                        }
                    }
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func setSubassemblyBehavior(
        id: UUID,
        behavior: SubassemblyBehavior,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let index = componentInstances.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(SolidId("component-\(id.uuidString)")))
        }
        guard componentInstances[index].isSubassembly else {
            return .failure(.invalidOperation("Component '\(componentInstances[index].name)' is not a subassembly"))
        }
        let oldBehavior = componentInstances[index].subassemblyBehavior
        guard oldBehavior != behavior else { return .success(()) }
        componentInstances[index].subassemblyBehavior = behavior
        if registerUndo {
            let effectiveActionName = actionName ?? (behavior == .flexible ? "Make Subassembly Flexible" : "Make Subassembly Rigid")
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.setSubassemblyBehavior(id: id, behavior: oldBehavior, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    public func setDocumentType(_ type: DocumentType, actionName: String? = nil, registerUndo: Bool = true) {
        guard documentType != type else { return }
        let oldType = documentType
        documentType = type
        syncObjectsFromFeatures()
        if registerUndo {
            let effectiveActionName = actionName ?? "Change Document Type"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setDocumentType(oldType, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
    }

    // MARK: - Assembly Constraints (BL-CON-10, #164)

    @discardableResult
    public func addAssemblyConstraint(_ constraint: AssemblyConstraint, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        assemblyConstraints.append(constraint)
        if registerUndo {
            let effectiveActionName = actionName ?? "Add Assembly Constraint"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeAssemblyConstraint(id: constraint.id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func removeAssemblyConstraint(id: UUID, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        guard let index = assemblyConstraints.firstIndex(where: { $0.id == id }) else {
            return .failure(.invalidOperation("Assembly constraint not found"))
        }
        let constraint = assemblyConstraints[index]
        assemblyConstraints.remove(at: index)
        if registerUndo {
            let effectiveActionName = actionName ?? "Remove Assembly Constraint"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.addAssemblyConstraint(constraint, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func updateAssemblyConstraint(_ constraint: AssemblyConstraint, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
        guard let index = assemblyConstraints.firstIndex(where: { $0.id == constraint.id }) else {
            return .failure(.invalidOperation("Assembly constraint not found"))
        }
        let old = assemblyConstraints[index]
        guard old != constraint else { return .success(()) }
        assemblyConstraints[index] = constraint
        if registerUndo {
            let effectiveActionName = actionName ?? "Update Assembly Constraint"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateAssemblyConstraint(old, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    /// Returns the assembly constraint system consisting of all current component instances and constraints (BL-ASM-05, #166).
    public func assemblyConstraintSystem() -> AssemblyConstraintSystem {
        AssemblyConstraintSystem(instances: componentInstances, constraints: assemblyConstraints)
    }

    /// Computes remaining total and per-instance degrees of freedom for the assembly (BL-ASM-05, #166).
    public func computeAssemblyDOF() -> (totalDOF: Int, instanceDOF: [UUID: Int]) {
        AssemblyConstraintSolver.computeSystemDOF(system: assemblyConstraintSystem())
    }

    private func updateTransforms(
        from solvedTransforms: [UUID: Transform],
        in instances: inout [ComponentInstance],
        parentTransform: Transform = .identity
    ) -> [UUID: Transform] {
        var oldMap: [UUID: Transform] = [:]
        for i in 0..<instances.count {
            if !instances[i].isSubassembly {
                if let newWorld = solvedTransforms[instances[i].id], !instances[i].isGrounded {
                    let newLocal = parentTransform.inverse * newWorld
                    if instances[i].transform != newLocal {
                        oldMap[instances[i].id] = instances[i].transform
                        instances[i].transform = newLocal
                    }
                }
            } else if instances[i].subassemblyBehavior == .rigid {
                if let newWorld = solvedTransforms[instances[i].id], !instances[i].isGrounded {
                    let newLocal = parentTransform.inverse * newWorld
                    if instances[i].transform != newLocal {
                        oldMap[instances[i].id] = instances[i].transform
                        instances[i].transform = newLocal
                    }
                }
            } else {
                if let newWorld = solvedTransforms[instances[i].id], !instances[i].isGrounded {
                    let newLocal = parentTransform.inverse * newWorld
                    if instances[i].transform != newLocal {
                        oldMap[instances[i].id] = instances[i].transform
                        instances[i].transform = newLocal
                    }
                }
                let currentSubWorld = parentTransform * instances[i].transform
                let childOld = updateTransforms(from: solvedTransforms, in: &instances[i].childInstances, parentTransform: currentSubWorld)
                oldMap.merge(childOld) { current, _ in current }
            }
        }
        return oldMap
    }

    @discardableResult
    public func solveAssemblyConstraints(dragTarget: AssemblyDragTarget? = nil, actionName: String? = nil, registerUndo: Bool = true) -> AssemblySolverResult {
        let system = assemblyConstraintSystem()
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)
        guard result.status.isConverged else {
            return result
        }

        let oldInstances = componentInstances
        let oldTransforms = updateTransforms(from: result.solvedTransforms, in: &componentInstances)

        if !oldTransforms.isEmpty {
            syncObjectsFromFeatures()
            if registerUndo && activeAssemblyDragInitialTransforms == nil {
                let effectiveActionName = actionName ?? "Solve Assembly Constraints"
                let newInstances = componentInstances
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        target.componentInstances = oldInstances
                        target.syncObjectsFromFeatures()
                        target.undoStateVersion += 1
                        target.undoManager?.setActionName(effectiveActionName)
                        target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                            MainActor.assumeIsolated {
                                redoTarget.componentInstances = newInstances
                                redoTarget.syncObjectsFromFeatures()
                                redoTarget.undoStateVersion += 1
                                redoTarget.undoManager?.setActionName(effectiveActionName)
                            }
                        }
                    }
                }
                undoManager?.setActionName(effectiveActionName)
            }
            undoStateVersion += 1
        }

        return result
    }

    // MARK: - Interactive Assembly Drag Sessions (BL-ASM-06)

    public func beginInteractiveAssemblyDrag(instanceId: UUID) {
        guard let comp = findComponentInstance(id: instanceId), !comp.isGrounded && !comp.isLocked else {
            return
        }
        var initialMap: [UUID: Transform] = [:]
        for inst in allComponentInstances {
            initialMap[inst.id] = inst.transform
        }
        activeAssemblyDragInitialTransforms = initialMap
        activeAssemblyDragInitialInstances = componentInstances
    }

    public func endInteractiveAssemblyDrag(instanceId: UUID, actionName: String? = nil) {
        let initialInstances = activeAssemblyDragInitialInstances
        activeAssemblyDragInitialInstances = nil
        activeAssemblyDragInitialTransforms = nil

        guard let initialInstances, initialInstances != componentInstances else { return }

        let oldInstances = initialInstances
        let newInstances = componentInstances
        let effectiveActionName = actionName ?? "Drag Component"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.componentInstances = oldInstances
                target.syncObjectsFromFeatures()
                target.undoStateVersion += 1
                target.undoManager?.setActionName(effectiveActionName)
                target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                    MainActor.assumeIsolated {
                        redoTarget.componentInstances = newInstances
                        redoTarget.syncObjectsFromFeatures()
                        redoTarget.undoStateVersion += 1
                        redoTarget.undoManager?.setActionName(effectiveActionName)
                    }
                }
            }
        }
        undoManager?.setActionName(effectiveActionName)
        undoStateVersion += 1
    }

    public func cancelInteractiveAssemblyDrag() {
        let initialInstances = activeAssemblyDragInitialInstances
        activeAssemblyDragInitialInstances = nil
        activeAssemblyDragInitialTransforms = nil

        guard let initialInstances, initialInstances != componentInstances else { return }
        componentInstances = initialInstances
        syncObjectsFromFeatures()
        undoStateVersion += 1
    }

    /// Returns all direct dependent objects of `rootId` (BL-FND-03).
    public func directDependentObjects(of rootId: ObjectId) -> [ObjectId] {
        if let feat = feature(for: rootId) {
            return directDependentFeatures(referencing: feat.id).compactMap(\.outputSolidId)
        }
        var result: [ObjectId] = []
        for obj in objects {
            if case .boolean(_, let a, let b) = obj.def, a == rootId || b == rootId {
                result.append(obj.id)
            }
        }
        return result
    }

    /// Returns all direct and transitive dependent objects of `rootId` in topological order (BL-FND-03).
    public func dependentObjects(of rootId: ObjectId) -> [ObjectId] {
        if let feat = feature(for: rootId) {
            return dependentFeatures(referencing: feat.id).compactMap(\.outputSolidId)
        }
        var result: [ObjectId] = []
        var visited: Set<ObjectId> = [rootId]
        for obj in objects {
            if case .boolean(_, let a, let b) = obj.def {
                if visited.contains(a) || visited.contains(b) {
                    visited.insert(obj.id)
                    result.append(obj.id)
                }
            }
        }
        return result
    }

    // MARK: - Assembly Component Patterns & Mirrors (BL-ASM-08, #169)

    public func findComponentInstanceLocation(id: UUID) -> (instance: ComponentInstance, parentId: UUID?, isTopLevel: Bool, topLevelIndex: Int?, childIndex: Int?)? {
        if let idx = componentInstances.firstIndex(where: { $0.id == id }) {
            return (componentInstances[idx], nil, true, idx, nil)
        }
        for subIdx in 0..<componentInstances.count {
            if let childIdx = componentInstances[subIdx].childInstances.firstIndex(where: { $0.id == id }) {
                return (componentInstances[subIdx].childInstances[childIdx], componentInstances[subIdx].id, false, subIdx, childIdx)
            }
        }
        return nil
    }

    private func insertComponentInstanceReplica(_ replica: ComponentInstance, parentId: UUID?) {
        if let parentId, let subIdx = componentInstances.firstIndex(where: { $0.id == parentId }) {
            componentInstances[subIdx].childInstances.append(replica)
        } else {
            componentInstances.append(replica)
        }
    }

    private func removeComponentInstanceReplica(id: UUID) {
        if let idx = componentInstances.firstIndex(where: { $0.id == id }) {
            componentInstances.remove(at: idx)
            return
        }
        for subIdx in 0..<componentInstances.count {
            if let childIdx = componentInstances[subIdx].childInstances.firstIndex(where: { $0.id == id }) {
                componentInstances[subIdx].childInstances.remove(at: childIdx)
                return
            }
        }
    }

    @discardableResult
    public func patternComponentInstance(
        params: AssemblyPatternParams,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ComponentPattern, DocumentMutationError> {
        guard params.count > 0 else {
            return .failure(.invalidOperation("Pattern count must be greater than zero"))
        }
        guard let (sourceInstance, parentId, _, _, _) = findComponentInstanceLocation(id: params.sourceInstanceId) else {
            return .failure(.objectNotFound(SolidId("component-\(params.sourceInstanceId.uuidString)")))
        }

        let isLinear: Bool
        switch params.patternType {
        case .linear:
            guard simd_length_squared(params.linearDirection) > 1e-12 else {
                return .failure(.invalidOperation("Linear pattern direction vector cannot be zero-length"))
            }
            isLinear = true
        case .circular:
            guard simd_length_squared(params.axisDirection) > 1e-12 else {
                return .failure(.invalidOperation("Circular pattern axis direction vector cannot be zero-length"))
            }
            isLinear = false
        case .featureDriven:
            if let fId = params.featurePatternId,
               let feat = features.first(where: { $0.id == fId }),
               case .pattern(let pParams) = feat.operation {
                isLinear = (pParams.patternType == .linear)
            } else {
                isLinear = simd_length_squared(params.linearDirection) > 1e-6
            }
        }

        let patternId = UUID()
        var replicaIds: [UUID] = []

        if params.count > 1 {
            for i in 1..<params.count {
                if params.skippedIndices.contains(i) {
                    continue
                }

                let stepTransform: Transform
                if isLinear {
                    let normDir = simd_normalize(params.linearDirection)
                    let spacing = params.linearSpacing
                    let stepInt: Int = params.isSymmetric ? ((i % 2 == 1) ? (i + 1) / 2 : -(i + 1) / 2) : i
                    stepTransform = Transform.linearStepTransform(direction: normDir, spacing: spacing, index: stepInt)
                } else {
                    let angularStep: Float
                    if params.isFullCircle || params.totalAngle >= 360.0 {
                        angularStep = 360.0 / Float(params.count)
                    } else {
                        angularStep = params.totalAngle / Float(max(1, params.count - 1))
                    }
                    let rad = Float(Double(i) * Double(angularStep) * .pi / 180.0)
                    stepTransform = Transform.circularStepTransform(
                        axisOrigin: params.axisOrigin,
                        axisDirection: params.axisDirection,
                        angleRadians: rad
                    )
                }

                let replicaTransform = stepTransform * sourceInstance.transform
                let replicaId = UUID()
                let replicaName = "\(sourceInstance.name) (Pattern \(i + 1))"
                let replica = ComponentInstance(
                    id: replicaId,
                    name: replicaName,
                    reference: sourceInstance.reference,
                    transform: replicaTransform,
                    isVisible: sourceInstance.isVisible,
                    isLocked: false,
                    isGrounded: false,
                    material: sourceInstance.material,
                    subassemblyBehavior: sourceInstance.subassemblyBehavior,
                    childInstances: sourceInstance.childInstances,
                    childConstraints: sourceInstance.childConstraints,
                    patternId: patternId,
                    mirrorId: nil
                )

                insertComponentInstanceReplica(replica, parentId: parentId)
                replicaIds.append(replicaId)
            }
        }

        let pattern = ComponentPattern(
            id: patternId,
            name: "Pattern \(componentPatterns.count + 1)",
            sourceInstanceId: sourceInstance.id,
            replicaInstanceIds: replicaIds,
            params: params
        )
        componentPatterns.append(pattern)
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Pattern Component"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeComponentPattern(id: pattern.id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(pattern)
    }

    @discardableResult
    public func patternComponentInstanceByFeaturePattern(
        instanceId: UUID,
        featurePatternId: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ComponentPattern, DocumentMutationError> {
        guard let feat = features.first(where: { $0.id == featurePatternId }) else {
            return .failure(.objectNotFound(ObjectId(featurePatternId.uuidString)))
        }
        guard case .pattern(let pParams) = feat.operation else {
            return .failure(.invalidOperation("Feature '\(feat.name)' is not a pattern feature"))
        }

        let params = AssemblyPatternParams(
            sourceInstanceId: instanceId,
            patternType: .featureDriven,
            count: pParams.count,
            linearSpacing: Float(pParams.linearSpacing),
            linearDirection: SIMD3<Float>(pParams.linearDirection),
            isSymmetric: pParams.isSymmetric,
            axisOrigin: SIMD3<Float>(pParams.axisOrigin),
            axisDirection: SIMD3<Float>(pParams.axisDirection),
            totalAngle: Float(pParams.totalAngle),
            isFullCircle: pParams.isFullCircle,
            featurePatternId: featurePatternId,
            skippedIndices: pParams.skippedIndices
        )

        return patternComponentInstance(
            params: params,
            actionName: actionName ?? "Pattern Component by Feature",
            registerUndo: registerUndo
        )
    }

    @discardableResult
    public func removeComponentPattern(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let pIdx = componentPatterns.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(SolidId("pattern-\(id.uuidString)")))
        }
        let pattern = componentPatterns[pIdx]
        var savedReplicas: [(instance: ComponentInstance, parentId: UUID?)] = []
        for replicaId in pattern.replicaInstanceIds {
            if let loc = findComponentInstanceLocation(id: replicaId) {
                savedReplicas.append((loc.instance, loc.parentId))
                removeComponentInstanceReplica(id: replicaId)
            }
        }
        componentPatterns.remove(at: pIdx)
        pruneInvalidSelection()
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Remove Component Pattern"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    for saved in savedReplicas {
                        target.insertComponentInstanceReplica(saved.instance, parentId: saved.parentId)
                    }
                    target.componentPatterns.append(pattern)
                    target.syncObjectsFromFeatures()
                    target.undoStateVersion += 1
                    target.undoManager?.setActionName(effectiveActionName)
                    target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                        MainActor.assumeIsolated {
                            _ = redoTarget.removeComponentPattern(id: pattern.id, actionName: effectiveActionName, registerUndo: true)
                        }
                    }
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func mirrorComponentInstance(
        params: AssemblyMirrorParams,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ComponentMirror, DocumentMutationError> {
        guard let (sourceInstance, parentId, _, _, _) = findComponentInstanceLocation(id: params.sourceInstanceId) else {
            return .failure(.objectNotFound(SolidId("component-\(params.sourceInstanceId.uuidString)")))
        }
        guard simd_length_squared(params.planeNormal) > 1e-12 else {
            return .failure(.invalidOperation("Mirror plane normal vector cannot be zero-length"))
        }

        let mirroredTransform = sourceInstance.transform.mirrored(
            planeOrigin: params.planeOrigin,
            planeNormal: params.planeNormal,
            mode: params.mirrorMode
        )

        let mirrorId = UUID()
        let replicaId = UUID()
        let replicaName = "\(sourceInstance.name) (Mirrored)"
        let replica = ComponentInstance(
            id: replicaId,
            name: replicaName,
            reference: sourceInstance.reference,
            transform: mirroredTransform,
            isVisible: true,
            isLocked: false,
            isGrounded: false,
            material: sourceInstance.material,
            subassemblyBehavior: sourceInstance.subassemblyBehavior,
            childInstances: sourceInstance.childInstances,
            childConstraints: sourceInstance.childConstraints,
            patternId: nil,
            mirrorId: mirrorId
        )

        insertComponentInstanceReplica(replica, parentId: parentId)

        if !params.keepOriginal {
            var updatedSource = sourceInstance
            updatedSource.isVisible = false
            _ = updateComponentInstance(updatedSource, registerUndo: false)
        }

        let mirror = ComponentMirror(
            id: mirrorId,
            name: "Mirror \(componentMirrors.count + 1)",
            sourceInstanceId: sourceInstance.id,
            replicaInstanceIds: [replicaId],
            params: params
        )
        componentMirrors.append(mirror)
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Mirror Component"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeComponentMirror(id: mirror.id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(mirror)
    }

    @discardableResult
    public func removeComponentMirror(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let mIdx = componentMirrors.firstIndex(where: { $0.id == id }) else {
            return .failure(.objectNotFound(SolidId("mirror-\(id.uuidString)")))
        }
        let mirror = componentMirrors[mIdx]
        var savedReplicas: [(instance: ComponentInstance, parentId: UUID?)] = []
        for replicaId in mirror.replicaInstanceIds {
            if let loc = findComponentInstanceLocation(id: replicaId) {
                savedReplicas.append((loc.instance, loc.parentId))
                removeComponentInstanceReplica(id: replicaId)
            }
        }
        if !mirror.params.keepOriginal {
            if let srcLoc = findComponentInstanceLocation(id: mirror.sourceInstanceId) {
                var copy = srcLoc.instance
                copy.isVisible = true
                _ = updateComponentInstance(copy, registerUndo: false)
            }
        }
        componentMirrors.remove(at: mIdx)
        pruneInvalidSelection()
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Remove Component Mirror"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    for saved in savedReplicas {
                        target.insertComponentInstanceReplica(saved.instance, parentId: saved.parentId)
                    }
                    if !mirror.params.keepOriginal {
                        if let sLoc = target.findComponentInstanceLocation(id: mirror.sourceInstanceId) {
                            var c = sLoc.instance
                            c.isVisible = false
                            _ = target.updateComponentInstance(c, registerUndo: false)
                        }
                    }
                    target.componentMirrors.append(mirror)
                    target.syncObjectsFromFeatures()
                    target.undoStateVersion += 1
                    target.undoManager?.setActionName(effectiveActionName)
                    target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                        MainActor.assumeIsolated {
                            _ = redoTarget.removeComponentMirror(id: mirror.id, actionName: effectiveActionName, registerUndo: true)
                        }
                    }
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    // MARK: - Exploded Views (BL-ASM-12)

    private func pruneComponentFromExplodedViews(id: UUID) {
        for vIdx in explodedViews.indices {
            for sIdx in explodedViews[vIdx].steps.indices {
                explodedViews[vIdx].steps[sIdx].targetInstanceIds.removeAll(where: { $0 == id })
            }
        }
    }

    public func explodedView(id: UUID) -> ExplodedView? {
        explodedViews.first(where: { $0.id == id })
    }

    /// Recursively returns the unexploded world transform for a component instance.
    public func worldTransform(for instanceId: UUID) -> Transform? {
        func search(in instances: [ComponentInstance], parentTransform: Transform) -> Transform? {
            for inst in instances {
                let world = parentTransform * inst.transform
                if inst.id == instanceId {
                    return world
                }
                if let childWorld = search(in: inst.childInstances, parentTransform: world) {
                    return childWorld
                }
            }
            return nil
        }
        return search(in: componentInstances, parentTransform: .identity)
    }

    /// Returns the effective transform of a component instance taking into account the active exploded view.
    public func effectiveTransform(for instanceId: UUID) -> Transform? {
        guard let base = worldTransform(for: instanceId) else { return nil }
        guard let activeId = activeExplodedViewId,
              let view = explodedView(id: activeId),
              !view.isCollapsed else {
            return base
        }
        return view.transformedPosition(for: instanceId, baseTransform: base)
    }

    /// Returns the effective transform of a component instance in a specific exploded view.
    public func effectiveTransform(for instanceId: UUID, in explodedViewId: UUID) -> Transform? {
        guard let base = worldTransform(for: instanceId),
              let view = explodedView(id: explodedViewId) else {
            return nil
        }
        guard !view.isCollapsed else {
            return base
        }
        return view.transformedPosition(for: instanceId, baseTransform: base)
    }

    /// Computes exploded view trail segments for a given exploded view.
    public func computeTrails(for explodedViewId: UUID) -> [ExplodeTrail] {
        guard let view = explodedView(id: explodedViewId) else { return [] }
        return view.computeTrails(instances: componentInstances)
    }

    @discardableResult
    public func addExplodedView(
        _ view: ExplodedView? = nil,
        name: String = "Exploded View",
        at index: Int? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ExplodedView, DocumentMutationError> {
        let newView = view ?? ExplodedView(id: UUID(), name: name)
        let insertionIndex = min(max(0, index ?? explodedViews.count), explodedViews.count)
        explodedViews.insert(newView, at: insertionIndex)
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Add Exploded View"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeExplodedView(id: newView.id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(newView)
    }

    @discardableResult
    public func addExplodedView(
        name: String,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ExplodedView, DocumentMutationError> {
        addExplodedView(nil, name: name, at: nil, actionName: actionName, registerUndo: registerUndo)
    }

    @discardableResult
    public func removeExplodedView(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let index = explodedViews.firstIndex(where: { $0.id == id }) else {
            return .failure(.invalidOperation("Exploded view with id \(id) not found"))
        }
        let removedView = explodedViews.remove(at: index)
        let oldActiveId = activeExplodedViewId
        if activeExplodedViewId == id {
            activeExplodedViewId = nil
        }
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Remove Exploded View"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.addExplodedView(removedView, at: index, actionName: effectiveActionName, registerUndo: true)
                    if oldActiveId == id {
                        _ = target.setActiveExplodedView(id: oldActiveId, actionName: effectiveActionName, registerUndo: false)
                    }
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func renameExplodedView(
        id: UUID,
        name: String,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let index = explodedViews.firstIndex(where: { $0.id == id }) else {
            return .failure(.invalidOperation("Exploded view with id \(id) not found"))
        }
        let oldName = explodedViews[index].name
        guard oldName != name else { return .success(()) }
        explodedViews[index].name = name

        if registerUndo {
            let effectiveActionName = actionName ?? "Rename Exploded View"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.renameExplodedView(id: id, name: oldName, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func setActiveExplodedView(
        id: UUID?,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        if let id {
            guard explodedViews.contains(where: { $0.id == id }) else {
                return .failure(.invalidOperation("Exploded view with id \(id) not found"))
            }
        }
        let oldActiveId = activeExplodedViewId
        guard oldActiveId != id else { return .success(()) }
        activeExplodedViewId = id
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? (id != nil ? "Activate Exploded View" : "Deactivate Exploded View")
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.setActiveExplodedView(id: oldActiveId, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func toggleExplodedViewCollapsed(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let index = explodedViews.firstIndex(where: { $0.id == id }) else {
            return .failure(.invalidOperation("Exploded view with id \(id) not found"))
        }
        explodedViews[index].isCollapsed.toggle()
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? (explodedViews[index].isCollapsed ? "Collapse Exploded View" : "Expand Exploded View")
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.toggleExplodedViewCollapsed(id: id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func addExplodeStep(
        viewId: UUID,
        step: ExplodeStep = ExplodeStep(),
        at index: Int? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<ExplodeStep, DocumentMutationError> {
        guard let viewIndex = explodedViews.firstIndex(where: { $0.id == viewId }) else {
            return .failure(.invalidOperation("Exploded view with id \(viewId) not found"))
        }
        let insertionIndex = min(max(0, index ?? explodedViews[viewIndex].steps.count), explodedViews[viewIndex].steps.count)
        explodedViews[viewIndex].steps.insert(step, at: insertionIndex)
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Add Explode Step"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeExplodeStep(viewId: viewId, stepId: step.id, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(step)
    }

    @discardableResult
    public func removeExplodeStep(
        viewId: UUID,
        stepId: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let viewIndex = explodedViews.firstIndex(where: { $0.id == viewId }) else {
            return .failure(.invalidOperation("Exploded view with id \(viewId) not found"))
        }
        guard let stepIndex = explodedViews[viewIndex].steps.firstIndex(where: { $0.id == stepId }) else {
            return .failure(.invalidOperation("Explode step with id \(stepId) not found"))
        }
        let removedStep = explodedViews[viewIndex].steps.remove(at: stepIndex)
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Remove Explode Step"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.addExplodeStep(viewId: viewId, step: removedStep, at: stepIndex, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func updateExplodeStep(
        viewId: UUID,
        step: ExplodeStep,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let viewIndex = explodedViews.firstIndex(where: { $0.id == viewId }) else {
            return .failure(.invalidOperation("Exploded view with id \(viewId) not found"))
        }
        guard let stepIndex = explodedViews[viewIndex].steps.firstIndex(where: { $0.id == step.id }) else {
            return .failure(.invalidOperation("Explode step with id \(step.id) not found"))
        }
        let oldStep = explodedViews[viewIndex].steps[stepIndex]
        guard oldStep != step else { return .success(()) }
        explodedViews[viewIndex].steps[stepIndex] = step
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Edit Explode Step"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateExplodeStep(viewId: viewId, step: oldStep, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func reorderExplodeSteps(
        viewId: UUID,
        stepIds: [UUID],
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Result<Void, DocumentMutationError> {
        guard let viewIndex = explodedViews.firstIndex(where: { $0.id == viewId }) else {
            return .failure(.invalidOperation("Exploded view with id \(viewId) not found"))
        }
        let oldSteps = explodedViews[viewIndex].steps
        let oldIds = oldSteps.map(\.id)
        guard oldIds != stepIds else { return .success(()) }

        var stepMap: [UUID: ExplodeStep] = [:]
        for step in oldSteps {
            stepMap[step.id] = step
        }
        var reordered: [ExplodeStep] = []
        for id in stepIds {
            if let step = stepMap.removeValue(forKey: id) {
                reordered.append(step)
            }
        }
        for remaining in oldSteps where stepMap[remaining.id] != nil {
            reordered.append(remaining)
        }
        explodedViews[viewIndex].steps = reordered
        syncObjectsFromFeatures()

        if registerUndo {
            let effectiveActionName = actionName ?? "Reorder Explode Steps"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.reorderExplodeSteps(viewId: viewId, stepIds: oldIds, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return .success(())
    }

    // MARK: - Drawing Sheet Mutators (BL-DRW-01, #208)

    @discardableResult
    public func addSheet(
        _ sheet: DrawingSheet? = nil,
        at index: Int? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> DrawingSheet {
        let newSheet = sheet ?? DrawingSheet(
            name: "Sheet \(sheets.count + 1)",
            size: .isoA3,
            orientation: .landscape
        )
        let insertionIndex = min(max(0, index ?? sheets.count), sheets.count)
        sheets.insert(newSheet, at: insertionIndex)
        let oldActiveId = activeSheetId
        activeSheetId = newSheet.id

        if registerUndo {
            let effectiveActionName = actionName ?? "Add Sheet"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeSheet(id: newSheet.id, actionName: effectiveActionName, registerUndo: true)
                    target.activeSheetId = oldActiveId
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return newSheet
    }

    @discardableResult
    public func removeSheet(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        guard sheets.count > 1 else { return false }
        guard let index = sheets.firstIndex(where: { $0.id == id }) else { return false }
        let removedSheet = sheets.remove(at: index)
        let oldActiveId = activeSheetId
        if activeSheetId == id {
            let fallbackIndex = min(index, sheets.count - 1)
            activeSheetId = sheets[fallbackIndex].id
        }
        if let selected = selectedDrawingViewId, removedSheet.views.contains(where: { $0.id == selected }) {
            selectedDrawingViewId = nil
        }
        if let selectedAnn = selectedDrawingAnnotationId, removedSheet.annotations.contains(where: { $0.id == selectedAnn }) {
            selectedDrawingAnnotationId = nil
        }

        if registerUndo {
            let effectiveActionName = actionName ?? "Delete Sheet"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.addSheet(removedSheet, at: index, actionName: effectiveActionName, registerUndo: true)
                    target.activeSheetId = oldActiveId
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    @discardableResult
    public func updateSheet(
        _ sheet: DrawingSheet,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        guard let index = sheets.firstIndex(where: { $0.id == sheet.id }) else { return false }
        let oldSheet = sheets[index]
        guard oldSheet != sheet else { return true }
        sheets[index] = sheet

        if registerUndo {
            let effectiveActionName = actionName ?? "Update Sheet"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateSheet(oldSheet, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    public func setActiveSheetId(
        _ id: UUID?,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) {
        if let id {
            guard sheets.contains(where: { $0.id == id }) else { return }
        }
        let oldActiveId = activeSheetId
        guard oldActiveId != id else { return }
        activeSheetId = id

        if registerUndo {
            let effectiveActionName = actionName ?? "Select Sheet"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.setActiveSheetId(oldActiveId, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
    }

    @discardableResult
    public func duplicateSheet(
        id: UUID,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> DrawingSheet? {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else { return nil }
        let original = sheets[index]
        let duplicated = DrawingSheet(
            id: UUID(),
            name: "\(original.name) Copy",
            size: original.size,
            orientation: original.orientation,
            scale: original.scale,
            titleBlockTemplate: original.titleBlockTemplate,
            projectionAngle: original.projectionAngle,
            views: original.views,
            customProperties: original.customProperties
        )
        let insertionIndex = index + 1
        return addSheet(duplicated, at: insertionIndex, actionName: actionName ?? "Duplicate Sheet", registerUndo: registerUndo)
    }

    public func reorderSheets(
        _ newSheets: [DrawingSheet],
        actionName: String? = nil,
        registerUndo: Bool = true
    ) {
        guard newSheets.count == sheets.count else { return }
        let oldSheets = sheets
        guard oldSheets != newSheets else { return }
        sheets = newSheets

        if registerUndo {
            let effectiveActionName = actionName ?? "Reorder Sheets"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.reorderSheets(oldSheets, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
    }

    @discardableResult
    public func setSheetProperty(
        sheetId: UUID,
        key: String,
        value: String?,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }
        guard let index = sheets.firstIndex(where: { $0.id == sheetId }) else { return false }
        let oldSheet = sheets[index]
        var updatedSheet = oldSheet
        updatedSheet.setProperty(key: trimmedKey, value: value)
        guard updatedSheet != oldSheet else { return true }
        sheets[index] = updatedSheet

        if registerUndo {
            let effectiveActionName = actionName ?? "Edit Sheet Property"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.setSheetProperty(
                        sheetId: sheetId,
                        key: trimmedKey,
                        value: oldSheet.property(forKey: trimmedKey),
                        actionName: effectiveActionName,
                        registerUndo: true
                    )
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    // MARK: - Drawing View Mutators (BL-DRW-03, #210)

    @discardableResult
    public func addDrawingView(
        _ view: DrawingView,
        at index: Int? = nil,
        to sheetId: UUID? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> DrawingView? {
        let targetSheetId = sheetId ?? activeSheetId
        guard let sIdx = sheets.firstIndex(where: { targetSheetId != nil ? $0.id == targetSheetId : true }) else {
            return nil
        }
        let sheetUUID = sheets[sIdx].id
        let insertionIndex = min(max(0, index ?? sheets[sIdx].views.count), sheets[sIdx].views.count)
        sheets[sIdx].views.insert(view, at: insertionIndex)
        selectedDrawingViewId = view.id

        if registerUndo {
            let effectiveActionName = actionName ?? "Add Drawing View"
            let viewId = view.id
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeDrawingView(id: viewId, from: sheetUUID, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return view
    }

    @discardableResult
    public func removeDrawingView(
        id viewId: UUID,
        from sheetId: UUID? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true,
        preserveAnnotationsAsDangling: Bool = false
    ) -> Bool {
        let targetSheetId = sheetId ?? activeSheetId
        guard let sIdx = sheets.firstIndex(where: { sheet in
            (targetSheetId != nil ? sheet.id == targetSheetId : true) && sheet.views.contains(where: { $0.id == viewId })
        }) else {
            return false
        }
        guard let vIdx = sheets[sIdx].views.firstIndex(where: { $0.id == viewId }) else {
            return false
        }
        let sheetUUID = sheets[sIdx].id
        let removedView = sheets[sIdx].views.remove(at: vIdx)

        // Detach projected views whose parent was this view
        var unlinkedChildren: [(sheetIndex: Int, viewIndex: Int, view: DrawingView)] = []
        for currentSheetIdx in sheets.indices {
            for currentViewIdx in sheets[currentSheetIdx].views.indices {
                if sheets[currentSheetIdx].views[currentViewIdx].parentViewId == viewId {
                    unlinkedChildren.append((currentSheetIdx, currentViewIdx, sheets[currentSheetIdx].views[currentViewIdx]))
                    sheets[currentSheetIdx].views[currentViewIdx].parentViewId = nil
                    sheets[currentSheetIdx].views[currentViewIdx].kind = .base
                }
            }
        }

        // Collect and detach/remove attached annotations
        let oldAnnotations = sheets[sIdx].annotations
        let attachedAnnotations = sheets[sIdx].annotations.filter { $0.viewId == viewId }

        if preserveAnnotationsAsDangling {
            for aIdx in sheets[sIdx].annotations.indices {
                if sheets[sIdx].annotations[aIdx].viewId == viewId {
                    sheets[sIdx].annotations[aIdx].isDangling = true
                }
            }
        } else {
            sheets[sIdx].annotations.removeAll { $0.viewId == viewId }
            if let selAnnId = selectedDrawingAnnotationId, attachedAnnotations.contains(where: { $0.id == selAnnId }) {
                selectedDrawingAnnotationId = nil
            }
        }

        let oldSelectedId = selectedDrawingViewId
        if selectedDrawingViewId == viewId {
            selectedDrawingViewId = nil
        }

        if registerUndo {
            let effectiveActionName = actionName ?? "Delete Drawing View"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if let targetSheetIdx = target.sheets.firstIndex(where: { $0.id == sheetUUID }) {
                        let insertIdx = min(vIdx, target.sheets[targetSheetIdx].views.count)
                        target.sheets[targetSheetIdx].views.insert(removedView, at: insertIdx)
                        for child in unlinkedChildren {
                            if child.sheetIndex < target.sheets.count,
                               let childViewIdx = target.sheets[child.sheetIndex].views.firstIndex(where: { $0.id == child.view.id }) {
                                target.sheets[child.sheetIndex].views[childViewIdx] = child.view
                            }
                        }
                        target.sheets[targetSheetIdx].annotations = oldAnnotations
                        target.selectedDrawingViewId = oldSelectedId ?? removedView.id
                        target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                            MainActor.assumeIsolated {
                                _ = redoTarget.removeDrawingView(id: removedView.id, from: sheetUUID, actionName: effectiveActionName, registerUndo: true, preserveAnnotationsAsDangling: preserveAnnotationsAsDangling)
                                redoTarget.undoManager?.setActionName(effectiveActionName)
                            }
                        }
                    }
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    @discardableResult
    public func updateDrawingView(
        _ view: DrawingView,
        on sheetId: UUID? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        let targetSheetId = sheetId ?? activeSheetId
        guard let sIdx = sheets.firstIndex(where: { sheet in
            (targetSheetId != nil ? sheet.id == targetSheetId : true) && sheet.views.contains(where: { $0.id == view.id })
        }) else {
            return false
        }
        guard let vIdx = sheets[sIdx].views.firstIndex(where: { $0.id == view.id }) else {
            return false
        }
        let sheetUUID = sheets[sIdx].id
        let oldView = sheets[sIdx].views[vIdx]
        guard oldView != view else { return true }
        sheets[sIdx].views[vIdx] = view

        if registerUndo {
            let effectiveActionName = actionName ?? "Update Drawing View"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateDrawingView(oldView, on: sheetUUID, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    @discardableResult
    public func repositionDrawingView(
        id viewId: UUID,
        positionMM: SIMD2<Double>,
        on sheetId: UUID? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        let targetSheetId = sheetId ?? activeSheetId
        guard let sIdx = sheets.firstIndex(where: { sheet in
            (targetSheetId != nil ? sheet.id == targetSheetId : true) && sheet.views.contains(where: { $0.id == viewId })
        }) else {
            return false
        }
        guard let vIdx = sheets[sIdx].views.firstIndex(where: { $0.id == viewId }) else {
            return false
        }
        let sheetUUID = sheets[sIdx].id
        let oldPosition = sheets[sIdx].views[vIdx].positionMM
        guard oldPosition != positionMM else { return true }
        sheets[sIdx].views[vIdx].positionMM = positionMM

        if registerUndo {
            let effectiveActionName = actionName ?? "Reposition Drawing View"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.repositionDrawingView(id: viewId, positionMM: oldPosition, on: sheetUUID, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    public func setSelectedDrawingViewId(_ id: UUID?) {
        selectedDrawingViewId = id
    }

    public func setSelectedDrawingAnnotationId(_ id: UUID?) {
        selectedDrawingAnnotationId = id
    }

    @discardableResult
    public func addDrawingAnnotation(
        _ annotation: DrawingAnnotation,
        to sheetId: UUID? = nil,
        index: Int? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> DrawingAnnotation? {
        let targetSheetId = sheetId ?? activeSheetId ?? sheets.first?.id
        guard let sIdx = sheets.firstIndex(where: { sheet in
            targetSheetId != nil ? sheet.id == targetSheetId : true
        }) else {
            return nil
        }
        let sheetUUID = sheets[sIdx].id
        let insertionIndex = min(max(0, index ?? sheets[sIdx].annotations.count), sheets[sIdx].annotations.count)
        sheets[sIdx].annotations.insert(annotation, at: insertionIndex)
        selectedDrawingAnnotationId = annotation.id

        if registerUndo {
            let effectiveActionName = actionName ?? "Add Annotation"
            let annId = annotation.id
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.removeDrawingAnnotation(id: annId, from: sheetUUID, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return annotation
    }

    @discardableResult
    public func removeDrawingAnnotation(
        id annotationId: UUID,
        from sheetId: UUID? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        let targetSheetId = sheetId ?? activeSheetId
        guard let sIdx = sheets.firstIndex(where: { sheet in
            (targetSheetId != nil ? sheet.id == targetSheetId : true) && sheet.annotations.contains(where: { $0.id == annotationId })
        }) else {
            return false
        }
        guard let aIdx = sheets[sIdx].annotations.firstIndex(where: { $0.id == annotationId }) else {
            return false
        }
        let sheetUUID = sheets[sIdx].id
        let removedAnnotation = sheets[sIdx].annotations.remove(at: aIdx)

        let oldSelectedId = selectedDrawingAnnotationId
        if selectedDrawingAnnotationId == annotationId {
            selectedDrawingAnnotationId = nil
        }

        if registerUndo {
            let effectiveActionName = actionName ?? "Delete Annotation"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if let targetSheetIdx = target.sheets.firstIndex(where: { $0.id == sheetUUID }) {
                        let insertIdx = min(aIdx, target.sheets[targetSheetIdx].annotations.count)
                        target.sheets[targetSheetIdx].annotations.insert(removedAnnotation, at: insertIdx)
                        target.selectedDrawingAnnotationId = oldSelectedId ?? removedAnnotation.id
                        target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                            MainActor.assumeIsolated {
                                _ = redoTarget.removeDrawingAnnotation(id: removedAnnotation.id, from: sheetUUID, actionName: effectiveActionName, registerUndo: true)
                                redoTarget.undoManager?.setActionName(effectiveActionName)
                            }
                        }
                    }
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    @discardableResult
    public func updateDrawingAnnotation(
        _ annotation: DrawingAnnotation,
        on sheetId: UUID? = nil,
        actionName: String? = nil,
        registerUndo: Bool = true
    ) -> Bool {
        let targetSheetId = sheetId ?? activeSheetId
        guard let sIdx = sheets.firstIndex(where: { sheet in
            (targetSheetId != nil ? sheet.id == targetSheetId : true) && sheet.annotations.contains(where: { $0.id == annotation.id })
        }) else {
            return false
        }
        guard let aIdx = sheets[sIdx].annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return false
        }
        let sheetUUID = sheets[sIdx].id
        let oldAnnotation = sheets[sIdx].annotations[aIdx]
        guard oldAnnotation != annotation else { return true }
        sheets[sIdx].annotations[aIdx] = annotation

        if registerUndo {
            let effectiveActionName = actionName ?? "Update Annotation"
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    _ = target.updateDrawingAnnotation(oldAnnotation, on: sheetUUID, actionName: effectiveActionName, registerUndo: true)
                    target.undoManager?.setActionName(effectiveActionName)
                }
            }
            undoManager?.setActionName(effectiveActionName)
        }
        undoStateVersion += 1
        return true
    }

    // MARK: - Drawing Associativity & Synchronization (BL-DRW-07, #214)

    /// Recomputes hidden line removal projections for drawing views and updates parametric annotation
    /// associativity across all drawing sheets when 3D model geometry or features change.
    public func updateDrawingAssociativity() {
        guard !sheets.isEmpty else { return }

        for sIdx in sheets.indices {
            // 1. Recompute view HLR projections if document contains 3D objects
            if !objects.isEmpty {
                for vIdx in sheets[sIdx].views.indices {
                    let view = sheets[sIdx].views[vIdx]
                    let direction = view.effectiveViewDirection
                    let baseHLR = HLREngine.computeHLR(
                        objects: objects,
                        direction: direction,
                        options: view.displayStyle.hlrOptions
                    )
                    var finalHLR = baseHLR
                    switch view.kind {
                    case .base, .projected, .auxiliary:
                        finalHLR = baseHLR
                    case .section:
                        if let hatchDef = view.hatchPattern, let bounds = baseHLR.bounds2D {
                            let hatchEdges = DrawingHatchGenerator.generateHatchLines(in: bounds, pattern: hatchDef)
                            finalHLR = HLRResult(edges: baseHLR.edges + hatchEdges, viewDirection: direction)
                        }
                    case .detail:
                        if let detailDef = view.detailDefinition {
                            let clipped = DrawingDetailProcessor.clipEdgesToCircle(
                                edges: baseHLR.edges,
                                centerMM: detailDef.centerMM,
                                radiusMM: detailDef.radiusMM
                            )
                            finalHLR = HLRResult(edges: clipped, viewDirection: direction)
                        }
                    case .broken:
                        if let breakDef = view.breakDefinition {
                            finalHLR = DrawingBreakProcessor.applyBreak(to: baseHLR, definition: breakDef)
                        }
                    }
                    sheets[sIdx].views[vIdx].cachedHLR = finalHLR
                }
            }

            // 2. Validate and synchronize annotations
            for aIdx in sheets[sIdx].annotations.indices {
                let annotation = sheets[sIdx].annotations[aIdx]

                // Check attached view
                if let viewId = annotation.viewId {
                    guard let attachedView = sheets[sIdx].views.first(where: { $0.id == viewId }) else {
                        sheets[sIdx].annotations[aIdx].isDangling = true
                        continue
                    }

                    let featureRefId = annotation.sourceFeatureId ?? annotation.attachment?.featureId ?? annotation.attachment?.topologicalReference?.sourceFeatureId
                    if let fId = featureRefId {
                        guard let feat = features.first(where: { $0.id == fId }) else {
                            sheets[sIdx].annotations[aIdx].isDangling = true
                            continue
                        }

                        if feat.isSuppressed || feat.errorState != nil {
                            sheets[sIdx].annotations[aIdx].isDangling = true
                            continue
                        }

                        // Feature is active: synchronize Hole Wizard callout or dimension
                        if case .hole(let holeParams) = feat.operation,
                           case .holeCallout(var holeData) = annotation.data {
                            holeData.holeType = holeParams.holeType
                            holeData.standard = holeParams.standard
                            holeData.sizeDesignation = holeParams.sizeDesignation
                            holeData.diameter = holeParams.diameter
                            holeData.depth = holeParams.depth
                            holeData.isThrough = holeParams.isThrough
                            holeData.counterboreDiameter = holeParams.counterboreDiameter
                            holeData.counterboreDepth = holeParams.counterboreDepth
                            holeData.countersinkDiameter = holeParams.countersinkDiameter
                            holeData.countersinkAngle = holeParams.countersinkAngle
                            if let thread = holeParams.threadMetadata?.designation ?? holeParams.sizeDesignation {
                                holeData.threadDesignation = thread
                            }
                            if !holeParams.points.isEmpty {
                                holeData.holeCount = holeParams.points.count
                            }
                            sheets[sIdx].annotations[aIdx].data = .holeCallout(holeData)
                            sheets[sIdx].annotations[aIdx].isDangling = false
                            continue
                        }

                        // Check model points reprojection
                        if let attachment = sheets[sIdx].annotations[aIdx].attachment, !attachment.modelPoints.isEmpty {
                            if case .linear(var linData) = sheets[sIdx].annotations[aIdx].data,
                               attachment.modelPoints.count >= 2 {
                                linData.startPointMM = attachedView.project(point3D: attachment.modelPoints[0])
                                linData.endPointMM = attachedView.project(point3D: attachment.modelPoints[1])
                                sheets[sIdx].annotations[aIdx].data = .linear(linData)
                            }
                        }

                        sheets[sIdx].annotations[aIdx].isDangling = false
                    } else if let attachment = annotation.attachment, !attachment.modelPoints.isEmpty {
                        // Dimension attached to 3D points without specific feature reference
                        if case .linear(var linData) = annotation.data,
                           attachment.modelPoints.count >= 2 {
                            linData.startPointMM = attachedView.project(point3D: attachment.modelPoints[0])
                            linData.endPointMM = attachedView.project(point3D: attachment.modelPoints[1])
                            sheets[sIdx].annotations[aIdx].data = .linear(linData)
                        }
                        sheets[sIdx].annotations[aIdx].isDangling = false
                    } else {
                        sheets[sIdx].annotations[aIdx].isDangling = false
                    }
                } else {
                    // Sheet-level annotation
                    let featureRefId = annotation.sourceFeatureId ?? annotation.attachment?.featureId ?? annotation.attachment?.topologicalReference?.sourceFeatureId
                    if let fId = featureRefId {
                        guard let feat = features.first(where: { $0.id == fId }) else {
                            sheets[sIdx].annotations[aIdx].isDangling = true
                            continue
                        }
                        if feat.isSuppressed || feat.errorState != nil {
                            sheets[sIdx].annotations[aIdx].isDangling = true
                            continue
                        }
                        if case .hole(let holeParams) = feat.operation,
                           case .holeCallout(var holeData) = annotation.data {
                            holeData.holeType = holeParams.holeType
                            holeData.standard = holeParams.standard
                            holeData.sizeDesignation = holeParams.sizeDesignation
                            holeData.diameter = holeParams.diameter
                            holeData.depth = holeParams.depth
                            holeData.isThrough = holeParams.isThrough
                            holeData.counterboreDiameter = holeParams.counterboreDiameter
                            holeData.counterboreDepth = holeParams.counterboreDepth
                            holeData.countersinkDiameter = holeParams.countersinkDiameter
                            holeData.countersinkAngle = holeParams.countersinkAngle
                            if let thread = holeParams.threadMetadata?.designation ?? holeParams.sizeDesignation {
                                holeData.threadDesignation = thread
                            }
                            if !holeParams.points.isEmpty {
                                holeData.holeCount = holeParams.points.count
                            }
                            sheets[sIdx].annotations[aIdx].data = .holeCallout(holeData)
                        }
                        sheets[sIdx].annotations[aIdx].isDangling = false
                    }
                }
            }
        }
    }
}

