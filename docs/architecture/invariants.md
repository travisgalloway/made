# Architectural Invariants

**This is the canonical list of design contracts for `made`.**

These invariants must hold at every phase. A violation is treated as a build break. If a task appears to require breaking one, stop and flag it rather than working around it.

> **The numbers are permanent.** Every one of the nine invariants is cited by number across the codebase: in comments, configuration, and unit tests. Phrasings include `invariant N`, `Invariant N`, `architecture invariant N`, and `invariants N and M`. **Never renumber.** Add any new invariants at the end.

---

## The Nine Invariants

1. **The kernel runs off the main thread.** No geometry generation or CSG boolean operation executes on the main UI thread. All kernel requests run within the `KernelClient` Swift actor.

2. **Rendering is on-demand.** No continuous animation loop. The Metal renderer draws only when the camera moves, a solid changes, or an interaction is active. In MetalKit, this is enforced by configuring `MTKView.isPaused = true` and `enableSetNeedsDisplay = true`, requesting frames explicitly via `setNeedsDisplay()`.

3. **The viewport is imperative, not reactive.** SwiftUI reactive state drives UI panels and inspector forms only. Viewport mesh geometry and per-frame state never reside in SwiftUI `@State` that would re-evaluate on each frame. Metal buffers are retained by the renderer.

4. **The kernel sits behind our own interface.** UI and viewport code communicate with an asynchronous `KernelClient` protocol contract (`KernelRequest` and `KernelResult`, through `KernelClientProtocol`), never directly with the underlying geometry engine (Euclid or OpenCASCADE). The geometry engine can be swapped or augmented without affecting viewport or UI code.

5. **Direct Metal 4 graphics pipeline.** The application renders natively through Apple's Metal 4 API (`MTL4CommandQueue`, argument tables, residency sets) via MetalKit, with Metal Shading Language (MSL) shaders compiled at build time. Metal 4 requires Apple silicon, so Intel Macs are unsupported. Offscreen render passes generate image snapshots for visual agent verification.

6. **Meshes cross boundaries as shared memory and live in shared-storage buffers.** `MeshPayload` carries one page-aligned `MAP_SHARED` region (`MeshStorage`), which crosses the kernel XPC boundary as `xpc_shmem` without a copy. The renderer copies each component once into a Metal buffer allocated with `.storageModeShared`, which Apple Silicon unified memory makes visible to both CPU and GPU.

7. **Thread-safe geometry execution.** Swift 6 language mode and actor isolation for `KernelClient`, `LocalKernelEngine`, and `XPCKernelEngine` guard kernel state. `DocumentModel` and `CADToolRegistry` are `@MainActor`, so agent tool calls mutate the document on the main actor. Seventeen types are `@unchecked Sendable` today (DSN-1eb23904). High-frequency parameter mutations are conflated with a 60 ms debounce window, and superseded results are dropped by job ID.

8. **Navigation and editing never share a gesture.** Multi-touch gestures drive camera navigation (pan, orbit, zoom), single-pointer input drives selection and manipulation, and the Apple Pencil provides a dedicated precision create-and-edit channel. The gesture arbiter locks mode on the first movement and holds it until release.

9. **Precision comes from snapping and typed values, not steady fingers.** Translation and dimension edits are guided by snapping candidates evaluated in strict priority order (Vertex > Edge > Grid) and exact numeric entries in the Inspector, rather than requiring unassisted manual positioning.

---

## Enforcement Matrix

Table 1 states what each invariant relies on today. "Tested" means a test in `macos/Tests/MadeCoreTests` exercises the rule. `MadeAppTests` cover individual SwiftUI views and `WorkspaceModel`, and the package has no UI (XCUITest) test target.

Table 1. Enforcement status per invariant, as of 2026-10-17.

| # | Status | Enforced By |
| - | ------ | ----------- |
| 1 | Partly tested | `KernelClient` and the engines are actors, and `KernelClientTests` exercise them. In the bundled app, geometry runs in the kernel XPC service; `KernelXPCTests` cover the crash, retry, breaker, and terminate paths against an in-process listener. `ShapeEvaluationTests.testEvaluationNeverRunsOnMainThread` asserts that DSL evaluation started on the main actor runs CSG off the main thread. No test covers the other request paths. |
| 2 | Tested on a GPU | `MTKView.isPaused = true` and `enableSetNeedsDisplay = true` in `CADMetalViewRepresentable.swift`. `ViewportCoordinatorTests.testRenderCountStaysFlatAtIdle` asserts a flat `renderCount` at idle. Layer 4 XCUITest `ViewportSelectionUITests` verifies idle `renderCount` stability in the shipped application under `make test-viewport` (#551). The viewport records the `model`, `camera`, and `interaction` invalidation reasons. |
| 3 | Tested | `LayeringTests` fails `swift test` when a file in `MadeCore/Viewport` references a type declared at top level in `MadeCore/Agent` or `MadeCore/Scene`. The forbidden names are read from those sources, so a new type is covered without a test edit. `Transform` lives in `MadeCore/Kernel`. The `SolidMeshSink` and `SnapshotProvider` conformances of `MetalRenderer` are declared in `Scene/MetalRenderer+SolidMeshSink.swift` and `Agent/MetalRenderer+SnapshotProvider.swift`. `MadeCore/Scene` holds the `@Observable DocumentModel`, and `MadeCore/Viewport` holds the Metal buffers. |
| 4 | Partly tested | `KernelClientProtocol` and the `Codable` wire types in `MadeCore/Kernel/Types.swift`. `KernelXPCTests.testRequestRoundTripsEveryCase` round-trips every request through the XPC wire encoding, which carries no Euclid type. `MadeApp/WorkspaceModel.swift` constructs `KernelClient.makeDefault()`. `LayeringTests.scriptingReferencesNoKernelInternals` fails `swift test` when a file in `MadeCore/Scripting` names Euclid, `EuclidEngine`, `Mesh`, `LocalKernelEngine`, `ShapeEvaluator`, `OCCTSwift`, `OCCTEngine`, or `Shape`. No lint rule covers `Viewport`, `Scene`, or `Agent`. |
| 5 | Tested on a GPU | `MetalRendererGeometryTests` builds the Metal 4 renderer, loads the precompiled shaders, and checks an offscreen render pixel by pixel. The renderer tests skip on a device without Metal 4, such as the paravirtual GPU on hosted CI runners, and the git hooks fail on that skip. `ShaderLibraryTests` runs on any Metal device and checks the bundled shader library. The `--mcp-stdio` server serves snapshots through `HeadlessSnapshotProvider` (#89). |
| 6 | Partly tested | `MeshStorageTests` check page alignment and the `xpc_shmem` round trip, and `KernelXPCTests.testBoxRoundTripsThroughService` checks a mesh crossing the service boundary. `MetalRenderer.createMesh` copies each mapped component once with `makeBuffer(bytes:length:options:)` into a `.storageModeShared` buffer; `MetalRendererGeometryTests` renders the result. |
| 7 | Partly tested | `KernelClientTests` cover the actor, the debounce, conflation, the stale-debounce race, and dispose during an executing job. `DocumentModelTests` drive agent tool calls from detached tasks while the main actor reads the document, and run clean under `--sanitize=thread`. Seventeen types are `@unchecked Sendable` (DSN-1eb23904). |
| 8 | Partly tested | `GestureArbiterTests` has 13 tests. `CameraTests` covers the `PointerRouter` click-versus-drag threshold, scroll and magnify events, and pen routing, and `ViewportToolTests` covers tool routing. `CADMetalViewRepresentable` feeds mouse events to the router. |
| 9 | Partly tested | `SnappingTests` has 30 tests covering vertex over edge over grid precedence, tolerance, and grid rounding. `CADMetalViewRepresentable` calls `resolveSnapAtPointer` during drags. |

---

## The Tenth Convention (Unnumbered)

The **right-handed Z-up world** ([`orientation.md`](./orientation.md)) carries the same architectural weight as the numbered list: violating it causes viewport rendering and the geometry kernel to disagree on spatial coordinates. It remains unnumbered because invariant numbering is fixed.

---

## Related Documentation

- [`threading-model.md`](./threading-model.md): Invariants 1, 6, and 7
- [`rendering.md`](./rendering.md): Invariants 2 and 5
- [`kernel.md`](./kernel.md): Invariants 1, 4, 6, and 7
- [`input.md`](./input.md): Invariants 8 and 9
- [`state-and-errors.md`](./state-and-errors.md): Invariant 3
