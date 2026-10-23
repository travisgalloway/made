import Foundation
import simd

/// A 3D nodal point within a discretized finite element volume mesh.
public struct VolumeMeshNode: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var position: SIMD3<Double>

    public init(id: Int, position: SIMD3<Double>) {
        self.id = id
        self.position = position
    }
}

/// A finite element (volume tetrahedron or boundary surface triangle).
public struct VolumeMeshElement: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var order: MeshElementOrder
    public var nodeIndices: [Int]
    public var tag: Int

    public init(
        id: Int,
        order: MeshElementOrder = .linear,
        nodeIndices: [Int],
        tag: Int = 0
    ) {
        self.id = id
        self.order = order
        self.nodeIndices = nodeIndices
        self.tag = tag
    }
}

/// Named finite element node and element subset for boundary conditions and load associations (ADR-D5 §4, #189).
public struct VolumeMeshSet: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var nodeIds: [Int]
    public var elementIds: [Int]
    public var subelementType: SubelementType?
    public var tag: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        nodeIds: [Int] = [],
        elementIds: [Int] = [],
        subelementType: SubelementType? = nil,
        tag: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.nodeIds = nodeIds
        self.elementIds = elementIds
        self.subelementType = subelementType
        self.tag = tag
    }
}

/// Discretized 3D volume mesh containing nodes, tetrahedral elements, and boundary surface triangles (ADR-D5 §4, #188, #189).
public struct VolumeMesh: Sendable, Codable, Equatable, Hashable {
    public var nodes: [VolumeMeshNode]
    public var elements: [VolumeMeshElement]
    public var surfaceTriangles: [VolumeMeshElement]
    public var statistics: SimulationMeshStatistics
    public var sets: [VolumeMeshSet]

    public init(
        nodes: [VolumeMeshNode] = [],
        elements: [VolumeMeshElement] = [],
        surfaceTriangles: [VolumeMeshElement] = [],
        statistics: SimulationMeshStatistics = SimulationMeshStatistics(),
        sets: [VolumeMeshSet] = []
    ) {
        self.nodes = nodes
        self.elements = elements
        self.surfaceTriangles = surfaceTriangles
        self.statistics = statistics
        self.sets = sets
    }

    enum CodingKeys: String, CodingKey {
        case nodes
        case elements
        case surfaceTriangles
        case statistics
        case sets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodes = try container.decodeIfPresent([VolumeMeshNode].self, forKey: .nodes) ?? []
        self.elements = try container.decodeIfPresent([VolumeMeshElement].self, forKey: .elements) ?? []
        self.surfaceTriangles = try container.decodeIfPresent([VolumeMeshElement].self, forKey: .surfaceTriangles) ?? []
        self.statistics = try container.decodeIfPresent(SimulationMeshStatistics.self, forKey: .statistics) ?? SimulationMeshStatistics()
        self.sets = try container.decodeIfPresent([VolumeMeshSet].self, forKey: .sets) ?? []
    }

    public func set(named name: String) -> VolumeMeshSet? {
        sets.first { $0.name == name }
    }

    public func nodeSet(named name: String) -> [VolumeMeshNode] {
        guard let s = set(named: name) else { return [] }
        let idSet = Set(s.nodeIds)
        return nodes.filter { idSet.contains($0.id) }
    }

    public func elementSet(named name: String) -> [VolumeMeshElement] {
        guard let s = set(named: name) else { return [] }
        let idSet = Set(s.elementIds)
        let vol = elements.filter { idSet.contains($0.id) }
        let surf = surfaceTriangles.filter { idSet.contains($0.id) }
        return vol + surf
    }
}

/// Resulting artifacts, metrics, and diagnostics from volume mesh generation (ADR-D5 §8, #188).
public struct VolumeMeshResult: Sendable, Codable, Equatable, Hashable {
    public var mesh: VolumeMesh
    public var meshFileURL: URL?
    public var runtimeDuration: Double
    public var exitCode: Int32
    public var rawOutput: String

    public init(
        mesh: VolumeMesh,
        meshFileURL: URL? = nil,
        runtimeDuration: Double = 0.0,
        exitCode: Int32 = 0,
        rawOutput: String = ""
    ) {
        self.mesh = mesh
        self.meshFileURL = meshFileURL
        self.runtimeDuration = runtimeDuration
        self.exitCode = exitCode
        self.rawOutput = rawOutput
    }
}
