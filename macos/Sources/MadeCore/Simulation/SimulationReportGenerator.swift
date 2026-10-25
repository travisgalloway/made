import Foundation
import CoreGraphics
import CoreText
import AppKit
import simd

/// Supported output formats for CAE numerical simulation reports (BL-RES-07, #327).
public enum SimulationReportFormat: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case html = "html"
    case pdf = "pdf"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .html:
            return "HTML Report"
        case .pdf:
            return "PDF Document"
        }
    }

    public var fileExtension: String { rawValue }
}

/// Engineering verdict for structural integrity and numerical simulation results (BL-RES-07, #327).
public enum SimulationVerdict: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case pass = "pass"
    case marginal = "marginal"
    case fail = "fail"
    case inconclusive = "inconclusive"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pass:
            return "Pass"
        case .marginal:
            return "Marginal"
        case .fail:
            return "Fail"
        case .inconclusive:
            return "Inconclusive"
        }
    }

    public var badgeColorHex: String {
        switch self {
        case .pass:
            return "#10b981"
        case .marginal:
            return "#f59e0b"
        case .fail:
            return "#ef4444"
        case .inconclusive:
            return "#6b7280"
        }
    }

    public var badgeTextColorHex: String {
        switch self {
        case .pass:
            return "#065f46"
        case .marginal:
            return "#92400e"
        case .fail:
            return "#991b1b"
        case .inconclusive:
            return "#374151"
        }
    }

    public var badgeBgColorHex: String {
        switch self {
        case .pass:
            return "#ecfdf5"
        case .marginal:
            return "#fffbeb"
        case .fail:
            return "#fef2f2"
        case .inconclusive:
            return "#f3f4f6"
        }
    }

    public var badgeBorderColorHex: String {
        switch self {
        case .pass:
            return "#a7f3d0"
        case .marginal:
            return "#fde68a"
        case .fail:
            return "#fecaca"
        case .inconclusive:
            return "#d1d5db"
        }
    }
}

/// Text horizontal alignment helper for vector report layout.
public enum ReportTextAlignment: Sendable {
    case left
    case center
    case right
}

/// User options and section inclusion toggles for simulation report generation (BL-RES-07, #327).
public struct SimulationReportOptions: Sendable, Codable, Equatable {
    public var title: String?
    public var author: String?
    public var company: String?
    public var notes: String?
    public var lengthUnit: LengthUnit
    public var includeSetup: Bool
    public var includeMeshStats: Bool
    public var includePlots: Bool
    public var includeExtrema: Bool
    public var includeConclusions: Bool
    public var includeReactions: Bool
    public var includeBodySummaries: Bool
    public var includeProbes: Bool

    public init(
        title: String? = nil,
        author: String? = nil,
        company: String? = nil,
        notes: String? = nil,
        lengthUnit: LengthUnit = .millimeters,
        includeSetup: Bool = true,
        includeMeshStats: Bool = true,
        includePlots: Bool = true,
        includeExtrema: Bool = true,
        includeConclusions: Bool = true,
        includeReactions: Bool = true,
        includeBodySummaries: Bool = true,
        includeProbes: Bool = true
    ) {
        self.title = title
        self.author = author
        self.company = company
        self.notes = notes
        self.lengthUnit = lengthUnit
        self.includeSetup = includeSetup
        self.includeMeshStats = includeMeshStats
        self.includePlots = includePlots
        self.includeExtrema = includeExtrema
        self.includeConclusions = includeConclusions
        self.includeReactions = includeReactions
        self.includeBodySummaries = includeBodySummaries
        self.includeProbes = includeProbes
    }
}

/// Synthesized engineering conclusions evaluating structural integrity and static equilibrium (BL-RES-07, #327).
public struct SimulationReportConclusions: Sendable, Codable, Equatable {
    public var overallVerdict: SimulationVerdict
    public var factorOfSafetyAssessment: String
    public var minFactorOfSafety: Double?
    public var targetDesignFactor: Double?
    public var marginOfSafety: Double?
    public var peakStressComparison: String?
    public var staticEquilibriumAssessment: String?
    public var reactionForceResidualN: Double?
    public var isEquilibriumSatisfied: Bool?
    public var meshQualityAssessment: String?
    public var keyFindings: [String]

    public init(
        overallVerdict: SimulationVerdict = .inconclusive,
        factorOfSafetyAssessment: String = "",
        minFactorOfSafety: Double? = nil,
        targetDesignFactor: Double? = nil,
        marginOfSafety: Double? = nil,
        peakStressComparison: String? = nil,
        staticEquilibriumAssessment: String? = nil,
        reactionForceResidualN: Double? = nil,
        isEquilibriumSatisfied: Bool? = nil,
        meshQualityAssessment: String? = nil,
        keyFindings: [String] = []
    ) {
        self.overallVerdict = overallVerdict
        self.factorOfSafetyAssessment = factorOfSafetyAssessment
        self.minFactorOfSafety = minFactorOfSafety
        self.targetDesignFactor = targetDesignFactor
        self.marginOfSafety = marginOfSafety
        self.peakStressComparison = peakStressComparison
        self.staticEquilibriumAssessment = staticEquilibriumAssessment
        self.reactionForceResidualN = reactionForceResidualN
        self.isEquilibriumSatisfied = isEquilibriumSatisfied
        self.meshQualityAssessment = meshQualityAssessment
        self.keyFindings = keyFindings
    }
}

/// Errors produced during simulation report export.
public enum SimulationReportError: Error, LocalizedError, Equatable {
    case contextCreationFailed
    case writeFailed(String)
    case studyNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create CoreGraphics PDF context."
        case .writeFailed(let reason):
            return "Failed to write simulation report: \(reason)"
        case .studyNotFound(let id):
            return "Simulation study with ID \(id) was not found."
        }
    }
}

public struct SimulationReportMaterialItem: Sendable, Codable, Equatable {
    public var name: String
    public var category: String
    public var youngsModulus: String
    public var poissonsRatio: String
    public var density: String
    public var yieldStrength: String

    public init(
        name: String,
        category: String,
        youngsModulus: String,
        poissonsRatio: String,
        density: String,
        yieldStrength: String
    ) {
        self.name = name
        self.category = category
        self.youngsModulus = youngsModulus
        self.poissonsRatio = poissonsRatio
        self.density = density
        self.yieldStrength = yieldStrength
    }
}

public struct SimulationReportFixtureItem: Sendable, Codable, Equatable {
    public var name: String
    public var kindDisplayName: String
    public var targetCount: Int
    public var restraintsDescription: String

    public init(
        name: String,
        kindDisplayName: String,
        targetCount: Int,
        restraintsDescription: String
    ) {
        self.name = name
        self.kindDisplayName = kindDisplayName
        self.targetCount = targetCount
        self.restraintsDescription = restraintsDescription
    }
}

public struct SimulationReportLoadItem: Sendable, Codable, Equatable {
    public var name: String
    public var kindDisplayName: String
    public var magnitudeDisplay: Double
    public var directionDisplay: SIMD3<Double>
    public var unitSymbol: String
    public var targetCount: Int

    public init(
        name: String,
        kindDisplayName: String,
        magnitudeDisplay: Double,
        directionDisplay: SIMD3<Double>,
        unitSymbol: String,
        targetCount: Int
    ) {
        self.name = name
        self.kindDisplayName = kindDisplayName
        self.magnitudeDisplay = magnitudeDisplay
        self.directionDisplay = directionDisplay
        self.unitSymbol = unitSymbol
        self.targetCount = targetCount
    }
}

public struct SimulationReportExtremaItem: Sendable, Codable, Equatable, Identifiable {
    public var id: String { fieldName }
    public var fieldName: String
    public var minValue: Double
    public var maxValue: Double
    public var unitSymbol: String

    public init(
        fieldName: String,
        minValue: Double,
        maxValue: Double,
        unitSymbol: String
    ) {
        self.fieldName = fieldName
        self.minValue = minValue
        self.maxValue = maxValue
        self.unitSymbol = unitSymbol
    }
}

public struct SimulationReportReactionItem: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var fixtureName: String
    public var forceMag: Double
    public var forceVec: SIMD3<Double>
    public var momentMag: Double
    public var momentVec: SIMD3<Double>
    public var centroid: SIMD3<Double>
    public var nodeCount: Int

    public init(
        id: UUID,
        fixtureName: String,
        forceMag: Double,
        forceVec: SIMD3<Double>,
        momentMag: Double,
        momentVec: SIMD3<Double>,
        centroid: SIMD3<Double>,
        nodeCount: Int
    ) {
        self.id = id
        self.fixtureName = fixtureName
        self.forceMag = forceMag
        self.forceVec = forceVec
        self.momentMag = momentMag
        self.momentVec = momentVec
        self.centroid = centroid
        self.nodeCount = nodeCount
    }
}

public struct SimulationReportBodySummaryItem: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var bodyName: String
    public var nodeCount: Int
    public var elementCount: Int
    public var maxStress: Double?
    public var maxDisplacement: Double?
    public var minFactorOfSafety: Double?
    public var maxTemperature: Double?

    public init(
        id: UUID,
        bodyName: String,
        nodeCount: Int,
        elementCount: Int,
        maxStress: Double? = nil,
        maxDisplacement: Double? = nil,
        minFactorOfSafety: Double? = nil,
        maxTemperature: Double? = nil
    ) {
        self.id = id
        self.bodyName = bodyName
        self.nodeCount = nodeCount
        self.elementCount = elementCount
        self.maxStress = maxStress
        self.maxDisplacement = maxDisplacement
        self.minFactorOfSafety = minFactorOfSafety
        self.maxTemperature = maxTemperature
    }
}

public struct SimulationReportProbeItem: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var index: Int
    public var name: String
    public var kindDisplayName: String
    public var position: SIMD3<Double>
    public var distanceAlongPath: Double?
    public var nodeId: Int?
    public var elementId: Int?
    public var primaryValue: Double?
    public var unitSymbol: String

    public init(
        id: UUID,
        index: Int,
        name: String,
        kindDisplayName: String,
        position: SIMD3<Double>,
        distanceAlongPath: Double? = nil,
        nodeId: Int? = nil,
        elementId: Int? = nil,
        primaryValue: Double? = nil,
        unitSymbol: String = ""
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.kindDisplayName = kindDisplayName
        self.position = position
        self.distanceAlongPath = distanceAlongPath
        self.nodeId = nodeId
        self.elementId = elementId
        self.primaryValue = primaryValue
        self.unitSymbol = unitSymbol
    }
}

/// Aggregated, formatted report data model decoupling numerical analysis from rendering engines.
public struct SimulationReportData: Sendable, Codable, Equatable {
    public var studyId: UUID
    public var studyName: String
    public var reportTitle: String
    public var studyType: SimulationStudyType
    public var status: SimulationExecutionStatus
    public var timestamp: String
    public var executionTimeSeconds: Double?
    public var options: SimulationReportOptions
    public var conclusions: SimulationReportConclusions

    // Setup
    public var targetCount: Int
    public var materials: [SimulationReportMaterialItem]
    public var fixtures: [SimulationReportFixtureItem]
    public var loads: [SimulationReportLoadItem]
    public var solverType: String
    public var solverTolerance: Double
    public var solverMaxIterations: Int

    // Discretization
    public var nodeCount: Int
    public var elementCount: Int
    public var elementOrder: String
    public var minQuality: Double
    public var avgQuality: Double
    public var maxAspectRatio: Double

    // Extrema
    public var extrema: [SimulationReportExtremaItem]

    // FoS & Stress
    public var minFactorOfSafety: Double?
    public var maxFactorOfSafety: Double?
    public var targetDesignFactor: Double?
    public var peakStress: Double?
    public var yieldStrength: Double?
    public var stressUnitSymbol: String

    // Reactions & Equilibrium
    public var reactions: [SimulationReportReactionItem]
    public var totalReactionForceMag: Double?
    public var totalReactionForceVec: SIMD3<Double>?
    public var totalReactionMomentMag: Double?
    public var totalReactionMomentVec: SIMD3<Double>?
    public var totalAppliedForceMag: Double?
    public var totalAppliedForceVec: SIMD3<Double>?
    public var forceResidualMag: Double?
    public var forceUnitSymbol: String
    public var momentUnitSymbol: String
    public var lengthUnitSymbol: String

    // Body summaries & Probes
    public var bodySummaries: [SimulationReportBodySummaryItem]
    public var probes: [SimulationReportProbeItem]

    public var hasPage3: Bool {
        !bodySummaries.isEmpty || !probes.isEmpty
    }

    public init(
        studyId: UUID,
        studyName: String,
        reportTitle: String,
        studyType: SimulationStudyType,
        status: SimulationExecutionStatus,
        timestamp: String,
        executionTimeSeconds: Double? = nil,
        options: SimulationReportOptions,
        conclusions: SimulationReportConclusions,
        targetCount: Int,
        materials: [SimulationReportMaterialItem],
        fixtures: [SimulationReportFixtureItem],
        loads: [SimulationReportLoadItem],
        solverType: String,
        solverTolerance: Double,
        solverMaxIterations: Int,
        nodeCount: Int,
        elementCount: Int,
        elementOrder: String,
        minQuality: Double,
        avgQuality: Double,
        maxAspectRatio: Double,
        extrema: [SimulationReportExtremaItem],
        minFactorOfSafety: Double? = nil,
        maxFactorOfSafety: Double? = nil,
        targetDesignFactor: Double? = nil,
        peakStress: Double? = nil,
        yieldStrength: Double? = nil,
        stressUnitSymbol: String,
        reactions: [SimulationReportReactionItem],
        totalReactionForceMag: Double? = nil,
        totalReactionForceVec: SIMD3<Double>? = nil,
        totalReactionMomentMag: Double? = nil,
        totalReactionMomentVec: SIMD3<Double>? = nil,
        totalAppliedForceMag: Double? = nil,
        totalAppliedForceVec: SIMD3<Double>? = nil,
        forceResidualMag: Double? = nil,
        forceUnitSymbol: String,
        momentUnitSymbol: String,
        lengthUnitSymbol: String,
        bodySummaries: [SimulationReportBodySummaryItem],
        probes: [SimulationReportProbeItem]
    ) {
        self.studyId = studyId
        self.studyName = studyName
        self.reportTitle = reportTitle
        self.studyType = studyType
        self.status = status
        self.timestamp = timestamp
        self.executionTimeSeconds = executionTimeSeconds
        self.options = options
        self.conclusions = conclusions
        self.targetCount = targetCount
        self.materials = materials
        self.fixtures = fixtures
        self.loads = loads
        self.solverType = solverType
        self.solverTolerance = solverTolerance
        self.solverMaxIterations = solverMaxIterations
        self.nodeCount = nodeCount
        self.elementCount = elementCount
        self.elementOrder = elementOrder
        self.minQuality = minQuality
        self.avgQuality = avgQuality
        self.maxAspectRatio = maxAspectRatio
        self.extrema = extrema
        self.minFactorOfSafety = minFactorOfSafety
        self.maxFactorOfSafety = maxFactorOfSafety
        self.targetDesignFactor = targetDesignFactor
        self.peakStress = peakStress
        self.yieldStrength = yieldStrength
        self.stressUnitSymbol = stressUnitSymbol
        self.reactions = reactions
        self.totalReactionForceMag = totalReactionForceMag
        self.totalReactionForceVec = totalReactionForceVec
        self.totalReactionMomentMag = totalReactionMomentMag
        self.totalReactionMomentVec = totalReactionMomentVec
        self.totalAppliedForceMag = totalAppliedForceMag
        self.totalAppliedForceVec = totalAppliedForceVec
        self.forceResidualMag = forceResidualMag
        self.forceUnitSymbol = forceUnitSymbol
        self.momentUnitSymbol = momentUnitSymbol
        self.lengthUnitSymbol = lengthUnitSymbol
        self.bodySummaries = bodySummaries
        self.probes = probes
    }
}

/// Standalone report generator producing HTML and multi-page vector PDF documents (BL-RES-07, #327).
public enum SimulationReportGenerator: Sendable {

    // MARK: - Conclusions Synthesis

    public static func synthesizeConclusions(
        study: SimulationStudy,
        unit: LengthUnit = .millimeters
    ) -> SimulationReportConclusions {
        let status = study.results.status

        guard status == .completed else {
            let meshStats = study.results.meshStatistics
            let meshAssessment: String
            if meshStats.elementCount > 0 {
                meshAssessment = "Mesh comprises \(meshStats.nodeCount) nodes and \(meshStats.elementCount) tetrahedral elements with average quality \(String(format: "%.3f", meshStats.avgElementQuality))."
            } else {
                meshAssessment = "Model is unmeshed."
            }
            return SimulationReportConclusions(
                overallVerdict: .inconclusive,
                factorOfSafetyAssessment: "Simulation has not completed execution (status: \(status.displayName)). No numerical results are available.",
                minFactorOfSafety: nil,
                targetDesignFactor: study.factorOfSafetySettings.targetDesignFactor,
                marginOfSafety: nil,
                peakStressComparison: nil,
                staticEquilibriumAssessment: "Static equilibrium evaluation requires completed solve results.",
                reactionForceResidualN: nil,
                isEquilibriumSatisfied: nil,
                meshQualityAssessment: meshAssessment,
                keyFindings: [
                    "Study status is \(status.displayName).",
                    "Execute the study to generate simulation results and engineering conclusions."
                ]
            )
        }

        let targetDesign = study.factorOfSafetySettings.targetDesignFactor
        let fosResult = study.results.factorOfSafety ?? FactorOfSafetyCalculator.evaluate(study: study)

        let overallVerdict: SimulationVerdict
        let fosAssessment: String
        let minFoS: Double?
        let marginOfSafety: Double?

        if let fos = fosResult {
            let mFoS = fos.minFactorOfSafety
            minFoS = mFoS
            let margin = (mFoS - targetDesign) / max(1e-6, targetDesign)
            marginOfSafety = margin

            if mFoS >= targetDesign {
                overallVerdict = .pass
                fosAssessment = "Factor of Safety requirement satisfied. Minimum FoS of \(String(format: "%.2f", mFoS)) meets or exceeds the target design factor of \(String(format: "%.2f", targetDesign)) (margin of safety: \(String(format: "%+.1f%%", margin * 100.0)))."
            } else if mFoS >= 1.0 {
                overallVerdict = .marginal
                fosAssessment = "Factor of Safety is marginal. Minimum FoS of \(String(format: "%.2f", mFoS)) exceeds yield (1.0) but falls below the target design factor of \(String(format: "%.2f", targetDesign)) (margin of safety: \(String(format: "%+.1f%%", margin * 100.0)))."
            } else {
                overallVerdict = .fail
                fosAssessment = "Structural integrity failure detected. Minimum FoS of \(String(format: "%.2f", mFoS)) is below 1.0, indicating localized yielding or structural failure."
            }
        } else {
            minFoS = nil
            marginOfSafety = nil
            if study.studyType == .linearStatic {
                overallVerdict = .fail
                fosAssessment = "Factor of Safety evaluation was not available for this linear static study."
            } else {
                overallVerdict = .inconclusive
                fosAssessment = "Factor of Safety evaluation is not applicable for \(study.studyType.displayName) studies."
            }
        }

        var peakStressComparison: String? = nil
        let peakExtrema = study.results.extrema.first { ext in
            let lower = ext.fieldName.lowercased()
            return lower.contains("von mises") || lower.contains("stress")
        }
        if let peak = peakExtrema?.maxValue ?? study.results.nodalVonMisesStresses?.values.max() {
            let matId = study.materials.first?.materialId ?? "structural-steel"
            let material = MaterialLibrary().material(withId: matId) ?? StandardMaterials.structuralSteel
            let yield = material.yieldStrengthMPa
            let pct = (peak / max(1e-6, yield)) * 100.0
            let dispPeak = SimulationUnitConversion.displayStress(peak, unit: unit)
            let dispYield = SimulationUnitConversion.displayStress(yield, unit: unit)
            let sym = SimulationUnitConversion.stressUnitSymbol(unit: unit)
            peakStressComparison = "Peak von Mises stress of \(String(format: "%.1f", dispPeak)) \(sym) reaches \(String(format: "%.1f%%", pct)) of material yield strength (\(String(format: "%.1f", dispYield)) \(sym))."
        }

        var totalAppliedForceN = SIMD3<Double>.zero
        var hasForceLoads = false
        for load in study.loads {
            switch load.kind {
            case .force, .remoteLoad, .bearing:
                totalAppliedForceN += load.direction * load.magnitude
                hasForceLoads = true
            default:
                break
            }
        }

        let isEquilibriumSatisfied: Bool?
        let reactionForceResidualN: Double?
        let staticEquilibriumAssessment: String?

        if let reactions = study.results.constraintReactions, !reactions.isEmpty {
            let totalReactionN = reactions.reduce(SIMD3<Double>.zero) { $0 + $1.reactionForce }
            let residualVec = totalAppliedForceN + totalReactionN
            let residualMag = simd_length(residualVec)
            reactionForceResidualN = residualMag

            let appliedMag = simd_length(totalAppliedForceN)
            let tolerance = max(1e-2, 0.02 * appliedMag)
            let satisfied = residualMag <= tolerance
            isEquilibriumSatisfied = satisfied

            let dispResidual = SimulationUnitConversion.displayForce(residualMag, unit: unit)
            let forceSym = SimulationUnitConversion.forceUnitSymbol(unit: unit)
            if satisfied {
                staticEquilibriumAssessment = "Static equilibrium satisfied with residual resultant force of \(String(format: "%.3g", dispResidual)) \(forceSym)."
            } else {
                staticEquilibriumAssessment = "Static equilibrium residual force of \(String(format: "%.3g", dispResidual)) \(forceSym) exceeds acceptable equilibrium tolerance."
            }
        } else {
            isEquilibriumSatisfied = nil
            reactionForceResidualN = nil
            staticEquilibriumAssessment = hasForceLoads ? "Constraint reactions not available to verify static equilibrium." : nil
        }

        let meshStats = study.results.meshStatistics
        let meshQualityAssessment: String?
        if meshStats.elementCount > 0 {
            let maxAspect = meshStats.qualityReport?.aspectRatioSummary.maxValue ?? 1.0
            let aspectCat = maxAspect <= 5.0 ? "optimal" : (maxAspect <= 10.0 ? "acceptable" : "marginal")
            meshQualityAssessment = "Mesh comprises \(meshStats.nodeCount) nodes and \(meshStats.elementCount) tetrahedral elements with average quality \(String(format: "%.3f", meshStats.avgElementQuality)) (min \(String(format: "%.3f", meshStats.minElementQuality)), max aspect ratio \(String(format: "%.1f", maxAspect > 0 ? maxAspect : 1.0)) - \(aspectCat))."
        } else {
            meshQualityAssessment = "Model is unmeshed."
        }

        var findings: [String] = []
        if let minF = minFoS {
            if minF >= targetDesign {
                findings.append("Structural integrity passed: Minimum Factor of Safety (\(String(format: "%.2f", minF))) exceeds the design target (\(String(format: "%.2f", targetDesign))).")
            } else if minF >= 1.0 {
                findings.append("Structural integrity marginal: Minimum Factor of Safety (\(String(format: "%.2f", minF))) exceeds yield but violates the design target (\(String(format: "%.2f", targetDesign))).")
            } else {
                findings.append("Structural integrity failure: Minimum Factor of Safety (\(String(format: "%.2f", minF))) indicates localized material yielding.")
            }
        }
        if let peakComp = peakStressComparison {
            findings.append(peakComp)
        }
        if let eqAssess = staticEquilibriumAssessment {
            findings.append(eqAssess)
        }
        if let meshAssess = meshQualityAssessment {
            findings.append(meshAssess)
        }
        if let dispExt = study.results.extrema.first(where: { $0.fieldName.lowercased().contains("displacement") }) {
            let dispVal = SimulationUnitConversion.displayLength(dispExt.maxValue, unit: unit)
            let lenSym = SimulationUnitConversion.lengthUnitSymbol(unit: unit)
            findings.append("Maximum displacement is \(String(format: "%.3f", dispVal)) \(lenSym).")
        }

        return SimulationReportConclusions(
            overallVerdict: overallVerdict,
            factorOfSafetyAssessment: fosAssessment,
            minFactorOfSafety: minFoS,
            targetDesignFactor: targetDesign,
            marginOfSafety: marginOfSafety,
            peakStressComparison: peakStressComparison,
            staticEquilibriumAssessment: staticEquilibriumAssessment,
            reactionForceResidualN: reactionForceResidualN,
            isEquilibriumSatisfied: isEquilibriumSatisfied,
            meshQualityAssessment: meshQualityAssessment,
            keyFindings: findings
        )
    }

    // MARK: - Data Building

    public static func buildReportData(
        study: SimulationStudy,
        options: SimulationReportOptions = .init()
    ) -> SimulationReportData {
        let unit = options.lengthUnit
        let conclusions = synthesizeConclusions(study: study, unit: unit)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let timestamp = dateFormatter.string(from: Date())

        var materials: [SimulationReportMaterialItem] = []
        for matAssign in study.materials {
            let mat = MaterialLibrary().material(withId: matAssign.materialId) ?? StandardMaterials.structuralSteel
            let dispE = SimulationUnitConversion.displayStress(mat.youngsModulusGPa * 1000.0, unit: unit)
            let dispYield = SimulationUnitConversion.displayStress(mat.yieldStrengthMPa, unit: unit)
            let stressSym = SimulationUnitConversion.stressUnitSymbol(unit: unit)
            let youngsStr = "\(String(format: "%.1f", dispE)) \(stressSym)"
            let yieldStr = "\(String(format: "%.1f", dispYield)) \(stressSym)"
            let densityStr = unit.isImperial ?
                String(format: "%.3f lb/in³", mat.densityKgPerM3 * 0.0000361273) :
                String(format: "%.0f kg/m³", mat.densityKgPerM3)
            let nuStr = String(format: "%.2f", mat.poissonsRatioValue)
            materials.append(
                SimulationReportMaterialItem(
                    name: matAssign.name.isEmpty ? mat.name : "\(matAssign.name) (\(mat.name))",
                    category: mat.category.displayName,
                    youngsModulus: youngsStr,
                    poissonsRatio: nuStr,
                    density: densityStr,
                    yieldStrength: yieldStr
                )
            )
        }

        var fixtures: [SimulationReportFixtureItem] = []
        for f in study.fixtures {
            var restraints: [String] = []
            if f.isRestrainedX { restraints.append("X") }
            if f.isRestrainedY { restraints.append("Y") }
            if f.isRestrainedZ { restraints.append("Z") }
            let rStr = restraints.isEmpty ? "None" : restraints.joined(separator: ", ")
            let desc = f.kind == .elasticSupport ?
                "Elastic (K=\(String(format: "%.1e", f.elasticStiffness.x)))" :
                "Restrained: [\(rStr)]"
            fixtures.append(
                SimulationReportFixtureItem(
                    name: f.name,
                    kindDisplayName: f.kind.displayName,
                    targetCount: f.targetReferences.count,
                    restraintsDescription: desc
                )
            )
        }

        var loads: [SimulationReportLoadItem] = []
        for l in study.loads {
            let dispMag = SimulationUnitConversion.displayLoadMagnitude(l.magnitude, kind: l.kind, unit: unit)
            let sym = SimulationUnitConversion.loadUnitSymbol(kind: l.kind, unit: unit)
            loads.append(
                SimulationReportLoadItem(
                    name: l.name,
                    kindDisplayName: l.kind.displayName,
                    magnitudeDisplay: dispMag,
                    directionDisplay: l.direction,
                    unitSymbol: sym,
                    targetCount: l.targetReferences.count
                )
            )
        }

        let convertedExtrema = SimulationUnitConversion.displayExtrema(
            study.results.extrema,
            coordinateSystem: nil,
            lengthUnit: unit
        )
        let extremaItems = convertedExtrema.map {
            SimulationReportExtremaItem(
                fieldName: $0.fieldName,
                minValue: $0.minValue,
                maxValue: $0.maxValue,
                unitSymbol: $0.unitSymbol
            )
        }

        let fos = study.results.factorOfSafety ?? FactorOfSafetyCalculator.evaluate(study: study)
        let peakExt = study.results.extrema.first { ext in
            let lower = ext.fieldName.lowercased()
            return lower.contains("von mises") || lower.contains("stress")
        }
        let peakMPa = peakExt?.maxValue ?? study.results.nodalVonMisesStresses?.values.max()
        let dispPeak = peakMPa.map { SimulationUnitConversion.displayStress($0, unit: unit) }
        let matId = study.materials.first?.materialId ?? "structural-steel"
        let material = MaterialLibrary().material(withId: matId) ?? StandardMaterials.structuralSteel
        let dispYield = SimulationUnitConversion.displayStress(material.yieldStrengthMPa, unit: unit)

        var reactionItems: [SimulationReportReactionItem] = []
        if let rxns = study.results.constraintReactions {
            for r in rxns {
                let fMag = simd_length(r.reactionForce)
                let dispFMag = SimulationUnitConversion.displayForce(fMag, unit: unit)
                let dispFVec = SimulationUnitConversion.displayForce(r.reactionForce, unit: unit)
                let mMag = simd_length(r.reactionMoment)
                let dispMMag = SimulationUnitConversion.displayMoment(mMag, unit: unit)
                let dispMVec = SimulationUnitConversion.displayMoment(r.reactionMoment, unit: unit)
                let dispCentroid = SIMD3<Double>(
                    SimulationUnitConversion.displayLength(r.referencePoint.x, unit: unit),
                    SimulationUnitConversion.displayLength(r.referencePoint.y, unit: unit),
                    SimulationUnitConversion.displayLength(r.referencePoint.z, unit: unit)
                )
                reactionItems.append(
                    SimulationReportReactionItem(
                        id: r.id,
                        fixtureName: r.fixtureName,
                        forceMag: dispFMag,
                        forceVec: dispFVec,
                        momentMag: dispMMag,
                        momentVec: dispMVec,
                        centroid: dispCentroid,
                        nodeCount: r.nodeCount
                    )
                )
            }
        }

        var totalReactionForceMagDisplay: Double? = nil
        var totalReactionForceVecDisplay: SIMD3<Double>? = nil
        if let totalF = study.results.totalReactionForce {
            totalReactionForceMagDisplay = SimulationUnitConversion.displayForce(simd_length(totalF), unit: unit)
            totalReactionForceVecDisplay = SimulationUnitConversion.displayForce(totalF, unit: unit)
        }

        var totalReactionMomentMagDisplay: Double? = nil
        var totalReactionMomentVecDisplay: SIMD3<Double>? = nil
        if let totalM = study.results.totalReactionMoment {
            totalReactionMomentMagDisplay = SimulationUnitConversion.displayMoment(simd_length(totalM), unit: unit)
            totalReactionMomentVecDisplay = SimulationUnitConversion.displayMoment(totalM, unit: unit)
        }

        var totalAppliedForceMagDisplay: Double? = nil
        var totalAppliedForceVecDisplay: SIMD3<Double>? = nil
        var totalAppliedN = SIMD3<Double>.zero
        for l in study.loads {
            if l.kind == .force || l.kind == .remoteLoad || l.kind == .bearing {
                totalAppliedN += l.direction * l.magnitude
            }
        }
        if simd_length(totalAppliedN) > 1e-6 {
            totalAppliedForceMagDisplay = SimulationUnitConversion.displayForce(simd_length(totalAppliedN), unit: unit)
            totalAppliedForceVecDisplay = SimulationUnitConversion.displayForce(totalAppliedN, unit: unit)
        }

        var forceResidualMagDisplay: Double? = nil
        if let resN = conclusions.reactionForceResidualN {
            forceResidualMagDisplay = SimulationUnitConversion.displayForce(resN, unit: unit)
        }

        var bodySummaryItems: [SimulationReportBodySummaryItem] = []
        if let bSummaries = study.results.bodySummaries {
            for b in bSummaries {
                let dispStress = b.maxVonMisesStress.map { SimulationUnitConversion.displayStress($0, unit: unit) }
                let dispDisp = b.maxDisplacement.map { SimulationUnitConversion.displayLength($0, unit: unit) }
                let dispTemp = b.maxTemperature.map { SimulationUnitConversion.displayTemperature($0, unit: unit) }
                bodySummaryItems.append(
                    SimulationReportBodySummaryItem(
                        id: b.id,
                        bodyName: b.bodyName,
                        nodeCount: b.nodeCount,
                        elementCount: b.elementCount,
                        maxStress: dispStress,
                        maxDisplacement: dispDisp,
                        minFactorOfSafety: b.minFactorOfSafety,
                        maxTemperature: dispTemp
                    )
                )
            }
        }

        var probeItems: [SimulationReportProbeItem] = []
        for (idx, p) in study.probeTable.probes.enumerated() {
            let dispPos = SIMD3<Double>(
                SimulationUnitConversion.displayLength(p.position.x, unit: unit),
                SimulationUnitConversion.displayLength(p.position.y, unit: unit),
                SimulationUnitConversion.displayLength(p.position.z, unit: unit)
            )
            let dispDist = p.distanceAlongPath.map { SimulationUnitConversion.displayLength($0, unit: unit) }
            let val = p.fieldValues[study.contourSettings.field] ?? p.fieldValues.first?.value
            probeItems.append(
                SimulationReportProbeItem(
                    id: p.id,
                    index: idx + 1,
                    name: p.name,
                    kindDisplayName: p.kind.displayName,
                    position: dispPos,
                    distanceAlongPath: dispDist,
                    nodeId: p.nodeId,
                    elementId: p.elementId,
                    primaryValue: val,
                    unitSymbol: study.contourSettings.field.defaultUnitSymbol
                )
            )
        }

        let mStats = study.results.meshStatistics

        return SimulationReportData(
            studyId: study.id,
            studyName: study.name,
            reportTitle: options.title ?? "\(study.name) - Simulation Report",
            studyType: study.studyType,
            status: study.results.status,
            timestamp: timestamp,
            executionTimeSeconds: study.results.runtimeDuration,
            options: options,
            conclusions: conclusions,
            targetCount: study.targets.count,
            materials: materials,
            fixtures: fixtures,
            loads: loads,
            solverType: study.solver.engine.displayName,
            solverTolerance: study.solver.convergenceTolerance,
            solverMaxIterations: study.solver.maxIterations,
            nodeCount: mStats.nodeCount,
            elementCount: mStats.elementCount,
            elementOrder: study.mesh.elementOrder.displayName,
            minQuality: mStats.minElementQuality,
            avgQuality: mStats.avgElementQuality,
            maxAspectRatio: mStats.qualityReport?.aspectRatioSummary.maxValue ?? 1.0,
            extrema: extremaItems,
            minFactorOfSafety: conclusions.minFactorOfSafety,
            maxFactorOfSafety: fos?.maxFactorOfSafety,
            targetDesignFactor: conclusions.targetDesignFactor,
            peakStress: dispPeak,
            yieldStrength: dispYield,
            stressUnitSymbol: SimulationUnitConversion.stressUnitSymbol(unit: unit),
            reactions: reactionItems,
            totalReactionForceMag: totalReactionForceMagDisplay,
            totalReactionForceVec: totalReactionForceVecDisplay,
            totalReactionMomentMag: totalReactionMomentMagDisplay,
            totalReactionMomentVec: totalReactionMomentVecDisplay,
            totalAppliedForceMag: totalAppliedForceMagDisplay,
            totalAppliedForceVec: totalAppliedForceVecDisplay,
            forceResidualMag: forceResidualMagDisplay,
            forceUnitSymbol: SimulationUnitConversion.forceUnitSymbol(unit: unit),
            momentUnitSymbol: SimulationUnitConversion.momentUnitSymbol(unit: unit),
            lengthUnitSymbol: SimulationUnitConversion.lengthUnitSymbol(unit: unit),
            bodySummaries: bodySummaryItems,
            probes: probeItems
        )
    }

    // MARK: - HTML Report Generation

    public static func generateHTML(
        study: SimulationStudy,
        options: SimulationReportOptions = .init()
    ) -> String {
        let data = buildReportData(study: study, options: options)
        return generateHTML(data: data, options: options)
    }

    public static func generateHTML(
        data: SimulationReportData,
        options: SimulationReportOptions = .init()
    ) -> String {
        func escape(_ str: String) -> String {
            str.replacingOccurrences(of: "&", with: "&amp;")
               .replacingOccurrences(of: "<", with: "&lt;")
               .replacingOccurrences(of: ">", with: "&gt;")
               .replacingOccurrences(of: "\"", with: "&quot;")
        }

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(data.reportTitle))</title>
          <style>
            :root {
              --bg: #f9fafb;
              --card-bg: #ffffff;
              --border: #e5e7eb;
              --text-main: #111827;
              --text-muted: #4b5563;
              --primary: #2563eb;
            }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
              background-color: var(--bg);
              color: var(--text-main);
              line-height: 1.5;
              margin: 0;
              padding: 32px 20px;
            }
            .container {
              max-width: 920px;
              margin: 0 auto;
            }
            .card {
              background: var(--card-bg);
              border: 1px solid var(--border);
              border-radius: 8px;
              padding: 24px;
              margin-bottom: 24px;
              box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
            }
            h1 {
              font-size: 26px;
              font-weight: 700;
              margin: 0 0 8px 0;
              color: var(--text-main);
            }
            h2 {
              font-size: 17px;
              font-weight: 600;
              margin: 0 0 16px 0;
              padding-bottom: 8px;
              border-bottom: 1px solid var(--border);
              color: var(--text-main);
            }
            .subtitle {
              color: var(--text-muted);
              font-size: 14px;
              margin-bottom: 16px;
            }
            .meta-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 12px;
              margin-bottom: 16px;
              font-size: 13px;
            }
            .meta-item {
              display: flex;
              flex-direction: column;
            }
            .meta-label {
              color: var(--text-muted);
              font-size: 11px;
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }
            .meta-val {
              font-weight: 600;
            }
            .verdict-badge {
              display: inline-flex;
              align-items: center;
              padding: 8px 16px;
              border-radius: 6px;
              font-weight: 700;
              font-size: 15px;
              margin-top: 8px;
              border: 1px solid;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 13px;
              margin-bottom: 12px;
            }
            th {
              background-color: #f3f4f6;
              text-align: left;
              padding: 8px 12px;
              font-weight: 600;
              border-bottom: 2px solid var(--border);
              color: #374151;
            }
            td {
              padding: 8px 12px;
              border-bottom: 1px solid var(--border);
            }
            tr:nth-child(even) td {
              background-color: #fcfcfd;
            }
            .findings-list {
              padding-left: 20px;
              margin: 8px 0;
            }
            .findings-list li {
              margin-bottom: 6px;
              font-size: 14px;
            }
            .svg-container {
              margin: 16px 0;
            }
            @media print {
              body { background: #fff; padding: 0; }
              .card { box-shadow: none; border: 1px solid #ddd; page-break-inside: avoid; }
            }
          </style>
        </head>
        <body>
        <div class="container">
        """

        // Header Card
        let verdict = data.conclusions.overallVerdict
        html += """
          <div class="card">
            <h1>\(escape(data.reportTitle))</h1>
            <div class="subtitle">Study: \(escape(data.studyName)) &bull; Type: \(escape(data.studyType.displayName))</div>
            <div class="meta-grid">
              <div class="meta-item"><span class="meta-label">Solve Status</span><span class="meta-val">\(escape(data.status.displayName))</span></div>
              <div class="meta-item"><span class="meta-label">Generated</span><span class="meta-val">\(escape(data.timestamp))</span></div>
        """
        if let author = options.author, !author.isEmpty {
            html += "<div class=\"meta-item\"><span class=\"meta-label\">Author</span><span class=\"meta-val\">\(escape(author))</span></div>"
        }
        if let company = options.company, !company.isEmpty {
            html += "<div class=\"meta-item\"><span class=\"meta-label\">Company</span><span class=\"meta-val\">\(escape(company))</span></div>"
        }
        if let dur = data.executionTimeSeconds {
            html += "<div class=\"meta-item\"><span class=\"meta-label\">Execution Time</span><span class=\"meta-val\">\(String(format: "%.2f s", dur))</span></div>"
        }
        html += """
            </div>
            <div class="verdict-badge" style="background-color: \(verdict.badgeBgColorHex); color: \(verdict.badgeTextColorHex); border-color: \(verdict.badgeBorderColorHex);">
              VERDICT: \(verdict.displayName.uppercased())
            </div>
          </div>
        """

        // Study Setup
        if options.includeSetup {
            html += """
              <div class="card">
                <h2>Study Setup &amp; Discretization</h2>
                <div class="meta-grid">
                  <div class="meta-item"><span class="meta-label">Model Targets</span><span class="meta-val">\(data.targetCount) targets</span></div>
                  <div class="meta-item"><span class="meta-label">Solver Type</span><span class="meta-val">\(escape(data.solverType))</span></div>
                  <div class="meta-item"><span class="meta-label">Tolerance</span><span class="meta-val">\(String(format: "%.1e", data.solverTolerance))</span></div>
                  <div class="meta-item"><span class="meta-label">Max Iterations</span><span class="meta-val">\(data.solverMaxIterations)</span></div>
                </div>

                <h3 style="font-size: 14px; margin: 16px 0 8px 0;">Assigned Materials</h3>
                <table>
                  <thead>
                    <tr><th>Material</th><th>Category</th><th>Young's Modulus</th><th>Poisson's Ratio</th><th>Density</th><th>Yield Strength</th></tr>
                  </thead>
                  <tbody>
            """
            if data.materials.isEmpty {
                html += "<tr><td colspan=\"6\" style=\"text-align:center; color:#6b7280;\">No material assignments defined</td></tr>"
            } else {
                for m in data.materials {
                    html += "<tr><td>\(escape(m.name))</td><td>\(escape(m.category))</td><td>\(escape(m.youngsModulus))</td><td>\(escape(m.poissonsRatio))</td><td>\(escape(m.density))</td><td>\(escape(m.yieldStrength))</td></tr>"
                }
            }
            html += """
                  </tbody>
                </table>

                <h3 style="font-size: 14px; margin: 16px 0 8px 0;">Boundary Fixtures</h3>
                <table>
                  <thead>
                    <tr><th>Fixture</th><th>Kind</th><th>Targets</th><th>Restraints / Stiffness</th></tr>
                  </thead>
                  <tbody>
            """
            if data.fixtures.isEmpty {
                html += "<tr><td colspan=\"4\" style=\"text-align:center; color:#6b7280;\">No boundary fixtures defined</td></tr>"
            } else {
                for f in data.fixtures {
                    html += "<tr><td>\(escape(f.name))</td><td>\(escape(f.kindDisplayName))</td><td>\(f.targetCount)</td><td>\(escape(f.restraintsDescription))</td></tr>"
                }
            }
            html += """
                  </tbody>
                </table>

                <h3 style="font-size: 14px; margin: 16px 0 8px 0;">Applied Loads</h3>
                <table>
                  <thead>
                    <tr><th>Load</th><th>Kind</th><th>Magnitude</th><th>Direction [X, Y, Z]</th><th>Targets</th></tr>
                  </thead>
                  <tbody>
            """
            if data.loads.isEmpty {
                html += "<tr><td colspan=\"5\" style=\"text-align:center; color:#6b7280;\">No loads applied</td></tr>"
            } else {
                for l in data.loads {
                    html += "<tr><td>\(escape(l.name))</td><td>\(escape(l.kindDisplayName))</td><td>\(String(format: "%.2f", l.magnitudeDisplay)) \(escape(l.unitSymbol))</td><td>[\(String(format: "%.2f", l.directionDisplay.x)), \(String(format: "%.2f", l.directionDisplay.y)), \(String(format: "%.2f", l.directionDisplay.z))]</td><td>\(l.targetCount)</td></tr>"
                }
            }
            html += """
                  </tbody>
                </table>
              </div>
            """
        }

        // Discretization Statistics
        if options.includeMeshStats {
            html += """
              <div class="card">
                <h2>Mesh Statistics &amp; Discretization Quality</h2>
                <table>
                  <thead>
                    <tr><th>Mesh Nodes</th><th>Tetrahedral Elements</th><th>Element Order</th><th>Min Element Quality</th><th>Avg Element Quality</th><th>Max Aspect Ratio</th></tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td>\(data.nodeCount)</td>
                      <td>\(data.elementCount)</td>
                      <td>\(escape(data.elementOrder))</td>
                      <td>\(String(format: "%.3f", data.minQuality))</td>
                      <td>\(String(format: "%.3f", data.avgQuality))</td>
                      <td>\(String(format: "%.1f", data.maxAspectRatio > 0 ? data.maxAspectRatio : 1.0))</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            """
        }

        // Extrema & Graphical Plots
        if options.includeExtrema || options.includePlots {
            html += """
              <div class="card">
                <h2>Results Extrema &amp; Graphical Plots</h2>
            """
            if options.includeExtrema {
                html += """
                <table>
                  <thead>
                    <tr><th>Field Name</th><th>Minimum Value</th><th>Maximum Value</th><th>Unit</th></tr>
                  </thead>
                  <tbody>
                """
                if data.extrema.isEmpty {
                    html += "<tr><td colspan=\"4\" style=\"text-align:center; color:#6b7280;\">No result extrema available</td></tr>"
                } else {
                    for ext in data.extrema {
                        html += "<tr><td>\(escape(ext.fieldName))</td><td>\(String(format: "%.3g", ext.minValue))</td><td>\(String(format: "%.3g", ext.maxValue))</td><td>\(escape(ext.unitSymbol))</td></tr>"
                    }
                }
                html += """
                  </tbody>
                </table>
                """
            }

            if options.includePlots {
                html += "<div class=\"svg-container\">"
                html += buildFoSGaugeSVG(minFoS: data.minFactorOfSafety, target: data.targetDesignFactor)
                html += "</div>"

                if let peak = data.peakStress, let yield = data.yieldStrength {
                    html += "<div class=\"svg-container\">"
                    html += buildStressChartSVG(peakStress: peak, yieldStrength: yield, unitSymbol: data.stressUnitSymbol)
                    html += "</div>"
                }
            }
            html += "</div>"
        }

        // Constraint Reactions & Static Equilibrium
        if options.includeReactions {
            html += """
              <div class="card">
                <h2>Constraint Reactions &amp; Static Equilibrium</h2>
                <table>
                  <thead>
                    <tr><th>Fixture</th><th>Resultant Force [\(escape(data.forceUnitSymbol))]</th><th>Resultant Moment [\(escape(data.momentUnitSymbol))]</th><th>Centroid [\(escape(data.lengthUnitSymbol))]</th><th>Nodes</th></tr>
                  </thead>
                  <tbody>
            """
            if data.reactions.isEmpty {
                html += "<tr><td colspan=\"5\" style=\"text-align:center; color:#6b7280;\">No constraint reactions recorded</td></tr>"
            } else {
                for rxn in data.reactions {
                    html += "<tr><td>\(escape(rxn.fixtureName))</td><td>\(String(format: "%.2f", rxn.forceMag)) [\(String(format: "%.2f", rxn.forceVec.x)), \(String(format: "%.2f", rxn.forceVec.y)), \(String(format: "%.2f", rxn.forceVec.z))]</td><td>\(String(format: "%.2f", rxn.momentMag)) [\(String(format: "%.2f", rxn.momentVec.x)), \(String(format: "%.2f", rxn.momentVec.y)), \(String(format: "%.2f", rxn.momentVec.z))]</td><td>[\(String(format: "%.1f", rxn.centroid.x)), \(String(format: "%.1f", rxn.centroid.y)), \(String(format: "%.1f", rxn.centroid.z))]</td><td>\(rxn.nodeCount)</td></tr>"
                }
            }
            html += """
                  </tbody>
                </table>
            """
            if let tfMag = data.totalReactionForceMag, let tfVec = data.totalReactionForceVec,
               let tmMag = data.totalReactionMomentMag, let tmVec = data.totalReactionMomentVec {
                html += """
                <div style="background:#f3f4f6; border-radius:6px; padding:12px; margin-top:12px; font-size:13px;">
                  <div><strong>Total Reaction Force:</strong> \(String(format: "%.2f", tfMag)) \(escape(data.forceUnitSymbol)) [\(String(format: "%.2f", tfVec.x)), \(String(format: "%.2f", tfVec.y)), \(String(format: "%.2f", tfVec.z))]</div>
                  <div><strong>Total Reaction Moment:</strong> \(String(format: "%.2f", tmMag)) \(escape(data.momentUnitSymbol)) [\(String(format: "%.2f", tmVec.x)), \(String(format: "%.2f", tmVec.y)), \(String(format: "%.2f", tmVec.z))]</div>
                """
                if let assess = data.conclusions.staticEquilibriumAssessment {
                    html += "<div style=\"margin-top:6px; color:#374151;\"><strong>Equilibrium Evaluation:</strong> \(escape(assess))</div>"
                }
                html += "</div>"
            }
            html += "</div>"
        }

        // Body Summaries
        if options.includeBodySummaries && !data.bodySummaries.isEmpty {
            html += """
              <div class="card">
                <h2>Partitioned Body Summaries</h2>
                <table>
                  <thead>
                    <tr><th>Body Name</th><th>Nodes</th><th>Elements</th><th>Max Stress [\(escape(data.stressUnitSymbol))]</th><th>Max Disp [\(escape(data.lengthUnitSymbol))]</th><th>Min FoS</th><th>Max Temp</th></tr>
                  </thead>
                  <tbody>
            """
            for b in data.bodySummaries {
                let sStr = b.maxStress.map { String(format: "%.1f", $0) } ?? "-"
                let dStr = b.maxDisplacement.map { String(format: "%.3f", $0) } ?? "-"
                let fosStr = b.minFactorOfSafety.map { String(format: "%.2f", $0) } ?? "-"
                let tStr = b.maxTemperature.map { String(format: "%.1f", $0) } ?? "-"
                html += "<tr><td>\(escape(b.bodyName))</td><td>\(b.nodeCount)</td><td>\(b.elementCount)</td><td>\(sStr)</td><td>\(dStr)</td><td>\(fosStr)</td><td>\(tStr)</td></tr>"
            }
            html += """
                  </tbody>
                </table>
              </div>
            """
        }

        // Probes
        if options.includeProbes && !data.probes.isEmpty {
            html += """
              <div class="card">
                <h2>Probes &amp; Inspection Results</h2>
                <table>
                  <thead>
                    <tr><th>#</th><th>Name</th><th>Kind</th><th>Position [\(escape(data.lengthUnitSymbol))]</th><th>Distance</th><th>Value</th></tr>
                  </thead>
                  <tbody>
            """
            for p in data.probes {
                let distStr = p.distanceAlongPath.map { String(format: "%.2f \(data.lengthUnitSymbol)", $0) } ?? "-"
                let valStr = p.primaryValue.map { "\(String(format: "%.2f", $0)) \(p.unitSymbol)" } ?? "-"
                html += "<tr><td>\(p.index)</td><td>\(escape(p.name))</td><td>\(escape(p.kindDisplayName))</td><td>(\(String(format: "%.1f", p.position.x)), \(String(format: "%.1f", p.position.y)), \(String(format: "%.1f", p.position.z)))</td><td>\(distStr)</td><td>\(valStr)</td></tr>"
            }
            html += """
                  </tbody>
                </table>
              </div>
            """
        }

        // Engineering Conclusions
        if options.includeConclusions {
            html += """
              <div class="card">
                <h2>Engineering Conclusions &amp; Synthesis</h2>
                <p><strong>Structural Integrity:</strong> \(escape(data.conclusions.factorOfSafetyAssessment))</p>
            """
            if let peakComp = data.conclusions.peakStressComparison {
                html += "<p><strong>Peak Stress Comparison:</strong> \(escape(peakComp))</p>"
            }
            if let eqAssess = data.conclusions.staticEquilibriumAssessment {
                html += "<p><strong>Equilibrium Residuals:</strong> \(escape(eqAssess))</p>"
            }
            html += """
                <h3 style="font-size: 14px; margin: 16px 0 8px 0;">Key Findings</h3>
                <ul class="findings-list">
            """
            for f in data.conclusions.keyFindings {
                html += "<li>\(escape(f))</li>"
            }
            html += """
                </ul>
              </div>
            """
        }

        html += """
        </div>
        </body>
        </html>
        """

        return html
    }

    private static func buildFoSGaugeSVG(minFoS: Double?, target: Double?) -> String {
        let targetVal = target ?? 1.5
        let minVal = minFoS ?? 1.0
        let maxScale = max(3.0, max(targetVal * 1.5, minVal * 1.25))
        let barWidth: Double = 420.0
        let startX: Double = 60.0
        let y: Double = 32.0
        let h: Double = 16.0

        let yieldX = startX + (1.0 / maxScale) * barWidth
        let targetX = startX + (targetVal / maxScale) * barWidth
        let redWidth = max(0.0, yieldX - startX)
        let amberWidth = max(0.0, targetX - yieldX)
        let greenWidth = max(0.0, (startX + barWidth) - targetX)

        let markerX = startX + (min(minVal, maxScale) / maxScale) * barWidth
        let markerColor = minVal >= targetVal ? "#10b981" : (minVal >= 1.0 ? "#f59e0b" : "#ef4444")

        return """
        <svg viewBox="0 0 540 85" width="100%" height="85" xmlns="http://www.w3.org/2000/svg" style="background:#f9fafb;border-radius:6px;border:1px solid #e5e7eb;padding:6px 0;">
          <text x="\(startX)" y="18" font-size="11" font-weight="600" fill="#374151">Factor of Safety Gauge</text>
          <rect x="\(startX)" y="\(y)" width="\(redWidth)" height="\(h)" fill="#ef4444" opacity="0.85" rx="3" />
          <rect x="\(yieldX)" y="\(y)" width="\(amberWidth)" height="\(h)" fill="#f59e0b" opacity="0.85" />
          <rect x="\(targetX)" y="\(y)" width="\(greenWidth)" height="\(h)" fill="#10b981" opacity="0.85" rx="3" />
          <line x1="\(yieldX)" y1="\(y - 4)" x2="\(yieldX)" y2="\(y + h + 4)" stroke="#1f2937" stroke-width="1.5" stroke-dasharray="2,2" />
          <text x="\(yieldX)" y="\(y + h + 15)" font-size="10" font-weight="500" fill="#4b5563" text-anchor="middle">1.0 (Yield)</text>
          <line x1="\(targetX)" y1="\(y - 4)" x2="\(targetX)" y2="\(y + h + 4)" stroke="#1f2937" stroke-width="1.5" stroke-dasharray="2,2" />
          <text x="\(targetX)" y="\(y + h + 15)" font-size="10" font-weight="500" fill="#4b5563" text-anchor="middle">Target (\(String(format: "%.1f", targetVal)))</text>
          <polygon points="\(markerX),\(y - 4) \(markerX - 4),\(y - 10) \(markerX + 4),\(y - 10)" fill="\(markerColor)" />
          <line x1="\(markerX)" y1="\(y - 4)" x2="\(markerX)" y2="\(y + h + 4)" stroke="\(markerColor)" stroke-width="2" />
          <text x="\(markerX)" y="\(y - 13)" font-size="11" font-weight="700" fill="\(markerColor)" text-anchor="middle">Min FoS: \(String(format: "%.2f", minVal))</text>
        </svg>
        """
    }

    private static func buildStressChartSVG(peakStress: Double, yieldStrength: Double, unitSymbol: String) -> String {
        let maxScale = max(peakStress, yieldStrength) * 1.25
        let barMaxWidth: Double = 310.0
        let startX: Double = 140.0
        let peakWidth = max(2.0, (peakStress / max(1e-6, maxScale)) * barMaxWidth)
        let yieldWidth = max(2.0, (yieldStrength / max(1e-6, maxScale)) * barMaxWidth)
        let pct = (peakStress / max(1e-6, yieldStrength)) * 100.0
        let peakColor = pct > 100.0 ? "#ef4444" : (pct > 80.0 ? "#f59e0b" : "#10b981")

        return """
        <svg viewBox="0 0 540 90" width="100%" height="90" xmlns="http://www.w3.org/2000/svg" style="background:#f9fafb;border-radius:6px;border:1px solid #e5e7eb;padding:6px 0;">
          <text x="130" y="30" font-size="11" font-weight="600" fill="#374151" text-anchor="end">Peak von Mises</text>
          <rect x="\(startX)" y="18" width="\(peakWidth)" height="15" fill="\(peakColor)" rx="3" />
          <text x="\(startX + peakWidth + 8)" y="30" font-size="11" font-weight="600" fill="\(peakColor)">\(String(format: "%.1f", peakStress)) \(unitSymbol) (\(String(format: "%.1f%%", pct)))</text>
          <text x="130" y="60" font-size="11" font-weight="600" fill="#374151" text-anchor="end">Yield Strength</text>
          <rect x="\(startX)" y="48" width="\(yieldWidth)" height="15" fill="#6b7280" opacity="0.6" rx="3" />
          <text x="\(startX + yieldWidth + 8)" y="60" font-size="11" font-weight="600" fill="#4b5563">\(String(format: "%.1f", yieldStrength)) \(unitSymbol)</text>
        </svg>
        """
    }

    // MARK: - CoreGraphics Multi-Page PDF Generation

    @MainActor
    public static func generatePDF(
        study: SimulationStudy,
        options: SimulationReportOptions = .init()
    ) throws -> Data {
        let data = buildReportData(study: study, options: options)
        return try generatePDF(data: data, options: options)
    }

    @MainActor
    public static func generatePDF(
        data: SimulationReportData,
        options: SimulationReportOptions = .init()
    ) throws -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw SimulationReportError.contextCreationFailed
        }

        // Standard Letter dimensions: 612 x 792 pt
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SimulationReportError.contextCreationFailed
        }

        let totalPages = data.hasPage3 ? 3 : 2

        // Page 1: Title, Executive Summary Badge, Setup & Materials
        context.beginPage(mediaBox: &mediaBox)
        renderPDFPage1(in: context, data: data, totalPages: totalPages)
        context.endPage()

        // Page 2: Mesh Stats, Extrema, FoS Gauge, Stress Bar, Reactions, Conclusions
        context.beginPage(mediaBox: &mediaBox)
        renderPDFPage2(in: context, data: data, totalPages: totalPages)
        context.endPage()

        // Page 3: Body Summaries & Probes (if present)
        if data.hasPage3 {
            context.beginPage(mediaBox: &mediaBox)
            renderPDFPage3(in: context, data: data, totalPages: totalPages)
            context.endPage()
        }

        context.closePDF()
        return pdfData as Data
    }

    @MainActor
    public static func exportReport(
        study: SimulationStudy,
        format: SimulationReportFormat,
        to url: URL,
        options: SimulationReportOptions = .init()
    ) throws {
        switch format {
        case .html:
            let html = generateHTML(study: study, options: options)
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw SimulationReportError.writeFailed(error.localizedDescription)
            }
        case .pdf:
            let data = try generatePDF(study: study, options: options)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw SimulationReportError.writeFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - PDF Page Renderers

    @MainActor
    private static func renderHeaderAndFooter(
        in context: CGContext,
        title: String,
        pageNumber: Int,
        totalPages: Int,
        timestamp: String
    ) {
        // Header line & title
        drawText(in: context, text: title, at: CGPoint(x: 36, y: 765), fontSize: 9.0, bold: true, color: CGColor(gray: 0.35, alpha: 1.0))
        drawText(in: context, text: timestamp, at: CGPoint(x: 576, y: 765), fontSize: 8.5, bold: false, color: CGColor(gray: 0.5, alpha: 1.0), hAlign: .right)
        drawLine(in: context, from: CGPoint(x: 36, y: 757), to: CGPoint(x: 576, y: 757), color: CGColor(gray: 0.85, alpha: 1.0))

        // Footer line & pagination
        drawLine(in: context, from: CGPoint(x: 36, y: 36), to: CGPoint(x: 576, y: 36), color: CGColor(gray: 0.85, alpha: 1.0))
        drawText(in: context, text: "Made CAE Simulation Suite", at: CGPoint(x: 36, y: 22), fontSize: 8.5, bold: false, color: CGColor(gray: 0.5, alpha: 1.0))
        drawText(in: context, text: "Page \(pageNumber) of \(totalPages)", at: CGPoint(x: 576, y: 22), fontSize: 8.5, bold: true, color: CGColor(gray: 0.35, alpha: 1.0), hAlign: .right)
    }

    @MainActor
    private static func renderPDFPage1(in context: CGContext, data: SimulationReportData, totalPages: Int) {
        renderHeaderAndFooter(in: context, title: data.reportTitle, pageNumber: 1, totalPages: totalPages, timestamp: data.timestamp)

        var y: CGFloat = 740

        // Title Block
        drawText(in: context, text: data.reportTitle, at: CGPoint(x: 36, y: y), fontSize: 18.0, bold: true, color: CGColor(gray: 0.1, alpha: 1.0))
        y -= 18
        drawText(in: context, text: "Study: \(data.studyName)  •  Type: \(data.studyType.displayName)", at: CGPoint(x: 36, y: y), fontSize: 10.0, bold: false, color: CGColor(gray: 0.4, alpha: 1.0))
        y -= 22

        // Executive Verdict Badge
        let verdict = data.conclusions.overallVerdict
        let verdictRect = CGRect(x: 36, y: y - 36, width: 540, height: 36)
        let (vFill, vBorder, vText) = verdictColors(verdict)
        drawRoundedRect(in: context, rect: verdictRect, radius: 4, fillColor: vFill, strokeColor: vBorder)

        drawText(in: context, text: "VERDICT: \(verdict.displayName.uppercased())", at: CGPoint(x: 48, y: y - 22), fontSize: 13.0, bold: true, color: vText)
        if let minF = data.minFactorOfSafety {
            let marginStr = data.conclusions.marginOfSafety.map { String(format: "%+.1f%%", $0 * 100) } ?? ""
            drawText(in: context, text: "Min FoS: \(String(format: "%.2f", minF)) (\(marginStr))", at: CGPoint(x: 564, y: y - 22), fontSize: 11.0, bold: true, color: vText, hAlign: .right)
        }
        y -= 52

        // Study Setup Section
        drawSectionHeader(in: context, title: "Study Setup & Configuration", at: &y)

        // Metadata grid table
        let metaHeaders = ["Model Targets", "Solver Type", "Convergence Tolerance", "Max Iterations"]
        let metaRow = ["\(data.targetCount) targets", data.solverType, String(format: "%.1e", data.solverTolerance), "\(data.solverMaxIterations)"]
        drawTable(in: context, colWidths: [135, 135, 135, 135], headers: metaHeaders, rows: [metaRow], currentY: &y)
        y -= 12

        // Assigned Materials Table
        drawText(in: context, text: "Assigned Materials", at: CGPoint(x: 36, y: y), fontSize: 10.5, bold: true, color: CGColor(gray: 0.2, alpha: 1.0))
        y -= 14
        let matHeaders = ["Material", "Category", "Young's Modulus", "Poisson's Ratio", "Density", "Yield Strength"]
        let matRows: [[String]] = data.materials.isEmpty ?
            [["No materials assigned", "-", "-", "-", "-", "-"]] :
            data.materials.map { [$0.name, $0.category, $0.youngsModulus, $0.poissonsRatio, $0.density, $0.yieldStrength] }
        drawTable(in: context, colWidths: [130, 80, 85, 75, 85, 85], headers: matHeaders, rows: matRows, currentY: &y)
        y -= 12

        // Boundary Fixtures Table
        drawText(in: context, text: "Boundary Fixtures", at: CGPoint(x: 36, y: y), fontSize: 10.5, bold: true, color: CGColor(gray: 0.2, alpha: 1.0))
        y -= 14
        let fixHeaders = ["Fixture", "Kind", "Targets", "Restraints / Elastic Stiffness"]
        let fixRows: [[String]] = data.fixtures.isEmpty ?
            [["No boundary fixtures defined", "-", "-", "-"]] :
            data.fixtures.map { [$0.name, $0.kindDisplayName, "\($0.targetCount)", $0.restraintsDescription] }
        drawTable(in: context, colWidths: [150, 110, 70, 210], headers: fixHeaders, rows: fixRows, currentY: &y)
        y -= 12

        // Applied Loads Table
        drawText(in: context, text: "Applied Loads", at: CGPoint(x: 36, y: y), fontSize: 10.5, bold: true, color: CGColor(gray: 0.2, alpha: 1.0))
        y -= 14
        let loadHeaders = ["Load", "Kind", "Magnitude", "Direction [X, Y, Z]", "Targets"]
        let loadRows: [[String]] = data.loads.isEmpty ?
            [["No loads applied", "-", "-", "-", "-"]] :
            data.loads.map { [
                $0.name,
                $0.kindDisplayName,
                "\(String(format: "%.2f", $0.magnitudeDisplay)) \($0.unitSymbol)",
                "[\(String(format: "%.2f", $0.directionDisplay.x)), \(String(format: "%.2f", $0.directionDisplay.y)), \(String(format: "%.2f", $0.directionDisplay.z))]",
                "\($0.targetCount)"
            ] }
        drawTable(in: context, colWidths: [140, 100, 110, 130, 60], headers: loadHeaders, rows: loadRows, currentY: &y)
    }

    @MainActor
    private static func renderPDFPage2(in context: CGContext, data: SimulationReportData, totalPages: Int) {
        renderHeaderAndFooter(in: context, title: data.reportTitle, pageNumber: 2, totalPages: totalPages, timestamp: data.timestamp)

        var y: CGFloat = 740

        // Discretization Statistics
        drawSectionHeader(in: context, title: "Mesh Statistics & Discretization Quality", at: &y)
        let meshHeaders = ["Nodes", "Elements", "Element Order", "Min Quality", "Avg Quality", "Max Aspect Ratio"]
        let meshRow = [
            "\(data.nodeCount)",
            "\(data.elementCount)",
            data.elementOrder,
            String(format: "%.3f", data.minQuality),
            String(format: "%.3f", data.avgQuality),
            String(format: "%.1f", data.maxAspectRatio > 0 ? data.maxAspectRatio : 1.0)
        ]
        drawTable(in: context, colWidths: [80, 80, 100, 95, 95, 90], headers: meshHeaders, rows: [meshRow], currentY: &y)
        y -= 14

        // Result Extrema Table
        drawSectionHeader(in: context, title: "Result Extrema", at: &y)
        let extHeaders = ["Field Name", "Minimum Value", "Maximum Value", "Unit"]
        let extRows: [[String]] = data.extrema.isEmpty ?
            [["No result extrema available", "-", "-", "-"]] :
            data.extrema.map { [$0.fieldName, String(format: "%.3g", $0.minValue), String(format: "%.3g", $0.maxValue), $0.unitSymbol] }
        drawTable(in: context, colWidths: [200, 110, 110, 120], headers: extHeaders, rows: extRows, currentY: &y)
        y -= 14

        // Graphical Plots (FoS gauge and Stress bar)
        drawSectionHeader(in: context, title: "Structural Integrity Evaluations", at: &y)
        drawPDFVectorFoSGauge(in: context, minFoS: data.minFactorOfSafety, target: data.targetDesignFactor, at: &y)
        y -= 10

        if let peak = data.peakStress, let yield = data.yieldStrength {
            drawPDFVectorStressBar(in: context, peakStress: peak, yieldStrength: yield, unitSymbol: data.stressUnitSymbol, at: &y)
            y -= 12
        }

        // Constraint Reactions & Static Equilibrium
        drawSectionHeader(in: context, title: "Constraint Reactions & Static Equilibrium", at: &y)
        let rxnHeaders = ["Fixture", "Resultant Force [\(data.forceUnitSymbol)]", "Resultant Moment [\(data.momentUnitSymbol)]", "Centroid [\(data.lengthUnitSymbol)]", "Nodes"]
        let rxnRows: [[String]] = data.reactions.isEmpty ?
            [["No constraint reactions recorded", "-", "-", "-", "-"]] :
            data.reactions.map { [
                $0.fixtureName,
                "\(String(format: "%.2f", $0.forceMag)) [\(String(format: "%.1f", $0.forceVec.x)), \(String(format: "%.1f", $0.forceVec.y)), \(String(format: "%.1f", $0.forceVec.z))]",
                "\(String(format: "%.2f", $0.momentMag)) [\(String(format: "%.1f", $0.momentVec.x)), \(String(format: "%.1f", $0.momentVec.y)), \(String(format: "%.1f", $0.momentVec.z))]",
                "[\(String(format: "%.1f", $0.centroid.x)), \(String(format: "%.1f", $0.centroid.y)), \(String(format: "%.1f", $0.centroid.z))]",
                "\($0.nodeCount)"
            ] }
        drawTable(in: context, colWidths: [130, 140, 140, 90, 40], headers: rxnHeaders, rows: rxnRows, currentY: &y)

        if let assess = data.conclusions.staticEquilibriumAssessment {
            y -= 6
            drawText(in: context, text: "Equilibrium: \(assess)", at: CGPoint(x: 36, y: y), fontSize: 8.5, bold: false, color: CGColor(gray: 0.3, alpha: 1.0))
            y -= 12
        }
        y -= 8

        // Engineering Conclusions
        drawSectionHeader(in: context, title: "Engineering Conclusions & Synthesis", at: &y)
        drawText(in: context, text: data.conclusions.factorOfSafetyAssessment, at: CGPoint(x: 36, y: y), fontSize: 8.5, bold: true, color: CGColor(gray: 0.2, alpha: 1.0))
        y -= 14

        for finding in data.conclusions.keyFindings.prefix(4) {
            drawText(in: context, text: "• \(finding)", at: CGPoint(x: 42, y: y), fontSize: 8.0, bold: false, color: CGColor(gray: 0.25, alpha: 1.0))
            y -= 12
        }
    }

    @MainActor
    private static func renderPDFPage3(in context: CGContext, data: SimulationReportData, totalPages: Int) {
        renderHeaderAndFooter(in: context, title: data.reportTitle, pageNumber: 3, totalPages: totalPages, timestamp: data.timestamp)

        var y: CGFloat = 740

        // Body Summaries
        if !data.bodySummaries.isEmpty {
            drawSectionHeader(in: context, title: "Partitioned Body Summaries", at: &y)
            let bodyHeaders = ["Body Name", "Nodes", "Elements", "Max Stress [\(data.stressUnitSymbol)]", "Max Disp [\(data.lengthUnitSymbol)]", "Min FoS", "Max Temp"]
            let bodyRows: [[String]] = data.bodySummaries.map {
                [
                    $0.bodyName,
                    "\($0.nodeCount)",
                    "\($0.elementCount)",
                    $0.maxStress.map { String(format: "%.1f", $0) } ?? "-",
                    $0.maxDisplacement.map { String(format: "%.3f", $0) } ?? "-",
                    $0.minFactorOfSafety.map { String(format: "%.2f", $0) } ?? "-",
                    $0.maxTemperature.map { String(format: "%.1f", $0) } ?? "-"
                ]
            }
            drawTable(in: context, colWidths: [130, 60, 60, 95, 85, 55, 55], headers: bodyHeaders, rows: bodyRows, currentY: &y)
            y -= 16
        }

        // Probes
        if !data.probes.isEmpty {
            drawSectionHeader(in: context, title: "Probes & Result Inspection Table", at: &y)
            let probeHeaders = ["#", "Name", "Kind", "Position [\(data.lengthUnitSymbol)]", "Distance", "Value"]
            let probeRows: [[String]] = data.probes.map { probe in
                [
                    "\(probe.index)",
                    probe.name,
                    probe.kindDisplayName,
                    "(\(String(format: "%.1f", probe.position.x)), \(String(format: "%.1f", probe.position.y)), \(String(format: "%.1f", probe.position.z)))",
                    probe.distanceAlongPath.map { String(format: "%.2f \(data.lengthUnitSymbol)", $0) } ?? "-",
                    probe.primaryValue.map { "\(String(format: "%.2f", $0)) \(probe.unitSymbol)" } ?? "-"
                ]
            }
            drawTable(in: context, colWidths: [30, 120, 90, 160, 70, 70], headers: probeHeaders, rows: probeRows, currentY: &y)
        }
    }

    // MARK: - CoreGraphics Drawing Primitives

    @MainActor
    private static func drawSectionHeader(in context: CGContext, title: String, at currentY: inout CGFloat) {
        currentY -= 16
        drawText(in: context, text: title, at: CGPoint(x: 36, y: currentY), fontSize: 11.5, bold: true, color: CGColor(gray: 0.15, alpha: 1.0))
        currentY -= 6
        drawLine(in: context, from: CGPoint(x: 36, y: currentY), to: CGPoint(x: 576, y: currentY), color: CGColor(gray: 0.85, alpha: 1.0))
        currentY -= 8
    }

    @MainActor
    private static func drawTable(
        in context: CGContext,
        colWidths: [CGFloat],
        headers: [String],
        rows: [[String]],
        currentY: inout CGFloat
    ) {
        let totalW = colWidths.reduce(0, +)
        let startX: CGFloat = 36.0

        // Header Row
        let headerH: CGFloat = 16.0
        currentY -= headerH
        let headerRect = CGRect(x: startX, y: currentY, width: totalW, height: headerH)
        drawRect(in: context, rect: headerRect, fillColor: CGColor(gray: 0.94, alpha: 1.0), strokeColor: nil)

        var x = startX
        for (i, h) in headers.enumerated() {
            let w = colWidths[i]
            drawText(in: context, text: h, at: CGPoint(x: x + 4, y: currentY + 4), fontSize: 8.0, bold: true, color: CGColor(gray: 0.25, alpha: 1.0))
            x += w
        }
        drawLine(in: context, from: CGPoint(x: startX, y: currentY), to: CGPoint(x: startX + totalW, y: currentY), color: CGColor(gray: 0.85, alpha: 1.0))

        // Data Rows
        let rowH: CGFloat = 14.0
        for (rowIdx, row) in rows.enumerated() {
            currentY -= rowH
            let rowRect = CGRect(x: startX, y: currentY, width: totalW, height: rowH)
            let rowBg: CGColor? = rowIdx % 2 == 1 ? CGColor(gray: 0.98, alpha: 1.0) : nil
            if let bg = rowBg {
                drawRect(in: context, rect: rowRect, fillColor: bg, strokeColor: nil)
            }

            var cellX = startX
            for (cIdx, cell) in row.enumerated() {
                let w = colWidths[cIdx]
                drawText(in: context, text: cell, at: CGPoint(x: cellX + 4, y: currentY + 3.5), fontSize: 7.5, bold: false, color: CGColor(gray: 0.15, alpha: 1.0))
                cellX += w
            }
            drawLine(in: context, from: CGPoint(x: startX, y: currentY), to: CGPoint(x: startX + totalW, y: currentY), color: CGColor(gray: 0.90, alpha: 1.0))
        }
        currentY -= 4
    }

    @MainActor
    private static func drawPDFVectorFoSGauge(
        in context: CGContext,
        minFoS: Double?,
        target: Double?,
        at currentY: inout CGFloat
    ) {
        let targetVal = target ?? 1.5
        let minVal = minFoS ?? 1.0
        let maxScale = max(3.0, max(targetVal * 1.5, minVal * 1.25))
        let barWidth: CGFloat = 360.0
        let startX: CGFloat = 120.0
        let barH: CGFloat = 12.0

        currentY -= 36
        drawText(in: context, text: "Factor of Safety Gauge", at: CGPoint(x: 36, y: currentY + 12), fontSize: 9.0, bold: true, color: CGColor(gray: 0.2, alpha: 1.0))

        let barY = currentY + 10
        let yieldX = startX + CGFloat(1.0 / maxScale) * barWidth
        let targetX = startX + CGFloat(targetVal / maxScale) * barWidth
        let redW = max(0, yieldX - startX)
        let amberW = max(0, targetX - yieldX)
        let greenW = max(0, (startX + barWidth) - targetX)

        // Colored zones
        drawRect(in: context, rect: CGRect(x: startX, y: barY, width: redW, height: barH), fillColor: CGColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 0.85), strokeColor: nil)
        drawRect(in: context, rect: CGRect(x: yieldX, y: barY, width: amberW, height: barH), fillColor: CGColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 0.85), strokeColor: nil)
        drawRect(in: context, rect: CGRect(x: targetX, y: barY, width: greenW, height: barH), fillColor: CGColor(srgbRed: 0.06, green: 0.72, blue: 0.50, alpha: 0.85), strokeColor: nil)

        // Yield tick & Target tick
        drawLine(in: context, from: CGPoint(x: yieldX, y: barY - 3), to: CGPoint(x: yieldX, y: barY + barH + 3), color: CGColor(gray: 0.2, alpha: 1.0), lineWidth: 1.0)
        drawText(in: context, text: "1.0", at: CGPoint(x: yieldX, y: barY - 11), fontSize: 7.5, bold: false, color: CGColor(gray: 0.3, alpha: 1.0), hAlign: .center)

        drawLine(in: context, from: CGPoint(x: targetX, y: barY - 3), to: CGPoint(x: targetX, y: barY + barH + 3), color: CGColor(gray: 0.2, alpha: 1.0), lineWidth: 1.0)
        drawText(in: context, text: "Target (\(String(format: "%.1f", targetVal)))", at: CGPoint(x: targetX, y: barY - 11), fontSize: 7.5, bold: false, color: CGColor(gray: 0.3, alpha: 1.0), hAlign: .center)

        // Marker
        let markerX = startX + CGFloat(min(minVal, maxScale) / maxScale) * barWidth
        let mColor = minVal >= targetVal ?
            CGColor(srgbRed: 0.06, green: 0.72, blue: 0.50, alpha: 1.0) :
            (minVal >= 1.0 ? CGColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0) : CGColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0))
        drawLine(in: context, from: CGPoint(x: markerX, y: barY - 3), to: CGPoint(x: markerX, y: barY + barH + 3), color: mColor, lineWidth: 2.0)
        drawText(in: context, text: "Min FoS: \(String(format: "%.2f", minVal))", at: CGPoint(x: markerX, y: barY + barH + 4), fontSize: 8.0, bold: true, color: mColor, hAlign: .center)
    }

    @MainActor
    private static func drawPDFVectorStressBar(
        in context: CGContext,
        peakStress: Double,
        yieldStrength: Double,
        unitSymbol: String,
        at currentY: inout CGFloat
    ) {
        let maxScale = max(peakStress, yieldStrength) * 1.25
        let barMaxWidth: CGFloat = 280.0
        let startX: CGFloat = 130.0
        let peakW = max(2.0, CGFloat(peakStress / max(1e-6, maxScale)) * barMaxWidth)
        let yieldW = max(2.0, CGFloat(yieldStrength / max(1e-6, maxScale)) * barMaxWidth)
        let pct = (peakStress / max(1e-6, yieldStrength)) * 100.0

        currentY -= 36
        // Peak row
        drawText(in: context, text: "Peak von Mises", at: CGPoint(x: 120, y: currentY + 18), fontSize: 8.5, bold: true, color: CGColor(gray: 0.2, alpha: 1.0), hAlign: .right)
        let peakColor = pct > 100.0 ?
            CGColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0) :
            (pct > 80.0 ? CGColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0) : CGColor(srgbRed: 0.06, green: 0.72, blue: 0.50, alpha: 1.0))
        drawRect(in: context, rect: CGRect(x: startX, y: currentY + 17, width: peakW, height: 10), fillColor: peakColor, strokeColor: nil)
        drawText(in: context, text: "\(String(format: "%.1f", peakStress)) \(unitSymbol) (\(String(format: "%.1f%%", pct)))", at: CGPoint(x: startX + peakW + 6, y: currentY + 18), fontSize: 8.0, bold: true, color: peakColor)

        // Yield row
        drawText(in: context, text: "Yield Strength", at: CGPoint(x: 120, y: currentY + 4), fontSize: 8.5, bold: true, color: CGColor(gray: 0.2, alpha: 1.0), hAlign: .right)
        drawRect(in: context, rect: CGRect(x: startX, y: currentY + 3, width: yieldW, height: 10), fillColor: CGColor(gray: 0.6, alpha: 0.6), strokeColor: nil)
        drawText(in: context, text: "\(String(format: "%.1f", yieldStrength)) \(unitSymbol)", at: CGPoint(x: startX + yieldW + 6, y: currentY + 4), fontSize: 8.0, bold: false, color: CGColor(gray: 0.35, alpha: 1.0))
    }

    @MainActor
    private static func drawText(
        in context: CGContext,
        text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor = CGColor(gray: 0.15, alpha: 1.0),
        hAlign: ReportTextAlignment = .left
    ) {
        guard !text.isEmpty else { return }

        let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .black
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        var textX = point.x
        switch hAlign {
        case .left:
            textX = point.x
        case .center:
            textX = point.x - (lineWidth * 0.5)
        case .right:
            textX = point.x - lineWidth
        }

        context.saveGState()
        context.textPosition = CGPoint(x: textX, y: point.y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    @MainActor
    private static func drawRect(
        in context: CGContext,
        rect: CGRect,
        fillColor: CGColor?,
        strokeColor: CGColor?,
        lineWidth: CGFloat = 1.0
    ) {
        context.saveGState()
        if let fill = fillColor {
            context.setFillColor(fill)
            context.fill(rect)
        }
        if let stroke = strokeColor {
            context.setStrokeColor(stroke)
            context.setLineWidth(lineWidth)
            context.stroke(rect)
        }
        context.restoreGState()
    }

    @MainActor
    private static func drawRoundedRect(
        in context: CGContext,
        rect: CGRect,
        radius: CGFloat,
        fillColor: CGColor?,
        strokeColor: CGColor?,
        lineWidth: CGFloat = 1.0
    ) {
        context.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let fill = fillColor {
            context.setFillColor(fill)
            context.addPath(path)
            context.fillPath()
        }
        if let stroke = strokeColor {
            context.setStrokeColor(stroke)
            context.setLineWidth(lineWidth)
            context.addPath(path)
            context.strokePath()
        }
        context.restoreGState()
    }

    @MainActor
    private static func drawLine(
        in context: CGContext,
        from start: CGPoint,
        to end: CGPoint,
        color: CGColor,
        lineWidth: CGFloat = 1.0
    ) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func verdictColors(_ verdict: SimulationVerdict) -> (fill: CGColor, border: CGColor, text: CGColor) {
        switch verdict {
        case .pass:
            return (
                fill: CGColor(srgbRed: 0.92, green: 0.99, blue: 0.95, alpha: 1.0),
                border: CGColor(srgbRed: 0.06, green: 0.72, blue: 0.50, alpha: 1.0),
                text: CGColor(srgbRed: 0.02, green: 0.37, blue: 0.27, alpha: 1.0)
            )
        case .marginal:
            return (
                fill: CGColor(srgbRed: 1.0, green: 0.98, blue: 0.92, alpha: 1.0),
                border: CGColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0),
                text: CGColor(srgbRed: 0.57, green: 0.25, blue: 0.05, alpha: 1.0)
            )
        case .fail:
            return (
                fill: CGColor(srgbRed: 1.0, green: 0.95, blue: 0.95, alpha: 1.0),
                border: CGColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0),
                text: CGColor(srgbRed: 0.60, green: 0.11, blue: 0.11, alpha: 1.0)
            )
        case .inconclusive:
            return (
                fill: CGColor(srgbRed: 0.95, green: 0.96, blue: 0.96, alpha: 1.0),
                border: CGColor(srgbRed: 0.42, green: 0.45, blue: 0.50, alpha: 1.0),
                text: CGColor(srgbRed: 0.22, green: 0.25, blue: 0.32, alpha: 1.0)
            )
        }
    }
}
