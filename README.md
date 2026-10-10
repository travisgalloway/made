# made

**made** (macOS-native Computer Aided Design and Engineering) is a native CAD application for macOS and Apple platforms (macOS 14+, iPadOS 17+) engineered with Swift 6, Metal 3, Euclid CSG, a Cadova-inspired declarative CAD DSL, and an embedded Model Context Protocol (MCP) server for AI copilot workflows.

Originally prototyped as `wade` (a web-based CAD PWA), the project is transitioning to pure native Apple architecture while upholding its core engineering invariants: off-thread geometry computation, on-demand Metal rendering, right-handed Z-up orientation, gesture arbitration, and snapping precedence.

## Native Application (`macos/`)

The native application and core modules live in `macos/`:
- **MadeCore**: Geometry engine (Euclid CSG), document state model, gesture arbiter, snapping engine, Metal 3 renderer, Cadova-style declarative DSL, and MCP server.
- **MadeApp**: Universal SwiftUI application and command-line MCP stdio server.

### Building & Running

Build the native application:
```sh
cd macos
swift build
```

Run unit test suites (33 tests covering DSL, CSG booleans, gesture arbiter, snapping, and MCP protocol):
```sh
cd macos
swift test
```

Run as a headless Model Context Protocol (MCP) server over standard I/O:
```sh
./macos/.build/debug/MadeApp --mcp-stdio
```

### Declarative CAD Scripting (Cadova-Style Swift DSL)

```swift
import MadeCore

// Declarative CSG modeling with native operators:
let mountingPlate = Box(width: 50, depth: 50, height: 10)
    - Cylinder(radius: 6, height: 20)
    + Box(width: 10, depth: 10, height: 5).translated(x: 20)

let payload = mountingPlate.toMeshPayload()
```

---

## Architectural Invariants

Nine architectural rules govern this codebase:
1. **The kernel runs off the main thread**: All geometry and CSG booleans execute in background actors (`KernelClient`).
2. **Rendering is on-demand**: No continuous animation loops. Renders only invalidate on camera movement, model mutations, or active gestures.
3. **Imperative viewport rendering**: Scene geometry buffers are retained in shared GPU memory.
4. **Isolated kernel interface**: Viewport and UI communicate with `KernelClient` through an asynchronous wire contract.
5. **Direct Metal 3 pipeline**: Low-overhead Apple Silicon rendering pipeline with offscreen snapshotting for visual verification.
6. **Zero-copy shared buffers**: Vertex and index buffers shared between engine and GPU.
7. **Thread-safe geometry execution**: Actor-isolated geometry generation with honest cancellation and debounce conflation.
8. **Navigation and editing never share a gesture**: Pointer gestures strictly isolate camera manipulation from object editing.
9. **Precision snapping hierarchy**: Vertex > Edge > Grid.

---

## Web Prototype (Legacy Reference)

The original web prototype (SvelteKit + brepjs/OpenCascade WASM + WebGPU) remains in `src/` for reference:
```sh
pnpm install
pnpm dev
pnpm test
```
