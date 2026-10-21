import Foundation
import Synchronization
import XPC
@testable import MadeCore

/// Wraps a local engine and runs `hook` before each job. A hook returning false stops the job:
/// it waits until its task is cancelled, as a hung or crashed service would never reply.
actor HookedEngine: KernelEngine {
    let inner = LocalKernelEngine()
    private let hook: @Sendable (KernelRequest) async -> Bool
    
    init(hook: @escaping @Sendable (KernelRequest) async -> Bool) {
        self.hook = hook
    }
    
    func execute(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        guard await hook(request) else {
            try? await Task.sleep(for: .seconds(60))
            return .failure(jobId: request.jobId, error: KernelError(code: .cancelled, message: "test job stopped"))
        }
        return await inner.execute(request)
    }
    
    func exportStep(objects: [SceneObject]) async -> KernelResult<Data> {
        await inner.exportStep(objects: objects)
    }
    
    func exportSTL(objects: [SceneObject], tolerance: Double, unit: LengthUnit, to url: URL) async -> KernelResult<Int> {
        await inner.exportSTL(objects: objects, tolerance: tolerance, unit: unit, to: url)
    }
    
    func exportThreeMF(objects: [SceneObject], tolerance: Double, unit: LengthUnit, to url: URL) async -> KernelResult<ThreeMFExportResult> {
        await inner.exportThreeMF(objects: objects, tolerance: tolerance, unit: unit, to: url)
    }
    
    func dispose(solidId: SolidId) async { await inner.dispose(solidId: solidId) }
    func terminate(jobId: JobId) async -> Bool { false }
    nonisolated func restarts() -> AsyncStream<KernelRestart> { inner.restarts() }
    func storeCounts() async -> KernelEngineCounts { await inner.storeCounts() }
}

/// An anonymous XPC listener running `KernelServiceHandler` in the test process, standing in for the service.
/// `crash()` cancels the service side of every session, which is what the app observes when the service dies.
final class KernelServiceHarness: Sendable {
    let listener: XPCListener
    private let state = Box()
    
    private final class Box: Sendable {
        let mutex = Mutex(State())
        func withLock<R>(_ body: (inout State) -> R) -> R { mutex.withLock { body(&$0) } }
    }
    
    private struct State {
        var sessions: [XPCSession] = []
        var engines: [HookedEngine] = []
        var peerGoneCount = 0
    }
    
    /// - Parameter hook: Runs before each job with the session index (0 for the first service launch)
    ///   and a closure that crashes the service.
    init(hook: @escaping @Sendable (_ session: Int, KernelRequest, _ crash: @Sendable () -> Void) async -> Bool = { _, _, _ in true }) {
        let state = self.state
        let crash: @Sendable () -> Void = { Self.cancelSessions(state) }
        let handler = KernelServiceHandler(
            makeEngine: {
                state.withLock { s in
                    let index = s.engines.count
                    let engine = HookedEngine { await hook(index, $0, crash) }
                    s.engines.append(engine)
                    return engine
                }
            },
            onPeerGone: { state.withLock { $0.peerGoneCount += 1 } },
            onSessionAccepted: { session in state.withLock { $0.sessions.append(session) } }
        )
        listener = XPCListener(incomingSessionHandler: handler.makeListenerHandler())
    }
    
    var peerGoneCount: Int { state.withLock { $0.peerGoneCount } }
    var sessionCount: Int { state.withLock { $0.sessions.count } }
    var engines: [HookedEngine] { state.withLock { $0.engines } }
    
    func crash() { Self.cancelSessions(state) }
    
    private static func cancelSessions(_ state: Box) {
        let sessions = state.withLock { s in
            defer { s.sessions.removeAll() }
            return s.sessions
        }
        for session in sessions { session.cancel(reason: "simulated crash") }
    }
    
    func makeEngine(maxRestarts: Int = 3, clock: TestClock = TestClock()) -> XPCKernelEngine {
        let endpoint = listener.endpoint
        return XPCKernelEngine(maxRestarts: maxRestarts, restartWindow: .seconds(30), now: { clock.now }) { cancellationHandler in
            try XPCSession(endpoint: endpoint, cancellationHandler: cancellationHandler)
        }
    }
    
    deinit {
        Self.cancelSessions(state)
        listener.cancel()
    }
}

final class TestClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func advance(_ duration: Duration) { instant.withLock { $0 += duration } }
}

/// A one-shot flag a test can wait on.
final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}

/// Polls `condition` for up to two seconds.
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

final class Counter: Sendable {
    private let value = Mutex(0)
    /// Returns the current count, then increments it.
    func next() -> Int { value.withLock { v in defer { v += 1 }; return v } }
}
