import Foundation

/// Wraps a kernel client and fails the next request on demand; the debug build's recompute-failure hook.
public actor FaultInjectingKernelClient: KernelClientProtocol {
    private let inner: any KernelClientProtocol
    private var pendingFault: KernelErrorCode?

    public init(wrapping inner: any KernelClientProtocol) {
        self.inner = inner
    }

    /// Makes the next `request` return a failure with `code` instead of reaching the inner client.
    public func failNextRequest(with code: KernelErrorCode) {
        pendingFault = code
    }

    public func request(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        if let code = pendingFault {
            pendingFault = nil
            return .failure(jobId: request.jobId, error: KernelError(code: code, message: "Forced failure"))
        }
        return await inner.request(request)
    }

    public func cancel(jobId: JobId) async { await inner.cancel(jobId: jobId) }
    public func dispose(solidId: SolidId) async { await inner.dispose(solidId: solidId) }
    public func getStats() async -> KernelStats { await inner.getStats() }
    public func restarts() async -> AsyncStream<KernelRestart> { await inner.restarts() }
}
