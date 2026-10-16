import Foundation
import CryptoKit

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

    public static func deterministicId(target: ReferenceTarget, role: String?) -> UUID {
        var hasher = SHA256()
        if let role {
            hasher.update(data: Data(role.utf8))
        }
        switch target {
        case .feature(let featId):
            hasher.update(data: Data("feature".utf8))
            hasher.update(data: Data(featId.uuidString.utf8))
        case .sketchEntity(let featId, let entityId):
            hasher.update(data: Data("sketchEntity".utf8))
            hasher.update(data: Data(featId.uuidString.utf8))
            hasher.update(data: Data(entityId.uuidString.utf8))
        case .body(let solidId):
            hasher.update(data: Data("body".utf8))
            hasher.update(data: Data(solidId.rawValue.utf8))
        case .face(let topRef):
            hasher.update(data: Data("face".utf8))
            hasher.update(data: Data(topRef.id.uuidString.utf8))
        case .edge(let topRef):
            hasher.update(data: Data("edge".utf8))
            hasher.update(data: Data(topRef.id.uuidString.utf8))
        case .vertex(let topRef):
            hasher.update(data: Data("vertex".utf8))
            hasher.update(data: Data(topRef.id.uuidString.utf8))
        }
        let digest = hasher.finalize()
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public init(id: UUID? = nil, role: String? = nil, target: ReferenceTarget) {
        self.id = id ?? Self.deterministicId(target: target, role: role)
        self.role = role
        self.target = target
    }

    public static func == (lhs: Reference, rhs: Reference) -> Bool {
        lhs.role == rhs.role && lhs.target == rhs.target
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(target)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decodeIfPresent(String.self, forKey: .role)
        let target = try container.decode(ReferenceTarget.self, forKey: .target)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.deterministicId(target: target, role: role)
        self.id = id
        self.role = role
        self.target = target
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
