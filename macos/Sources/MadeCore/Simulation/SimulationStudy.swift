import Foundation
import simd

/// Supported simulation study physics types (ADR-D5, #157).
public enum SimulationStudyType: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case linearStatic
    case thermalConduction
    case modalFrequency
    case linearBuckling

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linearStatic:
            return "Linear Static"
        case .thermalConduction:
            return "Thermal Conduction"
        case .modalFrequency:
            return "Modal Frequency"
        case .linearBuckling:
            return "Linear Buckling"
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
        case .linearBuckling:
            return "arrow.triangle.swap"
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
    public var sourceGroupNames: [String]
    public var targetGroupNames: [String]
    public var stiffness: Double
    public var searchTolerance: Double?

    public init(
        id: UUID = UUID(),
        name: String = "Connection",
        kind: SimulationConnectionKind = .bonded,
        sourceReferences: [SimulationGeometryReference] = [],
        targetReferences: [SimulationGeometryReference] = [],
        sourceGroupNames: [String] = [],
        targetGroupNames: [String] = [],
        stiffness: Double = 1e6,
        searchTolerance: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sourceReferences = sourceReferences
        self.targetReferences = targetReferences
        self.sourceGroupNames = sourceGroupNames
        self.targetGroupNames = targetGroupNames
        self.stiffness = stiffness
        self.searchTolerance = searchTolerance
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, sourceReferences, targetReferences
        case sourceGroupNames, targetGroupNames, stiffness, searchTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Connection"
        self.kind = try container.decodeIfPresent(SimulationConnectionKind.self, forKey: .kind) ?? .bonded
        self.sourceReferences = try container.decodeIfPresent([SimulationGeometryReference].self, forKey: .sourceReferences) ?? []
        self.targetReferences = try container.decodeIfPresent([SimulationGeometryReference].self, forKey: .targetReferences) ?? []
        self.sourceGroupNames = try container.decodeIfPresent([String].self, forKey: .sourceGroupNames) ?? []
        self.targetGroupNames = try container.decodeIfPresent([String].self, forKey: .targetGroupNames) ?? []
        self.stiffness = try container.decodeIfPresent(Double.self, forKey: .stiffness) ?? 1e6
        self.searchTolerance = try container.decodeIfPresent(Double.self, forKey: .searchTolerance)
    }
}

/// Boundary constraint classification for structural and thermal studies.
public enum SimulationFixtureKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case fixed
    case rollerSlider
    case pinned
    case prescribedDisplacement
    case symmetry
    case elasticSupport

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
        case .symmetry:
            return "Symmetry"
        case .elasticSupport:
            return "Elastic Support"
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
        case .symmetry:
            return "square.split.2x1"
        case .elasticSupport:
            return "waveform"
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
    public var elasticStiffness: SIMD3<Double>
    public var coordinateSystemId: UUID?

    public init(
        id: UUID = UUID(),
        name: String = "Fixed Support",
        kind: SimulationFixtureKind = .fixed,
        targetReferences: [SimulationGeometryReference] = [],
        groupNames: [String] = [],
        prescribedDisplacement: SIMD3<Double> = .zero,
        isRestrainedX: Bool = true,
        isRestrainedY: Bool = true,
        isRestrainedZ: Bool = true,
        elasticStiffness: SIMD3<Double> = SIMD3<Double>(repeating: 1e6),
        coordinateSystemId: UUID? = nil
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
        self.elasticStiffness = elasticStiffness
        self.coordinateSystemId = coordinateSystemId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, targetReferences, groupNames, prescribedDisplacement, isRestrainedX, isRestrainedY, isRestrainedZ, elasticStiffness, coordinateSystemId
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
        self.elasticStiffness = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .elasticStiffness) ?? SIMD3<Double>(repeating: 1e6)
        self.coordinateSystemId = try container.decodeIfPresent(UUID.self, forKey: .coordinateSystemId)
    }
}

/// Distribution mode for applied structural force loads (BL-FEA-03, #221).
public enum SimulationForceDistribution: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case total = "total"
    case perUnitArea = "perUnitArea"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .total:
            return "Total"
        case .perUnitArea:
            return "Per Unit Area"
        }
    }
}

/// Applied mechanical or thermal load classification.
public enum SimulationLoadKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case force
    case pressure
    case gravity
    case moment
    case remoteLoad
    case bearing
    case centrifugal
    case thermalLoad
    case thermalFlux
    case temperature
    case convection
    case heatPower

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .force:
            return "Force"
        case .pressure:
            return "Pressure"
        case .gravity:
            return "Gravity"
        case .moment:
            return "Moment"
        case .remoteLoad:
            return "Remote Load"
        case .bearing:
            return "Bearing Load"
        case .centrifugal:
            return "Centrifugal"
        case .thermalLoad:
            return "Thermal Load"
        case .thermalFlux:
            return "Heat Flux"
        case .temperature:
            return "Temperature"
        case .convection:
            return "Convection"
        case .heatPower:
            return "Heat Power"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .force, .remoteLoad, .bearing:
            return "N"
        case .pressure:
            return "MPa"
        case .gravity:
            return "m/s²"
        case .moment:
            return "N·m"
        case .centrifugal:
            return "rad/s"
        case .thermalLoad, .temperature:
            return "°C"
        case .thermalFlux:
            return "W/m²"
        case .convection:
            return "W/(m²·K)"
        case .heatPower:
            return "W"
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
        case .moment:
            return "arrow.triangle.2.circlepath"
        case .remoteLoad:
            return "arrow.up.and.line.horizontal.and.arrow.down"
        case .bearing:
            return "circle.circle"
        case .centrifugal:
            return "arrow.counterclockwise"
        case .thermalLoad:
            return "thermometer.sun.fill"
        case .thermalFlux:
            return "flame"
        case .temperature:
            return "thermometer.medium"
        case .convection:
            return "wind"
        case .heatPower:
            return "bolt.fill"
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
    public var coordinateSystemId: UUID?
    public var ambientTemperature: Double?
    public var forceDistribution: SimulationForceDistribution
    public var remotePoint: SIMD3<Double>?
    public var remoteMoment: SIMD3<Double>?
    public var axisOrigin: SIMD3<Double>?
    public var referenceTemperature: Double?

    public init(
        id: UUID = UUID(),
        name: String = "Force 1",
        kind: SimulationLoadKind = .force,
        targetReferences: [SimulationGeometryReference] = [],
        groupNames: [String] = [],
        magnitude: Double = 1000.0,
        direction: SIMD3<Double> = SIMD3<Double>(0, 0, -1),
        coordinateSystemId: UUID? = nil,
        ambientTemperature: Double? = nil,
        forceDistribution: SimulationForceDistribution = .total,
        remotePoint: SIMD3<Double>? = nil,
        remoteMoment: SIMD3<Double>? = nil,
        axisOrigin: SIMD3<Double>? = nil,
        referenceTemperature: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.targetReferences = targetReferences
        self.groupNames = groupNames
        self.magnitude = magnitude
        let len = simd_length(direction)
        self.direction = len > 1e-6 ? direction / len : SIMD3<Double>(0, 0, -1)
        self.coordinateSystemId = coordinateSystemId
        self.ambientTemperature = ambientTemperature ?? (kind == .convection ? 20.0 : nil)
        self.forceDistribution = forceDistribution
        self.remotePoint = remotePoint
        self.remoteMoment = remoteMoment
        self.axisOrigin = axisOrigin
        self.referenceTemperature = referenceTemperature
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, targetReferences, groupNames, magnitude, direction, coordinateSystemId, ambientTemperature
        case forceDistribution, remotePoint, remoteMoment, axisOrigin, referenceTemperature
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
        self.coordinateSystemId = try container.decodeIfPresent(UUID.self, forKey: .coordinateSystemId)
        self.ambientTemperature = try container.decodeIfPresent(Double.self, forKey: .ambientTemperature) ?? (self.kind == .convection ? 20.0 : nil)
        self.forceDistribution = try container.decodeIfPresent(SimulationForceDistribution.self, forKey: .forceDistribution) ?? .total
        self.remotePoint = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .remotePoint)
        self.remoteMoment = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .remoteMoment)
        self.axisOrigin = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .axisOrigin)
        self.referenceTemperature = try container.decodeIfPresent(Double.self, forKey: .referenceTemperature)
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

/// Coordinate axes for mesh slicing planes (BL-MSH-05, #278).
public enum MeshSliceAxis: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case x = "x"
    case y = "y"
    case z = "z"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .x: return "X Axis"
        case .y: return "Y Axis"
        case .z: return "Z Axis"
        }
    }
}

/// Viewport visualization and slicing configuration for finite element volume meshes (BL-MSH-05, #278).
public struct SimulationMeshDisplaySettings: Sendable, Codable, Equatable, Hashable {
    public var isVisible: Bool
    public var showEdges: Bool
    public var showFaces: Bool
    public var elementShrink: Double // 0.0 ... 0.9
    public var isSliceEnabled: Bool
    public var sliceAxis: MeshSliceAxis
    public var slicePosition: Double // 0.0 ... 1.0 (normalized bounding box position)
    public var isSliceInverted: Bool
    public var hideSolidBody: Bool

    public init(
        isVisible: Bool = true,
        showEdges: Bool = true,
        showFaces: Bool = true,
        elementShrink: Double = 0.0,
        isSliceEnabled: Bool = false,
        sliceAxis: MeshSliceAxis = .z,
        slicePosition: Double = 0.5,
        isSliceInverted: Bool = false,
        hideSolidBody: Bool = false
    ) {
        self.isVisible = isVisible
        self.showEdges = showEdges
        self.showFaces = showFaces
        self.elementShrink = max(0.0, min(0.9, elementShrink))
        self.isSliceEnabled = isSliceEnabled
        self.sliceAxis = sliceAxis
        self.slicePosition = max(0.0, min(1.0, slicePosition))
        self.isSliceInverted = isSliceInverted
        self.hideSolidBody = hideSolidBody
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible, showEdges, showFaces, elementShrink, isSliceEnabled, sliceAxis, slicePosition, isSliceInverted, hideSolidBody
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.showEdges = try container.decodeIfPresent(Bool.self, forKey: .showEdges) ?? true
        self.showFaces = try container.decodeIfPresent(Bool.self, forKey: .showFaces) ?? true
        let rawShrink = try container.decodeIfPresent(Double.self, forKey: .elementShrink) ?? 0.0
        self.elementShrink = max(0.0, min(0.9, rawShrink))
        self.isSliceEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSliceEnabled) ?? false
        self.sliceAxis = try container.decodeIfPresent(MeshSliceAxis.self, forKey: .sliceAxis) ?? .z
        let rawPos = try container.decodeIfPresent(Double.self, forKey: .slicePosition) ?? 0.5
        self.slicePosition = max(0.0, min(1.0, rawPos))
        self.isSliceInverted = try container.decodeIfPresent(Bool.self, forKey: .isSliceInverted) ?? false
        self.hideSolidBody = try container.decodeIfPresent(Bool.self, forKey: .hideSolidBody) ?? false
    }

    public mutating func clamp() {
        elementShrink = max(0.0, min(0.9, elementShrink))
        slicePosition = max(0.0, min(1.0, slicePosition))
    }

    public func clamped() -> SimulationMeshDisplaySettings {
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
    public var bucklingModesCount: Int
    public var modeCount: Int
    public var isPrestressEnabled: Bool

    public init(
        engine: SimulationSolverEngine = .calculix,
        maxIterations: Int = 100,
        convergenceTolerance: Double = 1e-4,
        timeStep: Double = 0.01,
        bucklingModesCount: Int = 1,
        modeCount: Int = 5,
        isPrestressEnabled: Bool = false
    ) {
        self.engine = engine
        self.maxIterations = maxIterations
        self.convergenceTolerance = convergenceTolerance
        self.timeStep = timeStep
        self.bucklingModesCount = bucklingModesCount
        self.modeCount = modeCount
        self.isPrestressEnabled = isPrestressEnabled
    }

    enum CodingKeys: String, CodingKey {
        case engine, maxIterations, convergenceTolerance, timeStep, bucklingModesCount, modeCount, isPrestressEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.engine = try container.decodeIfPresent(SimulationSolverEngine.self, forKey: .engine) ?? .calculix
        self.maxIterations = try container.decodeIfPresent(Int.self, forKey: .maxIterations) ?? 100
        self.convergenceTolerance = try container.decodeIfPresent(Double.self, forKey: .convergenceTolerance) ?? 1e-4
        self.timeStep = try container.decodeIfPresent(Double.self, forKey: .timeStep) ?? 0.01
        self.bucklingModesCount = try container.decodeIfPresent(Int.self, forKey: .bucklingModesCount) ?? 1
        self.modeCount = try container.decodeIfPresent(Int.self, forKey: .modeCount) ?? 5
        self.isPrestressEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPrestressEnabled) ?? false
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
    public var qualityReport: MeshQualityReport?

    public init(
        nodeCount: Int = 0,
        elementCount: Int = 0,
        minElementQuality: Double = 1.0,
        avgElementQuality: Double = 1.0,
        qualityReport: MeshQualityReport? = nil
    ) {
        self.nodeCount = nodeCount
        self.elementCount = elementCount
        self.minElementQuality = minElementQuality
        self.avgElementQuality = avgElementQuality
        self.qualityReport = qualityReport
    }

    enum CodingKeys: String, CodingKey {
        case nodeCount
        case elementCount
        case minElementQuality
        case avgElementQuality
        case qualityReport
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodeCount = try container.decodeIfPresent(Int.self, forKey: .nodeCount) ?? 0
        self.elementCount = try container.decodeIfPresent(Int.self, forKey: .elementCount) ?? 0
        self.minElementQuality = try container.decodeIfPresent(Double.self, forKey: .minElementQuality) ?? 1.0
        self.avgElementQuality = try container.decodeIfPresent(Double.self, forKey: .avgElementQuality) ?? 1.0
        self.qualityReport = try container.decodeIfPresent(MeshQualityReport.self, forKey: .qualityReport)
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

/// Eigenmode result for linear buckling analysis (BL-FEA-08, #226).
public struct SimulationBucklingMode: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: Int { modeNumber }
    public var modeNumber: Int
    public var loadFactor: Double
    public var nodalDisplacements: [Int: SIMD3<Double>]

    public init(modeNumber: Int, loadFactor: Double, nodalDisplacements: [Int: SIMD3<Double>]) {
        self.modeNumber = modeNumber
        self.loadFactor = loadFactor
        self.nodalDisplacements = nodalDisplacements
    }
}

/// Mode shape displacement eigenmode resulting from modal frequency analysis (#225).
public struct SimulationModeShape: Sendable, Codable, Equatable, Hashable {
    public var modeNumber: Int
    public var frequencyHz: Double
    public var nodalDisplacements: [Int: SIMD3<Double>]

    public init(modeNumber: Int, frequencyHz: Double, nodalDisplacements: [Int: SIMD3<Double>]) {
        self.modeNumber = modeNumber
        self.frequencyHz = frequencyHz
        self.nodalDisplacements = nodalDisplacements
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
    public var nodalTemperatures: [Int: Double]?
    public var nodalDisplacements: [Int: SIMD3<Double>]?
    public var nodalVonMisesStresses: [Int: Double]?
    public var bucklingModes: [SimulationBucklingMode]?
    public var modeShapes: [SimulationModeShape]?
    public var factorOfSafety: FactorOfSafetyResult?
    public var nodalCauchyTensors: [Int: CauchyStressTensor]?
    public var fieldStorage: ResultFieldStorageDescriptor?
    public var elementVonMisesStresses: [Int: Double]?
    public var elementHeatFluxes: [Int: SIMD3<Double>]?

    public init(
        status: SimulationExecutionStatus = .notRun,
        runtimeDuration: Double? = nil,
        meshStatistics: SimulationMeshStatistics = SimulationMeshStatistics(),
        meshSets: [VolumeMeshSet] = [],
        extrema: [SimulationFieldExtrema] = [],
        errorMessage: String? = nil,
        nodalTemperatures: [Int: Double]? = nil,
        nodalDisplacements: [Int: SIMD3<Double>]? = nil,
        nodalVonMisesStresses: [Int: Double]? = nil,
        bucklingModes: [SimulationBucklingMode]? = nil,
        modeShapes: [SimulationModeShape]? = nil,
        factorOfSafety: FactorOfSafetyResult? = nil,
        nodalCauchyTensors: [Int: CauchyStressTensor]? = nil,
        fieldStorage: ResultFieldStorageDescriptor? = nil,
        elementVonMisesStresses: [Int: Double]? = nil,
        elementHeatFluxes: [Int: SIMD3<Double>]? = nil
    ) {
        self.status = status
        self.runtimeDuration = runtimeDuration
        self.meshStatistics = meshStatistics
        self.meshSets = meshSets
        self.extrema = extrema
        self.errorMessage = errorMessage
        self.nodalTemperatures = nodalTemperatures
        self.nodalDisplacements = nodalDisplacements
        self.nodalVonMisesStresses = nodalVonMisesStresses
        self.bucklingModes = bucklingModes
        self.modeShapes = modeShapes
        self.factorOfSafety = factorOfSafety
        self.nodalCauchyTensors = nodalCauchyTensors
        self.fieldStorage = fieldStorage
        self.elementVonMisesStresses = elementVonMisesStresses
        self.elementHeatFluxes = elementHeatFluxes
    }

    enum CodingKeys: String, CodingKey {
        case status, runtimeDuration, meshStatistics, meshSets, extrema, errorMessage, nodalTemperatures, nodalDisplacements, nodalVonMisesStresses, bucklingModes, modeShapes, factorOfSafety, nodalCauchyTensors, fieldStorage, elementVonMisesStresses, elementHeatFluxes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(SimulationExecutionStatus.self, forKey: .status) ?? .notRun
        self.runtimeDuration = try container.decodeIfPresent(Double.self, forKey: .runtimeDuration)
        self.meshStatistics = try container.decodeIfPresent(SimulationMeshStatistics.self, forKey: .meshStatistics) ?? SimulationMeshStatistics()
        self.meshSets = try container.decodeIfPresent([VolumeMeshSet].self, forKey: .meshSets) ?? []
        self.extrema = try container.decodeIfPresent([SimulationFieldExtrema].self, forKey: .extrema) ?? []
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.nodalTemperatures = try container.decodeIfPresent([Int: Double].self, forKey: .nodalTemperatures)
        self.nodalDisplacements = try container.decodeIfPresent([Int: SIMD3<Double>].self, forKey: .nodalDisplacements)
        self.nodalVonMisesStresses = try container.decodeIfPresent([Int: Double].self, forKey: .nodalVonMisesStresses)
        self.bucklingModes = try container.decodeIfPresent([SimulationBucklingMode].self, forKey: .bucklingModes)
        self.modeShapes = try container.decodeIfPresent([SimulationModeShape].self, forKey: .modeShapes)
        self.factorOfSafety = try container.decodeIfPresent(FactorOfSafetyResult.self, forKey: .factorOfSafety)
        self.nodalCauchyTensors = try container.decodeIfPresent([Int: CauchyStressTensor].self, forKey: .nodalCauchyTensors)
        self.fieldStorage = try container.decodeIfPresent(ResultFieldStorageDescriptor.self, forKey: .fieldStorage)
        self.elementVonMisesStresses = try container.decodeIfPresent([Int: Double].self, forKey: .elementVonMisesStresses)
        self.elementHeatFluxes = try container.decodeIfPresent([Int: SIMD3<Double>].self, forKey: .elementHeatFluxes)
    }

    /// True when any heavy numerical result field array is currently resident in memory.
    public var isFieldsLoaded: Bool {
        nodalDisplacements != nil ||
        nodalVonMisesStresses != nil ||
        nodalTemperatures != nil ||
        nodalCauchyTensors != nil ||
        elementVonMisesStresses != nil ||
        elementHeatFluxes != nil ||
        bucklingModes != nil ||
        modeShapes != nil
    }

    /// Unloads heavy result arrays from memory while retaining metadata, extrema, and mesh statistics.
    public mutating func unloadFields() {
        nodalDisplacements = nil
        nodalVonMisesStresses = nil
        nodalTemperatures = nil
        nodalCauchyTensors = nil
        elementVonMisesStresses = nil
        elementHeatFluxes = nil
        bucklingModes = nil
        modeShapes = nil
        fieldStorage?.isResident = false
    }

    /// Lazy loads result fields into memory from the associated package cache file.
    public mutating func loadFields(from packageURL: URL) throws(CAEErrorCode) {
        guard let storage = fieldStorage else {
            throw CAEErrorCode.resultParsingFailed(details: "No field storage descriptor available to load results.")
        }
        let fileURL = packageURL.appendingPathComponent(storage.storagePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CAEErrorCode.resultParsingFailed(details: "Result file not found at \(fileURL.path).")
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CAEErrorCode.resultParsingFailed(details: "Failed to read result file at \(fileURL.path): \(error.localizedDescription)")
        }

        switch storage.format {
        case .vtu:
            let (_, fields) = try VTUResultFormat.importVTU(data: data)
            applyFields(fields)
        case .compactBinary:
            let fields = try CompactBinaryResultFormat.deserialize(data: data)
            applyFields(fields)
        }
        fieldStorage?.isResident = true
    }

    /// Applies populated field arrays from a `SimulationResultFields` container.
    public mutating func applyFields(_ fields: SimulationResultFields) {
        if let d = fields.nodalDisplacements { self.nodalDisplacements = d }
        if let v = fields.nodalVonMisesStresses { self.nodalVonMisesStresses = v }
        if let t = fields.nodalTemperatures { self.nodalTemperatures = t }
        if let c = fields.nodalCauchyTensors { self.nodalCauchyTensors = c }
        if let ev = fields.elementVonMisesStresses { self.elementVonMisesStresses = ev }
        if let hf = fields.elementHeatFluxes { self.elementHeatFluxes = hf }
        if let bm = fields.bucklingModes { self.bucklingModes = bm }
        if let ms = fields.modeShapes { self.modeShapes = ms }
        self.fieldStorage?.isResident = true
    }

    /// Extracts resident field arrays into a standalone `SimulationResultFields` container.
    public func extractFields(studyId: UUID) -> SimulationResultFields {
        SimulationResultFields(
            studyId: studyId,
            nodalDisplacements: nodalDisplacements,
            nodalVonMisesStresses: nodalVonMisesStresses,
            nodalTemperatures: nodalTemperatures,
            nodalCauchyTensors: nodalCauchyTensors,
            elementVonMisesStresses: elementVonMisesStresses,
            elementHeatFluxes: elementHeatFluxes,
            bucklingModes: bucklingModes,
            modeShapes: modeShapes
        )
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
    public var meshDisplay: SimulationMeshDisplaySettings
    public var solver: SolverConfiguration
    public var results: SimulationStudyResults
    public var isCollapsed: Bool
    public var coordinateSystemId: UUID?
    public var factorOfSafetySettings: FactorOfSafetySettings
    public var thermalStudyId: UUID?
    public var thermalReferenceTemperature: Double?

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
        meshDisplay: SimulationMeshDisplaySettings = SimulationMeshDisplaySettings(),
        solver: SolverConfiguration = SolverConfiguration(),
        results: SimulationStudyResults = SimulationStudyResults(),
        isCollapsed: Bool = false,
        coordinateSystemId: UUID? = nil,
        factorOfSafetySettings: FactorOfSafetySettings = FactorOfSafetySettings(),
        thermalStudyId: UUID? = nil,
        thermalReferenceTemperature: Double? = nil
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
        self.meshDisplay = meshDisplay
        self.solver = solver
        self.results = results
        self.isCollapsed = isCollapsed
        self.coordinateSystemId = coordinateSystemId
        self.factorOfSafetySettings = factorOfSafetySettings
        self.thermalStudyId = thermalStudyId
        self.thermalReferenceTemperature = thermalReferenceTemperature
    }

    enum CodingKeys: String, CodingKey {
        case id, name, studyType, targets, groups, materials, connections, fixtures, loads, mesh, meshDisplay, solver, results, isCollapsed, coordinateSystemId, factorOfSafetySettings, thermalStudyId, thermalReferenceTemperature
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
        self.meshDisplay = try container.decodeIfPresent(SimulationMeshDisplaySettings.self, forKey: .meshDisplay) ?? SimulationMeshDisplaySettings()
        self.solver = try container.decodeIfPresent(SolverConfiguration.self, forKey: .solver) ?? SolverConfiguration()
        self.results = try container.decodeIfPresent(SimulationStudyResults.self, forKey: .results) ?? SimulationStudyResults()
        self.isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        self.coordinateSystemId = try container.decodeIfPresent(UUID.self, forKey: .coordinateSystemId)
        self.factorOfSafetySettings = try container.decodeIfPresent(FactorOfSafetySettings.self, forKey: .factorOfSafetySettings) ?? FactorOfSafetySettings()
        self.thermalStudyId = try container.decodeIfPresent(UUID.self, forKey: .thermalStudyId)
        self.thermalReferenceTemperature = try container.decodeIfPresent(Double.self, forKey: .thermalReferenceTemperature)
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
