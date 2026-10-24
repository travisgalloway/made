import Foundation
import simd

/// Supported simulation study physics types (ADR-D5, #157).
public enum SimulationStudyType: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case linearStatic
    case thermalConduction
    case modalFrequency

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linearStatic:
            return "Linear Static"
        case .thermalConduction:
            return "Thermal Conduction"
        case .modalFrequency:
            return "Modal Frequency"
        }
    }

    public var systemImageName: String {
        switch self {
        case .linearStatic:
            return "waveform.path.ecg"
        case .thermalConduction:
            return "flame"
        case .modalFrequency:
            return "waveform"
        }
    }
}

/// Geometric target reference for simulation studies, boundary conditions, and loads (ADR-D5, #157).
public struct SimulationGeometryReference: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var targetId: UUID
    public var targetName: String
    public var subelementType: SubelementType?
    public var topologicalReference: TopologicalReference?

    public init(
        id: UUID = UUID(),
        targetId: UUID,
        targetName: String = "",
        subelementType: SubelementType? = nil,
        topologicalReference: TopologicalReference? = nil
    ) {
        self.id = id
        self.targetId = targetId
        self.targetName = targetName
        self.subelementType = subelementType
        self.topologicalReference = topologicalReference
    }
}

/// User-defined named geometry group aggregating multiple geometric references (ADR-D5 §4, #189).
public struct SimulationGeometryGroup: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var targetReferences: [SimulationGeometryReference]
    public var subelementType: SubelementType?

    public init(
        id: UUID = UUID(),
        name: String = "Group 1",
        targetReferences: [SimulationGeometryReference] = [],
        subelementType: SubelementType? = nil
    ) {
        self.id = id
        self.name = name
        self.targetReferences = targetReferences
        self.subelementType = subelementType
    }
}

/// Simulation material assignment mapping material definitions to geometry targets.
public struct SimulationMaterialAssignment: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var materialId: String
    public var targetReferences: [SimulationGeometryReference]

    public init(
        id: UUID = UUID(),
        name: String = "Material Assignment",
        materialId: String = "structural-steel",
        targetReferences: [SimulationGeometryReference] = []
    ) {
        self.id = id
        self.name = name
        self.materialId = materialId
        self.targetReferences = targetReferences
    }
}

/// Kinematic contact and connection kind between bodies or boundary surfaces.
public enum SimulationConnectionKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case bonded
    case contact
    case bolt
    case spring

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bonded:
            return "Bonded"
        case .contact:
            return "Contact"
        case .bolt:
            return "Bolt"
        case .spring:
            return "Spring"
        }
    }

    public var systemImageName: String {
        switch self {
        case .bonded:
            return "link"
        case .contact:
            return "hand.raised"
        case .bolt:
            return "bolt.fill"
        case .spring:
            return "waveform"
        }
    }
}

/// Contact or fastener connection specification between geometry targets.
public struct SimulationConnection: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: SimulationConnectionKind
    public var sourceReferences: [SimulationGeometryReference]
    public var targetReferences: [SimulationGeometryReference]
    public var stiffness: Double

    public init(
        id: UUID = UUID(),
        name: String = "Connection",
        kind: SimulationConnectionKind = .bonded,
        sourceReferences: [SimulationGeometryReference] = [],
        targetReferences: [SimulationGeometryReference] = [],
        stiffness: Double = 1e6
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sourceReferences = sourceReferences
        self.targetReferences = targetReferences
        self.stiffness = stiffness
    }
}

/// Boundary constraint classification for structural and thermal studies.
public enum SimulationFixtureKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case fixed
    case rollerSlider
    case pinned
    case prescribedDisplacement

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fixed:
            return "Fixed Support"
        case .rollerSlider:
            return "Roller / Slider"
        case .pinned:
            return "Pinned Support"
        case .prescribedDisplacement:
            return "Prescribed Displacement"
        }
    }

    public var systemImageName: String {
        switch self {
        case .fixed:
            return "lock.fill"
        case .rollerSlider:
            return "arrow.left.and.right"
        case .pinned:
            return "pin.fill"
        case .prescribedDisplacement:
            return "ruler"
        }
    }
}

/// Kinematic boundary fixture applied to target geometry.
public struct SimulationFixture: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: SimulationFixtureKind
    public var targetReferences: [SimulationGeometryReference]
    public var groupNames: [String]
    public var prescribedDisplacement: SIMD3<Double>
    public var isRestrainedX: Bool
    public var isRestrainedY: Bool
    public var isRestrainedZ: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Fixed Support",
        kind: SimulationFixtureKind = .fixed,
        targetReferences: [SimulationGeometryReference] = [],
        groupNames: [String] = [],
        prescribedDisplacement: SIMD3<Double> = .zero,
        isRestrainedX: Bool = true,
        isRestrainedY: Bool = true,
        isRestrainedZ: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.targetReferences = targetReferences
        self.groupNames = groupNames
        self.prescribedDisplacement = prescribedDisplacement
        self.isRestrainedX = isRestrainedX
        self.isRestrainedY = isRestrainedY
        self.isRestrainedZ = isRestrainedZ
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, targetReferences, groupNames, prescribedDisplacement, isRestrainedX, isRestrainedY, isRestrainedZ
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(SimulationFixtureKind.self, forKey: .kind)
        self.targetReferences = try container.decodeIfPresent([SimulationGeometryReference].self, forKey: .targetReferences) ?? []
        self.groupNames = try container.decodeIfPresent([String].self, forKey: .groupNames) ?? []
        self.prescribedDisplacement = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .prescribedDisplacement) ?? .zero
        self.isRestrainedX = try container.decodeIfPresent(Bool.self, forKey: .isRestrainedX) ?? true
        self.isRestrainedY = try container.decodeIfPresent(Bool.self, forKey: .isRestrainedY) ?? true
        self.isRestrainedZ = try container.decodeIfPresent(Bool.self, forKey: .isRestrainedZ) ?? true
    }
}

/// Applied mechanical or thermal load classification.
public enum SimulationLoadKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case force
    case pressure
    case gravity
    case thermalFlux
    case temperature

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .force:
            return "Force"
        case .pressure:
            return "Pressure"
        case .gravity:
            return "Gravity"
        case .thermalFlux:
            return "Heat Flux"
        case .temperature:
            return "Temperature"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .force:
            return "N"
        case .pressure:
            return "MPa"
        case .gravity:
            return "m/s²"
        case .thermalFlux:
            return "W/m²"
        case .temperature:
            return "°C"
        }
    }

    public var systemImageName: String {
        switch self {
        case .force:
            return "arrow.down.right"
        case .pressure:
            return "arrow.down.to.line"
        case .gravity:
            return "arrow.down"
        case .thermalFlux:
            return "flame"
        case .temperature:
            return "thermometer.medium"
        }
    }
}

/// Structural or thermal load applied to geometry targets.
public struct SimulationLoad: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: SimulationLoadKind
    public var targetReferences: [SimulationGeometryReference]
    public var groupNames: [String]
    public var magnitude: Double
    public var direction: SIMD3<Double>

    public init(
        id: UUID = UUID(),
        name: String = "Force 1",
        kind: SimulationLoadKind = .force,
        targetReferences: [SimulationGeometryReference] = [],
        groupNames: [String] = [],
        magnitude: Double = 1000.0,
        direction: SIMD3<Double> = SIMD3<Double>(0, 0, -1)
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.targetReferences = targetReferences
        self.groupNames = groupNames
        self.magnitude = magnitude
        let len = simd_length(direction)
        self.direction = len > 1e-6 ? direction / len : SIMD3<Double>(0, 0, -1)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, targetReferences, groupNames, magnitude, direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(SimulationLoadKind.self, forKey: .kind)
        self.targetReferences = try container.decodeIfPresent([SimulationGeometryReference].self, forKey: .targetReferences) ?? []
        self.groupNames = try container.decodeIfPresent([String].self, forKey: .groupNames) ?? []
        self.magnitude = try container.decodeIfPresent(Double.self, forKey: .magnitude) ?? 1000.0
        let dir = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .direction) ?? SIMD3<Double>(0, 0, -1)
        let len = simd_length(dir)
        self.direction = len > 1e-6 ? dir / len : SIMD3<Double>(0, 0, -1)
    }
}

/// Tetrahedral finite element polynomial order.
public enum MeshElementOrder: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case linear
    case quadratic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linear:
            return "Linear (C3D4)"
        case .quadratic:
            return "Quadratic (C3D10)"
        }
    }
}

/// Local mesh refinement region for critical geometry zones.
public struct MeshRefinementRegion: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var targetReferences: [SimulationGeometryReference]
    public var targetElementSize: Double

    public init(
        id: UUID = UUID(),
        name: String = "Refinement",
        targetReferences: [SimulationGeometryReference] = [],
        targetElementSize: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.targetReferences = targetReferences
        self.targetElementSize = targetElementSize
    }

    public mutating func clamp() {
        targetElementSize = max(0.0001, targetElementSize)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName.isEmpty ? "Refinement" : trimmedName
    }

    public func clamped() -> MeshRefinementRegion {
        var copy = self
        copy.clamp()
        return copy
    }
}

/// Tetrahedral volume meshing parameters (ADR-D5, #157, #188, #275).
public struct MeshSpecification: Sendable, Codable, Equatable, Hashable {
    public var elementOrder: MeshElementOrder
    public var targetElementSize: Double
    public var minElementSize: Double
    public var growthRate: Double
    public var curvatureRefinement: Bool
    public var curvatureElementsPerCircle: Double
    public var refinementRegions: [MeshRefinementRegion]

    public init(
        elementOrder: MeshElementOrder = .quadratic,
        targetElementSize: Double = 5.0,
        minElementSize: Double = 1.0,
        growthRate: Double = 1.2,
        curvatureRefinement: Bool = false,
        curvatureElementsPerCircle: Double = 12.0,
        refinementRegions: [MeshRefinementRegion] = []
    ) {
        self.elementOrder = elementOrder
        self.targetElementSize = targetElementSize
        self.minElementSize = minElementSize
        self.growthRate = growthRate
        self.curvatureRefinement = curvatureRefinement
        self.curvatureElementsPerCircle = curvatureElementsPerCircle
        self.refinementRegions = refinementRegions
    }

    private enum CodingKeys: String, CodingKey {
        case elementOrder
        case targetElementSize
        case minElementSize
        case growthRate
        case curvatureRefinement
        case curvatureElementsPerCircle
        case refinementRegions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.elementOrder = try container.decodeIfPresent(MeshElementOrder.self, forKey: .elementOrder) ?? .quadratic
        self.targetElementSize = try container.decodeIfPresent(Double.self, forKey: .targetElementSize) ?? 5.0
        self.minElementSize = try container.decodeIfPresent(Double.self, forKey: .minElementSize) ?? 1.0
        self.growthRate = try container.decodeIfPresent(Double.self, forKey: .growthRate) ?? 1.2
        self.curvatureRefinement = try container.decodeIfPresent(Bool.self, forKey: .curvatureRefinement) ?? false
        self.curvatureElementsPerCircle = try container.decodeIfPresent(Double.self, forKey: .curvatureElementsPerCircle) ?? 12.0
        self.refinementRegions = try container.decodeIfPresent([MeshRefinementRegion].self, forKey: .refinementRegions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(elementOrder, forKey: .elementOrder)
        try container.encode(targetElementSize, forKey: .targetElementSize)
        try container.encode(minElementSize, forKey: .minElementSize)
        try container.encode(growthRate, forKey: .growthRate)
        try container.encode(curvatureRefinement, forKey: .curvatureRefinement)
        try container.encode(curvatureElementsPerCircle, forKey: .curvatureElementsPerCircle)
        try container.encode(refinementRegions, forKey: .refinementRegions)
    }

    public mutating func clamp() {
        targetElementSize = max(0.001, targetElementSize)
        minElementSize = max(0.0001, min(minElementSize, targetElementSize))
        growthRate = max(1.0, growthRate)
        curvatureElementsPerCircle = max(3.0, curvatureElementsPerCircle)
        refinementRegions = refinementRegions.map { region in
            var copy = region
            copy.clamp()
            return copy
        }
    }

    public func clamped() -> MeshSpecification {
        var copy = self
        copy.clamp()
        return copy
    }
}

/// Supported numerical CAE solver engines.
public enum SimulationSolverEngine: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case calculix
    case pureSwift
    case gmsh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .calculix:
            return "CalculiX (ccx)"
        case .pureSwift:
            return "Pure Swift (FEM)"
        case .gmsh:
            return "Gmsh"
        }
    }
}

/// Numerical solver runtime configuration parameters.
public struct SolverConfiguration: Sendable, Codable, Equatable, Hashable {
    public var engine: SimulationSolverEngine
    public var maxIterations: Int
    public var convergenceTolerance: Double
    public var timeStep: Double

    public init(
        engine: SimulationSolverEngine = .calculix,
        maxIterations: Int = 100,
        convergenceTolerance: Double = 1e-4,
        timeStep: Double = 0.01
    ) {
        self.engine = engine
        self.maxIterations = maxIterations
        self.convergenceTolerance = convergenceTolerance
        self.timeStep = timeStep
    }
}

/// Execution status of a numerical simulation job.
public enum SimulationExecutionStatus: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case notRun
    case meshing
    case solving
    case completed
    case failed
    case cancelled

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notRun:
            return "Not Run"
        case .meshing:
            return "Meshing"
        case .solving:
            return "Solving"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    public var systemImageName: String {
        switch self {
        case .notRun:
            return "circle"
        case .meshing:
            return "gearshape.2"
        case .solving:
            return "play.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle"
        }
    }
}

/// Discretized finite element mesh statistics.
public struct SimulationMeshStatistics: Sendable, Codable, Equatable, Hashable {
    public var nodeCount: Int
    public var elementCount: Int
    public var minElementQuality: Double
    public var avgElementQuality: Double

    public init(
        nodeCount: Int = 0,
        elementCount: Int = 0,
        minElementQuality: Double = 1.0,
        avgElementQuality: Double = 1.0
    ) {
        self.nodeCount = nodeCount
        self.elementCount = elementCount
        self.minElementQuality = minElementQuality
        self.avgElementQuality = avgElementQuality
    }
}

/// Extreme value range for a scalar or vector field result.
public struct SimulationFieldExtrema: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String { fieldName }
    public var fieldName: String
    public var unitSymbol: String
    public var minValue: Double
    public var maxValue: Double

    public init(
        fieldName: String,
        unitSymbol: String,
        minValue: Double,
        maxValue: Double
    ) {
        self.fieldName = fieldName
        self.unitSymbol = unitSymbol
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

/// Aggregate simulation solve results and metadata.
public struct SimulationStudyResults: Sendable, Codable, Equatable, Hashable {
    public var status: SimulationExecutionStatus
    public var runtimeDuration: Double?
    public var meshStatistics: SimulationMeshStatistics
    public var meshSets: [VolumeMeshSet]
    public var extrema: [SimulationFieldExtrema]
    public var errorMessage: String?

    public init(
        status: SimulationExecutionStatus = .notRun,
        runtimeDuration: Double? = nil,
        meshStatistics: SimulationMeshStatistics = SimulationMeshStatistics(),
        meshSets: [VolumeMeshSet] = [],
        extrema: [SimulationFieldExtrema] = [],
        errorMessage: String? = nil
    ) {
        self.status = status
        self.runtimeDuration = runtimeDuration
        self.meshStatistics = meshStatistics
        self.meshSets = meshSets
        self.extrema = extrema
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case status, runtimeDuration, meshStatistics, meshSets, extrema, errorMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(SimulationExecutionStatus.self, forKey: .status) ?? .notRun
        self.runtimeDuration = try container.decodeIfPresent(Double.self, forKey: .runtimeDuration)
        self.meshStatistics = try container.decodeIfPresent(SimulationMeshStatistics.self, forKey: .meshStatistics) ?? SimulationMeshStatistics()
        self.meshSets = try container.decodeIfPresent([VolumeMeshSet].self, forKey: .meshSets) ?? []
        self.extrema = try container.decodeIfPresent([SimulationFieldExtrema].self, forKey: .extrema) ?? []
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// Canonical Computer-Aided Engineering simulation study entity (ADR-D5, #157, #189).
public struct SimulationStudy: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var studyType: SimulationStudyType
    public var targets: [SimulationGeometryReference]
    public var groups: [SimulationGeometryGroup]
    public var materials: [SimulationMaterialAssignment]
    public var connections: [SimulationConnection]
    public var fixtures: [SimulationFixture]
    public var loads: [SimulationLoad]
    public var mesh: MeshSpecification
    public var solver: SolverConfiguration
    public var results: SimulationStudyResults
    public var isCollapsed: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Study 1",
        studyType: SimulationStudyType = .linearStatic,
        targets: [SimulationGeometryReference] = [],
        groups: [SimulationGeometryGroup] = [],
        materials: [SimulationMaterialAssignment] = [],
        connections: [SimulationConnection] = [],
        fixtures: [SimulationFixture] = [],
        loads: [SimulationLoad] = [],
        mesh: MeshSpecification = MeshSpecification(),
        solver: SolverConfiguration = SolverConfiguration(),
        results: SimulationStudyResults = SimulationStudyResults(),
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.studyType = studyType
        self.targets = targets
        self.groups = groups
        self.materials = materials
        self.connections = connections
        self.fixtures = fixtures
        self.loads = loads
        self.mesh = mesh
        self.solver = solver
        self.results = results
        self.isCollapsed = isCollapsed
    }

    enum CodingKeys: String, CodingKey {
        case id, name, studyType, targets, groups, materials, connections, fixtures, loads, mesh, solver, results, isCollapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Study 1"
        self.studyType = try container.decodeIfPresent(SimulationStudyType.self, forKey: .studyType) ?? .linearStatic
        self.targets = try container.decodeIfPresent([SimulationGeometryReference].self, forKey: .targets) ?? []
        self.groups = try container.decodeIfPresent([SimulationGeometryGroup].self, forKey: .groups) ?? []
        self.materials = try container.decodeIfPresent([SimulationMaterialAssignment].self, forKey: .materials) ?? []
        self.connections = try container.decodeIfPresent([SimulationConnection].self, forKey: .connections) ?? []
        self.fixtures = try container.decodeIfPresent([SimulationFixture].self, forKey: .fixtures) ?? []
        self.loads = try container.decodeIfPresent([SimulationLoad].self, forKey: .loads) ?? []
        self.mesh = try container.decodeIfPresent(MeshSpecification.self, forKey: .mesh) ?? MeshSpecification()
        self.solver = try container.decodeIfPresent(SolverConfiguration.self, forKey: .solver) ?? SolverConfiguration()
        self.results = try container.decodeIfPresent(SimulationStudyResults.self, forKey: .results) ?? SimulationStudyResults()
        self.isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }
}

/// Exhaustive typed error enum matching ADR-D5 §8.
public enum CAEErrorCode: Sendable, Codable, Equatable, Hashable, Error, LocalizedError {
    case solverBinaryNotFound(solver: String, searchedPaths: [String])
    case meshingFailed(reason: String, exitCode: Int32)
    case solverFailed(reason: String, exitCode: Int32)
    case solverDiverged(iterations: Int, residual: Double)
    case invalidStudyConfiguration(message: String)
    case resultParsingFailed(details: String)
    case executionCancelled

    public var errorDescription: String? {
        switch self {
        case .solverBinaryNotFound(let solver, let searchedPaths):
            let pathList = searchedPaths.isEmpty ? "none" : searchedPaths.joined(separator: ", ")
            return "Solver binary not found for \(solver). Searched: \(pathList)"
        case .meshingFailed(let reason, let exitCode):
            return "Meshing failed with exit code \(exitCode): \(reason)"
        case .solverFailed(let reason, let exitCode):
            return "Solver failed with exit code \(exitCode): \(reason)"
        case .solverDiverged(let iterations, let residual):
            return "Solver diverged after \(iterations) iterations with residual \(residual)"
        case .invalidStudyConfiguration(let message):
            return "Invalid simulation study configuration: \(message)"
        case .resultParsingFailed(let details):
            return "Failed to parse simulation results: \(details)"
        case .executionCancelled:
            return "Simulation execution was cancelled"
        }
    }
}
