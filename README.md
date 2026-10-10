# made

**made** (macOS-native Computer Aided Design and Engineering) is a native CAD application for macOS 14+ engineered with Swift 6, Metal 3, Euclid CSG, a Cadova-inspired declarative CAD DSL, and an embedded Model Context Protocol (MCP) server for AI copilot workflows.

Originally prototyped as `wade` (a web-based CAD PWA), the project has moved to a native Apple architecture. It keeps the nine architectural invariants. Several features are not yet wired into the application. [`docs/feature-matrix.md`](docs/feature-matrix.md) lists the status of each capability, and [`docs/roadmap/phases.md`](docs/roadmap/phases.md) lists the open issues.

## Native Application (`macos/`)

The native application and core modules live in `macos/`:
- **MadeCore**: Geometry engine (Euclid CSG), document state model, gesture arbiter, snapping engine, Metal 3 renderer, Cadova-style declarative DSL, and MCP server.
- **MadeApp**: macOS SwiftUI application and command-line MCP stdio server. The package declares only `.macOS(.v14)`. An iPadOS target is planned (#84).

### Building & Running

Build the native application:
```sh
cd macos
swift build
```

Run the unit test suites (33 tests covering DSL, CSG booleans, gesture arbiter, snapping, document model, and MCP protocol). `KernelClientTests.testRapidRequestsConflateToLatestValue` fails today (#90):
```sh
cd macos
swift test
```

Launch the application, or run the MCP server over standard I/O:
```sh
cd macos
swift run MadeApp
swift run MadeApp --mcp-stdio
```
The `--mcp-stdio` mode still declares the SwiftUI window scene. Its tool registry has no snapshot provider, so `cad_capture_snapshot` returns an error (#89).

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
1. **The kernel runs off the main thread**: All geometry and CSG booleans execute in the `KernelClient` actor.
2. **Rendering is on-demand**: No continuous animation loops. Renders only invalidate on camera movement, model mutations, or active gestures.
3. **Imperative viewport rendering**: Scene geometry buffers are retained in GPU buffers allocated with shared storage.
4. **Isolated kernel interface**: Viewport and UI communicate with `KernelClient` through an asynchronous wire contract.
5. **Direct Metal 3 pipeline**: Low-overhead Apple Silicon rendering pipeline with offscreen snapshotting for visual verification.
6. **Shared-storage buffers**: Vertex and index buffers use `.storageModeShared`. `MeshPayload` arrays are copied into them once per upload.
7. **Thread-safe geometry execution**: Actor-isolated geometry generation with a 60 ms debounce. The conflation test currently fails (#90).
8. **Navigation and editing never share a gesture**: Pointer gestures strictly isolate camera manipulation from object editing.
9. **Precision snapping hierarchy**: Vertex > Edge > Grid. The snapping module is not yet called from the viewport (#88).

---

## Web Prototype (Archived Reference)

The original web prototype (SvelteKit + brepjs/OpenCascade WASM + WebGPU) remains in `src/` and `e2e/`, with the `pnpm` toolchain, for reference only. It is not part of the native application:
```sh
pnpm install
pnpm dev
pnpm test
```
