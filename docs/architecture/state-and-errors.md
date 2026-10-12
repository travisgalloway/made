# State & Error Handling

Error handling in `made` is designed to be **fault-tolerant and non-destructive**: a failed geometric calculation, degenerate parameter entry, or invalid boolean operation must never crash the application or wipe out previously valid mesh state.

---

## The Error Hierarchy

All kernel-level failures are represented by `KernelError` in [`MadeCore/Kernel/Types.swift`](../../macos/Sources/MadeCore/Kernel/Types.swift):

```swift
public enum KernelErrorCode: String, Sendable {
    case kernelInitFailed = "kernel-init-failed"
    case invalidParams = "invalid-params"      // Dimensions <= 0
    case geometryFailed = "geometry-failed"    // Also returned by the importStep stub
    case unknownSolid = "unknown-solid"        // Solid ID missing from the kernel cache
    case cancelled = "cancelled"               // Superseded, disposed, or cancelled before execution
    case workerCrashed = "worker-crashed"
}

public struct KernelError: Error, Equatable, Sendable {
    public let code: KernelErrorCode
    public let message: String
}
```

`KernelErrorCode` is a top-level enum with six cases. No `internalError` case exists. The JSON-RPC `internalError` (-32603) is a separate payload in `MCPProtocol.swift`. `XPCKernelEngine` produces `kernelInitFailed` when the kernel service session cannot be created or the restart breaker is open, and `workerCrashed` when the service stops twice while computing the same job (#245).

---

## Fault Tolerance Guarantees

### 1. Retention of Previous Valid Mesh
If an engineer enters an extreme or invalid dimension (e.g., width = 0), `KernelClient` rejects the job with `.invalidParams`.
- The viewport does not clear the mesh.
- The previous valid 3D geometry remains on screen.
- The Inspector's Dimensions section shows a warning row for the failed solid, naming its ID and the error code (`RecomputeFailures`). The console records the same line at error level. The next successful recompute of that solid, or its removal, clears the row.
- A `.cancelled` result produces no message and keeps any earlier failure visible, because a newer job is already pending.
- The slider ranges in `DocumentLimits` keep most degenerate values out of the kernel. A debug build can force the next recompute to fail with Debug > Fail Next Recompute (`FaultInjectingKernelClient`).

### 2. Honest Cancellation Handling
When a job is cancelled due to rapid slider scrubbing:
- The return status is `.failure(jobId: ..., error: KernelError(code: .cancelled, ...))`.
- A `.cancelled` result is a normal lifecycle event, because a newer job is already pending for the same solid.
- `KernelClientTests.testRapidRequestsConflateToLatestValue` checks that the first two of three rapid requests resolve as cancelled.

### 3. Agent Tool Error Reporting
When an AI agent invokes a tool that fails (e.g., referencing a nonexistent solid ID):
- The tool returns an `MCPToolCallResult` with `isError: true` and a text message prefixed `Error:`. The JSON-RPC response itself is a success (`result`), not an `error` payload (`MCPServer.swift`, `MCPProtocol.swift`).
- JSON-RPC `-32602` is returned only when `tools/call` has no `params.name`. `-32603` is returned only when encoding the result fails. `-32601` covers unknown methods and `-32700` covers unparseable input.
- The message gives a diagnostic hint (for example, *"Solid 'x' not found in scene"*), so the agent can correct its call and retry.
- Argument validation is partial: `cad_set_param` reports success for an unknown parameter name (#97), and transform and size arguments are not validated (#98).

---

## Related Documentation

- [`kernel.md`](./kernel.md): KernelClient error propagation
- [`agent-api.md`](./agent-api.md): JSON-RPC error mapping
- [`ui-controls.md`](./ui-controls.md): Inspector parameter feedback
