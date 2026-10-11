import Foundation

public struct SolidId: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

public struct JobId: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

public struct BoxParams: Hashable, Equatable, Sendable {
    public var width: Float
    public var depth: Float
    public var height: Float
    
    public init(width: Float, depth: Float, height: Float) {
        self.width = width
        self.depth = depth
        self.height = height
    }
}

public struct CylinderParams: Hashable, Equatable, Sendable {
    public var radius: Float
    public var height: Float
    
    public init(radius: Float, height: Float) {
        self.radius = radius
        self.height = height
    }
}

public struct MeshPayload: Sendable {
    public let positions: [Float]
    public let normals: [Float]
    public let indices: [UInt32]
    public let triangleCount: Int
    
    public init(positions: [Float], normals: [Float], indices: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.triangleCount = indices.count / 3
    }
}

public enum KernelErrorCode: String, Sendable {
    case kernelInitFailed = "kernel-init-failed"
    case invalidParams = "invalid-params"
    case geometryFailed = "geometry-failed"
    case unknownSolid = "unknown-solid"
    case cancelled = "cancelled"
    case workerCrashed = "worker-crashed"
}

public struct KernelError: Error, Equatable, Sendable {
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

public enum KernelRequest: Sendable {
    case makeBox(jobId: JobId, solidId: SolidId, params: BoxParams)
    case makeCylinder(jobId: JobId, solidId: SolidId, params: CylinderParams)
    case tessellate(jobId: JobId, solidId: SolidId)
    case importStep(jobId: JobId, solidId: SolidId, data: Data)
    case booleanOperation(jobId: JobId, solidId: SolidId, op: BooleanOp, solidA: SolidId, solidB: SolidId)
    
    public var jobId: JobId {
        switch self {
        case .makeBox(let j, _, _): return j
        case .makeCylinder(let j, _, _): return j
        case .tessellate(let j, _): return j
        case .importStep(let j, _, _): return j
        case .booleanOperation(let j, _, _, _, _): return j
        }
    }
    
    public var solidId: SolidId {
        switch self {
        case .makeBox(_, let s, _): return s
        case .makeCylinder(_, let s, _): return s
        case .tessellate(_, let s): return s
        case .importStep(_, let s, _): return s
        case .booleanOperation(_, let s, _, _, _): return s
        }
    }
}
