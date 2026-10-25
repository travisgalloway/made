import Foundation
import simd

/// Numerical result field selected for contour visualization (BL-RES-02, #193).
public enum SimulationResultFieldKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case vonMisesStress
    case displacementMagnitude
    case displacementX
    case displacementY
    case displacementZ
    case temperature
    case factorOfSafety
    case majorPrincipalStress
    case minorPrincipalStress
    case maxShearStress
    case elementVonMisesStress
    case elementHeatFluxMagnitude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vonMisesStress:
            return "von Mises Stress"
        case .displacementMagnitude:
            return "Displacement Magnitude"
        case .displacementX:
            return "Displacement X"
        case .displacementY:
            return "Displacement Y"
        case .displacementZ:
            return "Displacement Z"
        case .temperature:
            return "Temperature"
        case .factorOfSafety:
            return "Factor of Safety"
        case .majorPrincipalStress:
            return "Major Principal Stress (S1)"
        case .minorPrincipalStress:
            return "Minor Principal Stress (S3)"
        case .maxShearStress:
            return "Max Shear Stress (Tresca)"
        case .elementVonMisesStress:
            return "Element von Mises Stress"
        case .elementHeatFluxMagnitude:
            return "Heat Flux Magnitude"
        }
    }

    public var defaultUnitSymbol: String {
        switch self {
        case .vonMisesStress, .majorPrincipalStress, .minorPrincipalStress, .maxShearStress, .elementVonMisesStress:
            return "MPa"
        case .displacementMagnitude, .displacementX, .displacementY, .displacementZ:
            return "mm"
        case .temperature:
            return "°C"
        case .factorOfSafety:
            return ""
        case .elementHeatFluxMagnitude:
            return "W/m²"
        }
    }

    public var isNodal: Bool {
        switch self {
        case .elementVonMisesStress, .elementHeatFluxMagnitude:
            return false
        default:
            return true
        }
    }
}

/// Animation waveform modes for deformed shape visualization (BL-RES-03, #324).
public enum SimulationAnimationMode: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case harmonic
    case halfCycle
    case linearRamp
    case pingPong

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .harmonic:
            return "Harmonic"
        case .halfCycle:
            return "Half Cycle"
        case .linearRamp:
            return "Linear Ramp"
        case .pingPong:
            return "Ping-Pong"
        }
    }

    /// Computes the deformation multiplier factor for a given animation mode and normalized phase (0.0 to 1.0).
    public static func factor(for mode: SimulationAnimationMode, phase: Double) -> Double {
        let clampedPhase = max(0.0, min(1.0, phase))
        switch mode {
        case .harmonic:
            return sin(2.0 * .pi * clampedPhase)
        case .halfCycle:
            return sin(.pi * clampedPhase)
        case .linearRamp:
            return clampedPhase
        case .pingPong:
            if clampedPhase <= 0.5 {
                return clampedPhase * 2.0
            } else {
                return (1.0 - clampedPhase) * 2.0
            }
        }
    }
}

/// Discrete solution step in a multi-step or non-linear finite element analysis (BL-RES-03, #324).
public struct SimulationLoadStep: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: Int { stepNumber }
    public var stepNumber: Int
    public var timeOrFactor: Double
    public var nodalDisplacements: [Int: SIMD3<Double>]
    public var nodalVonMisesStresses: [Int: Double]?
    public var elementVonMisesStresses: [Int: Double]?

    public init(
        stepNumber: Int,
        timeOrFactor: Double,
        nodalDisplacements: [Int: SIMD3<Double>],
        nodalVonMisesStresses: [Int: Double]? = nil,
        elementVonMisesStresses: [Int: Double]? = nil
    ) {
        self.stepNumber = stepNumber
        self.timeOrFactor = timeOrFactor
        self.nodalDisplacements = nodalDisplacements
        self.nodalVonMisesStresses = nodalVonMisesStresses
        self.elementVonMisesStresses = elementVonMisesStresses
    }

    enum CodingKeys: String, CodingKey {
        case stepNumber
        case timeOrFactor
        case nodalDisplacements
        case nodalVonMisesStresses
        case elementVonMisesStresses
    }
}

/// User-configurable visualization parameters for CAE finite element contour plots (BL-RES-02, #193).
public struct SimulationContourSettings: Sendable, Codable, Equatable, Hashable {
    public var isVisible: Bool
    public var field: SimulationResultFieldKind
    public var colorMap: SimulationColorMapKind
    public var autoRange: Bool
    public var customMin: Double?
    public var customMax: Double?
    public var showMinMaxMarkers: Bool
    public var isDeformed: Bool
    public var deformationScale: Double
    public var showMeshEdges: Bool
    public var showUndeformedWireframe: Bool
    public var animationMode: SimulationAnimationMode
    public var animationSpeed: Double
    public var activeLoadStepNumber: Int?

    public init(
        isVisible: Bool = false,
        field: SimulationResultFieldKind = .vonMisesStress,
        colorMap: SimulationColorMapKind = .turbo,
        autoRange: Bool = true,
        customMin: Double? = nil,
        customMax: Double? = nil,
        showMinMaxMarkers: Bool = true,
        isDeformed: Bool = false,
        deformationScale: Double = 1.0,
        showMeshEdges: Bool = true,
        showUndeformedWireframe: Bool = false,
        animationMode: SimulationAnimationMode = .harmonic,
        animationSpeed: Double = 1.0,
        activeLoadStepNumber: Int? = nil
    ) {
        self.isVisible = isVisible
        self.field = field
        self.colorMap = colorMap
        self.autoRange = autoRange
        self.customMin = customMin
        self.customMax = customMax
        self.showMinMaxMarkers = showMinMaxMarkers
        self.isDeformed = isDeformed
        self.deformationScale = max(0.0, deformationScale)
        self.showMeshEdges = showMeshEdges
        self.showUndeformedWireframe = showUndeformedWireframe
        self.animationMode = animationMode
        self.animationSpeed = animationSpeed > 0 ? animationSpeed : 1.0
        self.activeLoadStepNumber = activeLoadStepNumber
    }

    enum CodingKeys: String, CodingKey {
        case isVisible
        case field
        case colorMap
        case autoRange
        case customMin
        case customMax
        case showMinMaxMarkers
        case isDeformed
        case deformationScale
        case showMeshEdges
        case showUndeformedWireframe
        case animationMode
        case animationSpeed
        case activeLoadStepNumber
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        self.field = try container.decodeIfPresent(SimulationResultFieldKind.self, forKey: .field) ?? .vonMisesStress
        self.colorMap = try container.decodeIfPresent(SimulationColorMapKind.self, forKey: .colorMap) ?? .turbo
        self.autoRange = try container.decodeIfPresent(Bool.self, forKey: .autoRange) ?? true
        self.customMin = try container.decodeIfPresent(Double.self, forKey: .customMin)
        self.customMax = try container.decodeIfPresent(Double.self, forKey: .customMax)
        self.showMinMaxMarkers = try container.decodeIfPresent(Bool.self, forKey: .showMinMaxMarkers) ?? true
        self.isDeformed = try container.decodeIfPresent(Bool.self, forKey: .isDeformed) ?? false
        self.deformationScale = try container.decodeIfPresent(Double.self, forKey: .deformationScale) ?? 1.0
        self.showMeshEdges = try container.decodeIfPresent(Bool.self, forKey: .showMeshEdges) ?? true
        self.showUndeformedWireframe = try container.decodeIfPresent(Bool.self, forKey: .showUndeformedWireframe) ?? false
        self.animationMode = try container.decodeIfPresent(SimulationAnimationMode.self, forKey: .animationMode) ?? .harmonic
        self.animationSpeed = try container.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? 1.0
        self.activeLoadStepNumber = try container.decodeIfPresent(Int.self, forKey: .activeLoadStepNumber)
    }

    /// Computes effective visualization bounds ensuring min <= max and honoring auto vs custom settings.
    public func effectiveRange(for actualMin: Double, actualMax: Double) -> (min: Double, max: Double) {
        if autoRange {
            return (actualMin, actualMax)
        }
        let lo = customMin ?? actualMin
        let hi = customMax ?? actualMax
        if lo <= hi {
            return (lo, hi)
        } else {
            return (hi, lo)
        }
    }
}

/// Extremum values and spatial marker coordinates computed from an active contour plot (BL-RES-02, #193).
public struct SimulationContourExtrema: Sendable, Codable, Equatable, Hashable {
    public var fieldName: String
    public var unitSymbol: String
    public var actualMin: Double
    public var actualMax: Double
    public var effectiveMin: Double
    public var effectiveMax: Double
    public var minNodeId: Int?
    public var maxNodeId: Int?
    public var minPosition: SIMD3<Double>?
    public var maxPosition: SIMD3<Double>?

    public init(
        fieldName: String,
        unitSymbol: String,
        actualMin: Double,
        actualMax: Double,
        effectiveMin: Double,
        effectiveMax: Double,
        minNodeId: Int? = nil,
        maxNodeId: Int? = nil,
        minPosition: SIMD3<Double>? = nil,
        maxPosition: SIMD3<Double>? = nil
    ) {
        self.fieldName = fieldName
        self.unitSymbol = unitSymbol
        self.actualMin = actualMin
        self.actualMax = actualMax
        self.effectiveMin = effectiveMin
        self.effectiveMax = effectiveMax
        self.minNodeId = minNodeId
        self.maxNodeId = maxNodeId
        self.minPosition = minPosition
        self.maxPosition = maxPosition
    }
}
