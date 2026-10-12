import Foundation
import Euclid

/// Runs Euclid geometry in the calling process. The kernel service hosts one; unbundled runs and tests use it directly.
public actor LocalKernelEngine: KernelEngine {
    private var solids: [SolidId: MeshPayload] = [:]
    private var euclidMeshes: [SolidId: Euclid.Mesh] = [:]
    
    public init() {}
    
    public func execute(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        let jobId = request.jobId
        switch request {
        case .makeBox(_, let sId, let params):
            if params.width <= 0 || params.depth <= 0 || params.height <= 0 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Box dimensions must be positive"))
            }
            let euclid = EuclidEngine.makeBox(width: params.width, depth: params.depth, height: params.height)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            return .success(jobId: jobId, value: mesh)
            
        case .makeCylinder(_, let sId, let params):
            if params.radius <= 0 || params.height <= 0 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Cylinder dimensions must be positive"))
            }
            let euclid = EuclidEngine.makeCylinder(radius: params.radius, height: params.height)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            return .success(jobId: jobId, value: mesh)
            
        case .booleanOperation(_, let sId, let op, let solidA, let solidB):
            guard let meshA = euclidMeshes[solidA] else {
                return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid A '\(solidA)' not found for CSG boolean"))
            }
            guard let meshB = euclidMeshes[solidB] else {
                return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid B '\(solidB)' not found for CSG boolean"))
            }
            
            let resultMesh: Euclid.Mesh
            switch op {
            case .subtract:
                resultMesh = EuclidEngine.subtract(meshA, meshB)
            case .union:
                resultMesh = EuclidEngine.union(meshA, meshB)
            case .intersect:
                resultMesh = EuclidEngine.intersect(meshA, meshB)
            }
            
            euclidMeshes[sId] = resultMesh
            let payload = EuclidEngine.toMeshPayload(resultMesh)
            solids[sId] = payload
            return .success(jobId: jobId, value: payload)
            
        case .evaluateShape(_, let sId, let shape):
            if let error = shape.validate() {
                return .failure(jobId: jobId, error: error)
            }
            let euclid = ShapeEvaluator.mesh(for: shape)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            return .success(jobId: jobId, value: mesh)
            
        case .tessellate(_, let sId):
            if let existing = solids[sId] {
                return .success(jobId: jobId, value: existing)
            }
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid \(sId) not found"))
            
        case .importStep(_, _, _):
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "STEP import pending OpenCASCADE bridge"))
        }
    }
    
    public func dispose(solidId: SolidId) async {
        solids.removeValue(forKey: solidId)
        euclidMeshes.removeValue(forKey: solidId)
    }
    
    /// An in-process job cannot be interrupted.
    public func terminate(jobId: JobId) async -> Bool { false }
    
    /// The in-process cache is never lost on its own.
    public nonisolated func restarts() -> AsyncStream<KernelRestart> {
        AsyncStream { $0.finish() }
    }
    
    public func storeCounts() async -> KernelEngineCounts {
        KernelEngineCounts(solids: solids.count, euclidMeshes: euclidMeshes.count)
    }
}
