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

/// Discretized 3D volume mesh containing nodes, tetrahedral elements, and boundary surface triangles (ADR-D5 §4, #188).
public struct VolumeMesh: Sendable, Codable, Equatable, Hashable {
    public var nodes: [VolumeMeshNode]
    public var elements: [VolumeMeshElement]
    public var surfaceTriangles: [VolumeMeshElement]
    public var statistics: SimulationMeshStatistics

    public init(
        nodes: [VolumeMeshNode] = [],
        elements: [VolumeMeshElement] = [],
        surfaceTriangles: [VolumeMeshElement] = [],
        statistics: SimulationMeshStatistics = SimulationMeshStatistics()
    ) {
        self.nodes = nodes
        self.elements = elements
        self.surfaceTriangles = surfaceTriangles
        self.statistics = statistics
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
