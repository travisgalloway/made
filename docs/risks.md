# Risk Analysis & Mitigations

This document identifies technical risks, deferred decisions, and architectural trade-offs in `made`.

---

## 1. OpenCASCADE C++ Framework Size & Complexity

### Risk
Integrating full OpenCASCADE (`OCCT.xcframework`) adds approximately 60–100 MB of compiled C++ binaries, increases build times, and introduces C++/Swift bridging headers that can complicate CI pipelines.

### Mitigation
The design uses a **multi-tier geometry engine strategy**. Tiers 1 and 2 exist in the code today:
- **Tier 1 (Implemented)**: Pure-Swift [`EuclidEngine`](../macos/Sources/MadeCore/Kernel/EuclidEngine.swift) has zero C++ dependencies. `Package.swift` also declares OCCTSwift. It handles box and cylinder primitives and CSG booleans.
- **Tier 2 (Implemented, #82)**: OpenCASCADE comes in through the `OCCTSwift` 3.0.0 package, declared in `Package.swift`, so builds do not compile OCCT from source. `OCCTEngine.importStep` and `OCCTEngine.exportStep` run STEP exchange. IGES has no entry point (#404).

---

## 2. App Store Sandboxing vs. Headless MCP Stdio Server

### Risk
macOS App Sandbox rules restrict arbitrary standard I/O pipe inheritance and child process execution, which could hinder distribution of the MCP server via the Mac App Store.

### Mitigation
- Provide a dual-distribution posture:
  - **Developer ID / Direct-Download Build (#254, BL-MAC-10)**: Distributed as a signed and notarized application bundle (.dmg, .zip) outside the Mac App Store (ADR-D8). Hardened Runtime is enabled with `com.apple.security.cs.allow-jit` for JavaScriptCore parametric scripting. Direct download does not require App Sandbox, operating under standard POSIX file permissions and loopback networking on port 9820 (`parameters.requiredInterfaceType = .loopback`, #129). Entitlements and update persistence are documented in `docs/distribution/entitlements.md`.
  - **App Store Build (#419)**: Sandboxed GUI application utilizing Apple native XPC services for agent communication. Sockets binding on loopback will require `com.apple.security.network.server`. The geometry kernel already runs in a bundled XPC service (#245).


---

## 3. CSG Floating-Point Coplanar Intersections

### Risk
BSP-tree constructive solid geometry (CSG) algorithms can experience degenerate polygons or non-manifold meshes when evaluating perfectly coplanar overlapping faces.

### Mitigation
None of the following is implemented. The code applies no rounding tolerance and no cutter extension. `LocalKernelEngine` runs a boolean through OCCT when both solids have an OCCT shape, and through Euclid otherwise (`LocalKernelEngine.swift:130-150`).
- Planned: round parameter inputs to an engineering tolerance (proposed $10^{-5}\text{ mm}$).
- Planned: extend cutters by a small epsilon (proposed $0.001\text{ mm}$) where a difference meets a coplanar boundary.
- Available (#82): Tier 2 OpenCASCADE B-Rep as the exact fallback for complex industrial tooling.

---

## 4. Apple Pencil Latency on High-Density Meshes

### Risk
Direct manipulation with the Apple Pencil demands sub-16 ms latency. Recalculating complex CSG meshes on every stylus drag event would drop frames and cause noticeable lag.

### Mitigation
The Apple Pencil channel is planned (#84). The viewport receives mouse and trackpad input today (orbit, pan, zoom, snapping, and transform gizmos from #71 and #72), but Pencil input does not exist.
- **Two-Physics Rule (planned)**: Stylus translation drags modify only the object's rigid transform matrix ($4\times 4$) on the GPU. The geometry kernel is not called during move or rotate gestures.
- Stylus dimension resize drags preview a GPU scale transform, then dispatch one debounced re-tessellation to the background actor on stylus lift.

---

## Related Documentation

- [`kernel.md`](./architecture/kernel.md): Multi-tier geometry engine
- [`agent-api.md`](./architecture/agent-api.md): MCP server transport
- [`input.md`](./architecture/input.md): Apple Pencil interaction model
