import Foundation

/// Declarative container holding 2D sketch geometry, active constraints, and fixed entity anchors (ADR-D4, #37).
public struct ConstraintSystem: Sendable, Codable, Equatable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public var fixedEntityIds: Set<UUID>

    public init(
        entities: [SketchEntity] = [],
        constraints: [SketchConstraint] = [],
        fixedEntityIds: Set<UUID> = []
    ) {
        self.entities = entities
        self.constraints = constraints
        self.fixedEntityIds = fixedEntityIds
    }

    /// Parameter layout mapping each entity to its slice in a flattened continuous parameter vector.
    public struct EntityParamRange: Sendable, Equatable {
        public var entityId: UUID
        public var kind: String
        public var startIndex: Int
        public var count: Int
    }

    /// Computes the parameter ranges for all entities in the system.
    public func parameterRanges() -> [EntityParamRange] {
        var ranges: [EntityParamRange] = []
        var offset = 0
        for entity in entities {
            let count: Int
            switch entity.kind {
            case "line":
                count = 4 // startX, startY, endX, endY
            case "circle":
                count = 3 // centerX, centerY, radius
            case "arc":
                count = 6 // startX, startY, endX, endY, centerX, centerY
            default:
                count = 0
            }
            ranges.append(EntityParamRange(entityId: entity.id, kind: entity.kind, startIndex: offset, count: count))
            offset += count
        }
        return ranges
    }

    /// Packs the entities into a continuous parameter vector X.
    public func packParameters() -> [Double] {
        var params: [Double] = []
        for entity in entities {
            switch entity.kind {
            case "line":
                params.append(entity.data["startX"] ?? 0.0)
                params.append(entity.data["startY"] ?? 0.0)
                params.append(entity.data["endX"] ?? 0.0)
                params.append(entity.data["endY"] ?? 0.0)
            case "circle":
                params.append(entity.data["centerX"] ?? 0.0)
                params.append(entity.data["centerY"] ?? 0.0)
                params.append(entity.data["radius"] ?? 10.0)
            case "arc":
                params.append(entity.data["startX"] ?? 0.0)
                params.append(entity.data["startY"] ?? 0.0)
                params.append(entity.data["endX"] ?? 0.0)
                params.append(entity.data["endY"] ?? 0.0)
                params.append(entity.data["centerX"] ?? 0.0)
                params.append(entity.data["centerY"] ?? 0.0)
            default:
                break
            }
        }
        return params
    }

    /// Unpacks a continuous parameter vector X into updated SketchEntities matching the system's template.
    public func unpackParameters(_ params: [Double]) -> [SketchEntity] {
        var result: [SketchEntity] = []
        var offset = 0
        for entity in entities {
            var copy = entity
            switch entity.kind {
            case "line":
                if offset + 4 <= params.count {
                    copy.data["startX"] = params[offset]
                    copy.data["startY"] = params[offset + 1]
                    copy.data["endX"] = params[offset + 2]
                    copy.data["endY"] = params[offset + 3]
                    offset += 4
                }
            case "circle":
                if offset + 3 <= params.count {
                    copy.data["centerX"] = params[offset]
                    copy.data["centerY"] = params[offset + 1]
                    copy.data["radius"] = max(1e-4, params[offset + 2])
                    offset += 3
                }
            case "arc":
                if offset + 6 <= params.count {
                    copy.data["startX"] = params[offset]
                    copy.data["startY"] = params[offset + 1]
                    copy.data["endX"] = params[offset + 2]
                    copy.data["endY"] = params[offset + 3]
                    copy.data["centerX"] = params[offset + 4]
                    copy.data["centerY"] = params[offset + 5]
                    offset += 6
                }
            default:
                break
            }
            result.append(copy)
        }
        return result
    }
}

/// Target coordinate descriptor for interactive dragging operations.
public struct DragTarget: Sendable, Codable, Equatable {
    public var entityId: UUID
    public var endpoint: EndpointTarget?
    public var targetPosition: SIMD2<Double>

    public enum EndpointTarget: String, Sendable, Codable {
        case start
        case end
        case center
    }

    public init(entityId: UUID, endpoint: EndpointTarget? = nil, targetPosition: SIMD2<Double>) {
        self.entityId = entityId
        self.endpoint = endpoint
        self.targetPosition = targetPosition
    }
}
