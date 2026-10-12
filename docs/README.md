# made: Documentation

**`made`** (**m**acOS-native **A**ided **D**esign and **E**ngineering) is a native CAD application for macOS 26+ engineered with Swift 6, Metal 4, Euclid CSG, a Cadova-inspired declarative CAD DSL, and an embedded Model Context Protocol (MCP) server for autonomous AI workflows.

---

## Start Here

**Read [`architecture/invariants.md`](./architecture/invariants.md) first.** Nine non-negotiable rules govern this codebase, the [enforcement matrix](./architecture/invariants.md#enforcement-matrix) states which ones tests cover today. Source code comments cite them by number.

Then navigate based on your task:

| If you are… | Read |
| ----------- | ---- |
| New to the project | [invariants](./architecture/invariants.md) → [threading model](./architecture/threading-model.md) → [roadmap](./roadmap/phases.md) |
| Touching geometry or CSG booleans | [kernel](./architecture/kernel.md) |
| Touching the viewport or Metal shaders | [rendering](./architecture/rendering.md) + [orientation](./architecture/orientation.md) |
| Touching pointer input, gestures, or snapping | [input](./architecture/input.md) |
| Connecting an AI agent or editing the MCP server | [agent-api](./architecture/agent-api.md) |
| Building inspector controls or scene state | [ui-controls](./architecture/ui-controls.md) + [document-model](./architecture/document-model.md) |
| Handling errors or kernel failures | [state and errors](./architecture/state-and-errors.md) |
| Writing tests or running verification | [testing](./guides/testing.md) |
| About to open a PR | [conventions](./guides/conventions.md) |
| Picking up the next engineering milestone | [roadmap](./roadmap/phases.md) → [Phase 4](./roadmap/phase-4-cad-depth.md) |
| Checking what is built and what is planned | [feature matrix](./feature-matrix.md) |
| Checking test coverage by type | [test plan](./test-plan.md) |
| Reading audit findings | [reviews](./reviews/) and [parked findings](./parked-findings.md) |

---

## Technical Stack

| Concern | Implementation Choice |
| ------- | --------------------- |
| **Language** | Swift 6 (`swift-tools-version: 6.2`, Swift 6 language mode) |
| **UI Framework** | SwiftUI (macOS 26+; iPadOS is planned, #84) |
| **3D Rendering** | Metal 4, MetalKit (`MTKView`), MSL shaders compiled at build time |
| **Memory Architecture** | Metal buffers allocated with `.storageModeShared`; mesh arrays are copied in at upload |
| **Geometry Kernel (Tier 1)** | Pure-Swift CSG (`nicklockwood/Euclid` 0.9.6) |
| **Geometry Kernel (Tier 2)** | Planned, not in `Package.swift`: OpenCASCADE B-Rep and STEP/IGES through `OCCTSwift` (#82) |
| **Agent Interface** | Model Context Protocol (JSON-RPC 2.0 over stdio and local TCP on port 9820) |
| **CAD Scripting DSL** | Cadova-inspired declarative Swift (`@resultBuilder`) |
| **Testing** | Swift Package Manager (`swift test`), Swift Testing (`@Test`) |

---

## Repository Layout

```
macos/
  Package.swift           # Swift 6 Package manifest defining MadeCore & MadeApp
  Sources/
    MadeCore/             # Core engineering library
      Kernel/             # Geometry generators, CSG engine, KernelClient actor
      Viewport/           # Metal 4 renderer, shaders, render loop instrumentation
      Input/              # Pointer router, gesture arbiter, priority snapping
      Scene/              # @Observable DocumentModel, scene commands
      Agent/              # MCP protocol, server, CAD tools registry
      Scripting/          # Cadova-inspired declarative Swift CAD DSL
      Platform/           # AppKit / UIKit platform abstraction shims
    MadeApp/              # Application executable target
      MadeApp.swift       # SwiftUI @main entrypoint & --mcp-stdio handler
      ContentView.swift   # NavigationSplitView and toolbar
      WorkspaceModel.swift, WorkspaceTypes.swift # Window state, selection, MCP server control
      NavigatorSidebarView.swift, InspectorPanelView.swift, ViewportCanvasView.swift # Navigator, inspector, viewport header and HUD
      ConsoleDrawerView.swift, MCPServerPopoutView.swift # Console drawer and MCP window
      CADMetalViewRepresentable.swift # MTKView representable (AppKit; UIKit branch is not built)
  Tests/
    MadeCoreTests/        # 18 test suites (DSL, CSG, Kernel, Arbiter, Snapping, Document, Tools, MCP, camera, grid, axes, viewport, renderer, shader)
docs/
  architecture/           # Canonical architecture reference specifications
  roadmap/                # Phased delivery status and backlog migration audit
  guides/                 # Testing and engineering conventions
  archive/web-prototype/  # Archived documentation for original web prototype
  feature-matrix.md       # Implementation status per capability
  test-plan.md            # Test coverage by type
  parked-findings.md      # Audit findings deferred from the current scope
  reviews/                # Audit reports (2026-10-10)
```

---

## Historical Archive

The web prototype code was removed from the tree. It is in the git history at commit `fa75631`.

The original web proof-of-concept (SvelteKit + brepjs/OpenCascade WASM + three.js WebGPU) documentation is preserved in [`docs/archive/web-prototype/`](./archive/web-prototype/README.md).
