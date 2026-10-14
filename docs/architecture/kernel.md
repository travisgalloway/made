# Geometry Kernel Architecture

The geometry kernel in `made` handles 3D solid construction, boolean operations, parameter evaluation, and polygon tessellation. All kernel requests go through the `KernelClient` actor, off the main UI thread. In the bundled app, geometry runs in a separate process, the `MadeKernelService` XPC service, so a crash in Euclid ends that process and not the app.

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
│   • Per-Solid Job Conflation                           │
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
│             Metal 4 Viewport (GPU Shared)              │
└────────────────────────────────────────────────────────┘
```

### Tier 1: Pure-Swift CSG (EuclidEngine)
- **Implementation**: [`EuclidEngine.swift`](../../macos/Sources/MadeCore/Kernel/EuclidEngine.swift), powered by `nicklockwood/Euclid` (0.9.6).
- **Capabilities**: Zero C++ compilation dependencies, memory-safe execution, parametric box/cylinder generators, BSP-tree CSG booleans (`subtract`, `union`, `intersect`), and conversion into indexed vertex arrays (`MeshPayload`).
- **Use Case**: Real-time parameter scrubbing in the Inspector, interactive modeling, and unit testing without heavy framework dependencies.

### Tier 2: Exact Boundary Representation (OCCTSwift), Planned (#82, ADR-D1)
Not built. OpenCASCADE Technology via `SecondMouseAU/OCCTSwift` is adopted as the canonical B-rep kernel ([ADR-D1](./adr/ADR-D1-canonical-geometry-kernel.md), #142). Today, `macos/Package.swift` declares only the Euclid dependency, and `KernelClient` answers `importStep` with `geometryFailed` ("STEP import pending OpenCASCADE bridge"). STEP import and export is tracked in #38.
- **Planned architecture**: Integration via `SecondMouseAU/OCCTSwift` using a pre-built universal `OCCT.xcframework`.
- **Planned capabilities**: True analytic curves and surfaces (NURBS, B-splines), topological data structures (`TopoDS_Shape`, `TopoDS_Face`, `TopoDS_Edge`), advanced manufacturing operations (fillet, chamfer, draft), and industrial format exchange (STEP, IGES).
- **Planned use case**: High-precision engineering exchange, production part export, and complex B-Rep fillets.

### Tier 3: Declarative CAD DSL (Cadova-Style Scripting)
- **Implementation**: [`CADDSL.swift`](../../macos/Sources/MadeCore/Scripting/CADDSL.swift).
- **Capabilities**: Declarative Swift result builders and operator overloads (`-`, `+`, `&`) allowing AI agents and engineers to express geometric models programmatically.
- **Evaluation**: The DSL performs no geometry work. Each shape builds a `ShapeNode` operation tree ([`ShapeNode.swift`](../../macos/Sources/MadeCore/Kernel/ShapeNode.swift)), and `evaluate(on:solidId:jobId:)` sends the whole tree through `KernelClient` as one `evaluateShape` request. `LocalKernelEngine` validates the tree against `ShapeLimits` (depth 64, 4,096 nodes, 3 to 512 cylinder slices, positive finite dimensions, finite offsets) and evaluates it on the engine actor. A failure returns `invalidParams` and stores nothing. `LayeringTests.scriptingReferencesNoEuclid` fails the build when `Scripting/` names Euclid.

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
    case evaluateShape(jobId: JobId, solidId: SolidId, shape: ShapeNode)
}

public struct MeshPayload: Sendable {
    public let storage: MeshStorage                 // one page-aligned MAP_SHARED region
    public var positions: MeshComponent<Float>      // 3 floats per vertex (X, Y, Z)
    public var normals: MeshComponent<Float>        // 3 floats per vertex (Nx, Ny, Nz)
    public var indices: MeshComponent<UInt32>       // 3 indices per triangle
    public var triangleCount: Int                   // indices.count / 3
}
```

Every wire type is `Codable`, and none names a Euclid type. `MeshStorage` lays out positions, then normals, then indices in one region allocated with `mmap(MAP_SHARED | MAP_ANON)`. `MeshComponent` is a read-only `RandomAccessCollection` over one component. `init(positions:normals:indices:)` copies arrays into new storage for tests and generated geometry.

`MeshPayload` carries no `solidId`. The `KernelResult` pairs it with a `JobId`, and the caller knows the `SolidId` it requested. The wire contract imports only Foundation, not rendering or UI frameworks.

---

## Actor Isolation & Debounce Conflation

The kernel is managed by `KernelClient`, an isolated Swift Actor enforcing Invariant 1 and Invariant 7:

```swift
public actor KernelClient {
    private let engine: any KernelEngine
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
When an engineer or an agent scrubs a dimensional parameter, slider events fire at 60–120 Hz. Queuing every intermediate step causes compute backlogs. `KernelClient` introduces a 60 ms debounce window per `SolidId`. Intermediate values overwrite the pending slot; only the latest parameters are dispatched for tessellation. A superseded request resolves as `.cancelled`. The debounce task checks the job ID before it takes the slot, so a stale task never strands a newer request.

### Honest Cancellation Guarantee
A request that arrives while an earlier request for the same solid is still waiting in the debounce window replaces it:
1. The earlier pending job resumes with `.failure(cancelled)` ("Conflated by newer request") and the `conflated` and `dropped` counters increase.
2. `cancel(jobId:)` adds a pending job to `cancelledJobs`, and `executePending` checks that set before it calls the engine. Cancelling a job the engine is executing calls `engine.terminate(jobId:)`, which ends the kernel service (see below).
3. After the engine returns, `KernelClient` compares `activeJobForSolid[solidId]` with the job ID. The engine call is an `await`, so a newer job for the same solid can start meanwhile, and the older result is then dropped as `cancelled`.
4. `dispose(solidId:)` drops the pending job and tells the engine to free the solid's mesh and Euclid mesh. When the solid's job is executing, `KernelClient` disposes again after the engine returns, so the result the job cached is freed too.

---

## Kernel XPC Service (#245)

`KernelClient` holds an `any KernelEngine`. Two engines exist:

- `LocalKernelEngine` runs Euclid in the calling process. The service hosts one, and `swift run`, tests, and unbundled runs use it directly.
- `XPCKernelEngine` sends each request to the `com.made.app.kernel` service over `XPCSession`. `KernelClient.makeDefault()` picks it when `Made.app/Contents/XPCServices/MadeKernelService.xpc` exists.

**Wire format.** `KernelWire` encodes a message as a binary property list under `message`. A reply holds a `KernelWireReply` header (job ID, error, component counts, and the answering engine's instance ID) under `header`. A non-empty mesh travels under `mesh` as an `xpc_shmem` object made from the `MeshStorage` region. The app maps the same pages with `xpc_shmem_map` and checks the mapped length against the header counts. A missing header or a short region returns `geometry-failed` ("Malformed kernel reply"). A zero-triangle mesh sends no region.

**Service side.** `KernelServiceHandler` accepts each session with its own engine and an ordered work queue, and replies from that queue. The session queue stays free, so the service sees the app leave while a job runs. The service exits when its session ends, and on a `terminate` message.

**One job at a time.** `XPCKernelEngine` sends jobs one by one from a FIFO, so the job in flight when the service stops caused the stop. Queued jobs never reach the dead service, and they run on the relaunched one.

**Crash recovery.** A reply error, or the session ending while a job is in flight, is a service loss. The engine drops the session and resends the job once on a new session, which relaunches the service. A second loss returns `worker-crashed` for that job. Every loss emits a `KernelRestart` on `restarts()`, after the job resolves:

- `.crashed` with no excluded solid, when the resend succeeded or the service died while idle.
- `.crashed` excluding the culprit solid, when the job got `worker-crashed`.
- `.terminated` excluding the solid, when a cancel ended the service.

XPC can relaunch an idle service behind a live session without reporting it. A reply from a new engine instance ID also emits `.crashed`.

**Regeneration.** A restart empties the service cache. `WorkspaceModel` and the `--mcp-stdio` server consume `restarts()` and resubmit every box and cylinder in their document through `KernelRegeneration`, except the excluded solid. The excluded solid keeps its previous mesh and shows its `worker-crashed` message in the Inspector; editing it retries. Boolean results are document objects under their kernel ID, but `KernelRegeneration` does not resubmit them, so a restart loses their cache entry, and a later boolean that names one returns `unknown-solid`.

**Breaker.** Three restarts inside 30 s open a breaker. While it is open, `execute` returns `kernel-init-failed` without contacting the service and emits no restart events. It closes 30 s after the last restart. Terminations do not count. A session that cannot be created also returns `kernel-init-failed`.

**Cancellation.** `terminate(jobId:)` acts only on the job in flight. It sends `terminate`, cancels the session, resolves the job as `cancelled`, and emits `.terminated`. The next request relaunches the service.

**Bundle.** `make bundle` runs `macos/scripts/bundle-app.sh`, which assembles `macos/.build/Made.app` with the service in `Contents/XPCServices` and ad-hoc signs both. `make run` and `make run-mcp` launch that bundle.

---

## Decided

- ADR-D1 (#142) is decided. OpenCASCADE Technology (OCCT) via OCCTSwift (#82) is the canonical B-rep engine for parts, with a clean-room Swift B-rep engine (#420 to #424) as the App Store fallback (#418). The kernel interface remains engine-neutral (invariant 4), and all OCCT calls execute on a single serial executor inside the MadeKernelService XPC service ([ADR-D1](./adr/ADR-D1-canonical-geometry-kernel.md)).
- ADR-D3 (#144) is decided. Downstream features reference topological entities (faces, edges, vertices) generated by upstream features via query-based references derived from algorithm generation history (`BRepTools_History`), with geometric signatures as fallback tie-breakers. Storing raw face or edge integer indices is strictly prohibited ([ADR-D3](./adr/ADR-D3-topological-naming.md), #152, #170).
- ADR-D4 (#146) is decided. FreeCAD `planegcs` (LGPL-2.1) is adopted as the canonical primary 2D geometric constraint solver, with a clean-room pure-Swift solver in `libs/` (#415) as the Mac App Store (#419) and iPadOS fallback. SolveSpace (`libslvs`, GPLv3) is rejected. Sketch constraint solving executes in-process on a dedicated background actor (Invariants 1 & 7) for zero-IPC-latency 60 Hz drag solving, conforming to an engine-neutral Swift interface in `MadeCore` (Invariant 4) with typed error diagnostics and degrees-of-freedom tracking ([ADR-D4](./adr/ADR-D4-2d-constraint-solver.md), #37).
- ADR-D5 (#147) is decided. Out-of-process file deck execution is adopted for CAE solvers and volume meshers. CalculiX `ccx` is selected for structural and thermal FEA (Abaqus `.inp` format), Gmsh for tetrahedral volume meshing from OCCT B-rep geometry, and OpenFOAM for CFD (#186). For direct-download releases, helper binaries are bundled under `Contents/Helpers/` (#413) as GPL mere aggregation. Clean-room pure-Swift solver and mesher packages in `libs/` (#415-#417) provide the Mac App Store (#419) and iPadOS (#84) fallback. Solvers run off the main thread on dedicated background actors with POSIX process group cancellation (Invariants 1 & 7) behind an engine-neutral interface (Invariant 4), streaming logs to the console drawer (#187) and storing results in `.made/cache/results/` ([ADR-D5](./adr/ADR-D5-cae-solver-and-mesher-integration.md)).
- ADR-D9 (#247) is decided. Euclid is permanently retained as the Tier 1 pure-Swift fast CSG preview engine and lightweight unit test backend, maintaining instant parameter scrubbing for procedural shape trees and zero-C++ test execution while OCCT serves as the Tier 2 canonical B-Rep kernel ([ADR-D9](./adr/ADR-D9-fate-of-euclid-mesh-path.md)).

---

## Open Decisions

No open kernel architecture decisions remain. All Phase 4.0 architecture decisions are decided.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 1, 4, 6, and 7
- [`threading-model.md`](./threading-model.md): Swift 6 actor scheduling
- [`rendering.md`](./rendering.md): How `MeshPayload` translates into Metal buffers
- [`agent-api.md`](./agent-api.md): Declarative scripting with `CADDSL`
- [ADR-D1: Canonical Geometry Kernel](./adr/ADR-D1-canonical-geometry-kernel.md)
- [ADR-D3: Topological Naming Strategy](./adr/ADR-D3-topological-naming.md)
- [ADR-D4: 2D Constraint Solver](./adr/ADR-D4-2d-constraint-solver.md)
- [ADR-D5: CAE Solver and Mesher Integration](./adr/ADR-D5-cae-solver-and-mesher-integration.md)
- [ADR-D9: Fate of Euclid Mesh Path](./adr/ADR-D9-fate-of-euclid-mesh-path.md)
