import Foundation
import Euclid
import os

private let kernelSignposter = OSSignposter(subsystem: "com.made.app", category: "Kernel")

public struct KernelStats: Sendable {
    public var dispatched: Int = 0
    public var conflated: Int = 0
    public var dropped: Int = 0
    public var completed: Int = 0
    
    public init() {}
}

public protocol KernelClientProtocol: Sendable {
    func request(_ request: KernelRequest) async -> KernelResult<MeshPayload>
    func cancel(jobId: JobId) async
    func dispose(solidId: SolidId) async
    func getStats() async -> KernelStats
}

public actor KernelClient: KernelClientProtocol {
    private var solids: [SolidId: MeshPayload] = [:]
    private var euclidMeshes: [SolidId: Euclid.Mesh] = [:]
    private var pendingJobs: [SolidId: (request: KernelRequest, continuation: CheckedContinuation<KernelResult<MeshPayload>, Never>)] = [:]
    private var activeJobForSolid: [SolidId: JobId] = [:]
    private var cancelledJobs: Set<JobId> = []
    private var debounceTasks: [SolidId: Task<Void, Never>] = [:]
    
    private var stats = KernelStats()
    private let debounceDuration: Duration
    
    public init(debounceDuration: Duration = .milliseconds(60)) {
        self.debounceDuration = debounceDuration
    }
    
    public func getStats() async -> KernelStats {
        return stats
    }
    
    public func cancel(jobId: JobId) async {
        cancelledJobs.insert(jobId)
    }
    
    public func dispose(solidId: SolidId) async {
        solids.removeValue(forKey: solidId)
        debounceTasks[solidId]?.cancel()
        debounceTasks.removeValue(forKey: solidId)
        if let pending = pendingJobs.removeValue(forKey: solidId) {
            stats.dropped += 1
            pending.continuation.resume(returning: .failure(jobId: pending.request.jobId, error: KernelError(code: .cancelled, message: "Solid disposed")))
        }
    }
    
    public func request(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        let solidId = request.solidId
        let jobId = request.jobId
        
        // If there's an existing pending job for this solid, conflate it
        if let existing = pendingJobs.removeValue(forKey: solidId) {
            stats.conflated += 1
            stats.dropped += 1
            existing.continuation.resume(returning: .failure(jobId: existing.request.jobId, error: KernelError(code: .cancelled, message: "Conflated by newer request")))
        }
        
        debounceTasks[solidId]?.cancel()
        
        return await withCheckedContinuation { continuation in
            pendingJobs[solidId] = (request, continuation)
            
            debounceTasks[solidId] = Task { [weak self, solidId, jobId, debounceDuration] in
                do {
                    try await Task.sleep(for: debounceDuration)
                } catch {
                    return // Task cancelled
                }
                
                await self?.executePending(for: solidId, expectedJobId: jobId)
            }
        }
    }
    
    /// Pending job for a solid, if any. Lets tests order requests deterministically.
    func pendingJobId(for solidId: SolidId) -> JobId? {
        pendingJobs[solidId]?.request.jobId
    }
    
    func executePending(for solidId: SolidId, expectedJobId: JobId) {
        // Check before removing: a stale debounce task must never take a newer job's slot (#90).
        guard let pending = pendingJobs[solidId], pending.request.jobId == expectedJobId else {
            return
        }
        pendingJobs.removeValue(forKey: solidId)
        debounceTasks.removeValue(forKey: solidId)
        
        let req = pending.request
        let jobId = req.jobId
        
        if cancelledJobs.contains(jobId) {
            cancelledJobs.remove(jobId)
            stats.dropped += 1
            pending.continuation.resume(returning: .failure(jobId: jobId, error: KernelError(code: .cancelled, message: "Job cancelled before execution")))
            return
        }
        
        activeJobForSolid[solidId] = jobId
        stats.dispatched += 1
        
        let interval = kernelSignposter.beginInterval("Kernel Job", id: kernelSignposter.makeSignpostID(), "\(solidId.rawValue, privacy: .public)")
        defer { kernelSignposter.endInterval("Kernel Job", interval) }
        
        // Compute geometry
        let result: KernelResult<MeshPayload>
        switch pending.request {
        case .makeBox(_, let sId, let params):
            if params.width <= 0 || params.depth <= 0 || params.height <= 0 {
                result = .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Box dimensions must be positive"))
            } else {
                let euclid = EuclidEngine.makeBox(width: params.width, depth: params.depth, height: params.height)
                euclidMeshes[sId] = euclid
                let mesh = EuclidEngine.toMeshPayload(euclid)
                solids[sId] = mesh
                result = .success(jobId: jobId, value: mesh)
            }
            
        case .makeCylinder(_, let sId, let params):
            if params.radius <= 0 || params.height <= 0 {
                result = .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Cylinder dimensions must be positive"))
            } else {
                let euclid = EuclidEngine.makeCylinder(radius: params.radius, height: params.height)
                euclidMeshes[sId] = euclid
                let mesh = EuclidEngine.toMeshPayload(euclid)
                solids[sId] = mesh
                result = .success(jobId: jobId, value: mesh)
            }
            
        case .booleanOperation(_, let sId, let op, let solidA, let solidB):
            guard let meshA = euclidMeshes[solidA] else {
                result = .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid A '\(solidA)' not found for CSG boolean"))
                break
            }
            guard let meshB = euclidMeshes[solidB] else {
                result = .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid B '\(solidB)' not found for CSG boolean"))
                break
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
            result = .success(jobId: jobId, value: payload)
            
        case .tessellate(_, let sId):
            if let existing = solids[sId] {
                result = .success(jobId: jobId, value: existing)
            } else {
                result = .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid \(sId) not found"))
            }
            
        case .importStep(_, _, _):
            result = .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "STEP import pending OpenCASCADE bridge"))
        }
        
        // Drop result if active job for solid changed in between (honest cancellation guarantee)
        if activeJobForSolid[solidId] == jobId {
            stats.completed += 1
            pending.continuation.resume(returning: result)
        } else {
            stats.dropped += 1
            pending.continuation.resume(returning: .failure(jobId: jobId, error: KernelError(code: .cancelled, message: "Result dropped: superseded during execution")))
        }
    }
}
