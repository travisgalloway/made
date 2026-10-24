import Foundation

/// Basis strength property used for mechanical factor of safety evaluation (ADR-D5, BL-FEA-09, #228).
public enum FactorOfSafetyBasis: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    case yield
    case ultimate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yield: return "Yield Strength"
        case .ultimate: return "Ultimate Tensile Strength"
        }
    }
}

/// Structural failure criterion used for multiaxial stress evaluation (ADR-D5, BL-FEA-09, #228).
public enum FactorOfSafetyCriterion: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    case vonMises
    case tresca
    case maxPrincipal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vonMises: return "von Mises (Distortion Energy)"
        case .tresca: return "Tresca (Maximum Shear Stress)"
        case .maxPrincipal: return "Maximum Principal Stress (Rankine)"
        }
    }
}

/// 3D symmetric Cauchy stress tensor in Cartesian coordinates (MPa).
public struct CauchyStressTensor: Sendable, Codable, Equatable, Hashable {
    public var sxx: Double
    public var syy: Double
    public var szz: Double
    public var sxy: Double
    public var syz: Double
    public var szx: Double

    public init(
        sxx: Double = 0.0,
        syy: Double = 0.0,
        szz: Double = 0.0,
        sxy: Double = 0.0,
        syz: Double = 0.0,
        szx: Double = 0.0
    ) {
        self.sxx = sxx
        self.syy = syy
        self.szz = szz
        self.sxy = sxy
        self.syz = syz
        self.szx = szx
    }

    /// von Mises equivalent stress in MPa:
    /// $\sigma_{vm} = \sqrt{\frac{1}{2}((\sigma_{xx}-\sigma_{yy})^2 + (\sigma_{yy}-\sigma_{zz})^2 + (\sigma_{zz}-\sigma_{xx})^2) + 3(\sigma_{xy}^2 + \sigma_{yz}^2 + \sigma_{zx}^2)}$
    public var vonMisesStress: Double {
        let diff1 = sxx - syy
        let diff2 = syy - szz
        let diff3 = szz - sxx
        let shearSq = sxy * sxy + syz * syz + szx * szx
        let vmSq = 0.5 * (diff1 * diff1 + diff2 * diff2 + diff3 * diff3) + 3.0 * shearSq
        return sqrt(max(0.0, vmSq))
    }

    /// Closed-form principal stresses ordered $\sigma_1 \ge \sigma_2 \ge \sigma_3$ in MPa.
    /// Solved using trigonometric diagonalization of symmetric 3x3 matrices (Smith 1961).
    public var principalStresses: (sigma1: Double, sigma2: Double, sigma3: Double) {
        let shearSq = sxy * sxy + syz * syz + szx * szx
        if shearSq < 1e-14 {
            let sorted = [sxx, syy, szz].sorted(by: >)
            return (sorted[0], sorted[1], sorted[2])
        }

        let I1 = sxx + syy + szz
        let q = I1 / 3.0
        let p1 = (sxx - q) * (sxx - q) + (syy - q) * (syy - q) + (szz - q) * (szz - q) + 2.0 * shearSq
        let p2 = p1 / 6.0
        let sp = sqrt(max(0.0, p2))
        if sp < 1e-14 {
            return (q, q, q)
        }

        // Normalized deviatoric matrix B = (sigma - q * I) / sp
        let bxx = (sxx - q) / sp
        let byy = (syy - q) / sp
        let bzz = (szz - q) / sp
        let bxy = sxy / sp
        let byz = syz / sp
        let bzx = szx / sp
        let detB = bxx * (byy * bzz - byz * byz) - bxy * (bxy * bzz - byz * bzx) + bzx * (bxy * byz - byy * bzx)
        var r = detB / 2.0
        if r.isNaN { r = 0.0 }
        let clampedR = max(-1.0, min(1.0, r))
        let phi = acos(clampedR) / 3.0

        let s1 = q + 2.0 * sp * cos(phi)
        let s3 = q + 2.0 * sp * cos(phi + 2.0 * Double.pi / 3.0)
        let s2 = 3.0 * q - s1 - s3

        let sorted = [s1, s2, s3].sorted(by: >)
        return (sorted[0], sorted[1], sorted[2])
    }

    /// Tresca maximum shear equivalent stress in MPa: $\sigma_{Tresca} = \sigma_1 - \sigma_3$.
    public var trescaStress: Double {
        let (s1, _, s3) = principalStresses
        return max(0.0, s1 - s3)
    }

    /// Maximum principal stress (Rankine) in MPa: $\sigma_{Rankine} = \max(|\sigma_1|, |\sigma_3|)$.
    public var maxPrincipalStress: Double {
        let (s1, _, s3) = principalStresses
        return max(abs(s1), abs(s3))
    }

    /// Equivalent scalar stress for the requested failure criterion.
    public func equivalentStress(for criterion: FactorOfSafetyCriterion) -> Double {
        switch criterion {
        case .vonMises: return vonMisesStress
        case .tresca: return trescaStress
        case .maxPrincipal: return maxPrincipalStress
        }
    }
}

/// User-configurable settings for Factor of Safety evaluation in a simulation study.
public struct FactorOfSafetySettings: Sendable, Codable, Equatable, Hashable {
    public var basis: FactorOfSafetyBasis
    public var criterion: FactorOfSafetyCriterion
    public var targetDesignFactor: Double
    public var maxClampedFOS: Double

    public init(
        basis: FactorOfSafetyBasis = .yield,
        criterion: FactorOfSafetyCriterion = .vonMises,
        targetDesignFactor: Double = 1.0,
        maxClampedFOS: Double = 15.0
    ) {
        self.basis = basis
        self.criterion = criterion
        self.targetDesignFactor = targetDesignFactor
        self.maxClampedFOS = maxClampedFOS
    }
}

/// Evaluated Factor of Safety results and node-level extrema.
public struct FactorOfSafetyResult: Sendable, Codable, Equatable, Hashable {
    public var basis: FactorOfSafetyBasis
    public var criterion: FactorOfSafetyCriterion
    public var allowableStrengthMPa: Double
    public var minFactorOfSafety: Double
    public var maxFactorOfSafety: Double
    public var criticalNodeId: Int?
    public var criticalStressMPa: Double?
    public var targetDesignFactor: Double
    public var meetsDesignFactor: Bool
    public var failingNodeCount: Int
    public var totalNodeCount: Int
    public var nodalFactorsOfSafety: [Int: Double]

    public init(
        basis: FactorOfSafetyBasis = .yield,
        criterion: FactorOfSafetyCriterion = .vonMises,
        allowableStrengthMPa: Double = 250.0,
        minFactorOfSafety: Double = 15.0,
        maxFactorOfSafety: Double = 15.0,
        criticalNodeId: Int? = nil,
        criticalStressMPa: Double? = nil,
        targetDesignFactor: Double = 1.0,
        meetsDesignFactor: Bool = true,
        failingNodeCount: Int = 0,
        totalNodeCount: Int = 0,
        nodalFactorsOfSafety: [Int: Double] = [:]
    ) {
        self.basis = basis
        self.criterion = criterion
        self.allowableStrengthMPa = allowableStrengthMPa
        self.minFactorOfSafety = minFactorOfSafety
        self.maxFactorOfSafety = maxFactorOfSafety
        self.criticalNodeId = criticalNodeId
        self.criticalStressMPa = criticalStressMPa
        self.targetDesignFactor = targetDesignFactor
        self.meetsDesignFactor = meetsDesignFactor
        self.failingNodeCount = failingNodeCount
        self.totalNodeCount = totalNodeCount
        self.nodalFactorsOfSafety = nodalFactorsOfSafety
    }
}

/// Evaluator resolving allowable strengths and computing Factor of Safety fields.
public enum FactorOfSafetyCalculator: Sendable {

    /// Resolves the allowable strength in MPa for a study given the specified basis.
    public static func resolveAllowableStrength(
        study: SimulationStudy,
        basis: FactorOfSafetyBasis
    ) -> Double {
        let mat = study.materials.first.flatMap { MaterialLibrary.standard.material(withId: $0.materialId) }
        return resolveAllowableStrength(material: mat, basis: basis)
    }

    /// Resolves the allowable strength in MPa for a material given the specified basis.
    /// Falls back to structural steel (yield 250 MPa, ultimate 400 MPa) if missing or non-positive.
    public static func resolveAllowableStrength(
        material: MaterialDefinition?,
        basis: FactorOfSafetyBasis
    ) -> Double {
        switch basis {
        case .yield:
            let strength = material?.yieldStrengthMPa ?? 0.0
            return strength > 0.0 ? strength : 250.0
        case .ultimate:
            let strength = material?.ultimateStrengthMPa ?? 0.0
            return strength > 0.0 ? strength : 400.0
        }
    }

    /// Evaluates factor of safety across a study using its results and settings.
    public static func evaluate(
        study: SimulationStudy,
        settings: FactorOfSafetySettings? = nil
    ) -> FactorOfSafetyResult? {
        let activeSettings = settings ?? study.factorOfSafetySettings
        let mat = study.materials.first.flatMap { MaterialLibrary.standard.material(withId: $0.materialId) }

        if let tensors = study.results.nodalCauchyTensors, !tensors.isEmpty {
            return evaluate(nodalTensors: tensors, material: mat, settings: activeSettings)
        } else if let nodalStresses = study.results.nodalVonMisesStresses, !nodalStresses.isEmpty {
            return evaluate(nodalVonMisesStresses: nodalStresses, material: mat, settings: activeSettings)
        }
        return nil
    }

    /// Evaluates factor of safety from nodal Cauchy stress tensors.
    public static func evaluate(
        nodalTensors: [Int: CauchyStressTensor],
        material: MaterialDefinition? = nil,
        settings: FactorOfSafetySettings = FactorOfSafetySettings()
    ) -> FactorOfSafetyResult {
        let allowable = resolveAllowableStrength(material: material, basis: settings.basis)
        var nodalFOS: [Int: Double] = [:]
        nodalFOS.reserveCapacity(nodalTensors.count)

        var minFOS = settings.maxClampedFOS
        var maxFOS = 0.0
        var criticalNodeId: Int? = nil
        var criticalStressMPa: Double? = nil
        var failingCount = 0

        let sortedNodeIds = nodalTensors.keys.sorted()
        for nodeId in sortedNodeIds {
            guard let tensor = nodalTensors[nodeId] else { continue }
            let eqStress = tensor.equivalentStress(for: settings.criterion)
            let fos: Double
            if !eqStress.isFinite || eqStress.isNaN || eqStress <= 1e-6 {
                fos = settings.maxClampedFOS
            } else {
                let rawFos = allowable / eqStress
                if !rawFos.isFinite || rawFos.isNaN {
                    fos = settings.maxClampedFOS
                } else {
                    fos = min(settings.maxClampedFOS, max(0.0, rawFos))
                }
            }
            nodalFOS[nodeId] = fos
            if fos < minFOS || criticalNodeId == nil {
                minFOS = fos
                criticalNodeId = nodeId
                criticalStressMPa = eqStress
            }
            if fos > maxFOS {
                maxFOS = fos
            }
            if fos < settings.targetDesignFactor {
                failingCount += 1
            }
        }

        if nodalTensors.isEmpty {
            minFOS = settings.maxClampedFOS
            maxFOS = settings.maxClampedFOS
        }

        return FactorOfSafetyResult(
            basis: settings.basis,
            criterion: settings.criterion,
            allowableStrengthMPa: allowable,
            minFactorOfSafety: minFOS,
            maxFactorOfSafety: maxFOS,
            criticalNodeId: criticalNodeId,
            criticalStressMPa: criticalStressMPa,
            targetDesignFactor: settings.targetDesignFactor,
            meetsDesignFactor: minFOS >= settings.targetDesignFactor,
            failingNodeCount: failingCount,
            totalNodeCount: nodalTensors.count,
            nodalFactorsOfSafety: nodalFOS
        )
    }

    /// Evaluates factor of safety from nodal von Mises stresses (fallback when Cauchy tensors are unavailable).
    public static func evaluate(
        nodalVonMisesStresses: [Int: Double],
        material: MaterialDefinition? = nil,
        settings: FactorOfSafetySettings = FactorOfSafetySettings()
    ) -> FactorOfSafetyResult {
        let allowable = resolveAllowableStrength(material: material, basis: settings.basis)
        var nodalFOS: [Int: Double] = [:]
        nodalFOS.reserveCapacity(nodalVonMisesStresses.count)

        var minFOS = settings.maxClampedFOS
        var maxFOS = 0.0
        var criticalNodeId: Int? = nil
        var criticalStressMPa: Double? = nil
        var failingCount = 0

        let sortedNodeIds = nodalVonMisesStresses.keys.sorted()
        for nodeId in sortedNodeIds {
            guard let eqStress = nodalVonMisesStresses[nodeId] else { continue }
            let fos: Double
            if !eqStress.isFinite || eqStress.isNaN || eqStress <= 1e-6 {
                fos = settings.maxClampedFOS
            } else {
                let rawFos = allowable / eqStress
                if !rawFos.isFinite || rawFos.isNaN {
                    fos = settings.maxClampedFOS
                } else {
                    fos = min(settings.maxClampedFOS, max(0.0, rawFos))
                }
            }
            nodalFOS[nodeId] = fos
            if fos < minFOS || criticalNodeId == nil {
                minFOS = fos
                criticalNodeId = nodeId
                criticalStressMPa = eqStress
            }
            if fos > maxFOS {
                maxFOS = fos
            }
            if fos < settings.targetDesignFactor {
                failingCount += 1
            }
        }

        if nodalVonMisesStresses.isEmpty {
            minFOS = settings.maxClampedFOS
            maxFOS = settings.maxClampedFOS
        }

        return FactorOfSafetyResult(
            basis: settings.basis,
            criterion: settings.criterion,
            allowableStrengthMPa: allowable,
            minFactorOfSafety: minFOS,
            maxFactorOfSafety: maxFOS,
            criticalNodeId: criticalNodeId,
            criticalStressMPa: criticalStressMPa,
            targetDesignFactor: settings.targetDesignFactor,
            meetsDesignFactor: minFOS >= settings.targetDesignFactor,
            failingNodeCount: failingCount,
            totalNodeCount: nodalVonMisesStresses.count,
            nodalFactorsOfSafety: nodalFOS
        )
    }
}
