# Geometry Kernel Architecture

The geometry kernel in `made` handles 3D solid construction, boolean operations, parameter evaluation, and polygon tessellation. All kernel operations execute asynchronously off the main UI thread within a dedicated Swift Actor.

---

## Multi-Tier Geometry Engine

The design uses a multi-tier geometry strategy. Tier 1 and Tier 3 exist in the code. Tier 2 is planned (#82) and marked PLANNED in the diagram below:

```
┌────────────────────────────────────────────────────────┐
│               SwiftUI & In-App Agent                   │
└──────────────────────────┬─────────────────────────────┘
                           │ KernelRequest (wire contract)
┌──────────────────────────▼─────────────────────────────┐
│                 KernelClient (Actor)                   │
│   • 60 ms Debounce Queue                               │
│   • Per-Solid Job Conflation (test failing, #90)       │
│   • Stale-result drop by job ID                        │
└──────────────┬──────────────────────────┬──────────────┘
               │                          │
   Tier 1: Fast CSG Engine     Tier 2: Exact B-Rep Engine
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│        EuclidEngine        │ │   OCCTSwift (PLANNED)   │
│   (Pure Swift CSG 0.9.6)   │ │  not in Package.swift   │
│ • Zero C++ dependencies    │ │ • Exact B-Rep topology  │
│ • Box / cylinder           │ │ • STEP / IGES I/O       │
│ • CSG booleans             │ │ • Fillets & chamfers    │
└──────────────┬─────────────┘ └──────────┬──────────────┘
               │                          │
               └───────────┬──────────────┘
                           │ MeshPayload (Positions, Normals, Indices)
┌──────────────────────────▼─────────────────────────────┐
│             Metal 3 Viewport (GPU Shared)              │
└────────────────────────────────────────────────────────┘
```

### Tier 1: Pure-Swift CSG (EuclidEngine)
- **Implementation**: [`EuclidEngine.swift`](../../macos/Sources/MadeCore/Kernel/EuclidEngine.swift), powered by `nicklockwood/Euclid` (0.9.6).
- **Capabilities**: Zero C++ compilation dependencies, memory-safe execution, parametric box/cylinder generators, BSP-tree CSG booleans (`subtract`, `union`, `intersect`), and conversion into indexed vertex arrays (`MeshPayload`).
- **Use Case**: Real-time parameter scrubbing in the Inspector, interactive modeling, and unit testing without heavy framework dependencies.

### Tier 2: Exact Boundary Representation (OCCTSwift), Planned (#82)
Not built. `macos/Package.swift` declares only the Euclid dependency, and `KernelClient` answers `importStep` with `geometryFailed` ("STEP import pending OpenCASCADE bridge"). STEP import and export is tracked in #38.
- **Planned architecture**: Integration via `SecondMouseAU/OCCTSwift` using a pre-built universal `OCCT.xcframework`.
- **Planned capabilities**: True analytic curves and surfaces (NURBS, B-splines), topological data structures (`TopoDS_Shape`, `TopoDS_Face`, `TopoDS_Edge`), advanced manufacturing operations (fillet, chamfer, draft), and industrial format exchange (STEP, IGES).
- **Planned use case**: High-precision engineering exchange, production part export, and complex B-Rep fillets.

### Tier 3: Declarative CAD DSL (Cadova-Style Scripting)
- **Implementation**: [`CADDSL.swift`](../../macos/Sources/MadeCore/Scripting/CADDSL.swift).
- **Capabilities**: Declarative Swift result builders and operator overloads (`-`, `+`, `&`) allowing AI agents and engineers to express geometric models programmatically.

---

## Wire Contract

All communication with the kernel traverses the typed wire contract defined in [`MadeCore/Kernel/Types.swift`](../../macos/Sources/MadeCore/Kernel/Types.swift):

```swift
public enum KernelRequest: Sendable {
    case makeBox(jobId: JobId, solidId: SolidId, params: BoxParams)
    case makeCylinder(jobId: JobId, solidId: SolidId, params: CylinderParams)
    case booleanOperation(jobId: JobId, solidId: SolidId, op: BooleanOp, solidA: SolidId, solidB: SolidId)
    case tessellate(jobId: JobId, solidId: SolidId)
    case importStep(jobId: JobId, solidId: SolidId, data: Data)
}

public struct MeshPayload: Sendable {
    public let positions: [Float]    // 3 floats per vertex (X, Y, Z)
    public let normals: [Float]      // 3 floats per vertex (Nx, Ny, Nz)
    public let indices: [UInt32]     // 3 indices per triangle
    public let triangleCount: Int    // indices.count / 3, set by init(positions:normals:indices:)
}
```

`MeshPayload` carries no `solidId`. The `KernelResult` pairs it with a `JobId`, and the caller knows the `SolidId` it requested. The wire contract imports only Foundation, not rendering or UI frameworks.

---

## Actor Isolation & Debounce Conflation

The kernel is managed by `KernelClient`, an isolated Swift Actor enforcing Invariant 1 and Invariant 7:

```swift
public actor KernelClient {
    private let debounceDuration: Duration
    private var debounceTasks: [SolidId: Task<Void, Never>] = [:]
    private var pendingJobs: [SolidId: (request: KernelRequest, continuation: CheckedContinuation<KernelResult<MeshPayload>, Never>)] = [:]
    private var activeJobForSolid: [SolidId: JobId] = [:]
    private var cancelledJobs: Set<JobId> = []
    
    public func request(_ req: KernelRequest) async -> KernelResult<MeshPayload> {
        // 60 ms debounce window conflating intermediate slider drags
        ...
    }
}
```

### The 60 ms Conflation Window
When an engineer or an agent scrubs a dimensional parameter, slider events fire at 60–120 Hz. Queuing every intermediate step causes compute backlogs. `KernelClient` introduces a 60 ms debounce window per `SolidId`. Intermediate values overwrite the pending slot; only the latest parameters are dispatched for tessellation. The test `testRapidRequestsConflateToLatestValue` fails today, and the conflation bug is tracked in #90.

### Honest Cancellation Guarantee
A request that arrives while an earlier request for the same solid is still waiting in the debounce window replaces it:
1. The earlier pending job resumes with `.failure(cancelled)` ("Conflated by newer request") and the `conflated` and `dropped` counters increase.
2. `cancel(jobId:)` adds the job to `cancelledJobs`. `executePending` checks that set before it calls the engine.
3. After the engine returns, `KernelClient` compares `activeJobForSolid[solidId]` with the job ID (line 162). The engine call is synchronous inside the actor, so this check seldom differs; the conflation path is the effective guard (see the feature matrix, KERN-12).
4. `dispose(solidId:)` removes the solid's cached payload and pending job but not its Euclid mesh (#93).

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 1, 4, 6, and 7
- [`threading-model.md`](./threading-model.md): Swift 6 actor scheduling
- [`rendering.md`](./rendering.md): How `MeshPayload` translates into Metal buffers
- [`agent-api.md`](./agent-api.md): Declarative scripting with `CADDSL`
