import Foundation
import simd

/// A single sequential displacement step in an exploded view (BL-ASM-12).
public struct ExplodeStep: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var targetInstanceIds: [UUID]
    public var direction: SIMD3<Float>
    public var distance: Float
    public var hasTrail: Bool

    /// Computed 3D displacement vector along normalized direction.
    public var translation: SIMD3<Float> {
        let length = simd_length(direction)
        guard length > 1e-6 else {
            return .zero
        }
        return (direction / length) * distance
    }

    public init(
        id: UUID = UUID(),
        name: String = "Explode Step",
        targetInstanceIds: [UUID] = [],
        direction: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
        distance: Float = 50.0,
        hasTrail: Bool = true
    ) {
        self.id = id
        self.name = name
        self.targetInstanceIds = targetInstanceIds
        self.direction = direction
        self.distance = distance
        self.hasTrail = hasTrail
    }
}

/// A line segment trail representing the trajectory of a component during an explode step (BL-ASM-12).
public struct ExplodeTrail: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: UUID
    public var stepId: UUID
    public var instanceId: UUID
    public var startPoint: SIMD3<Float>
    public var endPoint: SIMD3<Float>
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        stepId: UUID,
        instanceId: UUID,
        startPoint: SIMD3<Float>,
        endPoint: SIMD3<Float>,
        isVisible: Bool = true
    ) {
        self.id = id
        self.stepId = stepId
        self.instanceId = instanceId
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.isVisible = isVisible
    }
}

/// A named exploded view configuration containing sequential steps and trail calculations (BL-ASM-12).
public struct ExplodedView: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var steps: [ExplodeStep]
    public var isCollapsed: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Exploded View",
        steps: [ExplodeStep] = [],
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.isCollapsed = isCollapsed
    }

    /// Computes cumulative 3D displacement vectors for all target component instances across all steps.
    public func cumulativeDisplacements() -> [UUID: SIMD3<Float>] {
        var displacements: [UUID: SIMD3<Float>] = [:]
        for step in steps {
            let translation = step.translation
            for targetId in step.targetInstanceIds {
                displacements[targetId, default: .zero] += translation
            }
        }
        return displacements
    }

    /// Applies cumulative step displacements to a component's base transform.
    public func transformedPosition(for instanceId: UUID, baseTransform: Transform) -> Transform {
        var result = baseTransform
        if let displacement = cumulativeDisplacements()[instanceId] {
            result.position += displacement
        }
        return result
    }

    /// Simulates sequential step displacements starting from base component positions and emits trail segments.
    public func computeTrails(instances: [ComponentInstance]) -> [ExplodeTrail] {
        var currentPositions: [UUID: SIMD3<Float>] = [:]
        func collectPositions(from list: [ComponentInstance], parentTransform: Transform) {
            for inst in list {
                let world = parentTransform * inst.transform
                currentPositions[inst.id] = world.position
                if !inst.childInstances.isEmpty {
                    collectPositions(from: inst.childInstances, parentTransform: world)
                }
            }
        }
        collectPositions(from: instances, parentTransform: .identity)

        var trails: [ExplodeTrail] = []
        for step in steps {
            let translation = step.translation
            for targetId in step.targetInstanceIds {
                guard let startPoint = currentPositions[targetId] else { continue }
                let endPoint = startPoint + translation
                currentPositions[targetId] = endPoint
                if step.hasTrail {
                    trails.append(
                        ExplodeTrail(
                            stepId: step.id,
                            instanceId: targetId,
                            startPoint: startPoint,
                            endPoint: endPoint,
                            isVisible: true
                        )
                    )
                }
            }
        }
        return trails
    }
}
