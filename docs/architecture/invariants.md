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

5. **Direct Metal 3 graphics pipeline.** The application renders natively through Apple's Metal 3 API via MetalKit, utilizing compiled Metal Shading Language (MSL) pipelines. Offscreen render passes generate high-resolution image snapshots for visual agent verification.

6. **Meshes cross boundaries as typed arrays and live in shared-storage buffers.** `MeshPayload` carries `[Float]` and `[UInt32]` arrays. The renderer copies them into Metal buffers allocated with `.storageModeShared`, which Apple Silicon unified memory makes visible to both CPU and GPU.

7. **Thread-safe geometry execution.** Swift 6 language mode and actor isolation for `KernelClient` guard kernel state. Other types are `@unchecked Sendable` today (#91). High-frequency parameter mutations are conflated with a 60 ms debounce window, and superseded results are dropped by job ID.

8. **Navigation and editing never share a gesture.** Multi-touch gestures drive camera navigation (pan, orbit, zoom), single-pointer input drives selection and manipulation, and the Apple Pencil provides a dedicated precision create-and-edit channel. The gesture arbiter locks mode on the first movement and holds it until release.

9. **Precision comes from snapping and typed values, not steady fingers.** Translation and dimension edits are guided by snapping candidates evaluated in strict priority order (Vertex > Edge > Grid) and exact numeric entries in the Inspector, rather than requiring unassisted manual positioning.

---

## Enforcement Matrix

Table 1 states what each invariant relies on today. "Tested" means a test in `macos/Tests/MadeCoreTests` exercises the rule. No test target covers `MetalRenderer`, `RenderInstrumentation`, or the SwiftUI views, and the package has no UI test target.

Table 1. Enforcement status per invariant, as of 2026-10-10.

| # | Status | Enforced By |
| - | ------ | ----------- |
| 1 | Partly tested | `KernelClient` is an `actor`, and `KernelClientTests` exercise it. No test asserts that the main thread stays free. |
| 2 | Not tested | `MTKView.isPaused = true` and `enableSetNeedsDisplay = true` in `CADMetalViewRepresentable.swift`. Nothing in `macos/Tests` references `renderCount`, so a flat-at-idle test does not exist. Only the `model` invalidation reason is recorded today (#94). |
| 3 | Not tested | Module separation only: `MadeCore/Scene` holds the `@Observable DocumentModel`, and `MadeCore/Viewport` holds the Metal buffers. |
| 4 | Convention only | `KernelClientProtocol` and the wire types in `MadeCore/Kernel/Types.swift`. `MadeApp/ContentView.swift` constructs `KernelClient` and `MetalRenderer` directly. No lint rule or test enforces the boundary. |
| 5 | Not tested | The renderer uses Metal through `MetalKit`. No test creates a Metal device or compiles the shaders. The offscreen snapshot works only in the GUI; the headless server has no provider (#89). |
| 6 | Not tested | `MetalRenderer.createMesh` allocates three `.storageModeShared` buffers with `makeBuffer(bytes:length:options:)`. That call copies the `[Float]` and `[UInt32]` arrays once per upload. |
| 7 | Partly tested | `KernelClientTests` cover the actor, the debounce, conflation, and the stale-debounce race. Several types are `@unchecked Sendable` (#91). |
| 8 | Partly tested | `GestureArbiterTests` has three tests: single-pointer drag, two-pointer drag, and a pure tap. `PointerRouter` has no test. Nothing feeds pointer events to the router in the viewport (#87). |
| 9 | Partly tested | `SnappingTests` has four tests for vertex over edge over grid precedence, tolerance, and grid rounding. The snapping module has no caller in `MadeApp` or the viewport (#88). |

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
