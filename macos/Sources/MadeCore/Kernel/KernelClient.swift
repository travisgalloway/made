import Foundation
import os

private let kernelSignposter = OSSignposter(subsystem: "com.made.app", category: "Kernel")

public struct KernelStats: Equatable, Sendable {
    public var dispatched: Int = 0
    public var conflated: Int = 0
    public var dropped: Int = 0
    public var completed: Int = 0
    
    public init() {}
}

/// Per-store entry counts. Lets tests prove dispose leaves nothing behind.
struct KernelStoreCounts: Equatable, Sendable {
    var solids = 0
    var euclidMeshes = 0
    var occtShapes = 0
    var pendingJobs = 0
    var activeJobs = 0
    var cancelledJobs = 0
    var debounceTasks = 0
}

public protocol KernelClientProtocol: Sendable {
    func request(_ request: KernelRequest) async -> KernelResult<MeshPayload>
    func exportStep(objects: [SceneObject]) async -> KernelResult<Data>
    func exportSTL(objects: [SceneObject], tolerance: Double, unit: LengthUnit, to url: URL) async -> KernelResult<Int>
    func cancel(jobId: JobId) async
    func dispose(solidId: SolidId) async
    func getStats() async -> KernelStats
    /// Events after which the kernel holds no solids; callers resubmit from the document.
    func restarts() async -> AsyncStream<KernelRestart>
}

extension KernelClientProtocol {
    public func restarts() async -> AsyncStream<KernelRestart> {
        AsyncStream { $0.finish() }
    }

    public func exportStep(objects: [SceneObject]) async -> KernelResult<Data> {
        .failure(jobId: JobId("export"), error: KernelError(code: .geometryFailed, message: "STEP export not supported by this client"))
    }

    public func exportSTL(objects: [SceneObject], tolerance: Double, unit: LengthUnit, to url: URL) async -> KernelResult<Int> {
        .failure(jobId: JobId("export"), error: KernelError(code: .geometryFailed, message: "STL export not supported by this client"))
    }
}

public actor KernelClient: KernelClientProtocol {
    private let engine: any KernelEngine
    private var pendingJobs: [SolidId: (request: KernelRequest, continuation: CheckedContinuation<KernelResult<MeshPayload>, Never>)] = [:]
    private var activeJobForSolid: [SolidId: JobId] = [:]
    private var cancelledJobs: Set<JobId> = []
    /// Jobs awaiting the engine. A dispose that lands meanwhile must free what the job writes back.
    private var executingJobs: Set<JobId> = []
    private var disposedWhileExecuting: Set<JobId> = []
    private var debounceTasks: [SolidId: Task<Void, Never>] = [:]
    
    private var stats = KernelStats()
    private let debounceDuration: Duration
    
    public init(engine: any KernelEngine = LocalKernelEngine(), debounceDuration: Duration = .milliseconds(60)) {
        self.engine = engine
        self.debounceDuration = debounceDuration
    }
    
    public func restarts() async -> AsyncStream<KernelRestart> {
        engine.restarts()
    }
    
    public func getStats() async -> KernelStats {
        return stats
    }

    public func exportStep(objects: [SceneObject]) async -> KernelResult<Data> {
        await engine.exportStep(objects: objects)
    }

    public func exportSTL(objects: [SceneObject], tolerance: Double, unit: LengthUnit, to url: URL) async -> KernelResult<Int> {
        await engine.exportSTL(objects: objects, tolerance: tolerance, unit: unit, to: url)
    }
    
    /// A pending job is dropped before it runs. An executing job is ended by the engine, which may stop the service.
    public func cancel(jobId: JobId) async {
        if executingJobs.contains(jobId) {
            _ = await engine.terminate(jobId: jobId)
        } else {
            cancelledJobs.insert(jobId)
        }
    }
    
    public func dispose(solidId: SolidId) async {
        if let active = activeJobForSolid.removeValue(forKey: solidId), executingJobs.contains(active) {
            disposedWhileExecuting.insert(active)
        }
        debounceTasks[solidId]?.cancel()
        debounceTasks.removeValue(forKey: solidId)
        if let pending = pendingJobs.removeValue(forKey: solidId) {
            cancelledJobs.remove(pending.request.jobId)
            stats.dropped += 1
            pending.continuation.resume(returning: .failure(jobId: pending.request.jobId, error: KernelError(code: .cancelled, message: "Solid disposed")))
        }
        await engine.dispose(solidId: solidId)
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
    
    func storeCounts() async -> KernelStoreCounts {
        let engineCounts = await engine.storeCounts()
        return KernelStoreCounts(solids: engineCounts.solids, euclidMeshes: engineCounts.euclidMeshes, occtShapes: engineCounts.occtShapes, pendingJobs: pendingJobs.count,
                          activeJobs: activeJobForSolid.count, cancelledJobs: cancelledJobs.count, debounceTasks: debounceTasks.count)
    }
    
    func executePending(for solidId: SolidId, expectedJobId: JobId) async {
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
        
        executingJobs.insert(jobId)
        let result = await engine.execute(req)
        executingJobs.remove(jobId)
        
        if disposedWhileExecuting.remove(jobId) != nil {
            // The engine cached this solid after dispose cleared it; free it unless a newer job owns the solid.
            if activeJobForSolid[solidId] == nil {
                await engine.dispose(solidId: solidId)
            }
            stats.dropped += 1
            pending.continuation.resume(returning: .failure(jobId: jobId, error: KernelError(code: .cancelled, message: "Solid disposed during execution")))
            return
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
