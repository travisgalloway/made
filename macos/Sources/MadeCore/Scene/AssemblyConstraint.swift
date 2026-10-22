import Foundation
import simd

/// The geometric kind of assembly constraint or mate between 3D rigid bodies (ADR-D4, #164).
public enum AssemblyConstraintKind: String, Sendable, Codable, CaseIterable {
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
    /// Locks two features rigidly in relative position and orientation (6 constraints: 3 translation, 3 rotation).
    case fastened
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
        self.name = name ?? kind.rawValue.capitalized
        self.kind = kind
        self.firstFeature = firstFeature
        self.secondFeature = secondFeature
        self.value = value
        self.isSuppressed = isSuppressed
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
