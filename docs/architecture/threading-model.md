# Threading Model & Concurrency

The threading model in `made` is built on the Swift 6 language mode (`swift-tools-version: 6.0` in `Package.swift`). It upholds Invariant 1 (kernel off main thread) and Invariant 7 (thread-safe execution). `KernelClient` is the only actor with compiler-enforced isolation. The other shared types opt out of checking, as described under Current Isolation.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│        Main thread (SwiftUI and MetalKit callbacks)    │
│   • SwiftUI View Hierarchy (Inspector, Copilot)        │
│   • AppKit Event RunLoop                               │
│   • GestureArbiter & PointerRouter (no caller yet)     │
│   • DocumentModel (@Observable, not @MainActor)        │
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
│   • Arrays copied in once per upload                   │
└────────────────────────────────────────────────────────┘
```

---

## Responsibilities by Domain

### 1. Main Thread
`@MainActor` appears only on the two `Coordinator` classes in `CADMetalViewRepresentable.swift`, plus `MainActor.run` calls in `ContentView.swift` and `InAppAgentController.swift`. `DocumentModel`, `GestureArbiter`, and `PointerRouter` are `final class ... @unchecked Sendable` with no actor isolation. Moving them onto `@MainActor` is tracked in #91. The main thread owns these responsibilities:
- **SwiftUI Views**: Renders UI components, inspector controls, and chat dialogs.
- **Input Routing (planned, #87)**: `PointerRouter` and `GestureArbiter` decide the gesture mode synchronously. The viewport does not send them events today.
- **Document Mutations**: `@Observable class DocumentModel` updates object parameters. Agent tool calls also mutate it from the stdio task, off the main thread (#91).
- **Metal Command Encoding**: Encodes draw primitives into `MTLCommandBuffer` on demand when invalidated.

### 2. Geometry Background Actor (`KernelClient`)
All CAD math, boundary evaluations, and CSG booleans execute inside `KernelClient`:
- **Isolation Guarantee**: Swift actor isolation prevents concurrent access to kernel state (cache of solids, pending jobs, Euclid meshes) from outside the actor.
- **Async Interface**: The UI calls `await kernelClient.request(...)`, which suspends the caller without blocking the main thread.
- **Cancellation**: A newer request for the same solid replaces the pending one, which resumes with `.cancelled`. The engine call runs synchronously inside the actor, so an in-flight job cannot be interrupted. The conflation test currently fails (#90).

### 3. Apple Silicon Unified Memory
Apple Silicon shares physical memory between CPU and GPU.
- `MeshPayload` holds plain `[Float]` and `[UInt32]` arrays. It does not own a Metal buffer.
- `MetalRenderer.createMesh` calls `makeBuffer(bytes:length:options: .storageModeShared)` three times. Each call copies an array into a shared-storage buffer.
- The GPU then reads those buffers during vertex fetch without a further transfer.

---

## Swift 6 Sendable Concurrency Contracts

Data structures crossing actor boundaries conform to `Sendable`:
- **`KernelRequest` & `KernelResult`**: Pure enums carrying value types.
- **`MeshPayload`**: Immutable struct containing `[Float]` and `[UInt32]`.
- **`MetalMesh`**: Encapsulates `MTLBuffer` references and is marked `@unchecked Sendable`.

### Current Isolation
Nine types opt out of compiler checking with `@unchecked Sendable`: `DocumentModel`, `GestureArbiter`, `PointerRouter`, `CADToolRegistry`, `MCPServer`, `InAppAgentController`, `RenderInstrumentation`, `MetalRenderer`, and `MetalMesh`. Each holds mutable state without a lock or actor. Removing the opt-outs is tracked in #91.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 1, 6, and 7
- [`kernel.md`](./kernel.md): Debounce conflation and cancellation logic
- [`rendering.md`](./rendering.md): Metal buffer management
