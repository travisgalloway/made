# Project Roadmap & Phase Status

## Rules of Engagement

- **Complete phases in dependency order.** Foundations must be solid and verified before downstream features are built.
- **The [architectural invariants](../architecture/invariants.md) are non-negotiable.** A violation is treated as a build break.
- **Verify every phase with automated tests.** Run `swift test` and confirm all test suites pass with zero failures before declaring a phase complete.

---

## Status at a Glance

| Phase | Description | Status | Verification Target |
| ----- | ----------- | ------ | ------------------- |
| **0** | **Native Foundation** | ✅ Done | Swift 6 Package, `MadeCore`, `MadeApp`, strict concurrency. |
| **1** | **Metal 3 Viewport** | ✅ Done | On-demand rendering (`MTKView`), gesture arbiter, snapping engine. |
| **2** | **Native CSG Kernel** | ✅ Done | `EuclidEngine` pure-Swift CSG, `KernelClient` actor, 60 ms conflation. |
| **3** | **Agentic Subsystem** | ✅ Done | Embedded MCP server over stdio, Cadova-style Swift DSL, vision loop. |
| **4** | **CAD Depth** | 🔜 **Next** | OCCT B-Rep, 2D sketches, constraints, 3D gizmos, `.made` files. |

---

## Phase 0 — Native Foundation ✅
Established the Swift 6 package hierarchy for `MadeNative`:
- `MadeCore`: Library target containing geometry, viewport, input, and agent modules.
- `MadeApp`: Executable SwiftUI application target.
- Target platforms: `.macOS(.v14)` and `.iOS(.v17)`.

---

## Phase 1 — Metal 3 Viewport & Universal Input ✅
Delivered the native hardware-accelerated 3D viewport:
- Direct Metal 3 pipeline with compiled Metal Shading Language shaders.
- On-demand invalidation loop enforcing Invariant 2 (`MTKView.isPaused = true`).
- Telemetry HUD tracking draw calls and render counts.
- `GestureArbiter` locking navigate vs manipulate modes on first move (Invariant 8).
- `Snapping` engine enforcing Vertex > Edge > Grid precedence (Invariant 9).

---

## Phase 2 — Native CSG Kernel ✅
Integrated high-performance pure-Swift CSG geometry computation:
- `EuclidEngine` generating parametric boxes and cylinders.
- Exact BSP-tree boolean operations (`subtract`, `union`, `intersect`).
- Off-thread actor execution in `KernelClient` with 60 ms debounce conflation.
- Stale job cancellation preventing visual flicker.

---

## Phase 3 — Agentic Subsystem & MCP Stdio Server ✅
Integrated autonomous AI capabilities directly into the application:
- Pure-Swift JSON-RPC 2.0 and Model Context Protocol (2024-11-05 spec) implementation.
- Headless `--mcp-stdio` CLI flag allowing external agents (Claude Desktop, Cursor) to drive CAD sessions.
- 8 registered CAD tools covering scene inspection, parameter updates, booleans, and offscreen Metal snapshots.
- Cadova-inspired declarative Swift CAD DSL ([`CADDSL.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Scripting/CADDSL.swift)) with operator overloads (`-`, `+`, `&`).
- Multimodal visual feedback loop for vision-capable LLMs.

See [`phase-3-native-agent.md`](./phase-3-native-agent.md).

---

## Phase 4 — CAD Depth 🔜
The active development frontier, expanding engineering capabilities:
- **4.1 Feature Tree UI**: Hierarchical parametric history tree in SwiftUI.
- **4.2 Multi-Body Booleans**: Expanding CSG booleans across arbitrary scene objects.
- **4.3 2D Sketching Layer**: Sketch planes, line/arc drawing, and profile extrusions.
- **4.4 2D Constraint Solver**: Geometric constraints (parallel, coincident, tangent, distance).
- **4.5 OCCTSwift B-Rep Bridge**: STEP/IGES import and export with analytic topology.
- **4.6 Undo/Redo Engine**: Command pattern integration with `UndoManager`.
- **4.7 Direct Manipulation 3D Gizmos**: Visual translate, rotate, and scale handles.
- **4.8 Native File Format**: `.made` bundle package using `FileDocument`.

See [`phase-4-cad-depth.md`](./phase-4-cad-depth.md).
