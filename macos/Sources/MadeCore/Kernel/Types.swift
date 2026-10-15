import Foundation
import simd

public struct SolidId: Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let str = try? container.decode(String.self) {
            self.rawValue = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(String.self, forKey: .rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct JobId: Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let str = try? container.decode(String.self) {
            self.rawValue = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(String.self, forKey: .rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BoxParams: Hashable, Equatable, Sendable, Codable {
    public var width: Float
    public var depth: Float
    public var height: Float
    
    public init(width: Float, depth: Float, height: Float) {
        self.width = width
        self.depth = depth
        self.height = height
    }
}

public struct CylinderParams: Hashable, Equatable, Sendable, Codable {
    public var radius: Float
    public var height: Float
    
    public init(radius: Float, height: Float) {
        self.radius = radius
        self.height = height
    }
}

public struct SphereParams: Hashable, Equatable, Sendable, Codable {
    public var radius: Float
    
    public init(radius: Float) {
        self.radius = radius
    }
}

public struct ConeParams: Hashable, Equatable, Sendable, Codable {
    public var bottomRadius: Float
    public var topRadius: Float
    public var height: Float
    
    public init(bottomRadius: Float, topRadius: Float = 0, height: Float) {
        self.bottomRadius = bottomRadius
        self.topRadius = topRadius
        self.height = height
    }
}

/// A triangle mesh held in one page-aligned shared-memory region, so it can cross XPC without a copy (invariant 6).
public struct MeshPayload: Sendable {
    public let storage: MeshStorage
    public var positions: MeshComponent<Float> { storage.positions }
    public var normals: MeshComponent<Float> { storage.normals }
    public var indices: MeshComponent<UInt32> { storage.indices }
    public var triangleCount: Int { storage.indexCount / 3 }
    public var isEmpty: Bool { triangleCount == 0 }
    
    public init(storage: MeshStorage) {
        self.storage = storage
    }
    
    public init(positions: [Float], normals: [Float], indices: [UInt32]) {
        self.storage = MeshStorage(positionCount: positions.count, normalCount: normals.count, indexCount: indices.count) { p, n, i in
            _ = p.initialize(from: positions)
            _ = n.initialize(from: normals)
            _ = i.initialize(from: indices)
        }
    }
}

public enum KernelErrorCode: String, Sendable, Codable, CaseIterable {
    case kernelInitFailed = "kernel-init-failed"
    case invalidParams = "invalid-params"
    case geometryFailed = "geometry-failed"
    case unknownSolid = "unknown-solid"
    case cancelled = "cancelled"
    case workerCrashed = "worker-crashed"
}

public struct KernelError: Error, Equatable, Sendable, Codable {
    public let code: KernelErrorCode
    public let message: String
    
    public init(code: KernelErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum KernelResult<T: Sendable>: Sendable {
    case success(jobId: JobId, value: T)
    case failure(jobId: JobId, error: KernelError)
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var jobId: JobId {
        switch self {
        case .success(let id, _): return id
        case .failure(let id, _): return id
        }
    }
    
    public var value: T? {
        if case .success(_, let v) = self { return v }
        return nil
    }
    
    public var error: KernelError? {
        if case .failure(_, let e) = self { return e }
        return nil
    }
}

public enum BooleanOp: String, Sendable, Codable {
    case subtract
    case union
    case intersect
}

public enum KernelRequest: Sendable, Codable, Equatable {
    case makeBox(jobId: JobId, solidId: SolidId, params: BoxParams)
    case makeCylinder(jobId: JobId, solidId: SolidId, params: CylinderParams)
    case tessellate(jobId: JobId, solidId: SolidId)
    case importStep(jobId: JobId, solidId: SolidId, data: Data)
    case booleanOperation(jobId: JobId, solidId: SolidId, op: BooleanOp, solidA: SolidId, solidB: SolidId)
    case evaluateShape(jobId: JobId, solidId: SolidId, shape: ShapeNode)
    
    public var jobId: JobId {
        switch self {
        case .makeBox(let j, _, _): return j
        case .makeCylinder(let j, _, _): return j
        case .tessellate(let j, _): return j
        case .importStep(let j, _, _): return j
        case .booleanOperation(let j, _, _, _, _): return j
        case .evaluateShape(let j, _, _): return j
        }
    }
    
    public var solidId: SolidId {
        switch self {
        case .makeBox(_, let s, _): return s
        case .makeCylinder(_, let s, _): return s
        case .tessellate(_, let s): return s
        case .importStep(_, let s, _): return s
        case .booleanOperation(_, let s, _, _, _): return s
        case .evaluateShape(_, let s, _): return s
        }
    }
}

// MARK: - Topological Query Types (ADR-D3)

public enum SubelementType: String, Sendable, Codable, Equatable, Hashable {
    case face
    case edge
    case vertex
}

public enum HistoryStepKind: String, Sendable, Codable, Equatable, Hashable {
    case generated
    case modified
    case deleted
}

public struct HistoryStep: Sendable, Codable, Equatable, Hashable {
    public var kind: HistoryStepKind
    public var label: String
    public var sourceIndex: Int?

    public init(kind: HistoryStepKind, label: String, sourceIndex: Int? = nil) {
        self.kind = kind
        self.label = label
        self.sourceIndex = sourceIndex
    }
}

public struct GeometricSignature: Sendable, Codable, Equatable, Hashable {
    public var surfaceOrCurveType: String?
    public var normal: SIMD3<Float>?
    public var centroid: SIMD3<Float>?
    public var areaOrLength: Double?

    public init(
        surfaceOrCurveType: String? = nil,
        normal: SIMD3<Float>? = nil,
        centroid: SIMD3<Float>? = nil,
        areaOrLength: Double? = nil
    ) {
        self.surfaceOrCurveType = surfaceOrCurveType
        self.normal = normal
        self.centroid = centroid
        self.areaOrLength = areaOrLength
    }
}

public struct TopologicalReference: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var sourceFeatureId: UUID
    public var elementType: SubelementType
    public var historyPath: [HistoryStep]
    public var disambiguator: GeometricSignature?

    public init(
        id: UUID = UUID(),
        sourceFeatureId: UUID,
        elementType: SubelementType,
        historyPath: [HistoryStep] = [],
        disambiguator: GeometricSignature? = nil
    ) {
        self.id = id
        self.sourceFeatureId = sourceFeatureId
        self.elementType = elementType
        self.historyPath = historyPath
        self.disambiguator = disambiguator
    }
}
