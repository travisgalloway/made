# Viewport Rendering Architecture

The rendering engine in `made` is built on Apple's **Metal 3** framework and **MetalKit** (`MTKView`), optimized for Apple Silicon unified memory architecture. It enforces Invariant 2 (on-demand rendering), Invariant 3 (imperative viewport state), and Invariant 5 (direct Metal 3 pipeline).

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
Every render call increments telemetry tracked in [`RenderInstrumentation`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Viewport/RenderLoop.swift#L11):
- `renderCount`: Total frames submitted to the GPU.
- `drawCalls`: Number of distinct mesh draw primitives issued in the last pass.
- `lastReason`: The invalidation trigger responsible for the frame.

This telemetry is exposed in the SwiftUI HUD in the viewport corner and is verified by automated tests to ensure `renderCount` remains flat at idle.

---

## Metal 3 Graphics Pipeline

The rendering pipeline is implemented in [`MetalRenderer.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Viewport/MetalRenderer.swift):

```
┌────────────────────────────────────────────────────────┐
│                   DocumentModel                        │
│         (N Solids: Box, Cylinder, CSG Mesh)            │
└──────────────────────────┬─────────────────────────────┘
                           │ MeshPayload updates
┌──────────────────────────▼─────────────────────────────┐
│                 MetalRenderer                          │
│   • MTLDevice (Apple Silicon Default)                  │
│   • MTLCommandQueue                                    │
│   • MTLRenderPipelineState (MSL Shaders)               │
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

### Unified Shared Memory (Zero-Copy)
Apple Silicon integrates CPU and GPU memory on a single high-bandwidth bus. `made` allocates vertex and index buffers with `MTLResourceOptions.storageModeShared`:

```swift
let vertexBuffer = device.makeBuffer(
    bytes: payload.positions,
    length: payload.positions.count * MemoryLayout<Float>.size,
    options: .storageModeShared
)
```

No CPU-to-GPU data copies occur across PCIe buses. The geometry engine writes vertices directly into shared buffers that the Metal rasterizer consumes.

### Shading & Lighting Model
Shaders are written in Metal Shading Language (MSL) in [`MetalShaders.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Viewport/MetalShaders.swift):
- **Vertex Shader**: Transforms vertices by `modelMatrix`, `viewMatrix`, and `projectionMatrix`, computing eye-space normals.
- **Fragment Shader**: Evaluates Lambertian diffuse reflection combined with Blinn-Phong specular highlights against a directional key light and ambient fill.

---

## Multimodal Visual Verification Loop

For autonomous AI agents and local copilot workflows, numerical CAD parameters are insufficient to verify aesthetics, clearance, and topology. Agents require visual feedback.

`MetalRenderer` implements the [`SnapshotProvider`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Agent/CADTools.swift#L4) protocol:

```swift
public protocol SnapshotProvider: Sendable {
    func captureSnapshotPngBase64() async -> String?
}
```

### Execution Flow
1. An agent calls the `cad_capture_snapshot` MCP tool.
2. `MetalRenderer` creates an offscreen `MTLTexture` (standard 800×600 RGBA8).
3. A non-blocking render pass draws the scene into the texture using the active camera orientation.
4. When the command buffer completes asynchronously, texture bytes are extracted into a `CGImage` and compressed to a PNG data stream using Apple's `ImageIO` framework.
5. The resulting base64 data URI is returned in the MCP JSON-RPC response, allowing multimodal LLMs (e.g., Claude 3.5 Sonnet, Gemini Pro Vision) to inspect the 3D model visually and iterate.

---

## Related Documentation

- [`invariants.md`](./invariants.md) — Invariants 2, 3, and 5
- [`orientation.md`](./orientation.md) — Right-handed Z-up standard in Metal NDC
- [`agent-api.md`](./agent-api.md) — Multimodal visual verification toolchain
