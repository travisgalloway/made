# Architectural Invariants

**This is the canonical list of design contracts for `made`.**

These invariants must hold at every phase. A violation is treated as a build break. If a task appears to require breaking one, stop and flag it rather than working around it.

> **The numbers are load-bearing.** Every one of the nine invariants is cited by number across the codebase — in comments, configuration, and unit tests. Phrasings include `invariant N`, `Invariant N`, `architecture invariant N`, and `invariants N and M`. **Never renumber.** Add any new invariants at the end.

---

## The Nine Invariants

1. **The kernel runs off the main thread.** No geometry generation or CSG boolean operation executes on the main UI thread. All kernel requests run within the `KernelClient` Swift Actor.

2. **Rendering is on-demand.** No continuous animation loop. The Metal renderer draws only when the camera moves, a solid changes, or an interaction is active. In MetalKit, this is enforced by configuring `MTKView.isPaused = true` and `enableSetNeedsDisplay = true`, requesting frames explicitly via `setNeedsDisplay()`.

3. **The viewport is imperative, not reactive.** SwiftUI reactive state drives UI panels and inspector forms only. Viewport mesh geometry and per-frame state never reside in SwiftUI `@State` that would re-evaluate on each frame. Metal buffers are retained in shared GPU memory.

4. **The kernel sits behind our own interface.** UI and viewport code communicate with an asynchronous `KernelClient` protocol contract (`KernelRequest` and `KernelResult`), never directly with the underlying geometry engine (Euclid or OpenCASCADE). The geometry engine can be swapped or augmented without affecting viewport or UI code.

5. **Direct Metal 3 graphics pipeline.** The application renders natively through Apple's Metal 3 API via MetalKit, utilizing compiled Metal Shading Language (MSL) pipelines. Offscreen render passes generate high-resolution image snapshots for visual agent verification.

6. **Meshes cross boundaries as zero-copy shared buffers.** Vertex and index arrays utilize Apple Silicon unified memory with `MTLResourceStorageModeShared`, enabling zero-copy shared memory access between CPU geometry computation and GPU rasterization.

7. **Thread-safe geometry execution.** Swift 6 strict concurrency and actor isolation prevent data races. High-frequency parameter mutations are conflated with a 60 ms debounce window, and superseded compute jobs are cancelled before tessellation.

8. **Navigation and editing never share a gesture.** Multi-touch gestures drive camera navigation (pan, orbit, zoom), single-pointer input drives selection and manipulation, and the Apple Pencil provides a dedicated precision create-and-edit channel. The gesture arbiter locks mode on the first movement threshold and holds it until release.

9. **Precision comes from snapping and typed values, not steady fingers.** Translation and dimension edits are guided by snapping candidates evaluated in strict priority order (Vertex > Edge > Grid) and exact numeric entries in the Inspector, rather than requiring unassisted manual positioning.

---

## Enforcement Matrix

| # | Status | Enforced By |
| - | ------ | ----------- |
| 1 | **Checked** | Swift 6 compiler actor isolation (`actor KernelClient`) and Swift Concurrency checking. Unit tests in `KernelClientTests`. |
| 2 | **Checked** | `RenderInstrumentation.shared.renderCount` verified in `MetalRenderer` unit tests and UI state assertions. `MTKView.isPaused` set to `true`. |
| 3 | **Checked** | Module separation: `MadeCore/Scene` defines `@Observable DocumentModel`, while `MadeCore/Viewport` maintains direct Metal device buffers without SwiftUI view dependencies. |
| 4 | **Checked** | `KernelClient` interface boundaries in `MadeCore/Kernel/Types.swift`. Viewport and UI targets import only `KernelClient` wire types. |
| 5 | **Checked** | Metal 3 pipeline compilation tests in `MetalRendererTests`. Device verification via `MTLCreateSystemDefaultDevice()`. |
| 6 | **Checked** | `MeshPayload` layout matches SIMD vector alignments and initializes `MTLBuffer` with `.storageModeShared`. |
| 7 | **Checked** | Unit tests in `KernelClientTests` asserting 60 ms conflation, honest cancellation of superseded jobs, and actor isolation. |
| 8 | **Checked** | Unit tests in `GestureArbiterTests` verifying mode locking on drag movement and pointer type isolation. |
| 9 | **Checked** | Unit tests in `SnappingTests` covering vertex > edge > grid precedence order and tolerance clamping. |

---

## The Tenth Convention (Unnumbered)

The **right-handed Z-up world** ([`orientation.md`](./orientation.md)) carries the same architectural weight as the numbered list: violating it causes viewport rendering and the geometry kernel to disagree on spatial coordinates. It remains unnumbered because invariant numbering is fixed.

---

## Related Documentation

- [`threading-model.md`](./threading-model.md) — Invariants 1, 6, and 7
- [`rendering.md`](./rendering.md) — Invariants 2 and 5
- [`kernel.md`](./kernel.md) — Invariants 1, 4, 6, and 7
- [`input.md`](./input.md) — Invariants 8 and 9
- [`state-and-errors.md`](./state-and-errors.md) — Invariant 3
