import Foundation

/// Why the kernel's geometry cache was lost. Consumers resubmit every solid except `excludedSolid`.
public struct KernelRestart: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// The kernel service stopped on its own, by a crash or an abort.
        case crashed
        /// The app ended the service to stop a job it cancelled.
        case terminated
    }
    
    public let reason: Reason
    /// The solid whose job was running when the service stopped; resubmitting it may stop the service again.
    public let excludedSolid: SolidId?
    
    public init(reason: Reason, excludedSolid: SolidId?) {
        self.reason = reason
        self.excludedSolid = excludedSolid
    }
}

/// Cache entry counts held by an engine. Lets tests prove dispose leaves nothing behind.
public struct KernelEngineCounts: Equatable, Sendable {
    public var solids = 0
    /// Number of cached Euclid meshes held in the Tier 1 fast CSG engine cache (ADR-D9 #247).
    public var euclidMeshes = 0
    
    public init(solids: Int = 0, euclidMeshes: Int = 0) {
        self.solids = solids
        self.euclidMeshes = euclidMeshes
    }
}

/// Runs geometry for `KernelClient`, in this process or in the kernel XPC service (invariants 1 and 4).
public protocol KernelEngine: Actor {
    func execute(_ request: KernelRequest) async -> KernelResult<MeshPayload>
    func dispose(solidId: SolidId) async
    /// Ends the job if it is executing; returns false when it is not.
    func terminate(jobId: JobId) async -> Bool
    /// Cache-loss events. One consumer.
    nonisolated func restarts() -> AsyncStream<KernelRestart>
    func storeCounts() async -> KernelEngineCounts
}
