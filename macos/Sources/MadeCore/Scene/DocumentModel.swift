import Foundation
import Observation
import simd

public typealias ObjectId = SolidId

public enum ObjectDef: Sendable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams)
    case imported(name: String, sourceURL: URL? = nil, data: Data? = nil)
    /// A boolean result: the operation and its operand IDs, with no replay (#35).
    case boolean(op: BooleanOp, solidA: ObjectId, solidB: ObjectId)
    /// A scripted `.part.ts` or `.part.js` source file on disk, with its last evaluated shape tree (#427).
    case part(url: URL, shape: ShapeNode? = nil)
    
    public var kind: String {
        switch self {
        case .box: return "box"
        case .cylinder: return "cylinder"
        case .imported: return "imported"
        case .boolean: return "boolean"
        case .part: return "part"
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
        case .imported(let name, _, _):
            return name.isEmpty ? "Imported mesh" : name
        case .boolean(let op, let solidA, let solidB):
            return "\(op.rawValue)(\(solidA.rawValue), \(solidB.rawValue))"
        case .part(let url, _):
            let filename = url.lastPathComponent
            return (filename.isEmpty || filename == "/") ? "part" : filename
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
        case "imported":
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            let assetPath = try container.decodeIfPresent(String.self, forKey: .assetPath)
            let sourceURL = assetPath.map { URL(fileURLWithPath: $0) }
            self = .imported(name: name, sourceURL: sourceURL, data: nil)
        case "boolean":
            let op = try container.decode(BooleanOp.self, forKey: .op)
            let solidA = try container.decode(ObjectId.self, forKey: .solidA)
            let solidB = try container.decode(ObjectId.self, forKey: .solidB)
            self = .boolean(op: op, solidA: solidA, solidB: solidB)
        case "part":
            let urlString = try container.decode(String.self, forKey: .url)
            let url: URL
            if urlString.hasPrefix("file://"), let parsed = URL(string: urlString) {
                url = parsed
            } else {
                url = URL(fileURLWithPath: urlString)
            }
            self = DocumentLimits.clamp(.part(url: url, shape: nil))
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
            if url.path.contains("/parts/") || url.path.hasPrefix("parts/") {
                try container.encode("parts/\(filename)", forKey: .url)
            } else {
                try container.encode(url.isFileURL ? url.path : url.absoluteString, forKey: .url)
            }
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

    public static func clamp(_ def: ObjectDef) -> ObjectDef {
        switch def {
        case .box(let p):
            return .box(BoxParams(width: boxWidth.clamp(p.width), depth: boxDepth.clamp(p.depth), height: boxHeight.clamp(p.height)))
        case .cylinder(let p):
            return .cylinder(CylinderParams(radius: cylinderRadius.clamp(p.radius), height: cylinderHeight.clamp(p.height)))
        case .part(let url, let shape):
            return .part(url: url.standardizedFileURL, shape: shape)
        case .imported, .boolean:
            return def
        }
    }
}

public enum DocumentMutationError: Error, Equatable, Sendable, CustomStringConvertible {
    case objectLocked(ObjectId)
    case objectNotFound(ObjectId)

    public var description: String {
        switch self {
        case .objectLocked(let id):
            return "Solid '\(id.rawValue)' is locked and cannot be modified"
        case .objectNotFound(let id):
            return "Solid '\(id.rawValue)' not found"
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
            if newValue == nil || _selectedSubElement?.solidId != newValue {
                selectedSubElement = nil
            }
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
        }
    }
    
    public init(settings: DocumentSettings = DocumentSettings()) {
        // Initialize with default box and cylinder matching document.svelte.ts
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
        self._selectedId = boxSolidId
        self.settings = settings
        syncObjectsFromFeatures()
        self.seq = Self.computeMaxSequence(features: self.features)
        setupUndoObservers()
    }

    public init(features: [Feature], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
        self.features = features
        if let idx = rollbackIndex {
            let clamped = min(max(0, idx), features.count)
            self.rollbackIndex = (clamped >= features.count) ? nil : clamped
        } else {
            self.rollbackIndex = nil
        }
        self.settings = settings ?? DocumentSettings()
        syncObjectsFromFeatures()
        self._selectedId = selectedId ?? activeFeatures.compactMap(\.outputSolidId).first
        self.seq = Self.computeMaxSequence(features: features)
        setupUndoObservers()
    }

    public init(objects: [SceneObject], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
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
        self._selectedId = selectedId ?? activeFeatures.compactMap(\.outputSolidId).first
        self.seq = Self.computeMaxSequence(objects: objects)
        setupUndoObservers()
    }

    public func reset(with newFeatures: [Feature], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
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
        self.selectedId = selectedId ?? activeFeatures.compactMap(\.outputSolidId).first
        self.selectedSubElement = nil
        activeInteractiveParamEdit = nil
        undoStateVersion += 1
    }

    public func reset(with newObjects: [SceneObject], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, settings: DocumentSettings? = nil) {
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
        self.selectedId = selectedId ?? activeFeatures.compactMap(\.outputSolidId).first
        self.selectedSubElement = nil
        activeInteractiveParamEdit = nil
        undoStateVersion += 1
    }

    private func syncObjectsFromFeatures() {
        objects = activeFeatures.compactMap { $0.toSceneObject() }
        bodies = objects.map { Body(from: $0) }
        if let selected = _selectedId, !objects.contains(where: { $0.id == selected }) {
            selectedId = nil
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
        newSettings.tolerances = tolerances
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
    public func removeFeature(id: UUID) -> Result<Void, DocumentMutationError> {
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

        let redoName = undoManager?.isUndoing == true ? "Add \(removedFeature.name)" : "Delete \(removedFeature.name)"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertFeature(removedFeature, at: removedIndex, actionName: redoName)
                target.rollbackIndex = previousRollback
                target.undoManager?.setActionName(redoName)
                if let solidId = removedFeature.outputSolidId {
                    target.onUndoRedoMutation?(.added(solidId))
                }
            }
        }
        undoManager?.setActionName(redoName)
        undoStateVersion += 1
        return .success(())
    }

    @discardableResult
    public func insertFeature(_ feature: Feature, at index: Int, actionName: String? = nil) -> Result<Void, DocumentMutationError> {
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
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.removeFeature(id: feature.id)
                target.rollbackIndex = previousRollback
                target.undoManager?.setActionName(undoName)
                if let solidId = feature.outputSolidId {
                    target.onUndoRedoMutation?(.removed(solidId))
                }
            }
        }
        undoManager?.setActionName(undoName)
        undoStateVersion += 1
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
        case .primitive, .part, .imported:
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
        case .imported, .boolean, .part, .sketch, .extrude:
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
    public func addObject(def: ObjectDef, transform: Transform = .identity, material: MaterialAttributes? = nil) -> ObjectId {
        addObject(reserveId(for: def), def: def, transform: transform, material: material)
    }
    
    /// Advances the sequence and returns an ID no object has used; the caller may never add it.
    public func reserveId(for def: ObjectDef) -> ObjectId {
        seq += 1
        return ObjectId("\(def.kind)-\(seq)")
    }
    
    /// Adds an object under an ID from `reserveId(for:)`, so a kernel call can use the ID before the object exists.
    @discardableResult
    public func addObject(_ id: ObjectId, def: ObjectDef, transform: Transform = .identity, material: MaterialAttributes? = nil) -> ObjectId {
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

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.removeObject(id: id)
                target.rollbackIndex = previousRollback
                guard case .success = res else { return }
                target.undoManager?.setActionName("Add \(clamped.kind.capitalized)")
                target.onUndoRedoMutation?(.removed(id))
            }
        }
        undoManager?.setActionName("Add \(clamped.kind.capitalized)")
        undoStateVersion += 1
        return id
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
    public func removeObject(id: ObjectId) -> Result<Void, DocumentMutationError> {
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

        let kind = removedFeature.toSceneObject()?.def.kind.capitalized ?? "Solid"
        let redoName = undoManager?.isUndoing == true ? "Add \(kind)" : "Delete \(removedFeature.name)"
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                _ = target.insertFeature(removedFeature, at: removedIndex, actionName: redoName)
                target.rollbackIndex = previousRollback
                target.undoManager?.setActionName(redoName)
                target.onUndoRedoMutation?(.added(id))
            }
        }
        undoManager?.setActionName(redoName)
        undoStateVersion += 1
        return .success(())
    }
    
    @discardableResult
    public func setParam(id: ObjectId, key: String, value: Float) -> Result<Void, DocumentMutationError> {
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
            
        case .imported, .boolean, .part, .sketch, .extrude:
            return .success(())
        }

        if clampedValue == oldValue {
            return .success(())
        }

        if let active = activeInteractiveParamEdit, active.id == id, active.key == key {
            features[index] = updatedFeature
            return .success(())
        }

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.setParam(id: id, key: key, value: oldValue)
                guard case .success = res else { return }
                target.undoManager?.setActionName("Change \(key.capitalized)")
                target.onUndoRedoMutation?(.paramChanged(id, key: key, value: oldValue))
            }
        }
        undoManager?.setActionName("Change \(key.capitalized)")
        undoStateVersion += 1
        features[index] = updatedFeature
        return .success(())
    }
    
    @discardableResult
    public func setTransform(id: ObjectId, transform: Transform) -> Result<Void, DocumentMutationError> {
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

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let res = target.setTransform(id: id, transform: oldTransform)
                guard case .success = res else { return }
                target.undoManager?.setActionName("Move Solid")
                target.onUndoRedoMutation?(.transformChanged(id, transform: oldTransform))
            }
        }
        undoManager?.setActionName("Move Solid")
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

