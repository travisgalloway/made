import Foundation
import simd

public typealias BodyId = SolidId

/// The fundamental topological nature of a body within a part (BL-FND-12, ADR-D2).
public enum BodyType: String, Sendable, Codable, Equatable, CaseIterable {
    case solid
    case surface
}

/// The mode of geometry generation declared by a feature on its target body (BL-FND-12, ADR-D2).
public enum BodyOperation: String, Sendable, Codable, Equatable, CaseIterable {
    /// Mints a distinct, new body in the part.
    case create
    /// Unites or joins the feature geometry into an existing target body.
    case add
    /// Subtracts the feature geometry from an existing target body.
    case cut
    /// Intersects the feature geometry with an existing target body.
    case intersect
}

extension BodyOperation {
    /// Maps a boolean operation mode to kernel BooleanOp, or nil for new body creation.
    public var booleanOp: BooleanOp? {
        switch self {
        case .create: return nil
        case .add: return .union
        case .cut: return .subtract
        case .intersect: return .intersect
        }
    }

    /// Initializes a BodyOperation from a kernel BooleanOp.
    public init?(booleanOp: BooleanOp) {
        switch booleanOp {
        case .union: self = .add
        case .subtract: self = .cut
        case .intersect: self = .intersect
        }
    }
}

/// A first-class solid or surface body within a part document (BL-FND-12).
public struct Body: Identifiable, Sendable, Codable, Equatable {
    public let id: BodyId
    public var name: String
    public var type: BodyType
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
    public var transform: Transform

    public var color: SIMD4<Float> {
        get { material.color }
        set { material.color = newValue }
    }

    public init(
        id: BodyId,
        name: String,
        type: BodyType = .solid,
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes(),
        transform: Transform = .identity
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.material = material
        self.transform = transform
    }

    public init(from object: SceneObject) {
        self.id = object.id
        self.name = object.name
        self.type = .solid
        self.isVisible = object.isVisible
        self.isLocked = object.isLocked
        self.material = object.material
        self.transform = object.transform
    }

    public func toSceneObject(def: ObjectDef) -> SceneObject {
        SceneObject(
            id: id,
            name: name,
            def: def,
            transform: transform,
            isVisible: isVisible,
            isLocked: isLocked,
            material: material
        )
    }
}
