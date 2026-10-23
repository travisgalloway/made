import Foundation
import simd

/// Mass and center-of-mass override model for purchased parts and off-the-shelf components (BL-MAT-05, #258).
public struct MassOverride: Sendable, Equatable, Codable {
    public var isPurchased: Bool
    public var overrideMass: Double?
    public var overrideCenterOfMass: SIMD3<Double>?

    /// Whether this override has active values applied (purchased status true and at least one property overridden).
    public var hasActiveOverride: Bool {
        isPurchased && (overrideMass != nil || overrideCenterOfMass != nil)
    }

    public init(
        isPurchased: Bool = false,
        overrideMass: Double? = nil,
        overrideCenterOfMass: SIMD3<Double>? = nil
    ) {
        self.isPurchased = isPurchased

        if let mass = overrideMass, mass > 0, mass.isFinite {
            self.overrideMass = mass
        } else {
            self.overrideMass = nil
        }

        if let com = overrideCenterOfMass, com.x.isFinite, com.y.isFinite, com.z.isFinite {
            self.overrideCenterOfMass = com
        } else {
            self.overrideCenterOfMass = nil
        }
    }

    /// Parses mass override settings from a string metadata dictionary.
    public init(metadata: [String: String]) {
        if let p = metadata[CustomPropertyKey.isPurchased] {
            let lower = p.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.isPurchased = lower == "true" || lower == "1" || lower == "yes"
        } else {
            self.isPurchased = false
        }

        if let massStr = metadata[CustomPropertyKey.overrideMass]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let massVal = Double(massStr), massVal > 0, massVal.isFinite {
            self.overrideMass = massVal
        } else {
            self.overrideMass = nil
        }

        let xStr = metadata[CustomPropertyKey.overrideCenterOfMassX]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let yStr = metadata[CustomPropertyKey.overrideCenterOfMassY]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let zStr = metadata[CustomPropertyKey.overrideCenterOfMassZ]?.trimmingCharacters(in: .whitespacesAndNewlines)

        let xVal = xStr.flatMap(Double.init)
        let yVal = yStr.flatMap(Double.init)
        let zVal = zStr.flatMap(Double.init)

        // Reject center of mass if any provided coordinate fails to parse or is non-finite (NaN / Inf)
        let hasInvalidX = (xStr != nil && (xVal == nil || !xVal!.isFinite))
        let hasInvalidY = (yStr != nil && (yVal == nil || !yVal!.isFinite))
        let hasInvalidZ = (zStr != nil && (zVal == nil || !zVal!.isFinite))

        if hasInvalidX || hasInvalidY || hasInvalidZ {
            self.overrideCenterOfMass = nil
        } else if xVal != nil || yVal != nil || zVal != nil {
            self.overrideCenterOfMass = SIMD3<Double>(xVal ?? 0.0, yVal ?? 0.0, zVal ?? 0.0)
        } else {
            self.overrideCenterOfMass = nil
        }
    }

    /// Mutates the given metadata dictionary to persist or remove override keys.
    public func applying(to metadata: inout [String: String]) {
        if isPurchased {
            metadata[CustomPropertyKey.isPurchased] = "true"
        } else {
            metadata.removeValue(forKey: CustomPropertyKey.isPurchased)
        }

        if let m = overrideMass, m > 0, m.isFinite {
            metadata[CustomPropertyKey.overrideMass] = String(m)
        } else {
            metadata.removeValue(forKey: CustomPropertyKey.overrideMass)
        }

        if let com = overrideCenterOfMass, com.x.isFinite, com.y.isFinite, com.z.isFinite {
            metadata[CustomPropertyKey.overrideCenterOfMassX] = String(com.x)
            metadata[CustomPropertyKey.overrideCenterOfMassY] = String(com.y)
            metadata[CustomPropertyKey.overrideCenterOfMassZ] = String(com.z)
        } else {
            metadata.removeValue(forKey: CustomPropertyKey.overrideCenterOfMassX)
            metadata.removeValue(forKey: CustomPropertyKey.overrideCenterOfMassY)
            metadata.removeValue(forKey: CustomPropertyKey.overrideCenterOfMassZ)
        }
    }
}

// MARK: - PropertyContainer Extensions

extension PropertyContainer {
    /// Mass override model for purchased parts.
    public var massOverride: MassOverride {
        get { MassOverride(metadata: metadata) }
        set { newValue.applying(to: &metadata) }
    }

    /// Whether this body or component is flagged as a purchased part.
    public var isPurchased: Bool {
        get { massOverride.isPurchased }
        set {
            var override = massOverride
            override.isPurchased = newValue
            override.applying(to: &metadata)
        }
    }
}
