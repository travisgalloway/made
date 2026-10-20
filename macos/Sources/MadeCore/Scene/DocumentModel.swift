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
    case imported(name: String, sourceURL: URL? = nil, data: Data? = nil)
    /// A boolean result: the operation and its operand IDs, with no replay (#35).
    case boolean(op: BooleanOp, solidA: ObjectId, solidB: ObjectId)
    /// A scripted `.part.ts` or `.part.js` source file on disk, with its last evaluated shape tree (#427).
    case part(url: URL, shape: ShapeNode? = nil)
    /// A solid extruded from a 2D sketch profile.
    case extrude(ExtrudeParams)
    
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
        }
    }
}

extension ObjectDef {
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
        case .imported(let name, _, _):
            return name.isEmpty ? "Imported mesh" : name
        case .boolean(let op, let solidA, let solidB):
            return "\(op.rawValue)(\(solidA.rawValue), \(solidB.rawValue))"
        case .part(let url, _):
            let filename = url.lastPathComponent
            return (filename.isEmpty || filename == "/") ? "part" : filename
        case .extrude(let p):
            return "h \(Self.formatDim(Float(p.distance))) mm"
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

public struct SceneObject: Identifiable, Sendable, Equatable {
    public let id: ObjectId
    public var name: String
    public var def: ObjectDef
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
    
    public init(
        id: ObjectId,
        name: String? = nil,
        def: ObjectDef,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes()
    ) {
        self.id = id
        self.name = name ?? id.rawValue
        self.def = def
        self.transform = transform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.material = material
    }
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
            let packageURL = decoder.userInfo[.packageURL] as? URL
            let sourceURL: URL? = assetPath.map { path in
                if let packageURL {
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
            self = .imported(name: name, sourceURL: sourceURL, data: nil)
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
        case .imported(let name, let sourceURL, _):
            try container.encode("imported", forKey: .kind)
            try container.encode(name, forKey: .name)
            if let sourceURL {
                let filename = sourceURL.lastPathComponent
                try container.encode("assets/\(filename)", forKey: .assetPath)
            } else if !name.isEmpty {
                let filename = (name.hasSuffix(".step") || name.hasSuffix(".stp") || name.hasSuffix(".iges") || name.hasSuffix(".igs")) ? name : "\(name).step"
                try container.encode("assets/\(filename)", forKey: .assetPath)
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
        case .imported, .boolean:
            return def
        }
    }
}

public enum DocumentMutationError: Error, Equatable, Sendable, CustomStringConvertible {
    case objectLocked(ObjectId)
    case objectNotFound(ObjectId)
    case sketchError(SketchError)
    case referenceResolutionFailed(ReferenceResolutionError)

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
        }
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
    public private(set) var settings: DocumentSettings = DocumentSettings()
    private var seq: Int = 1
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
            if case .body(let solidId) = ref.target {
                return solidId
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
                    return objects.contains(where: { $0.id == solidId })
                case .face(let feat, _), .edge(let feat, _), .vertex(let feat, _):
                    return isFeatureActive(id: feat.id) && !feat.isSuppressed
                }
            case .failure:
                return false
            }
        }
        if validSelection != _selection {
            selection = validSelection
        }
        if let selId = _selectedId, !objects.contains(where: { $0.id == selId }) {
            selectedId = nil
        }
    }
    
    public init(settings: DocumentSettings = DocumentSettings()) {
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
        syncObjectsFromFeatures()
        self.seq = Self.computeMaxSequence(features: self.features)
        setupUndoObservers()
    }

    public init(features: [Feature], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
        self.features = features
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

    public init(objects: [SceneObject], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
        let convertedFeatures = objects.map { Feature(from: $0) }
        self.features = convertedFeatures
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

    public func reset(with newFeatures: [Feature], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
        undoManager?.removeAllActions()
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
            self.selectedId = activeFeatures.compactMap(\.outputSolidId).first
        }
        self.selectedSubElement = nil
        activeInteractiveParamEdit = nil
        activeInteractiveSketchDrag = nil
        undoStateVersion += 1
    }

    public func reset(with newObjects: [SceneObject], selection: Set<Reference>? = nil, selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
        undoManager?.removeAllActions()
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
            self.selectedId = activeFeatures.compactMap(\.outputSolidId).first
        }
        self.selectedSubElement = nil
        activeInteractiveParamEdit = nil
        activeInteractiveSketchDrag = nil
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
            case .imported(let name, let sourceURL, let data):
                if let sourceURL {
                    let filename = sourceURL.lastPathComponent
                    guard !filename.isEmpty && filename != "/" else { break }
                    let newURL = packageURL.appendingPathComponent("assets/\(filename)")
                    if sourceURL != newURL {
                        objects[i].def = .imported(name: name, sourceURL: newURL, data: data)
                    }
                }
            default:
                break
            }
        }
    }

    private func syncObjectsFromFeatures() {
        objects = activeFeatures.compactMap { $0.toSceneObject() }
        bodies = objects.map { Body(from: $0) }
        pruneInvalidSelection()
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
        features[index].errorState = error
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
        case .imported, .boolean, .part, .sketch, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem:
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
        } else if case .imported(let name, _, _) = clamped, !name.isEmpty {
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

    @discardableResult
    public func removeObject(id: ObjectId, actionName: String? = nil, registerUndo: Bool = true) -> Result<Void, DocumentMutationError> {
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
    
    @discardableResult
    public func setParam(id: ObjectId, key: String, value: Float, actionName: String? = nil) -> Result<Void, DocumentMutationError> {
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else {
            return .failure(.objectNotFound(id))
        }
        guard !features[index].isLocked else {
            return .failure(.objectLocked(id))
        }
        guard let oldValue = paramValue(for: id, key: key) else {
            return .success(())
        }
        let clampedValue: Float
        var updatedFeature = features[index]
        switch updatedFeature.operation {
        case .primitive(.box(var params)):
            switch key {
            case "width": params.width = DocumentLimits.clampBox(key: "width", value: value)
            case "depth": params.depth = DocumentLimits.clampBox(key: "depth", value: value)
            case "height": params.height = DocumentLimits.clampBox(key: "height", value: value)
            default: break
            }
            clampedValue = (key == "width" ? params.width : (key == "depth" ? params.depth : params.height))
            updatedFeature.operation = .primitive(.box(params))
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)
            
        case .primitive(.cylinder(var params)):
            switch key {
            case "radius": params.radius = DocumentLimits.clampCylinder(key: "radius", value: value)
            case "height": params.height = DocumentLimits.clampCylinder(key: "height", value: value)
            default: break
            }
            clampedValue = (key == "radius" ? params.radius : params.height)
            updatedFeature.operation = .primitive(.cylinder(params))
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)

        case .primitive(.sphere(var params)):
            switch key {
            case "radius": params.radius = DocumentLimits.clampSphere(key: "radius", value: value)
            default: break
            }
            clampedValue = params.radius
            updatedFeature.operation = .primitive(.sphere(params))
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)

        case .primitive(.cone(var params)):
            switch key {
            case "bottomRadius": params.bottomRadius = DocumentLimits.clampCone(key: "bottomRadius", value: value)
            case "topRadius": params.topRadius = DocumentLimits.clampCone(key: "topRadius", value: value)
            case "height": params.height = DocumentLimits.clampCone(key: "height", value: value)
            default: break
            }
            clampedValue = (key == "bottomRadius" ? params.bottomRadius : (key == "topRadius" ? params.topRadius : params.height))
            updatedFeature.operation = .primitive(.cone(params))
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)

        case .primitive(.torus(var params)):
            switch key {
            case "majorRadius": params.majorRadius = DocumentLimits.clampTorus(key: "majorRadius", value: value, minorRadius: params.minorRadius)
            case "minorRadius": params.minorRadius = DocumentLimits.clampTorus(key: "minorRadius", value: value, majorRadius: params.majorRadius)
            default: break
            }
            clampedValue = (key == "majorRadius" ? params.majorRadius : params.minorRadius)
            updatedFeature.operation = .primitive(.torus(params))
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)

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
            updatedFeature.operation = .primitive(.wedge(params))
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)
            
        case .extrude(var data):
            switch key {
            case "distance":
                data.distance = Double(DocumentLimits.clampExtrude(key: "distance", value: value))
            default: break
            }
            clampedValue = Float(data.distance)
            updatedFeature.operation = .extrude(data)
            updatedFeature.inputExpressions[key] = FeatureExpression(value: clampedValue)

        case .imported, .boolean, .part, .sketch, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem:
            return .success(())
        }

        if clampedValue == oldValue {
            return .success(())
        }

        if let active = activeInteractiveParamEdit, active.id == id, active.key == key {
            features[index] = updatedFeature
            return .success(())
        }

        let effectiveActionName = actionName ?? "Change \(key.capitalized)"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.setParam(id: id, key: key, value: oldValue, actionName: effectiveActionName)
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
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        guard !features[index].isLocked else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard features[index].name != trimmed else { return }
        features[index].name = trimmed
    }
    
    public func setVisibility(id: ObjectId, isVisible: Bool) {
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        features[index].isVisible = isVisible
    }
    
    public func setLocked(id: ObjectId, isLocked: Bool) {
        guard let index = features.firstIndex(where: { $0.outputSolidId == id }) else { return }
        features[index].isLocked = isLocked
    }
    
    @discardableResult
    public func setMaterial(id: ObjectId, material: MaterialAttributes) -> Result<Void, DocumentMutationError> {
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
}

