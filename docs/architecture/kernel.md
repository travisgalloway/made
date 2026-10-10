# Geometry Kernel Architecture

The geometry kernel in `made` handles 3D solid construction, boolean operations, parameter evaluation, and polygon tessellation. All kernel operations execute asynchronously off the main UI thread within a dedicated Swift Actor.

---

## Multi-Tier Geometry Engine

The native architecture uses a multi-tier geometry strategy that balances zero-dependency developer velocity with high-precision engineering standards:

```
┌────────────────────────────────────────────────────────┐
│               SwiftUI & In-App Agent                   │
└──────────────────────────┬─────────────────────────────┘
                           │ KernelRequest (wire contract)
┌──────────────────────────▼─────────────────────────────┐
│                 KernelClient (Actor)                   │
│   • 60 ms Debounce Queue                               │
│   • Per-Solid Job Conflation                           │
│   • Honest Cancellation Guarantee                      │
└──────────────┬──────────────────────────┬──────────────┘
               │                          │
   Tier 1: Fast CSG Engine     Tier 2: Exact B-Rep Engine
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│        EuclidEngine        │ │        OCCTSwift        │
│   (Pure Swift CSG 0.9.6)   │ │  (OpenCASCADE Framework)│
│ • Zero C++ dependencies    │ │ • Exact B-Rep topology  │
│ • Instant box / cylinder   │ │ • STEP / IGES I/O       │
│ • Watertight CSG booleans  │ │ • Fillets & chamfers    │
└──────────────┬─────────────┘ └──────────┬──────────────┘
               │                          │
               └───────────┬──────────────┘
                           │ MeshPayload (Positions, Normals, Indices)
┌──────────────────────────▼─────────────────────────────┐
│             Metal 3 Viewport (GPU Shared)              │
└────────────────────────────────────────────────────────┘
```

### Tier 1: Pure-Swift CSG (EuclidEngine)
- **Implementation**: [`EuclidEngine.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Kernel/EuclidEngine.swift), powered by `nicklockwood/Euclid` (0.9.6).
- **Capabilities**: Zero C++ compilation dependencies, memory-safe execution, parametric box/cylinder generators, exact BSP-tree CSG booleans (`subtract`, `union`, `intersect`), and zero-copy triangulation into indexed vertex arrays.
- **Use Case**: Real-time parameter scrubbing in the Inspector, interactive modeling, and unit testing without heavy framework dependencies.

### Tier 2: Exact Boundary Representation (OCCTSwift)
- **Architecture**: Integrated via `SecondMouseAU/OCCTSwift` using pre-built universal `OCCT.xcframework`.
- **Capabilities**: True analytic curves and surfaces (NURBS, B-splines), topological data structures (`TopoDS_Shape`, `TopoDS_Face`, `TopoDS_Edge`), advanced manufacturing operations (fillet, chamfer, draft), and industrial format exchange (STEP, IGES).
- **Use Case**: High-precision engineering exchange, production part export, and complex B-Rep fillets.

### Tier 3: Declarative CAD DSL (Cadova-Style Scripting)
- **Implementation**: [`CADDSL.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Scripting/CADDSL.swift).
- **Capabilities**: Declarative Swift result builders and operator overloads (`-`, `+`, `&`) allowing AI agents and engineers to express geometric models programmatically.

---

## Wire Contract

All communication with the kernel traverses the typed wire contract defined in [`MadeCore/Kernel/Types.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Kernel/Types.swift):

```swift
public enum KernelRequest: Sendable {
    case makeBox(jobId: JobId, solidId: SolidId, params: BoxParams)
    case makeCylinder(jobId: JobId, solidId: SolidId, params: CylinderParams)
    case booleanOperation(jobId: JobId, solidId: SolidId, op: BooleanOp, solidA: SolidId, solidB: SolidId)
    case tessellate(jobId: JobId, solidId: SolidId)
    case importStep(jobId: JobId, solidId: SolidId, data: Data)
}

public struct MeshPayload: Sendable {
    public let solidId: SolidId
    public let positions: [Float]    // 3 floats per vertex (X, Y, Z)
    public let normals: [Float]      // 3 floats per vertex (Nx, Ny, Nz)
    public let indices: [UInt32]     // 3 indices per triangle
    public let triangleCount: Int
}
```

The wire contract has zero dependencies on rendering or UI frameworks.

---

## Actor Isolation & Debounce Conflation

The kernel is managed by `KernelClient`, an isolated Swift Actor enforcing Invariant 1 and Invariant 7:

```swift
public actor KernelClient {
    private let debounceDuration: Duration
    private var pendingDebounce: [SolidId: Task<Void, Never>] = [:]
    private var pendingRequests: [SolidId: PendingJob] = [:]
    private var activeJobForSolid: [SolidId: JobId] = [:]
    private var cancelledJobs: Set<JobId> = []
    
    public func request(_ req: KernelRequest) async -> KernelResult<MeshPayload> {
        // 60 ms debounce window conflating intermediate slider drags
        ...
    }
}
```

### The 60 ms Conflation Window
When an engineer or an agent scrubs a dimensional parameter, slider events fire at 60–120 Hz. Queuing every intermediate step causes compute backlogs. `KernelClient` introduces a 60 ms debounce window per `SolidId`. Intermediate values overwrite the pending slot; only the latest parameters are dispatched for tessellation.

### Honest Cancellation Guarantee
If job $J_1$ is currently being computed by the geometry engine and a new request $J_2$ arrives for the same solid:
1. $J_1$ is marked as cancelled in the actor's state table.
2. When $J_1$'s computation completes, `KernelClient` inspects `activeJobForSolid[solidId]`. Because the active job is now $J_2$, $J_1$'s result is discarded immediately.
3. The continuation for $J_1$ returns `.failure(cancelled)`.
4. Stale meshes are never delivered to the viewport, preventing visual flicker.

---

## Related Documentation

- [`invariants.md`](./invariants.md) — Invariants 1, 4, 6, and 7
- [`threading-model.md`](./threading-model.md) — Swift 6 actor scheduling
- [`rendering.md`](./rendering.md) — How `MeshPayload` translates into Metal buffers
- [`agent-api.md`](./agent-api.md) — Declarative scripting with `CADDSL`
