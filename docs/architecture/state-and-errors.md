# State & Error Handling

Error handling in `made` is designed to be **fault-tolerant and non-destructive**: a failed geometric calculation, degenerate parameter entry, or invalid boolean operation must never crash the application or wipe out previously valid mesh state.

---

## The Error Hierarchy

All kernel-level failures are represented by `KernelError` in [`MadeCore/Kernel/Types.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Kernel/Types.swift):

```swift
public struct KernelError: Error, Sendable {
    public enum Code: String, Sendable {
        case invalidParams    // Dimensions <= 0 or non-numeric
        case unknownSolid     // Solid ID missing from scene/cache
        case geometryFailed   // CSG intersection failure or non-manifold topology
        case cancelled        // Computation superseded by newer request
        case internalError    // Unexpected system or tool error
    }
    
    public let code: Code
    public let message: String
}
```

---

## Fault Tolerance Guarantees

### 1. Retention of Previous Valid Mesh
If an engineer enters an extreme or invalid dimension (e.g., width = 0), `KernelClient` rejects the job with `.invalidParams`.
- The viewport **does not** clear the mesh.
- The previous valid 3D geometry remains on screen.
- An inline warning indicator appears in the Inspector next to the offending parameter.

### 2. Honest Cancellation Handling
When a job is cancelled due to rapid slider scrubbing:
- The return status is `.failure(jobId: ..., error: KernelError(code: .cancelled, ...))`.
- The UI layer treats `.cancelled` as a normal lifecycle event, ignoring the failure silently because a newer job is already rendering.

### 3. Agent Tool Error Reporting
When an AI agent invokes a tool that fails (e.g., referencing a nonexistent solid ID):
- The MCP server catches the error and returns a formal JSON-RPC error payload (`-32602` for invalid arguments or `-32603` for geometry failure).
- The error message provides diagnostic hints (e.g., *"Solid B 'bracket-hole' not found for CSG boolean"*), allowing the agent to self-correct its query and retry.

---

## Related Documentation

- [`kernel.md`](./kernel.md) — KernelClient error propagation
- [`agent-api.md`](./agent-api.md) — JSON-RPC error mapping
- [`ui-controls.md`](./ui-controls.md) — Inspector parameter feedback
