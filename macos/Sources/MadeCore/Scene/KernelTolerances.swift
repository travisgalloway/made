import Foundation

/// Geometric kernel tolerances governing linear precision, angular deflection, and chordal tessellation error.
public struct KernelTolerances: Codable, Equatable, Sendable {
    public static let defaultLinearTolerance: Double = 0.001
    public static let defaultAngularTolerance: Double = 0.1
    public static let defaultChordalTolerance: Double = 0.01

    public static let minLinearTolerance: Double = 0.0001
    public static let maxLinearTolerance: Double = 10.0

    public static let minAngularTolerance: Double = 0.001
    public static let maxAngularTolerance: Double = 45.0

    public static let minChordalTolerance: Double = 0.0005
    public static let maxChordalTolerance: Double = 5.0

    public var linearTolerance: Double
    public var angularTolerance: Double
    public var chordalTolerance: Double

    public init(
        linearTolerance: Double = Self.defaultLinearTolerance,
        angularTolerance: Double = Self.defaultAngularTolerance,
        chordalTolerance: Double = Self.defaultChordalTolerance
    ) {
        self.linearTolerance = linearTolerance
        self.angularTolerance = angularTolerance
        self.chordalTolerance = chordalTolerance
    }

    public static let `default` = KernelTolerances()

    /// Guarantees all tolerances remain strictly positive, finite, and within safe numerical stability bounds.
    public func clamped() -> KernelTolerances {
        let clampedLinear: Double
        if linearTolerance.isNaN || linearTolerance.isInfinite {
            clampedLinear = Self.defaultLinearTolerance
        } else {
            clampedLinear = min(max(linearTolerance, Self.minLinearTolerance), Self.maxLinearTolerance)
        }

        let clampedAngular: Double
        if angularTolerance.isNaN || angularTolerance.isInfinite {
            clampedAngular = Self.defaultAngularTolerance
        } else {
            clampedAngular = min(max(angularTolerance, Self.minAngularTolerance), Self.maxAngularTolerance)
        }

        let clampedChordal: Double
        if chordalTolerance.isNaN || chordalTolerance.isInfinite {
            clampedChordal = Self.defaultChordalTolerance
        } else {
            clampedChordal = min(max(chordalTolerance, Self.minChordalTolerance), Self.maxChordalTolerance)
        }

        return KernelTolerances(
            linearTolerance: clampedLinear,
            angularTolerance: clampedAngular,
            chordalTolerance: clampedChordal
        )
    }

    public var isValid: Bool {
        !linearTolerance.isNaN && !linearTolerance.isInfinite &&
        linearTolerance >= Self.minLinearTolerance && linearTolerance <= Self.maxLinearTolerance &&
        !angularTolerance.isNaN && !angularTolerance.isInfinite &&
        angularTolerance >= Self.minAngularTolerance && angularTolerance <= Self.maxAngularTolerance &&
        !chordalTolerance.isNaN && !chordalTolerance.isInfinite &&
        chordalTolerance >= Self.minChordalTolerance && chordalTolerance <= Self.maxChordalTolerance
    }
}
