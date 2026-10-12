# made

**made** (macOS-native Computer Aided Design and Engineering) is a native CAD application for macOS 26+ built with Swift 6, SwiftUI, Metal 4, [Euclid](https://github.com/nicklockwood/Euclid) CSG, a [Cadova](https://github.com/tomasf/Cadova)-inspired declarative CAD DSL, and an embedded Model Context Protocol (MCP) server for AI copilot workflows.

Originally prototyped as `wade` (a web-based CAD PWA), the project has moved to a native Apple architecture. It keeps the nine architectural invariants. Several features are not yet wired into the application. [`docs/feature-matrix.md`](docs/feature-matrix.md) lists the status of each capability, and [`docs/roadmap/phases.md`](docs/roadmap/phases.md) lists the open issues.

## Platform and Toolchain

| Item | Target |
| --- | --- |
| Operating system | macOS 26 or later (`.macOS(.v26)` in `Package.swift`) |
| Hardware | Apple silicon only, because the renderer uses the Metal 4 API |
| Language | Swift 6 with strict concurrency (`swift-tools-version: 6.2`) |
| Interface | SwiftUI, with AppKit shims for the Metal view |
| Rendering | Metal 4 (`MTL4CommandQueue`, argument tables, residency sets) through MetalKit |
| Build system | Swift Build (`--build-system swiftbuild`), which compiles `Shaders.metal` |
| Shader toolchain | Metal Toolchain, installed with `xcodebuild -downloadComponent MetalToolchain` |
| Tests | Swift Testing (`@Test`) in `macos/Tests/MadeCoreTests` |
| Agent protocol | MCP over JSON-RPC 2.0, protocol version `2024-11-05` |

An iPadOS target is planned (#84). The package does not declare one yet.

## Core Dependencies

| Project | Role in `made` | Status |
| --- | --- | --- |
| [Euclid](https://github.com/nicklockwood/Euclid) | Pure-Swift mesh geometry and CSG (constructive solid geometry) kernel | The only package dependency (`from: "0.9.6"`) |
| [Cadova](https://github.com/tomasf/Cadova) | Model for the declarative CAD DSL in `Scripting/CADDSL.swift` | Design reference, not a dependency |
| [OCCTSwift](https://github.com/SecondMouseAU/OCCTSwift) | OpenCASCADE B-rep kernel for STEP and IGES exchange, fillets, and chamfers | Planned (#82), not a dependency |
| [Model Context Protocol](https://github.com/modelcontextprotocol/modelcontextprotocol) | Specification for the embedded agent server | Implemented natively in `Agent/`, with no SDK dependency |

## Native Application (`macos/`)

The native application and core modules live in `macos/`:
- **MadeCore**: Geometry engine (Euclid CSG), document state model, gesture arbiter, snapping engine, Metal 4 renderer, Cadova-style declarative DSL, and MCP server.
- **MadeApp**: macOS SwiftUI application and command-line MCP stdio server.

### Building & Running

Run `make setup` once to install the Metal Toolchain and the git hooks. Run commands from the repository root with `make`, or from `macos/` with `swift`. Direct `swift` commands need `--build-system swiftbuild`.

Build the native application:
```sh
make build          # or: cd macos && swift build --build-system swiftbuild
```

Run the unit test suites:
```sh
make test           # or: cd macos && swift test --build-system swiftbuild
make test FILTER=DocumentModelTests
```

Launch the application GUI, or run the MCP server over standard I/O:
```sh
make run            # or: cd macos && swift run --build-system swiftbuild MadeApp
make run-mcp        # or: cd macos && swift run --build-system swiftbuild MadeApp --mcp-stdio
```
The window also starts an in-app MCP server over TCP on port 9820 (see `docs/architecture/agent-api.md`). The listener must accept connections only from the local machine, and it binds every interface today (#129). The `--mcp-stdio` mode still declares the SwiftUI window scene. Its tool registry has no snapshot provider, so `cad_capture_snapshot` returns an error (#89).

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
5. **Direct Metal 4 pipeline**: Low-overhead Apple Silicon rendering pipeline with offscreen snapshotting for visual verification.
6. **Shared-storage buffers**: Vertex and index buffers use `.storageModeShared`. `MeshPayload` arrays are copied into them once per upload.
7. **Thread-safe geometry execution**: Actor-isolated geometry generation with a 60 ms debounce. Superseded jobs resolve as cancelled, and the latest request always completes.
8. **Navigation and editing never share a gesture**: Pointer gestures strictly isolate camera manipulation from object editing.
9. **Precision snapping hierarchy**: Vertex > Edge > Grid.

---

## Web Prototype (Archived Reference)

The original web prototype (SvelteKit + brepjs/OpenCascade WASM + WebGPU) was removed from the tree. Its code is in the git history at commit `fa75631`, and its documentation is in [`docs/archive/web-prototype/`](docs/archive/web-prototype/README.md).

---

## License

Copyright (C) 2026 Travis Galloway. `made` is released under the [Mozilla Public License 2.0](LICENSE) (`MPL-2.0`). Bundled libraries keep their own licenses, which the app lists in its Open Source Licenses window (#425). [ADR-D8](docs/architecture/adr/ADR-D8-project-license.md) records the decision and its effect on dependencies.
