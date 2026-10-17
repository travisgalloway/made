import Foundation

/// A geometric or dimensional constraint applied to 2D sketch entities (ADR-D4, #37).
public struct SketchConstraint: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: Kind
    public var entityIds: [UUID]
    public var referenceEntityId: UUID?
    public var isDriven: Bool
    public var isTemporary: Bool

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case parallel
        case perpendicular
        case tangent
        case concentric
        case symmetric
        case coincident
        case horizontal
        case vertical
    }

    public init(
        id: UUID = UUID(),
        kind: Kind,
        entityIds: [UUID],
        referenceEntityId: UUID? = nil,
        isDriven: Bool = false,
        isTemporary: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.entityIds = entityIds
        self.referenceEntityId = referenceEntityId
        self.isDriven = isDriven
        self.isTemporary = isTemporary
    }
}
