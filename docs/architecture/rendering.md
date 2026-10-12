# Viewport Rendering Architecture

The rendering engine in `made` is built on Apple's **Metal 4** API and **MetalKit** (`MTKView`), for Apple silicon unified memory. It enforces Invariant 2 (on-demand rendering), Invariant 3 (imperative viewport state), and Invariant 5 (direct Metal 4 pipeline).

---

## On-Demand Invalidation Loop

CAD applications operate on precision models rather than game-loop animations. Idling at 60–120 FPS drains battery and consumes thermal budget unnecessarily.

`made` renders strictly on demand:

```swift
view.isPaused = true
view.enableSetNeedsDisplay = true
```

A frame is submitted to the GPU only when an explicit invalidation signal is raised:

```swift
public enum InvalidateReason: String, Sendable {
    case camera       // Camera orbit, pan, or zoom
    case resize       // Viewport window resizing
    case model        // Parametric dimension or transform change
    case interaction  // Active gesture or direct manipulation drag
}
```

### Render Instrumentation & Observability
Every render call increments telemetry tracked in [`RenderInstrumentation`](../../macos/Sources/MadeCore/Viewport/RenderLoop.swift#L11):
- `renderCount`: Total frames submitted to the GPU.
- `drawCalls`: Number of distinct mesh draw primitives issued in the last pass.
- `lastReason`: The invalidation trigger responsible for the frame.

This telemetry is exposed in the SwiftUI HUD in the viewport corner. No automated test reads `renderCount`, so the flat-at-idle behavior is not yet tested. Only the `model` reason is recorded today (#94).

---

## Metal 4 Graphics Pipeline

The rendering pipeline is implemented in [`MetalRenderer.swift`](../../macos/Sources/MadeCore/Viewport/MetalRenderer.swift):

```
┌────────────────────────────────────────────────────────┐
│                   DocumentModel                        │
│         (N Solids: Box, Cylinder, CSG Mesh)            │
└──────────────────────────┬─────────────────────────────┘
                           │ MeshPayload updates
┌──────────────────────────▼─────────────────────────────┐
│                 MetalRenderer                          │
│   • MTLDevice (Apple Silicon Default)                  │
│   • MTL4CommandQueue + 3 MTL4CommandAllocators         │
│   • MTL4ArgumentTable, MTLResidencySet, UniformArena   │
│   • MTL4Compiler pipelines from default.metallib       │
│   • MTLDepthStencilState (Depth testing enabled)       │
└──────────────┬──────────────────────────┬──────────────┘
               │                          │
       Screen Render Pass        Offscreen Snapshot Pass
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│       MTKView Drawable     │ │   Offscreen MTLTexture  │
│      (Interactive 3D)      │ │   (800x600 Snapshot)    │
└────────────────────────────┘ └──────────┬──────────────┘
                                          │ Async readback
                               ┌──────────▼──────────────┐
                               │ ImageIO Base64 PNG      │
                               │ (Multimodal Agent Loop) │
                               └─────────────────────────┘
```

### Metal 4 Frame Structure
- Three frames are in flight. Each frame owns an `MTL4CommandAllocator` and a `UniformArena`, and an `MTLSharedEvent` keeps the CPU from reusing a slot the GPU still reads.
- Metal 4 has no `setVertexBytes`. Uniforms are copied into the frame's `UniformArena`, and their GPU addresses go into an `MTL4ArgumentTable`, as do the vertex buffers, the label texture, and the sampler.
- Every buffer and texture the renderer binds is in one `MTLResidencySet` on the queue, and the residency set is rebuilt when `meshes` changes. The `CAMetalLayer` residency set covers the drawables.
- Pipelines are built by an `MTL4Compiler` from the bundle's `default.metallib`, which SwiftPM compiles from `Viewport/Shaders.metal`.
- `OSSignposter` marks each frame (`Renderer` category) and each kernel job (`Kernel` category) for Instruments.

### Shared-Storage Buffers
Apple Silicon integrates CPU and GPU memory on a single bus. `made` allocates vertex, normal, and index buffers with `MTLResourceOptions.storageModeShared`:

```swift
let vertexBuffer = device.makeBuffer(
    bytes: payload.positions,
    length: payload.positions.count * MemoryLayout<Float>.size,
    options: .storageModeShared
)
```

`makeBuffer(bytes:length:options:)` copies the `MeshPayload` arrays into the buffer once per upload (`MetalRenderer.createMesh`). The buffers are then visible to the GPU without a second transfer. The pipeline is not zero-copy end to end.

Every position and normal buffer is tightly packed at 12 bytes per vertex. The vertex shaders therefore read them as `packed_float3`, because MSL `float3` has a 16-byte stride. Euclid emits counter-clockwise triangles, so the solid pass sets `setFrontFacing(.counterClockwise)` before it enables back-face culling. `MetalRendererGeometryTests` renders a box offscreen and checks both rules against its pixels.

### Shading & Lighting Model
Shaders are written in Metal Shading Language (MSL) in [`MetalShaders.swift`](../../macos/Sources/MadeCore/Viewport/MetalShaders.swift):
- **Vertex Shader**: Transforms vertices by `modelMatrix`, `viewMatrix`, and `projectionMatrix`, and transforms normals to world space with `normalMatrix`.
- **Fragment Shader**: Evaluates Lambertian diffuse shading from two directional lights (key weight 0.7, fill weight 0.3) plus a 0.25 ambient term. It has no specular term. Blinn-Phong highlights are not implemented.

The viewport draws a ground grid on Z = 0 (#102) with 10 mm pitch matching snapToGrid, and a labelled XYZ axes indicator at the origin (#103).

---

## Multimodal Visual Verification Loop

For autonomous AI agents and local copilot workflows, numerical CAD parameters are insufficient to verify aesthetics, clearance, and topology. Agents require visual feedback.

`MetalRenderer` implements the [`SnapshotProvider`](../../macos/Sources/MadeCore/Agent/CADTools.swift#L4) protocol, which is declared in `Agent/CADTools.swift`, not in the renderer file:

```swift
public protocol SnapshotProvider: AnyObject, Sendable {
    func captureSnapshotPngBase64() async -> String?
}
```

The GUI wires the renderer into the tool registry (`ContentView.swift`). The `--mcp-stdio` mode builds its registry without a provider, so `cad_capture_snapshot` returns an error there (#89).

### Execution Flow
1. An agent calls the `cad_capture_snapshot` MCP tool.
2. `MetalRenderer` creates an offscreen `MTLTexture` (standard 800×600 RGBA8).
3. A non-blocking render pass draws the scene into the texture using the active camera orientation.
4. When the command buffer completes asynchronously, texture bytes are extracted into a `CGImage` and compressed to a PNG data stream using Apple's `ImageIO` framework.
5. The tool returns the raw base64 PNG (no `data:` prefix) as MCP `image` content with MIME type `image/png`, so a multimodal model can inspect the 3D model.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 2, 3, and 5
- [`orientation.md`](./orientation.md): Right-handed Z-up standard in Metal NDC
- [`agent-api.md`](./agent-api.md): Multimodal visual verification toolchain
