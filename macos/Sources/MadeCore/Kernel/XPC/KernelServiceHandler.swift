import Foundation
import XPC

/// The kernel service's side of the XPC boundary. Each accepted session gets its own engine and an ordered
/// work queue, so the session queue stays free to report the peer leaving while a job runs.
public final class KernelServiceHandler: Sendable {
    private let makeEngine: @Sendable () -> any KernelEngine
    private let onPeerGone: @Sendable () -> Void
    private let onSessionAccepted: (@Sendable (XPCSession) -> Void)?
    
    /// - Parameters:
    ///   - onPeerGone: Called when a session ends. The service process exits; tests record it.
    ///   - onSessionAccepted: Takes each accepted session; tests cancel it to reproduce a service crash.
    public init(
        makeEngine: @escaping @Sendable () -> any KernelEngine = { LocalKernelEngine() },
        onPeerGone: @escaping @Sendable () -> Void,
        onSessionAccepted: (@Sendable (XPCSession) -> Void)? = nil
    ) {
        self.makeEngine = makeEngine
        self.onPeerGone = onPeerGone
        self.onSessionAccepted = onSessionAccepted
    }
    
    /// The incoming-session handler for `XPCListener(service:)` and the anonymous test listener.
    public func makeListenerHandler() -> @Sendable (XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision {
        { [makeEngine, onPeerGone, onSessionAccepted] request in
            let worker = KernelServiceWorker(engine: makeEngine(), onTerminate: onPeerGone)
            let receive: @Sendable (XPCDictionary) -> XPCDictionary? = { message in
                worker.receive(message)
                return nil // Replies are sent from the work queue.
            }
            let ended: @Sendable (XPCRichError) -> Void = { _ in
                worker.stop()
                onPeerGone()
            }
            guard let onSessionAccepted else {
                return request.accept(incomingMessageHandler: receive, cancellationHandler: ended)
            }
            // The observer owns the returned session and must cancel it before releasing it.
            let (decision, session) = request.accept(incomingMessageHandler: receive, cancellationHandler: ended)
            onSessionAccepted(session)
            return decision
        }
    }
}

/// Runs one session's messages in arrival order against its engine.
final class KernelServiceWorker: Sendable {
    private struct Item: Sendable {
        let message: KernelWireMessage?
        let reply: @Sendable (XPCDictionary) -> Void
    }
    
    private let continuation: AsyncStream<Item>.Continuation
    private let task: Task<Void, Never>
    private let onTerminate: @Sendable () -> Void
    
    init(engine: any KernelEngine, onTerminate: @escaping @Sendable () -> Void) {
        self.onTerminate = onTerminate
        let (stream, continuation) = AsyncStream<Item>.makeStream()
        self.continuation = continuation
        let instance = UUID().uuidString
        task = Task {
            for await item in stream {
                switch item.message {
                case .execute(let request):
                    let result = await engine.execute(request)
                    if Task.isCancelled { return }
                    item.reply(KernelWire.encodeReply(result, instance: instance))
                case .dispose(let solidId):
                    await engine.dispose(solidId: solidId)
                case .terminate:
                    break // Handled in `receive`.
                case nil:
                    item.reply(KernelWire.encodeReply(.failure(jobId: JobId(""), error: KernelError(code: .geometryFailed, message: "Unreadable kernel message")), instance: instance))
                }
            }
        }
    }
    
    /// Called on the session queue; decodes and enqueues without blocking it.
    func receive(_ message: XPCDictionary) {
        let decoded = try? KernelWire.decodeMessage(message)
        if decoded == .terminate {
            // The app cancelled a job that is still running; the job cannot be interrupted, so the process ends.
            stop()
            onTerminate()
            return
        }
        // The received message is only used to send its one reply, from the work queue.
        nonisolated(unsafe) let received = message
        continuation.yield(Item(message: decoded, reply: { received.reply($0) }))
    }
    
    func stop() {
        continuation.finish()
        task.cancel()
    }
}
