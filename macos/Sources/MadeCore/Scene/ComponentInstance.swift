import Foundation
import simd

public typealias ComponentInstanceId = UUID

/// Target reference for an assembly component instance.
public enum ComponentReference: Sendable, Codable, Equatable, Hashable {
    case internalPart(name: String, bodyId: BodyId? = nil)
    case externalDocument(url: URL, partName: String? = nil)

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
        }
    }
}

/// An instance of a part positioned in 3D assembly space.
public struct ComponentInstance: Identifiable, Sendable, Codable, Equatable {
    public var id: ComponentInstanceId
    public var name: String
    public var reference: ComponentReference
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var isGrounded: Bool
    public var material: MaterialAttributes

    public var isFixed: Bool {
        get { isGrounded }
        set { isGrounded = newValue }
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
        material: MaterialAttributes = MaterialAttributes()
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.transform = transform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isGrounded = isGrounded
        self.material = material
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
    }

    public func toSceneObject() -> SceneObject {
        let def: ObjectDef
        switch reference {
        case .internalPart(let refName, _):
            def = .imported(name: refName, sourceURL: nil, data: nil, isLinked: false)
        case .externalDocument(let url, let partName):
            let displayName = partName ?? url.deletingPathExtension().lastPathComponent
            def = .imported(name: displayName, sourceURL: url, data: nil, isLinked: true)
        }
        return SceneObject(
            id: solidId,
            name: name,
            def: def,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked || isGrounded,
            material: material
        )
    }
}
