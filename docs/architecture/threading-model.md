# Threading Model & Concurrency

The threading model in `made` is built on the Swift 6 language mode (`swift-tools-version: 6.2` in `Package.swift`). It upholds Invariant 1 (kernel off main thread) and Invariant 7 (thread-safe execution). `KernelClient` is the only actor with compiler-enforced isolation. The other shared types opt out of checking, as described under Current Isolation.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│        Main thread (SwiftUI and MetalKit callbacks)    │
│   • SwiftUI View Hierarchy (Navigator, Inspector, Console)   │
│   • AppKit Event RunLoop                               │
│   • GestureArbiter & PointerRouter                     │
│   • DocumentModel (@Observable, @MainActor)            │
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
`@MainActor` appears on `DocumentModel`, `CADToolRegistry`, and the two `Coordinator` classes in `CADMetalViewRepresentable.swift`, plus `Task { @MainActor }` hops in `WorkspaceModel.swift` (a `@MainActor` class) and `MainActor.run` calls in `InAppAgentController.swift`. `GestureArbiter` and `PointerRouter` are `final class ... @unchecked Sendable` with no actor isolation. Moving them onto `@MainActor` belongs to DSN-1eb23904. The main thread owns these responsibilities:
- **SwiftUI Views**: Renders UI components, inspector controls, and chat dialogs.
- **Input Routing**: `PointerRouter` and `GestureArbiter` decide the gesture mode synchronously. The viewport coordinator sends them mouse and trackpad events.
- **Document Mutations**: `@Observable class DocumentModel` updates object parameters. Agent tool calls from the stdio task and the TCP listener reach it through the `@MainActor` `CADToolRegistry`, so each call hops to the main actor and back.
- **Metal Command Encoding**: Encodes draw primitives into `MTLCommandBuffer` on demand when invalidated.

### 2. Geometry Background Actor (`KernelClient`)
All CAD math, boundary evaluations, and CSG booleans execute inside `KernelClient`:
- **Isolation Guarantee**: Swift actor isolation prevents concurrent access to kernel state (cache of solids, pending jobs, Euclid meshes) from outside the actor.
- **Async Interface**: The UI calls `await kernelClient.request(...)`, which suspends the caller without blocking the main thread.
- **Cancellation**: A newer request for the same solid replaces the pending one, which resumes with `.cancelled`. The engine call runs synchronously inside the actor, so an in-flight job cannot be interrupted.

### 3. Apple Silicon Unified Memory
Apple Silicon shares physical memory between CPU and GPU.
- `MeshPayload` holds plain `[Float]` and `[UInt32]` arrays. It does not own a Metal buffer.
- `MetalRenderer.createMesh` calls `makeBuffer(bytes:length:options: .storageModeShared)` three times. Each call copies an array into a shared-storage buffer.
- The GPU then reads those buffers during vertex fetch without a further transfer.

---

## Swift 6 Sendable Concurrency Contracts

Data structures crossing actor boundaries conform to `Sendable`:
- **`KernelRequest` & `KernelResult`**: Pure enums carrying value types.
- **`MeshPayload`**: Immutable struct over a `MeshStorage` shared-memory region. `MeshStorage` is `@unchecked Sendable` because its region is written only inside `init`.
- **`MetalMesh`**: Encapsulates `MTLBuffer` references and is marked `@unchecked Sendable`.

### Current Isolation
Seven types opt out of compiler checking with `@unchecked Sendable`: `GestureArbiter`, `PointerRouter`, `MCPServer`, `InAppAgentController`, `RenderInstrumentation`, `MetalRenderer`, and `MetalMesh`. Each holds mutable state without a lock or actor. Removing the opt-outs belongs to DSN-1eb23904.

---

### App and Kernel Service Processes
The bundled app runs geometry in the `MadeKernelService` XPC service (#245). `KernelClient` stays an actor in the app and keeps the debounce, conflation, and job bookkeeping. `XPCKernelEngine`, a second actor, owns the `XPCSession`, sends one job at a time, and resumes callers from XPC reply handlers through `Task` hops onto the actor. In the service, `KernelServiceHandler` runs each session's messages on an ordered `AsyncStream` consumer, so the XPC session queue never blocks on geometry. A crash in the service ends that process only. The app relaunches it and regenerates from the document, as `kernel.md` describes.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 1, 6, and 7
- [`kernel.md`](./kernel.md): Debounce conflation and cancellation logic
- [`rendering.md`](./rendering.md): Metal buffer management
