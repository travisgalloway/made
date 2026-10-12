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

6. **Meshes cross boundaries as typed arrays and live in shared-storage buffers.** `MeshPayload` carries `[Float]` and `[UInt32]` arrays. The renderer copies them into Metal buffers allocated with `.storageModeShared`, which Apple Silicon unified memory makes visible to both CPU and GPU.

7. **Thread-safe geometry execution.** Swift 6 language mode and actor isolation for `KernelClient` guard kernel state. Other types are `@unchecked Sendable` today (#91). High-frequency parameter mutations are conflated with a 60 ms debounce window, and superseded results are dropped by job ID.

8. **Navigation and editing never share a gesture.** Multi-touch gestures drive camera navigation (pan, orbit, zoom), single-pointer input drives selection and manipulation, and the Apple Pencil provides a dedicated precision create-and-edit channel. The gesture arbiter locks mode on the first movement and holds it until release.

9. **Precision comes from snapping and typed values, not steady fingers.** Translation and dimension edits are guided by snapping candidates evaluated in strict priority order (Vertex > Edge > Grid) and exact numeric entries in the Inspector, rather than requiring unassisted manual positioning.

---

## Enforcement Matrix

Table 1 states what each invariant relies on today. "Tested" means a test in `macos/Tests/MadeCoreTests` exercises the rule. No test covers the SwiftUI views, and the package has no UI test target.

Table 1. Enforcement status per invariant, as of 2026-10-11.

| # | Status | Enforced By |
| - | ------ | ----------- |
| 1 | Partly tested | `KernelClient` is an `actor`, and `KernelClientTests` exercise it. No test asserts that the main thread stays free. |
| 2 | Partly tested | `MTKView.isPaused = true` and `enableSetNeedsDisplay = true` in `CADMetalViewRepresentable.swift`. `ViewportCoordinatorTests.testRenderCountStaysFlatAtIdle` asserts a flat `renderCount` at idle. The viewport records the `model`, `camera`, and `interaction` invalidation reasons. |
| 3 | Not tested | Module separation only: `MadeCore/Scene` holds the `@Observable DocumentModel`, and `MadeCore/Viewport` holds the Metal buffers. |
| 4 | Convention only | `KernelClientProtocol` and the wire types in `MadeCore/Kernel/Types.swift`. `MadeApp/WorkspaceModel.swift` constructs `KernelClient` and holds the `MetalRenderer` through the viewport manager. No lint rule or test enforces the boundary. |
| 5 | Tested on a GPU | `MetalRendererGeometryTests` builds the Metal 4 renderer, loads the precompiled shaders, and checks an offscreen render pixel by pixel. The renderer tests skip on a device without Metal 4, such as the paravirtual GPU on hosted CI runners, and the git hooks fail on that skip. `ShaderLibraryTests` runs on any Metal device and checks the bundled shader library. The headless server has no snapshot provider (#89). |
| 6 | Not tested | `MetalRenderer.createMesh` allocates three `.storageModeShared` buffers with `makeBuffer(bytes:length:options:)`. That call copies the `[Float]` and `[UInt32]` arrays once per upload. |
| 7 | Partly tested | `KernelClientTests` cover the actor, the debounce, conflation, and the stale-debounce race. Several types are `@unchecked Sendable` (#91). |
| 8 | Partly tested | `GestureArbiterTests` has seven tests. `CameraTests` covers the `PointerRouter` click-versus-drag threshold, scroll and magnify events, and pen routing, and `ViewportToolTests` covers tool routing. `CADMetalViewRepresentable` feeds mouse events to the router. |
| 9 | Partly tested | `SnappingTests` has 17 tests covering vertex over edge over grid precedence, tolerance, and grid rounding. `CADMetalViewRepresentable` calls `resolveSnapAtPointer` during drags. |

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
