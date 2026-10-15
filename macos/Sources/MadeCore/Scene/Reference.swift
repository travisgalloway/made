import Foundation

/// Supported target entities for parametric feature references (ADR-D2, ADR-D3).
public enum ReferenceTarget: Sendable, Equatable, Hashable {
    case feature(UUID)
    case sketchEntity(featureId: UUID, entityId: UUID)
    case body(SolidId)
    case face(TopologicalReference)
    case edge(TopologicalReference)
    case vertex(TopologicalReference)
}

extension ReferenceTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case featureId
        case entityId
        case solidId
        case topologicalReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "feature":
            let id = try container.decode(UUID.self, forKey: .featureId)
            self = .feature(id)
        case "sketchEntity":
            let featureId = try container.decode(UUID.self, forKey: .featureId)
            let entityId = try container.decode(UUID.self, forKey: .entityId)
            self = .sketchEntity(featureId: featureId, entityId: entityId)
        case "body":
            let solidId = try container.decode(SolidId.self, forKey: .solidId)
            self = .body(solidId)
        case "face":
            let ref = try container.decode(TopologicalReference.self, forKey: .topologicalReference)
            self = .face(ref)
        case "edge":
            let ref = try container.decode(TopologicalReference.self, forKey: .topologicalReference)
            self = .edge(ref)
        case "vertex":
            let ref = try container.decode(TopologicalReference.self, forKey: .topologicalReference)
            self = .vertex(ref)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown ReferenceTarget type: '\(type)'")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .feature(let id):
            try container.encode("feature", forKey: .type)
            try container.encode(id, forKey: .featureId)
        case .sketchEntity(let featureId, let entityId):
            try container.encode("sketchEntity", forKey: .type)
            try container.encode(featureId, forKey: .featureId)
            try container.encode(entityId, forKey: .entityId)
        case .body(let solidId):
            try container.encode("body", forKey: .type)
            try container.encode(solidId, forKey: .solidId)
        case .face(let ref):
            try container.encode("face", forKey: .type)
            try container.encode(ref, forKey: .topologicalReference)
        case .edge(let ref):
            try container.encode("edge", forKey: .type)
            try container.encode(ref, forKey: .topologicalReference)
        case .vertex(let ref):
            try container.encode("vertex", forKey: .type)
            try container.encode(ref, forKey: .topologicalReference)
        }
    }
}

/// Strongly typed parametric reference connecting features, entities, solids, or topological subelements (ADR-D2, ADR-D3).
public struct Reference: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: UUID
    public var role: String?
    public var target: ReferenceTarget

    public init(id: UUID = UUID(), role: String? = nil, target: ReferenceTarget) {
        self.id = id
        self.role = role
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decodeIfPresent(String.self, forKey: .role)
        self.target = try container.decode(ReferenceTarget.self, forKey: .target)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(target, forKey: .target)
    }

    // MARK: - Factory Helpers

    public static func feature(_ id: UUID, role: String? = nil) -> Reference {
        Reference(role: role, target: .feature(id))
    }

    public static func sketchEntity(featureId: UUID, entityId: UUID, role: String? = nil) -> Reference {
        Reference(role: role, target: .sketchEntity(featureId: featureId, entityId: entityId))
    }

    public static func body(_ id: SolidId, role: String? = nil) -> Reference {
        Reference(role: role, target: .body(id))
    }

    public static func face(_ ref: TopologicalReference, role: String? = nil) -> Reference {
        Reference(role: role, target: .face(ref))
    }

    public static func edge(_ ref: TopologicalReference, role: String? = nil) -> Reference {
        Reference(role: role, target: .edge(ref))
    }

    public static func vertex(_ ref: TopologicalReference, role: String? = nil) -> Reference {
        Reference(role: role, target: .vertex(ref))
    }

    // MARK: - Primary Feature Accessor

    /// Extracts the primary feature UUID if directly identifiable from the reference target.
    public var referencedFeatureId: UUID? {
        switch target {
        case .feature(let id):
            return id
        case .sketchEntity(let featureId, _):
            return featureId
        case .body:
            return nil
        case .face(let topRef), .edge(let topRef), .vertex(let topRef):
            return topRef.sourceFeatureId
        }
    }
}
