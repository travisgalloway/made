import Foundation
import simd

/// The geometric kind of assembly constraint or mate between 3D rigid bodies (ADR-D4, #164).
public enum AssemblyConstraintKind: String, Sendable, Codable, CaseIterable {
    // Mates
    /// Aligns two feature origins to coincide (3 translational constraints).
    case coincident
    /// Aligns two feature axes to be collinear (2 angular + 2 lateral position constraints = 4 constraints; leaves 1 axial translation and 1 axial rotation).
    case concentric
    /// Constrains the distance between two features to a specified offset (1 constraint).
    case distance
    /// Aligns two orientation axes to be parallel (2 angular constraints).
    case parallel
    /// Constrains two orientation axes to be perpendicular (1 angular constraint).
    case perpendicular
    /// Constrains the angle between two orientation axes to a specified angle theta (1 angular constraint).
    case angle
    /// Constrains two features to be tangent (e.g. cylinder-to-plane, point/sphere-to-plane).
    case tangent
    /// Locks two features rigidly in relative position and orientation (6 constraints: 3 translation, 3 rotation).
    case fastened

    // Kinematic Joints
    /// Constrains 5 DOFs, leaving 1 rotational DOF free around primary axis.
    case revolute
    /// Prismatic joint constraining 5 DOFs, leaving 1 translational DOF free along primary axis.
    case slider
    /// Constrains 4 DOFs, leaving 1 axial translation and 1 axial rotation free along primary axis.
    case cylindrical
    /// Constrains 4 DOFs, leaving 1 translation along slot axis and 1 rotation around pin axis free.
    case pinSlot
    /// Constrains 3 DOFs, leaving 2 planar translations and 1 normal rotation free.
    case planar
    /// Spherical joint constraining 3 translation DOFs, leaving 3 rotational DOFs free.
    case ball

    /// Indicates whether this constraint kind represents a kinematic joint.
    public var isJoint: Bool {
        switch self {
        case .fastened, .revolute, .slider, .cylindrical, .pinSlot, .planar, .ball:
            return true
        case .coincident, .concentric, .distance, .parallel, .perpendicular, .angle, .tangent:
            return false
        }
    }

    /// Nominal number of free degrees of freedom left unconstrained for a single pair of bodies.
    public var nominalFreeDOFs: Int {
        switch self {
        case .fastened: return 0
        case .revolute, .slider: return 1
        case .cylindrical, .pinSlot: return 2
        case .planar, .ball, .coincident: return 3
        case .concentric: return 2
        case .parallel: return 4
        case .perpendicular, .angle, .tangent, .distance: return 5
        }
    }

    /// Convenience alias for `nominalFreeDOFs`.
    public var freeDOFs: Int {
        nominalFreeDOFs
    }

    /// Human-readable display title.
    public var displayName: String {
        switch self {
        case .coincident: return "Coincident"
        case .concentric: return "Concentric"
        case .distance: return "Distance"
        case .parallel: return "Parallel"
        case .perpendicular: return "Perpendicular"
        case .angle: return "Angle"
        case .tangent: return "Tangent"
        case .fastened: return "Fastened"
        case .revolute: return "Revolute"
        case .slider: return "Slider"
        case .cylindrical: return "Cylindrical"
        case .pinSlot: return "Pin-Slot"
        case .planar: return "Planar"
        case .ball: return "Ball"
        }
    }

    /// SF Symbol icon name representing this constraint or joint.
    public var systemImageName: String {
        switch self {
        case .coincident: return "target"
        case .concentric: return "circle.circle"
        case .distance: return "arrow.left.and.right"
        case .parallel: return "equal"
        case .perpendicular: return "angle"
        case .angle: return "compass.drawing"
        case .tangent: return "circle.and.line.horizontal"
        case .fastened: return "lock.fill"
        case .revolute: return "arrow.triangle.2.circlepath"
        case .slider: return "arrow.left.and.right.square"
        case .cylindrical: return "cylinder.split.1x2"
        case .pinSlot: return "capsule"
        case .planar: return "square.2.layers.3d"
        case .ball: return "globe"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "coincident": self = .coincident
        case "concentric": self = .concentric
        case "distance": self = .distance
        case "parallel": self = .parallel
        case "perpendicular": self = .perpendicular
        case "angle": self = .angle
        case "tangent": self = .tangent
        case "fastened", "rigid": self = .fastened
        case "revolute": self = .revolute
        case "slider": self = .slider
        case "cylindrical": self = .cylindrical
        case "pinslot": self = .pinSlot
        case "planar": self = .planar
        case "ball", "spherical": self = .ball
        default:
            if let standard = AssemblyConstraintKind(rawValue: raw) {
                self = standard
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown assembly constraint kind: '\(raw)'"
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A reference feature on a 3D component instance or assembly ground coordinate frame (ADR-D4, #164).
public struct AssemblyFeature: Sendable, Codable, Equatable, Hashable {
    /// Target component instance identifier. If nil, designates the assembly world coordinate frame (ground).
    public var componentInstanceId: UUID?
    /// Feature origin relative to the component coordinate frame.
    public var localOrigin: SIMD3<Float>
    /// Primary orientation / normal axis. Default is +Z `(0, 0, 1)`.
    public var localAxis: SIMD3<Float>
    /// Secondary orientation axis orthogonal to primary axis. Default is +X `(1, 0, 0)`.
    public var localSecondaryAxis: SIMD3<Float>
    /// Whether an explicit axis was specified (vs origin-only feature).
    public var hasExplicitAxis: Bool

    public init(
        componentInstanceId: UUID? = nil,
        localOrigin: SIMD3<Float> = .zero,
        localAxis: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
        localSecondaryAxis: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        hasExplicitAxis: Bool = true
    ) {
        self.componentInstanceId = componentInstanceId
        self.localOrigin = localOrigin
        let axisLen = simd_length(localAxis)
        self.localAxis = axisLen > 1e-6 ? localAxis / axisLen : SIMD3<Float>(0, 0, 1)
        let secLen = simd_length(localSecondaryAxis)
        self.localSecondaryAxis = secLen > 1e-6 ? localSecondaryAxis / secLen : SIMD3<Float>(1, 0, 0)
        self.hasExplicitAxis = hasExplicitAxis
    }

    /// Convenience initializer for an origin-only feature.
    public init(componentInstanceId: UUID? = nil, origin: SIMD3<Float>) {
        self.init(
            componentInstanceId: componentInstanceId,
            localOrigin: origin,
            localAxis: SIMD3<Float>(0, 0, 1),
            localSecondaryAxis: SIMD3<Float>(1, 0, 0),
            hasExplicitAxis: false
        )
    }

    /// Convenience initializer for an origin and primary orientation axis.
    public init(componentInstanceId: UUID? = nil, origin: SIMD3<Float>, axis: SIMD3<Float>) {
        let normAxis = simd_length(axis) > 1e-6 ? simd_normalize(axis) : SIMD3<Float>(0, 0, 1)
        let secAxis: SIMD3<Float>
        if abs(normAxis.x) < 0.9 {
            secAxis = simd_normalize(simd_cross(normAxis, SIMD3<Float>(1, 0, 0)))
        } else {
            secAxis = simd_normalize(simd_cross(normAxis, SIMD3<Float>(0, 1, 0)))
        }
        self.init(
            componentInstanceId: componentInstanceId,
            localOrigin: origin,
            localAxis: normAxis,
            localSecondaryAxis: secAxis,
            hasExplicitAxis: true
        )
    }

    /// Convenience initializer from a local Transform frame.
    public init(componentInstanceId: UUID? = nil, transform: Transform) {
        let primary = simd_normalize(transform.rotation.act(SIMD3<Float>(0, 0, 1)))
        let secondary = simd_normalize(transform.rotation.act(SIMD3<Float>(1, 0, 0)))
        self.init(
            componentInstanceId: componentInstanceId,
            localOrigin: transform.position,
            localAxis: primary,
            localSecondaryAxis: secondary,
            hasExplicitAxis: true
        )
    }
}

/// A 3D assembly mate or constraint between two features (ADR-D4, #164).
public struct AssemblyConstraint: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: AssemblyConstraintKind
    public var firstFeature: AssemblyFeature
    public var secondFeature: AssemblyFeature
    /// Optional numeric parameter value (distance offset in mm, or angle in radians).
    public var value: Double?
    /// Whether this constraint is suppressed from solver calculations.
    public var isSuppressed: Bool

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        kind: AssemblyConstraintKind,
        firstFeature: AssemblyFeature,
        secondFeature: AssemblyFeature,
        value: Double? = nil,
        isSuppressed: Bool = false
    ) {
        self.id = id
        self.name = name ?? kind.displayName
        self.kind = kind
        self.firstFeature = firstFeature
        self.secondFeature = secondFeature
        self.value = value
        self.isSuppressed = isSuppressed
    }

    /// Whether this constraint represents a kinematic joint.
    public var isJoint: Bool {
        kind.isJoint
    }

    /// Theoretical free degrees of freedom allowed by this constraint or joint.
    public var freeDOFs: Int {
        kind.freeDOFs
    }
}

/// Status of the 3D assembly constraint solve and diagnostic analysis (ADR-D4, #164).
public enum AssemblySolverStatus: Sendable, Codable, Equatable {
    case converged
    case overConstrained(conflictingConstraints: [UUID])
    case redundant(redundantConstraints: [UUID])
    case failedToConverge(reason: String)

    public var isConverged: Bool {
        switch self {
        case .converged, .redundant:
            return true
        case .overConstrained, .failedToConverge:
            return false
        }
    }

    public var isOverConstrained: Bool {
        if case .overConstrained = self { return true }
        return false
    }

    public var isRedundant: Bool {
        if case .redundant = self { return true }
        return false
    }

    public var conflictingConstraints: [UUID] {
        if case .overConstrained(let ids) = self { return ids }
        return []
    }

    public var redundantConstraints: [UUID] {
        if case .redundant(let ids) = self { return ids }
        return []
    }

    public var summaryText: String {
        switch self {
        case .converged:
            return "Converged"
        case .overConstrained(let ids):
            return "Over-constrained (\(ids.count) conflicting)"
        case .redundant(let ids):
            return "Redundant (\(ids.count) redundant)"
        case .failedToConverge(let reason):
            return "Failed to converge: \(reason)"
        }
    }
}

/// Result envelope returned by the 3D assembly constraint solver (ADR-D4, #164).
public struct AssemblySolverResult: Sendable, Codable, Equatable {
    public var status: AssemblySolverStatus
    public var solvedTransforms: [UUID: Transform]
    public var totalDOF: Int
    public var instanceDOF: [UUID: Int]
    public var message: String?

    public init(
        status: AssemblySolverStatus,
        solvedTransforms: [UUID: Transform],
        totalDOF: Int,
        instanceDOF: [UUID: Int] = [:],
        message: String? = nil
    ) {
        self.status = status
        self.solvedTransforms = solvedTransforms
        self.totalDOF = totalDOF
        self.instanceDOF = instanceDOF
        self.message = message
    }
}

/// System of component instances and 3D assembly constraints passed to the solver (ADR-D4, #164).
public struct AssemblyConstraintSystem: Sendable, Codable, Equatable {
    public var instances: [ComponentInstance]
    public var constraints: [AssemblyConstraint]

    public init(instances: [ComponentInstance], constraints: [AssemblyConstraint]) {
        self.instances = instances
        self.constraints = constraints
    }
}
