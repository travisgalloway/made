import Foundation
import simd

public typealias ComponentInstanceId = UUID

/// Target reference for an assembly component instance.
public enum ComponentReference: Sendable, Codable, Equatable, Hashable {
    case internalPart(name: String, bodyId: BodyId? = nil)
    case externalDocument(url: URL, partName: String? = nil)
    case subassembly(name: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case bodyId
        case url
        case partName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "internalPart":
            let name = try container.decode(String.self, forKey: .name)
            let bodyId = try container.decodeIfPresent(BodyId.self, forKey: .bodyId)
            self = .internalPart(name: name, bodyId: bodyId)
        case "externalDocument":
            let url = try container.decode(URL.self, forKey: .url)
            let partName = try container.decodeIfPresent(String.self, forKey: .partName)
            self = .externalDocument(url: url, partName: partName)
        case "subassembly":
            let name = try container.decode(String.self, forKey: .name)
            self = .subassembly(name: name)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown ComponentReference type: '\(type)'")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .internalPart(let name, let bodyId):
            try container.encode("internalPart", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(bodyId, forKey: .bodyId)
        case .externalDocument(let url, let partName):
            try container.encode("externalDocument", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(partName, forKey: .partName)
        case .subassembly(let name):
            try container.encode("subassembly", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

/// Kinematic behavior mode for subassemblies (BL-ASM-07, #168).
public enum SubassemblyBehavior: String, Sendable, Codable, CaseIterable, Equatable {
    case rigid
    case flexible
}

/// An instance of a part positioned in 3D assembly space.
public struct ComponentInstance: Identifiable, Sendable, Codable, Equatable, PropertyContainer {
    public var id: ComponentInstanceId
    public var name: String
    public var reference: ComponentReference
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var isGrounded: Bool
    public var material: MaterialAttributes
    public var subassemblyBehavior: SubassemblyBehavior
    public var childInstances: [ComponentInstance]
    public var childConstraints: [AssemblyConstraint]
    public var patternId: UUID?
    public var mirrorId: UUID?
    public var configurationName: String?
    public var configurationId: UUID?
    public var metadata: [String: String]

    public var isFixed: Bool {
        get { isGrounded }
        set { isGrounded = newValue }
    }

    public var isSubassembly: Bool {
        if case .subassembly = reference { return true }
        return !childInstances.isEmpty
    }

    public var solidId: SolidId {
        SolidId("component-\(id.uuidString)")
    }

    public init(
        id: ComponentInstanceId = UUID(),
        name: String,
        reference: ComponentReference,
        transform: Transform = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        isGrounded: Bool = false,
        material: MaterialAttributes = MaterialAttributes(),
        subassemblyBehavior: SubassemblyBehavior = .rigid,
        childInstances: [ComponentInstance] = [],
        childConstraints: [AssemblyConstraint] = [],
        patternId: UUID? = nil,
        mirrorId: UUID? = nil,
        configurationName: String? = nil,
        configurationId: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.transform = transform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isGrounded = isGrounded
        self.material = material
        self.subassemblyBehavior = subassemblyBehavior
        self.childInstances = childInstances
        self.childConstraints = childConstraints
        self.patternId = patternId
        self.mirrorId = mirrorId
        self.configurationName = configurationName
        self.configurationId = configurationId
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case reference
        case transform
        case isVisible
        case isLocked
        case isGrounded
        case material
        case subassemblyBehavior
        case childInstances
        case childConstraints
        case patternId
        case mirrorId
        case configurationName
        case configurationId
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.reference = try container.decode(ComponentReference.self, forKey: .reference)
        self.transform = try container.decodeIfPresent(Transform.self, forKey: .transform) ?? .identity
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.isGrounded = try container.decodeIfPresent(Bool.self, forKey: .isGrounded) ?? false
        self.material = try container.decodeIfPresent(MaterialAttributes.self, forKey: .material) ?? MaterialAttributes()
        self.subassemblyBehavior = try container.decodeIfPresent(SubassemblyBehavior.self, forKey: .subassemblyBehavior) ?? .rigid
        self.childInstances = try container.decodeIfPresent([ComponentInstance].self, forKey: .childInstances) ?? []
        self.childConstraints = try container.decodeIfPresent([AssemblyConstraint].self, forKey: .childConstraints) ?? []
        self.patternId = try container.decodeIfPresent(UUID.self, forKey: .patternId)
        self.mirrorId = try container.decodeIfPresent(UUID.self, forKey: .mirrorId)
        self.configurationName = try container.decodeIfPresent(String.self, forKey: .configurationName)
        self.configurationId = try container.decodeIfPresent(UUID.self, forKey: .configurationId)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(reference, forKey: .reference)
        try container.encode(transform, forKey: .transform)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isGrounded, forKey: .isGrounded)
        try container.encode(material, forKey: .material)
        try container.encode(subassemblyBehavior, forKey: .subassemblyBehavior)
        try container.encode(childInstances, forKey: .childInstances)
        try container.encode(childConstraints, forKey: .childConstraints)
        try container.encodeIfPresent(patternId, forKey: .patternId)
        try container.encodeIfPresent(mirrorId, forKey: .mirrorId)
        try container.encodeIfPresent(configurationName, forKey: .configurationName)
        try container.encodeIfPresent(configurationId, forKey: .configurationId)
        if !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }
    }

    public func toSceneObject() -> SceneObject {
        let def: ObjectDef
        switch reference {
        case .internalPart(let refName, _):
            def = .imported(name: refName, sourceURL: nil, data: nil, isLinked: false)
        case .externalDocument(let url, let partName):
            let displayName = partName ?? url.deletingPathExtension().lastPathComponent
            def = .imported(name: displayName, sourceURL: url, data: nil, isLinked: true)
        case .subassembly(let name):
            def = .imported(name: name, sourceURL: nil, data: nil, isLinked: false)
        }
        return SceneObject(
            id: solidId,
            name: name,
            def: def,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked || isGrounded,
            material: material,
            metadata: metadata
        )
    }

    /// Recursively projects scene objects for this instance and its children in world coordinates.
    public func toSceneObjects(parentTransform: Transform = .identity) -> [SceneObject] {
        let worldTransform = parentTransform * transform
        if childInstances.isEmpty {
            var obj = toSceneObject()
            obj.transform = worldTransform
            return [obj]
        } else {
            return childInstances.flatMap { child in
                child.toSceneObjects(parentTransform: worldTransform)
            }
        }
    }

    /// Returns a list of all component instances in the hierarchy.
    public func allComponentInstances(recursive: Bool = true, includeSelf: Bool = true) -> [ComponentInstance] {
        var result: [ComponentInstance] = includeSelf ? [self] : []
        if recursive {
            for child in childInstances {
                result.append(contentsOf: child.allComponentInstances(recursive: true, includeSelf: true))
            }
        } else {
            result.append(contentsOf: childInstances)
        }
        return result
    }

    /// Recursively finds a component instance by UUID, returning the instance and its immediate parent ID if nested.
    public func findComponent(id: UUID) -> (instance: ComponentInstance, parentId: UUID?)? {
        if self.id == id { return (self, nil) }
        for child in childInstances {
            if child.id == id { return (child, self.id) }
            if let found = child.findComponent(id: id) {
                return (found.instance, found.parentId ?? self.id)
            }
        }
        return nil
    }

    /// Recursively finds a component instance by SolidId, returning the instance and its immediate parent ID if nested.
    public func findComponent(solidId: SolidId) -> (instance: ComponentInstance, parentId: UUID?)? {
        if self.solidId == solidId { return (self, nil) }
        for child in childInstances {
            if child.solidId == solidId { return (child, self.id) }
            if let found = child.findComponent(solidId: solidId) {
                return (found.instance, found.parentId ?? self.id)
            }
        }
        return nil
    }
}
