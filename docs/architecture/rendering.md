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

This telemetry is exposed in the viewport status bar (`ViewportStatusBar`) under the viewport. `ViewportCoordinatorTests.testRenderCountStaysFlatAtIdle` reads `renderCount` to check the flat-at-idle behavior. The viewport records the `model`, `camera`, and `interaction` reasons.

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
Shaders are written in Metal Shading Language (MSL) in [`Shaders.metal`](../../macos/Sources/MadeCore/Viewport/Shaders.metal):
- **Vertex Shader**: Transforms vertices by `modelMatrix`, `viewMatrix`, and `projectionMatrix`, and transforms normals to world space with `normalMatrix`.
- **Fragment Shader**: Evaluates Lambertian diffuse shading from two directional lights (key weight 0.7, fill weight 0.3) plus a 0.25 ambient term. It has no specular term. Blinn-Phong highlights are not implemented.

The viewport draws a ground grid on Z = 0 (#102) with 10 mm pitch matching snapToGrid, and a labelled XYZ axes indicator at the origin (#103).

### Camera & Large-Coordinate Precision
`Camera` in `Camera.swift` holds a position, a target, distance and pitch limits, projection mode (`CameraProjection`: `.perspective` or `.orthographic`), and `orthographicScale`. It provides orbit, pan, and zoom operations, plus view presets (perspective, top, front, right, isometric). Users switch projections via the segmented picker in the viewport header (#128). In perspective mode, zooming adjusts camera distance along the line of sight; in orthographic mode, zooming scales `orthographicScale` (adjusting view frustum extents `halfH` and `halfW`) without moving the eye position or target. `CameraFraming.swift` computes `SceneBounds` and frames the camera on the scene. `ViewportTool` (select, orbit, pan, zoom) chooses what a drag does. Camera input and projection switches invalidate the viewport with the `camera` reason.

**Dual-Precision CPU Camera Math & Camera-Relative 32-bit Float Shaders:**
Industrial CAD models span millimeter features up to multi-meter assemblies. Evaluating 3D transformations purely in 32-bit floating-point coordinates causes severe precision degradation, z-fighting, and visible polygon jitter during close-up inspection of distant geometry:
1. **64-bit CPU Precision:** All camera world positions, look-at targets, view orbit/pan accumulators, and scene bounding box calculations are computed in double precision (`Double`, `simd_double4x4`).
2. **Camera-Relative 32-bit GPU Upload:** Prior to uploading matrices to the GPU argument table, model and view transformations are converted to camera-relative 32-bit floats (`Float`, `simd_float4x4`):
   $$\mathbf{x}_{\text{eye}} = \mathbf{V}_{\text{rel}} \cdot (\mathbf{x}_{\text{world}} - \mathbf{c}_{\text{camera}})$$
   By centering coordinates about the camera eye before single-precision truncation, 32-bit Metal vertex shaders maintain full 24-bit mantissa precision directly within the local view frustum, completely eliminating floating-point cancellation artifacts and z-buffer flutter.

---

## Transparency & Order-Independent Transparency (WBOIT, #391)

Mechanical CAD assemblies routinely exhibit overlapping translucent geometry: thin-wall transparent casings, fluid flow cavities, phantom reference geometry (ADR-D3), sketch planes, and ghosted downstream features. Standard alpha blending requires sorting thousands of transparent triangles back-to-front every frame on the CPU—a process that fails on intersecting or cyclic meshes and severely degrades frame rates.

`made` implements **McGuire & Bavoil Weighted Blended Order-Independent Transparency (WBOIT)** (#391):

1. **Accumulation Pass:** Transparent geometry is rendered after the opaque geometry pass with depth testing enabled but depth writes disabled (`MTLDepthWriteMaskZero`). The fragment shader outputs to two offscreen render targets simultaneously:
   - **Accumulation Texture (`RGBA16Float`):** Accumulates weighted color:
     $$\mathbf{C}_{\text{accum}} = \sum_{i} \mathbf{C}_i \cdot \alpha_i \cdot w(z_i, \alpha_i)$$
     using McGuire's depth weighting function:
     $$w(z, \alpha) = \alpha \cdot \max\left(10^{-2}, \min\left(3 \cdot 10^3, \frac{10}{10^{-5} + (|z| / 200.0)^3}\right)\right)$$
   - **Revealage Texture (`R8Unorm`):** Accumulates the multiplicative transmittance product using `MTLBlendOperationAdd` with `destinationAlpha * (1 - sourceAlpha)`:
     $$R = \prod_{i} (1 - \alpha_i)$$
2. **Compositing Pass:** A full-screen post-processing quad blends the accumulated transparent colors over the opaque framebuffer:
   $$\mathbf{C}_{\text{final}} = \frac{\mathbf{C}_{\text{accum}}}{\max(1.0 - R, 10^{-4})} \cdot (1 - R) + \mathbf{C}_{\text{opaque}} \cdot R$$
This produces artifact-free, order-independent transparency for overlapping surfaces at zero CPU sorting cost.

---

## CAE Simulation Visualization Pipeline (#192, #194, #195, #219)

The viewport rendering engine integrates specialized Metal 4 compute and vertex pipelines for interactive finite element (FEA) and computational fluid dynamics (CFD) post-processing:

### 1. Zero-Copy GPU Deformed-Shape Displacement
In structural FEA (#219), nodal displacement vector fields $\mathbf{u} = (u_x, u_y, u_z)$ are uploaded into `.storageModeShared` Metal buffers alongside original rest coordinates $\mathbf{x}_0$. 

Rather than regenerating deformed triangle meshes on the CPU, the vertex shader computes the deformed position on-the-fly:
$$\mathbf{x}_{\text{rendered}} = \mathbf{x}_0 + s \cdot \mathbf{u}$$
where $s$ is an interactive displacement scale factor bound to an Inspector slider. The user can scrub deformation magnification smoothly at 120 Hz with zero CPU overhead, zero memory allocations, and zero kernel dispatches.

### 2. Interactive Colorbar Legend Clamping & Iso-Volume Mode
Scalar nodal fields (e.g., von Mises equivalent stress, principal stresses, temperatures) are mapped to perceptually uniform colormaps (Turbo, Viridis) via a 1D texture lookup table.
- **Dynamic Clamping:** Dual-slider handles on the viewport colorbar legend dynamically update scalar thresholds $[v_{\text{min}}, v_{\text{max}}]$ in shader uniforms, rescaling the color gradient across specific stress ranges.
- **`Iso-Volume` Clipping Mode:** When enabled, the fragment shader executes `discard_fragment()` for any pixel where the interpolated scalar value falls outside $[v_{\text{min}}, v_{\text{max}}]$. This allows interactive "volume peeling" to visually isolate yielding structural regions or thermal hotspots deep within solid bodies without clipping planes.

### 3. Marching Tetrahedra Isosurfaces (#194)
For volumetric visualization of 3D scalar fields across tetrahedral meshes ($C3D4$, $C3D10$), `made` executes a GPU Marching Tetrahedra compute pass. Because tetrahedra have planar boundaries and unambiguous linear interpolation across edges, the algorithm extracts smooth, watertight 3D isosurfaces ($f(x, y, z) = c$) directly into GPU vertex buffers without the topological ambiguities and hole artifacts inherent to Marching Cubes.

### 4. RK4 GPU Streamlines (#195)
For CFD velocity vector fields $\mathbf{v}(\mathbf{x})$ (#186), a Metal compute kernel implements 4th-order Runge-Kutta (RK4) particle integration:
$$\mathbf{k}_1 = \mathbf{v}(\mathbf{x}_n), \quad \mathbf{k}_2 = \mathbf{v}\left(\mathbf{x}_n + \frac{\Delta t}{2}\mathbf{k}_1\right), \quad \mathbf{k}_3 = \mathbf{v}\left(\mathbf{x}_n + \frac{\Delta t}{2}\mathbf{k}_2\right), \quad \mathbf{k}_4 = \mathbf{v}(\mathbf{x}_n + \Delta t \mathbf{k}_3)$$
$$\mathbf{x}_{n+1} = \mathbf{x}_n + \frac{\Delta t}{6}(\mathbf{k}_1 + 2\mathbf{k}_2 + 2\mathbf{k}_3 + \mathbf{k}_4)$$
The compute pass advects thousands of particles simultaneously through the fluid domain, dynamically emitting 3D camera-facing ribbon geometry or line strips colored by local velocity magnitude, rendering animated flow streaklines at 60–120 FPS.

---

## Multimodal Visual Verification Loop

For autonomous AI agents and local copilot workflows, numerical CAD parameters are insufficient to verify aesthetics, clearance, and topology. Agents require visual feedback.

`MetalRenderer` implements the [`SnapshotProvider`](../../macos/Sources/MadeCore/Agent/CADTools.swift#L4) protocol, which is declared in `Agent/CADTools.swift`. The conformance is declared in [`Agent/MetalRenderer+SnapshotProvider.swift`](../../macos/Sources/MadeCore/Agent/MetalRenderer+SnapshotProvider.swift), so no Viewport file names an Agent type (invariant 3):

```swift
public protocol SnapshotProvider: AnyObject, Sendable {
    func captureSnapshotPngBase64() async -> String?
}
```

The GUI wires the renderer into the tool registry (`WorkspaceModel.swift`). The `--mcp-stdio` mode builds its registry with a `HeadlessSnapshotProvider`, which renders from an offscreen renderer (#89).

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
