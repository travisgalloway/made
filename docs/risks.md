# Risk Analysis & Mitigations

This document identifies technical risks, deferred decisions, and architectural trade-offs in `made`.

---

## 1. OpenCASCADE C++ Framework Size & Complexity

### Risk
Integrating full OpenCASCADE (`OCCT.xcframework`) adds approximately 60–100 MB of compiled C++ binaries, increases build times, and introduces C++/Swift bridging headers that can complicate CI pipelines.

### Mitigation
The design uses a **multi-tier geometry engine strategy**. Only Tier 1 exists in the code today:
- **Tier 1 (Implemented)**: Pure-Swift [`EuclidEngine`](../macos/Sources/MadeCore/Kernel/EuclidEngine.swift) has zero C++ dependencies. `Package.swift` declares Euclid as the only dependency. It handles box and cylinder primitives and CSG booleans.
- **Tier 2 (Planned, #82)**: OpenCASCADE would sit in a separate SPM target (`OCCTSwift`) backed by a pre-built xcframework, so builds do not compile OCCT from source. No such target or dependency exists yet. `importStep` returns `geometryFailed` with the message "STEP import pending OpenCASCADE bridge".

---

## 2. App Store Sandboxing vs. Headless MCP Stdio Server

### Risk
macOS App Sandbox rules restrict arbitrary standard I/O pipe inheritance and child process execution, which could hinder distribution of the MCP server via the Mac App Store.

### Mitigation
- Provide a dual-distribution posture:
  - **Developer / CLI Build**: Distributed as an open binary or Homebrew package where `--mcp-stdio` connects directly to local AI agents (Claude Desktop, Cursor).
  - **App Store Build**: Sandboxed GUI application utilizing Apple's native XPC services for agent communication. A TCP listener on port 9820 exists in the GUI (`MCPServer.start`), restricted to loopback interfaces via `requiredInterfaceType = .loopback` (#129). Sandbox entitlements remain open work. The geometry kernel already runs in a bundled XPC service (#245); its sandbox entitlements are also open.

---

## 3. CSG Floating-Point Coplanar Intersections

### Risk
BSP-tree constructive solid geometry (CSG) algorithms can experience degenerate polygons or non-manifold meshes when evaluating perfectly coplanar overlapping faces.

### Mitigation
None of the following is implemented. The code applies no rounding tolerance and no cutter extension. It relies on the Euclid booleans as they are.
- Planned: round parameter inputs to an engineering tolerance (proposed $10^{-5}\text{ mm}$).
- Planned: extend cutters by a small epsilon (proposed $0.001\text{ mm}$) where a difference meets a coplanar boundary.
- Planned (#82): Tier 2 OpenCASCADE B-Rep as the exact fallback for complex industrial tooling.

---

## 4. Apple Pencil Latency on High-Density Meshes

### Risk
Direct manipulation with the Apple Pencil demands sub-16 ms latency. Recalculating complex CSG meshes on every stylus drag event would drop frames and cause noticeable lag.

### Mitigation
The Apple Pencil channel is planned (#84), and the gizmo interactions are planned (#71, #72). The viewport receives mouse and trackpad input today (orbit, pan, zoom, and snapping), but Pencil input and gizmos do not exist.
- **Two-Physics Rule (planned)**: Stylus translation drags modify only the object's rigid transform matrix ($4\times 4$) on the GPU. The geometry kernel is not called during move or rotate gestures.
- Stylus dimension resize drags preview a GPU scale transform, then dispatch one debounced re-tessellation to the background actor on stylus lift.

---

## Related Documentation

- [`kernel.md`](./architecture/kernel.md): Multi-tier geometry engine
- [`agent-api.md`](./architecture/agent-api.md): MCP server transport
- [`input.md`](./architecture/input.md): Apple Pencil interaction model
