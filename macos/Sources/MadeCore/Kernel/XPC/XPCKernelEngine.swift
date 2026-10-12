import Foundation
import XPC
import os

private let logger = Logger(subsystem: "com.made.app", category: "Kernel")

/// Runs geometry in the kernel XPC service, so a crash in Euclid ends the service and not the app (invariant 1).
/// Sends one job at a time, so the job in flight when the service stops is the one that stopped it.
public actor XPCKernelEngine: KernelEngine {
    /// Opens a session; the handler reports the session ending.
    public typealias SessionFactory = @Sendable (_ cancellationHandler: @escaping @Sendable (XPCRichError) -> Void) throws -> XPCSession

    private enum Outcome {
        case reply(KernelResult<MeshPayload>, instance: String?)
        case lost(String)
        case terminated
    }

    private struct Attempt {
        let id: Int
        let jobId: JobId
        let solidId: SolidId
        let continuation: CheckedContinuation<Outcome, Never>
    }

    private let makeSession: SessionFactory
    private let maxRestarts: Int
    private let restartWindow: Duration
    private let now: @Sendable () -> ContinuousClock.Instant

    private var session: XPCSession?
    private var sessionGeneration = 0
    private var waiting: [(request: KernelRequest, continuation: CheckedContinuation<KernelResult<MeshPayload>, Never>)] = []
    private var isDraining = false
    private var attempt: Attempt?
    private var attemptCounter = 0
    private var restartTimes: [ContinuousClock.Instant] = []
    /// The engine instance that answered last. XPC can relaunch an idle service without telling the session,
    /// so a changed instance is the only sign that the service cache was lost.
    private var serviceInstance: String?

    private let restartStream: AsyncStream<KernelRestart>
    private let restartContinuation: AsyncStream<KernelRestart>.Continuation

    public init(
        maxRestarts: Int = 3,
        restartWindow: Duration = .seconds(30),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        makeSession: @escaping SessionFactory
    ) {
        self.makeSession = makeSession
        self.maxRestarts = maxRestarts
        self.restartWindow = restartWindow
        self.now = now
        (restartStream, restartContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    deinit {
        // XPC traps when a session is released before it is cancelled.
        session?.cancel(reason: "kernel engine released")
    }
    
    public nonisolated func restarts() -> AsyncStream<KernelRestart> { restartStream }

    /// The app holds no geometry; the service's cache is out of reach.
    public func storeCounts() async -> KernelEngineCounts { KernelEngineCounts() }

    public func execute(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        await withCheckedContinuation { continuation in
            waiting.append((request, continuation))
            if !isDraining {
                isDraining = true
                Task { await drain() }
            }
        }
    }

    public func dispose(solidId: SolidId) async {
        // With no session there is no service cache to free.
        guard let session, let message = try? KernelWire.encode(.dispose(solidId)) else { return }
        try? session.send(message: message)
    }

    public func terminate(jobId: JobId) async -> Bool {
        guard let current = attempt, current.jobId == jobId else { return false }
        attempt = nil
        if let session, let message = try? KernelWire.encode(.terminate) {
            try? session.send(message: message)
        }
        discardSession(reason: "job cancelled")
        emitRestart(.terminated, excluding: current.solidId)
        current.continuation.resume(returning: .terminated)
        return true
    }

    private func drain() async {
        while !waiting.isEmpty {
            let job = waiting.removeFirst()
            job.continuation.resume(returning: await run(job.request))
        }
        isDraining = false
    }

    private func run(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        let jobId = request.jobId
        if isBreakerOpen() {
            return .failure(jobId: jobId, error: KernelError(code: .kernelInitFailed, message: "Kernel service restarted too often; retrying after \(restartWindow.components.seconds) s"))
        }
        // A lost service gets one resend on a new session; a second loss blames this job.
        for resend in 0..<2 {
            let current: XPCSession
            do {
                current = try currentSession()
            } catch {
                return .failure(jobId: jobId, error: KernelError(code: .kernelInitFailed, message: "Kernel service unavailable: \(error)"))
            }
            switch await send(request, on: current) {
            case .reply(let result, let instance):
                let relaunched = serviceInstance != nil && instance != nil && serviceInstance != instance
                if resend > 0 || relaunched { emitRestart(.crashed, excluding: nil) }
                if instance != nil { serviceInstance = instance }
                return result
            case .terminated:
                return .failure(jobId: jobId, error: KernelError(code: .cancelled, message: "Job cancelled; kernel service terminated"))
            case .lost(let reason):
                logger.log("Kernel service lost during \(jobId.rawValue, privacy: .public): \(reason, privacy: .public)")
                recordRestart()
            }
        }
        emitRestart(.crashed, excluding: request.solidId)
        return .failure(jobId: jobId, error: KernelError(code: .workerCrashed, message: "Kernel service stopped while computing \(request.solidId)"))
    }

    private func send(_ request: KernelRequest, on session: XPCSession) async -> Outcome {
        let message: XPCDictionary
        do {
            message = try KernelWire.encode(.execute(request))
        } catch {
            return .reply(.failure(jobId: request.jobId, error: KernelError(code: .invalidParams, message: "Request could not be encoded: \(error)")), instance: nil)
        }
        attemptCounter += 1
        let id = attemptCounter
        let jobId = request.jobId
        return await withCheckedContinuation { continuation in
            attempt = Attempt(id: id, jobId: jobId, solidId: request.solidId, continuation: continuation)
            session.send(message: message) { [weak self] result in
                let outcome: Outcome
                switch result {
                case .success(let reply): outcome = .reply(KernelWire.decodeReply(reply, jobId: jobId), instance: KernelWire.instance(of: reply))
                case .failure(let error): outcome = .lost(error.debugDescription)
                }
                Task { await self?.finish(attempt: id, outcome) }
            }
        }
    }

    private func finish(attempt id: Int, _ outcome: Outcome) {
        guard let current = attempt, current.id == id else { return }
        attempt = nil
        // Drop the session now, so its own end notice cannot read as a second, idle loss.
        if case .lost = outcome { discardSession(reason: "kernel service lost") }
        current.continuation.resume(returning: outcome)
    }

    private func currentSession() throws -> XPCSession {
        if let session { return session }
        sessionGeneration += 1
        let generation = sessionGeneration
        let created = try makeSession { [weak self] error in
            Task { await self?.sessionEnded(generation: generation, error.debugDescription) }
        }
        session = created
        return created
    }

    /// The service left. A job in flight takes the resend path; an idle loss still tells callers to regenerate.
    private func sessionEnded(generation: Int, _ reason: String) {
        logger.log("Kernel service session ended: \(reason, privacy: .public)")
        guard generation == sessionGeneration, session != nil else { return }
        if let current = attempt {
            finish(attempt: current.id, .lost(reason))
        } else {
            discardSession(reason: "kernel service lost")
            recordRestart()
            if !isBreakerOpen() {
                emitRestart(.crashed, excluding: nil)
            }
        }
    }

    /// Tells consumers to regenerate. The next reply names the new instance, so it is not reported twice.
    private func emitRestart(_ reason: KernelRestart.Reason, excluding solid: SolidId?) {
        serviceInstance = nil
        restartContinuation.yield(KernelRestart(reason: reason, excludedSolid: solid))
    }
    
    private func discardSession(reason: String) {
        guard let old = session else { return }
        session = nil
        sessionGeneration += 1
        old.cancel(reason: reason)
    }

    private func recordRestart() {
        let time = now()
        restartTimes.removeAll { time - $0 >= restartWindow }
        restartTimes.append(time)
    }

    /// Open once `maxRestarts` restarts fall inside the window, until the window passes after the last one.
    private func isBreakerOpen() -> Bool {
        guard let last = restartTimes.last else { return false }
        if now() - last >= restartWindow {
            restartTimes.removeAll()
            return false
        }
        return restartTimes.count >= maxRestarts
    }
}
