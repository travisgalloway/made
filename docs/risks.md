# Risk Analysis & Mitigations

This document identifies technical risks, deferred decisions, and architectural trade-offs in `made`.

---

## 1. OpenCASCADE C++ Framework Size & Complexity

### Risk
Integrating full OpenCASCADE (`OCCT.xcframework`) adds approximately 60–100 MB of compiled C++ binaries, increases build times, and introduces C++/Swift bridging headers that can complicate CI pipelines.

### Mitigation
Adopted the **multi-tier geometry engine strategy**:
- **Tier 1 (Default)**: Pure-Swift [`EuclidEngine`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Kernel/EuclidEngine.swift) has zero C++ dependencies, weighs less than 1 MB, and compiles in under 1 second. It handles all basic primitives and CSG booleans.
- **Tier 2 (Enterprise / Industrial)**: OpenCASCADE is encapsulated inside a separate SPM framework target (`OCCTSwift`). It is compiled into a pre-built dynamic xcframework so that application development does not require compiling OCCT from source on every build.

---

## 2. App Store Sandboxing vs. Headless MCP Stdio Server

### Risk
macOS App Sandbox rules restrict arbitrary standard I/O pipe inheritance and child process execution, which could hinder distribution of the MCP server via the Mac App Store.

### Mitigation
- Provide a dual-distribution posture:
  - **Developer / CLI Build**: Distributed as an open binary or Homebrew package where `--mcp-stdio` connects directly to local AI agents (Claude Desktop, Cursor).
  - **App Store Build**: Sandboxed GUI application utilizing Apple's native XPC services or a local loopback WebSocket endpoint for agent communication.

---

## 3. CSG Floating-Point Coplanar Intersections

### Risk
BSP-tree constructive solid geometry (CSG) algorithms can experience degenerate polygons or non-manifold meshes when evaluating perfectly coplanar overlapping faces.

### Mitigation
- Parameter inputs are rounded to engineering tolerances ($10^{-5}\text{ mm}$).
- Where CSG boolean differences meet coplanar boundaries, cutters are automatically extended by a micro-epsilon ($0.001\text{ mm}$) to ensure unambiguous topological splits.
- Tier 2 OpenCASCADE B-Rep serves as the exact fallback for complex industrial tooling.

---

## 4. Apple Pencil Latency on High-Density Meshes

### Risk
Direct manipulation with the Apple Pencil demands sub-16 ms latency. Recalculating complex CSG meshes on every stylus drag event would drop frames and cause noticeable lag.

### Mitigation
- **Two-Physics Rule**: Stylus translation drags modify only the object's rigid transform matrix ($4\times 4$) on the GPU. The geometry kernel is never called during move or rotate gestures.
- Stylus dimension resize drags preview a GPU scale transform, dispatching exactly one debounced re-tessellation to the background actor upon stylus lift.

---

## Related Documentation

- [`kernel.md`](./architecture/kernel.md) — Multi-tier geometry engine
- [`agent-api.md`](./architecture/agent-api.md) — MCP server transport
- [`input.md`](./architecture/input.md) — Apple Pencil interaction model
