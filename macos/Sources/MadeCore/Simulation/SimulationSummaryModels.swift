import Foundation
import simd

/// Reaction force and moment resultant at a boundary constraint fixture (ADR-D5, BL-RES-06, #326).
public struct SimulationConstraintReaction: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// ID of the constrained fixture.
    public var id: UUID
    /// Display name of the fixture.
    public var fixtureName: String
    /// Resultant reaction force vector in canonical Newtons (N).
    public var reactionForce: SIMD3<Double>
    /// Resultant reaction moment vector about reference centroid in canonical Newton-meters (N·m).
    public var reactionMoment: SIMD3<Double>
    /// Reference centroid coordinates of the constrained nodes in canonical millimeters (mm).
    public var referencePoint: SIMD3<Double>
    /// Number of mesh nodes participating in this constraint.
    public var nodeCount: Int
    /// Optional per-node reaction force vectors in canonical Newtons (N).
    public var nodalReactionForces: [Int: SIMD3<Double>]?

    public init(
        id: UUID,
        fixtureName: String,
        reactionForce: SIMD3<Double>,
        reactionMoment: SIMD3<Double>,
        referencePoint: SIMD3<Double>,
        nodeCount: Int,
        nodalReactionForces: [Int: SIMD3<Double>]? = nil
    ) {
        self.id = id
        self.fixtureName = fixtureName
        self.reactionForce = reactionForce
        self.reactionMoment = reactionMoment
        self.referencePoint = referencePoint
        self.nodeCount = nodeCount
        self.nodalReactionForces = nodalReactionForces
    }
}

/// Partitioned result summary extrema and statistics for an individual body or solid target (ADR-D5, BL-RES-06, #326).
public struct SimulationBodySummary: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Target geometry reference ID or synthetic body UUID.
    public var id: UUID
    /// Display name of the body or solid partition.
    public var bodyName: String
    /// Number of mesh nodes associated with this body.
    public var nodeCount: Int
    /// Number of finite volume elements associated with this body.
    public var elementCount: Int
    /// Maximum von Mises stress within this body in MPa.
    public var maxVonMisesStress: Double?
    /// Maximum displacement magnitude within this body in mm.
    public var maxDisplacement: Double?
    /// Minimum Factor of Safety within this body.
    public var minFactorOfSafety: Double?
    /// Maximum temperature within this body in °C.
    public var maxTemperature: Double?
    /// Extrema ranges for all active fields evaluated on this body.
    public var extrema: [SimulationFieldExtrema]

    public init(
        id: UUID,
        bodyName: String,
        nodeCount: Int,
        elementCount: Int,
        maxVonMisesStress: Double? = nil,
        maxDisplacement: Double? = nil,
        minFactorOfSafety: Double? = nil,
        maxTemperature: Double? = nil,
        extrema: [SimulationFieldExtrema] = []
    ) {
        self.id = id
        self.bodyName = bodyName
        self.nodeCount = nodeCount
        self.elementCount = elementCount
        self.maxVonMisesStress = maxVonMisesStress
        self.maxDisplacement = maxDisplacement
        self.minFactorOfSafety = minFactorOfSafety
        self.maxTemperature = maxTemperature
        self.extrema = extrema
    }
}
