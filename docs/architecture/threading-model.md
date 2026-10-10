# Threading Model & Concurrency

The threading model in `made` is designed around **Swift 6 Strict Concurrency** (`-strict-concurrency=complete`), enforcing Invariant 1 (kernel off main thread) and Invariant 7 (thread-safe execution). It guarantees that UI interactions remain smooth at 120 Hz while intensive geometry computations execute safely in the background.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                      @MainActor                        │
│   • SwiftUI View Hierarchy (Inspector, Copilot)        │
│   • AppKit / UIKit Event RunLoop                       │
│   • GestureArbiter & PointerRouter                     │
│   • DocumentModel (@Observable)                        │
│   • MetalKit MTKView Command Encoding                  │
└──────────────────────────┬─────────────────────────────┘
                           │ await client.request(job)
┌──────────────────────────▼─────────────────────────────┐
│                 KernelClient (Actor)                   │
│   • Debounce Task Scheduling (60 ms)                   │
│   • Stale Job Cancellation                             │
│   • Background Geometry & CSG Booleans                 │
│   • Polygon Triangulation                              │
└──────────────────────────┬─────────────────────────────┘
                           │ MeshPayload (Sendable)
┌──────────────────────────▼─────────────────────────────┐
│             Apple Silicon Unified Memory               │
│   • MTLBuffer (.storageModeShared)                     │
│   • Zero-copy shared access between CPU & GPU          │
└────────────────────────────────────────────────────────┘
```

---

## Responsibilities by Domain

### 1. Main Thread (`@MainActor`)
The main thread owns all presentation and interaction state:
- **SwiftUI Views**: Renders UI components, inspector controls, and chat dialogs.
- **Input Routing**: Handles pointer move, drag, magnification, and Apple Pencil events. Mode decisions are locked synchronously before dispatching changes.
- **Document Mutations**: `@Observable class DocumentModel` updates object parameters and tracks selection.
- **Metal Command Encoding**: Encodes draw primitives into `MTLCommandBuffer` on demand when invalidated.

### 2. Geometry Background Actor (`KernelClient`)
All CAD math, boundary evaluations, and CSG booleans execute inside `KernelClient`:
- **Isolation Guarantee**: Swift 6 actor isolation ensures that kernel state (cache of active solids, pending jobs, Euclid meshes) cannot be accessed concurrently from outside the actor.
- **Async Interface**: The UI calls `await kernelClient.request(...)`, returning a Swift `Task` continuation that does not block the main thread.
- **Honest Cancellation**: If a user drags a parameter slider rapidly, intermediate jobs are cancelled. If a job is already in flight, its completion is checked against the active job table, dropping stale results before they reach the main thread.

### 3. Apple Silicon Unified Memory
Unlike traditional PC architectures where geometry must be serialized over a PCIe bus, Apple Silicon shares physical memory between CPU and GPU.
- `MeshPayload` creates an `MTLBuffer` using `MTLResourceStorageModeShared`.
- The CPU computes vertex coordinates and normals directly in shared memory.
- The GPU reads those exact memory addresses during vertex fetch, providing zero-copy performance without transferable array buffer serialization.

---

## Swift 6 Sendable Concurrency Contracts

All data structures crossing actor boundaries must conform to `Sendable`:
- **`KernelRequest` & `KernelResult`**: Pure enums carrying value types.
- **`MeshPayload`**: Immutable struct containing `[Float]` and `[UInt32]`.
- **`MetalMesh`**: Encapsulates `MTLBuffer` references marked `@unchecked Sendable` because Metal buffers are internally thread-safe for reading once command buffers are committed.

---

## Related Documentation

- [`invariants.md`](./invariants.md) — Invariants 1, 6, and 7
- [`kernel.md`](./kernel.md) — Debounce conflation and cancellation logic
- [`rendering.md`](./rendering.md) — Metal buffer management
